# localcraft

A Claude Code skill that bootstraps a complete local dev setup for any repo: detects the stack, picks matching mock dependencies (Postgres / Redis / Kafka / LocalStack / Prometheus+Grafana / Mailhog / …), generates a working `docker-compose.local.yml` + `.env.local` with sample-secret values, and prints the run command.

No binary, no install step beyond a symlink. The "detector" is Claude reading your repo via the skill instructions; the "synthesizer" is Claude stitching sample compose snippets from `samples/`.

## Install

```sh
git clone <this repo> ~/code/localcraft
ln -s ~/code/localcraft ~/.claude/skills/localcraft
```

Open any repo in Claude Code and type `/localcraft`.

## Use

```
/localcraft                # detect + generate .localcraft/ + print run command
/localcraft detect         # print detected stack JSON; write nothing
/localcraft refresh        # regenerate, overwriting existing .localcraft/
/localcraft add metrics    # add prometheus+grafana to an existing setup
```

Then in the target repo:

```sh
cd .localcraft && docker compose -f docker-compose.local.yml --env-file .env.local up
```

## Supported stacks

Detection covers manifests for Python, Node/TS, Go, Java/Kotlin, Ruby, Rust, .NET, PHP, Elixir, and their major frameworks (Django, Flask, FastAPI, Express, NestJS, Next, Spring Boot, Rails, Laravel, Phoenix, …). It maps known driver/SDK packages to mock services: Postgres, MySQL, Redis, MongoDB, Elasticsearch, Kafka, RabbitMQ, AWS (via LocalStack), Prometheus metrics, Mailhog SMTP.

The full mapping lives in `SKILL.md` — that file IS the skill.

## Extending

Add a new mock service:

1. Drop `samples/compose/<service>.yml` (one service per file, self-contained — no env vars from outside the file).
2. Add the row to the service-detection table in `SKILL.md` (which dep names map to this service, per language).
3. Add env-var hints to the value table in `SKILL.md` if the service introduces conventional env names.

Override a default for your org:

- Create `samples/compose/<service>.user.yml` — it takes precedence over `<service>.yml` whenever that service is detected. Useful for swapping in an image with seeds baked in, custom ports, or extra sidecars.

Drop in reference Helm charts or Dockerfiles:

- `samples/helm/<archetype>/` — full chart skeleton (`Chart.yaml`, `values.yaml`, `templates/`)
- `samples/docker/<stack>.Dockerfile` — production-ready multi-stage build per stack

See the README in each directory for the expected layout.

## Files

```
SKILL.md                          # the entire detector + synthesizer (Claude reads this)
samples/compose/*.yml             # one service per file; merged into docker-compose.local.yml
samples/env/*.env                 # reference env files per framework
samples/helm/                     # drop reference charts here
samples/docker/                   # drop reference Dockerfiles here
```
