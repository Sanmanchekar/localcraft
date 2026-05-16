# samples/helm/

Reference Helm chart archetypes. The skill uses these as templates when generating EKS-mode output (`/localcraft eks`) and the target repo doesn't already have a chart of its own.

## Bundled archetypes (v0.9+)

| Archetype | Use for | Bundled features |
|---|---|---|
| `web-service/` | Stateless HTTP service (REST API, GraphQL, gateway, sidecar) | Deployment + Service + Ingress (ALB), HPA, PDB, RBAC + ServiceAccount, ExternalSecret (AWS Secrets Manager via External Secrets Operator), ServiceMonitor (Prometheus), startup/liveness/readiness probes, PSS-restricted namespace template, NOTES.txt for post-install help |

Each archetype is a working Helm chart with sane defaults in `values.yaml`. Production-shape — uses External Secrets Operator pattern, ALB ingress, kube-prometheus-stack ServiceMonitor. Override what you need.

## How the skill uses these (EKS mode)

`/localcraft eks` Phase 6 locates a chart in this order:
1. Target repo's local `helm/` or `charts/` directory
2. Target repo's origin `feature/helm` branch (via `gh api`)
3. Target repo's origin `helm/production` branch (via `gh api`)
4. **Fallback**: copy `samples/helm/<archetype>/` from this dir into `.localcraft/k8s/chart/` and parameterize Chart.yaml `name` to the target repo name

If none of 1-4 work, the skill prints a note and skips chart generation (won't fabricate one).

## Adding an archetype

Drop a complete chart under `samples/helm/<archetype>/`:
```
samples/helm/<archetype>/
  Chart.yaml         # name: <archetype>, description, version, appVersion
  values.yaml        # production-shape defaults
  templates/
    deployment.yaml
    service.yaml
    ... etc.
```

Use Helm template helpers (`{{ include "<archetype>.fullname" . }}`) in templates/_helpers.tpl so renaming via `Chart.Name` propagates everywhere.

## Org overrides

Drop `samples/helm/<archetype>.user/` (a sibling sister dir, not a file) to override the bundled chart for your org without forking. Same convention as `samples/compose/<svc>.user.yml` and `samples/docker/<stack>.user.Dockerfile`.

## Archetypes not yet bundled (PRs welcome)

- `worker/` — Deployment-only (no Service, no Ingress) for Celery/Sidekiq/BullMQ consumers
- `cron/` — CronJob for scheduled tasks
- `migration-job/` — One-shot Job for database migrations (different from inline init container)
- `database/` — StatefulSet wrapper for self-hosted DB (rare; usually use Bitnami chart)

Until these land, the skill falls through to the "no chart available" path for those archetypes.
