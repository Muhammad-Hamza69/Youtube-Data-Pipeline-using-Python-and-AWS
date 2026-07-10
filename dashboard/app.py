"""
Pipeline Control Dashboard
──────────────────────────
Interactive front door into the YouTube data pipeline, running on Kubernetes
(EKS) as a separate concern from the pipeline itself: shows recent Step
Functions executions, the last data-quality check result, and Gold table
row counts, and can trigger a new pipeline run and run a small set of
predefined Gold-table queries. All AWS access is via IRSA.

The NodePort is reachable from any IP (the operator's IP changes too often
for a CIDR allowlist to be practical), so every route except /healthz
requires HTTP Basic Auth instead — the browser's native login prompt caches
the credentials for the session and automatically attaches them to the
page's own fetch() calls too, so there's no separate in-page API key field.

Environment Variables:
    STATE_MACHINE_ARN   — the yt-data-pipeline state machine ARN
    ATHENA_WORKGROUP     — the dashboard's own Athena workgroup
    GOLD_DATABASE        — yt_pipeline_gold_db
    TRIGGER_API_KEY       — shared secret; any username + this as the password via HTTP Basic Auth
    AWS_REGION           — set automatically by EKS/IRSA
"""

import json
import os
import time
import logging

import boto3
from flask import Flask, Response, render_template, request, jsonify

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)

STATE_MACHINE_ARN = os.environ["STATE_MACHINE_ARN"]
ATHENA_WORKGROUP = os.environ["ATHENA_WORKGROUP"]
GOLD_DATABASE = os.environ["GOLD_DATABASE"]
TRIGGER_API_KEY = os.environ["TRIGGER_API_KEY"].strip()

sfn_client = boto3.client("stepfunctions")
athena_client = boto3.client("athena")

_cache = {"data": None, "expires_at": 0}
CACHE_TTL_SECONDS = 60

# Predefined, fixed Gold queries — bounded scan cost, no free-form SQL
# accepted from the network. Columns match glue_jobs/silver_to_gold_analytics.py.
GOLD_QUERIES = {
    "top_channels": (
        "SELECT channel_title, region, total_views, avg_engagement_rate, "
        "rank_in_region FROM channel_analytics WHERE rank_in_region <= 10 "
        "ORDER BY region, rank_in_region LIMIT 50"
    ),
    "top_categories": (
        "SELECT category_name, region, total_views, view_share_pct "
        "FROM category_analytics ORDER BY total_views DESC LIMIT 20"
    ),
    "trending_summary": (
        "SELECT region, trending_date_parsed, total_videos, total_views, "
        "avg_engagement_rate FROM trending_analytics "
        "ORDER BY trending_date_parsed DESC LIMIT 20"
    ),
}


def run_athena_query(sql: str, timeout_seconds: int = 30):
    """Run a query against the dashboard's Athena workgroup and return rows."""
    query_id = athena_client.start_query_execution(
        QueryString=sql,
        QueryExecutionContext={"Database": GOLD_DATABASE},
        WorkGroup=ATHENA_WORKGROUP,
    )["QueryExecutionId"]

    deadline = time.time() + timeout_seconds
    while time.time() < deadline:
        status = athena_client.get_query_execution(QueryExecutionId=query_id)
        state = status["QueryExecution"]["Status"]["State"]
        if state == "SUCCEEDED":
            break
        if state in ("FAILED", "CANCELLED"):
            reason = status["QueryExecution"]["Status"].get(
                "StateChangeReason", "unknown"
            )
            logger.warning("Athena query failed: %s", reason)
            return None
        time.sleep(1)
    else:
        logger.warning("Athena query timed out")
        return None

    result = athena_client.get_query_results(QueryExecutionId=query_id)
    rows = result["ResultSet"]["Rows"]
    if len(rows) < 2:
        return []
    header = [c.get("VarCharValue", "") for c in rows[0]["Data"]]
    return [
        dict(zip(header, [c.get("VarCharValue", "") for c in row["Data"]]))
        for row in rows[1:]
    ]


