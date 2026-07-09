# Deployment Setup

This repo is wired so that a push to `main` automatically builds the Lambda/dashboard
Docker images, pushes them to ECR, runs `terraform apply`, and rolls the dashboard out
to EKS (`.github/workflows/deploy.yml`). None of that can run until the steps below are
done once, manually, by someone with real AWS and GitHub admin access. This is a
chicken-and-egg problem: the roles GitHub Actions needs to authenticate to AWS don't
exist until you create them, and CI can't create its own trust relationship.

## 1. Apply the bootstrap stack (once)

```
cd terraform/bootstrap
terraform init
terraform apply
```

This creates:
- The Terraform remote state backend (S3 bucket + DynamoDB lock table) that
  `terraform/envs/prod/backend.tf` depends on.
- A GitHub OIDC provider, plus two IAM roles GitHub Actions assumes via short-lived
  tokens (no long-lived AWS keys stored in the repo):
  - `gha-plan-role` — read-only, usable from pull request builds.
  - `gha-deploy-role` — full deploy permissions, usable only from pushes to `main`.

Note the two role ARNs from the output (`gha_plan_role_arn`, `gha_deploy_role_arn`) —
you'll need them in step 2.

Its state is kept separate from `envs/prod` on purpose (see the comment at the top of
`terraform/bootstrap/main.tf`) — it changes rarely and manages the account-level trust
relationship that everything else depends on.

## 2. Configure the GitHub repository

In **Settings → Secrets and variables → Actions**:

| Type | Name | Value |
|---|---|---|
| Variable | `AWS_REGION` | `us-east-1` |
| Variable | `AWS_PLAN_ROLE_ARN` | `gha_plan_role_arn` output from step 1 |
| Variable | `AWS_DEPLOY_ROLE_ARN` | `gha_deploy_role_arn` output from step 1 |
| Variable | `DASHBOARD_ALLOWED_CIDR` | Your office/VPN CIDR (e.g. `203.0.113.4/32`) — **never `0.0.0.0/0`**, the dashboard pod carries AWS read credentials via IRSA behind that NodePort |
| Secret | `YOUTUBE_API_KEY` | A freshly issued YouTube Data API v3 key |
| Secret | `DASHBOARD_TRIGGER_API_KEY` | A random shared secret you generate (e.g. `openssl rand -hex 32`) — required as the `X-API-Key` header to `POST /trigger` on the dashboard |

> If you're rotating off a previously exposed key (see the Security Notes below),
> generate a brand new one in Google Cloud Console rather than reusing the old value.

In **Settings → Environments**, create an environment named `production` and add at
least one required reviewer. `deploy.yml`'s `terraform-apply` job targets this
environment as a manual-approval gate — every infrastructure change gets a human
sign-off before it applies, even though the rest of the pipeline is automatic.

## 3. Push to `main`

With steps 1-2 done, a push to `main` runs, in order:
1. **lint** — flake8/black on the Python components, `terraform fmt -check`.
2. **build-and-push-images** — builds and pushes only the components that changed
   (`yt-ingest`, `yt-json-to-parquet`, `yt-data-quality`, `yt-dashboard`) to ECR. On the
   very first run it also creates each ECR repository if it doesn't exist yet, so this
   works even before `terraform apply` has ever run.
3. **terraform-apply** — waits for the `production` environment approval, then applies
   everything: S3 buckets, IAM roles, Glue jobs/catalog, Lambda functions (referencing
   the images just pushed), Step Functions, EventBridge schedule, SNS, Athena, Secrets
   Manager, and the EKS cluster.
4. **deploy-dashboard** — points `kubectl` at the new cluster, ensures the `monitoring`
   namespace and `dashboard-api-key` secret exist, applies `k8s/`, patches the
   dashboard's IRSA role ARN onto its service account, and rolls out the `yt-dashboard`
   image.

## The dashboard is a control panel, not just a viewer

The dashboard (NodePort 30080) shows recent Step Functions executions, the last
data-quality result, and Gold table stats — and can also:
- **Trigger a new pipeline run**: `POST /trigger` with header `X-API-Key: <DASHBOARD_TRIGGER_API_KEY>`.
  Returns `401` on a missing/wrong key, `409` if a run is already in progress (prevents
  overlapping executions), `200` + the new execution name/ARN otherwise. Each trigger
  costs real YouTube API quota and AWS compute, hence the API key requirement on top of
  the `DASHBOARD_ALLOWED_CIDR` network restriction.
- **Run predefined Gold-table queries**: `GET /query/top_channels`, `/query/top_categories`,
  `/query/trending_summary` — fixed queries only (no free-form SQL), to keep Athena scan
  cost bounded and avoid exposing a query-injection surface on a network port.

## Ongoing cost

Once applied, the EKS cluster (control plane + 2× `t3.small` nodes) runs continuously
at roughly **$100-120/month** until torn down — this is not a one-time cost. To tear
everything down: `terraform -chdir=terraform/envs/prod destroy` (the bootstrap stack's
state bucket and lock table have `prevent_destroy = true` and are meant to be kept).

## Security notes

- The dashboard's NodePort (30080) is only reachable from `DASHBOARD_ALLOWED_CIDR` —
  set this to a real, narrow CIDR before the first apply, not `0.0.0.0/0`.
- `youtube_api_key` and the AWS role ARNs are never written to disk or `.tfvars` in
  this repo; they're passed as `-var` flags from GitHub Actions secrets/variables at
  apply time.
- If you ever find a real credential committed to this repo, treat it as compromised
  immediately (rotate it at the provider) even after removing it from git history —
  history rewrites don't undo prior exposure on a pushed remote.
