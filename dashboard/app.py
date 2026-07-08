"""
Pipeline Monitoring Dashboard
─────────────────────────────
Read-only view into the YouTube data pipeline: recent Step Functions
executions, the last data-quality check result, and Gold table row counts.
Runs on Kubernetes (EKS) as a separate concern from the pipeline itself —
it never writes to any pipeline resource, only reads via IRSA.

Environment Variables:
    STATE_MACHINE_ARN   — the yt-data-pipeline state machine ARN
    ATHENA_WORKGROUP     — the dashboard's own Athena workgroup
    GOLD_DATABASE        — yt_pipeline_gold_db
    AWS_REGION           — set automatically by EKS/IRSA
"""

import json
import os
import time
import logging

import boto3
from flask import Flask, render_template

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)

STATE_MACHINE_ARN = os.environ["STATE_MACHINE_ARN"]
ATHENA_WORKGROUP = os.environ["ATHENA_WORKGROUP"]
GOLD_DATABASE = os.environ["GOLD_DATABASE"]

sfn_client = boto3.client("stepfunctions")
athena_client = boto3.client("athena")

_cache = {"data": None, "expires_at": 0}
CACHE_TTL_SECONDS = 60


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
            reason = status["QueryExecution"]["Status"].get("StateChangeReason", "unknown")
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
    resp = sfn_client.list_executions(stateMachineArn=STATE_MACHINE_ARN, maxResults=limit)
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

    execution_arn = (
        f"{STATE_MACHINE_ARN.replace(':stateMachine:', ':execution:')}:{executions[0]['name']}"
    )
    try:
        history = sfn_client.get_execution_history(
            executionArn=execution_arn, reverseOrder=True, maxResults=50
        )
    except Exception as e:
        logger.warning("Could not fetch execution history: %s", e)
        return None

    for event in history["events"]:
        details = event.get("taskSucceededEventDetails") or event.get("lambdaFunctionSucceededEventDetails")
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


@app.route("/")
def index():
    return render_template("dashboard.html", **get_dashboard_data())


@app.route("/healthz")
def healthz():
    return {"status": "ok"}, 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
