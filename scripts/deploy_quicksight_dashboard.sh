#!/usr/bin/env bash
# Publishes/updates the "YouTube Trending Insights" QuickSight dashboard from
# quicksight_dashboard.json. Deliberately not Terraform-managed (see
# terraform/modules/quicksight's header comment) — the visual definition is
# content, not infrastructure, and iterates far faster against the API
# directly than through Terraform's HCL translation of the same JSON.
#
# Run from the repo root: ./scripts/deploy_quicksight_dashboard.sh
set -euo pipefail

ACCOUNT_ID="300617413029"
DASHBOARD_ID="yt-pipeline-insights"
DEFINITION_FILE="$(dirname "$0")/quicksight_dashboard.json"
USER_ARN="arn:aws:quicksight:us-east-1:${ACCOUNT_ID}:user/default/${ACCOUNT_ID}"
PERMISSIONS="Principal=${USER_ARN},Actions=quicksight:DescribeDashboard,quicksight:ListDashboardVersions,quicksight:UpdateDashboardPermissions,quicksight:QueryDashboard,quicksight:UpdateDashboard,quicksight:DeleteDashboard,quicksight:DescribeDashboardPermissions,quicksight:UpdateDashboardPublishedVersion"

if aws quicksight describe-dashboard --aws-account-id "$ACCOUNT_ID" --dashboard-id "$DASHBOARD_ID" >/dev/null 2>&1; then
  echo "Dashboard exists — updating..."
  aws quicksight update-dashboard \
    --aws-account-id "$ACCOUNT_ID" \
    --dashboard-id "$DASHBOARD_ID" \
    --name "YouTube Trending Insights" \
    --definition "file://${DEFINITION_FILE}"
  aws quicksight update-dashboard-published-version \
    --aws-account-id "$ACCOUNT_ID" \
    --dashboard-id "$DASHBOARD_ID" \
    --version-number "$(aws quicksight describe-dashboard --aws-account-id "$ACCOUNT_ID" --dashboard-id "$DASHBOARD_ID" --query 'Dashboard.Version.VersionNumber' --output text)"
else
  echo "Dashboard does not exist — creating..."
  aws quicksight create-dashboard \
    --aws-account-id "$ACCOUNT_ID" \
    --dashboard-id "$DASHBOARD_ID" \
    --name "YouTube Trending Insights" \
    --definition "file://${DEFINITION_FILE}" \
    --permissions "$PERMISSIONS"
fi

echo "Dashboard URL: https://us-east-1.quicksight.aws.amazon.com/sn/dashboards/${DASHBOARD_ID}"
