#!/usr/bin/env bash
set -euo pipefail

mkdir -p ~/.dbt
envsubst < /dbt/profiles/profiles.yml.template > ~/.dbt/profiles.yml

cd /dbt
dbt deps

# dbt build materializes curated + enriched (respecting the DAG: enriched
# depends on curated via ref()) AND runs all attached tests — the 4
# non-freshness ported DQ checks (row count, null %, contract/schema, value
# range) all live as tests here, so a failing test fails this command's exit
# code, which is what makes the whole Job/pod fail, which is what the
# dbt-trigger Lambda watches for. No separate "evaluate quality" step needed.
dbt build

# Source freshness (the 5th ported DQ check) is NOT run by `dbt build` — it
# must be invoked separately, and must also gate the container's exit code.
dbt source freshness
