# ArgoCD itself needs no AWS permissions — it only talks to the in-cluster
# Kubernetes API via its own Helm-chart-created ServiceAccount/RBAC. Kept
# ClusterIP-only (chart default): no NodePort/ingress, since UI access
# wasn't requested. Use `kubectl port-forward` for the rare manual look.
#
# The Application CR that points ArgoCD at this repo's k8s/ directory is
# applied once, manually (see DEPLOYMENT.md) rather than as a
# kubernetes_manifest resource here — that resource type validates the CRD
# schema at plan time, which doesn't exist yet on the very first apply
# before this helm_release has run. Not worth fighting for a resource this
# static.
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.chart_version
  namespace        = "argocd"
  create_namespace = true
}
