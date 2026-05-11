Drop your org's reference Helm chart(s) here as named subdirectories — for example:

```
samples/helm/web-service/
  Chart.yaml
  values.yaml
  templates/
    deployment.yaml
    service.yaml
    ingress.yaml
```

When `/localcraft` runs against a repo that has its own `helm/` directory, the skill will not auto-emit helm output in v0, but it will note in the summary that these references exist. Ask "use the web-service helm reference" as a follow-up and the skill will scaffold a chart matching the detected stack.

Naming: use the service archetype as the directory name (`web-service`, `worker`, `cron`, `migration-job`). The skill matches by archetype, not by exact name.