def get_recent_executions(limit: int = 10):
    resp = sfn_client.list_executions(
        stateMachineArn=STATE_MACHINE_ARN, maxResults=limit
    )
    return [
        {
            "name": e["name"],
            "status": e["status"],
            "startDate": e["startDate"].isoformat(),
            "stopDate": e.get("stopDate").isoformat() if e.get("stopDate") else None,
        }
        for e in resp["executions"]
    ]


def get_last_dq_result(executions):
    """
    Walk the most recent execution's history looking for the
    RunDataQualityChecks task's output — the DQ Lambda's return value is
    already captured there, so no separate persistence layer is needed.
    """
    if not executions:
        return None

    execution_arn = f"{STATE_MACHINE_ARN.replace(':stateMachine:', ':execution:')}:{executions[0]['name']}"
    try:
        history = sfn_client.get_execution_history(
            executionArn=execution_arn, reverseOrder=True, maxResults=50
        )
    except Exception as e:
        logger.warning("Could not fetch execution history: %s", e)
        return None

    for event in history["events"]:
        details = event.get("taskSucceededEventDetails") or event.get(
            "lambdaFunctionSucceededEventDetails"
        )
        if details and "output" in details:
            try:
                payload = json.loads(details["output"])
                body = payload.get("Payload", payload)
                if "quality_passed" in body:
                    return body
            except (json.JSONDecodeError, AttributeError):
                continue
    return None


def get_gold_stats():
    stats = {}
    for table in ("trending_analytics", "channel_analytics", "category_analytics"):
        rows = run_athena_query(f'SELECT COUNT(*) AS row_count FROM "{table}"')
        stats[table] = rows[0]["row_count"] if rows else "n/a"
    return stats


def get_dashboard_data():
    now = time.time()
    if _cache["data"] and _cache["expires_at"] > now:
        return _cache["data"]

    executions = get_recent_executions()
    data = {
        "executions": executions,
        "dq_result": get_last_dq_result(executions),
        "gold_stats": get_gold_stats(),
    }
    _cache["data"] = data
    _cache["expires_at"] = now + CACHE_TTL_SECONDS
    return data


@app.before_request
def _require_auth():
    """HTTP Basic Auth on every route except /healthz (hit unauthenticated by k8s probes)."""
    if request.path == "/healthz":
        return None
    auth = request.authorization
    if auth is None or auth.password != TRIGGER_API_KEY:
        return Response(
            "Authentication required",
            401,
            {"WWW-Authenticate": 'Basic realm="YT Pipeline Dashboard"'},
        )
    return None


@app.route("/")
def index():
    return render_template(
        "dashboard.html", **get_dashboard_data(), query_names=list(GOLD_QUERIES)
    )


@app.route("/healthz")
def healthz():
    return {"status": "ok"}, 200


@app.route("/trigger", methods=["POST"])
def trigger():
    """Start a new pipeline execution (auth already enforced by _require_auth)."""
    running = sfn_client.list_executions(
        stateMachineArn=STATE_MACHINE_ARN, statusFilter="RUNNING", maxResults=1
    )["executions"]
    if running:
        return (
            jsonify(
                {
                    "error": "a pipeline execution is already running",
                    "execution": running[0]["name"],
                }
            ),
            409,
        )

    execution_name = f"manual-{int(time.time())}"
    resp = sfn_client.start_execution(
        stateMachineArn=STATE_MACHINE_ARN, name=execution_name
    )
    _cache["expires_at"] = 0  # force fresh data on next page load
    logger.info("Triggered execution %s", execution_name)
    return jsonify({"executionArn": resp["executionArn"], "name": execution_name}), 200


@app.route("/query/<name>")
def query(name):
    """Run one of the fixed, predefined Gold-table queries."""
    sql = GOLD_QUERIES.get(name)
    if sql is None:
        return jsonify({"error": f"unknown query '{name}'"}), 404
    rows = run_athena_query(sql)
    if rows is None:
        return jsonify({"error": "query failed or timed out"}), 502
    return jsonify({"query": name, "rows": rows}), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
