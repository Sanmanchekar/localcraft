---
name: localcraft
description: Generate a complete local dev setup (Dockerfile.dev + docker-compose.dev.yml + .env.dev + Makefile.dev + mocked external deps; optionally an EKS/Helm package via the `eks` keyword) for the current repo. Detects the stack — language, framework, databases, caches, queues, cloud SDKs, metrics/logs/traces, env vars — by scanning manifests, framework config modules, source code, Dockerfile, helm/, k8s/. Stitches matching sample compose snippets from the bundled samples/ library, generates a Makefile.dev with `up`/`down`/`logs`/`migrate`/`seed`/`shell` targets, scrubs real-looking secrets from .env*.example before reuse in .env.dev, and prints one command to start everything. Use when the user types /localcraft, asks to "set up local dev", "spin up dependencies", "mock the database/redis/aws", "make this repo runnable locally", "bootstrap this repo", wants metrics/grafana/loki/tempo mocked, or wants a k3s/EKS/helm deployment of the dev stack (says "eks", "k8s", "rancher", "helm").
---

# localcraft

Generate a runnable local dev setup for the current repo:
**detect stack → pick matching samples → write `.localcraft/` → print run command.**

## Modes

Default action: full **init** flow (Phase 1 → 5 below).

If the user message contains:
- `detect`, `what stack`, `analyze` → run **Phase 1 only**, print the stack JSON, do NOT write files
- `refresh`, `regenerate`, `redo`, `force` → run init, **overwrite** any existing `.localcraft/`
- `add metrics`, `add grafana` → load existing `.localcraft/docker-compose.dev.yml`, add the prometheus-grafana sample, write back
- `eks`, `k8s`, `kubernetes`, `rancher`, `helm` → run init (Phases 1–5) AND **Phase 6** (EKS/Helm mode below) to also emit a k3s/EKS-style deployment package under `.localcraft/k8s/`

## Phase 1 — Detect

Walk the current working directory. **Skip** these directories everywhere: `.git/`, `node_modules/`, `__pycache__/`, `.venv/`, `venv/`, `dist/`, `build/`, `.next/`, `target/`, `vendor/`, `.gradle/`, `.idea/`, `.vscode/`, `coverage/`.

### 1a. Languages & frameworks (read manifests)

| Manifest file | Language | Parse | Frameworks to detect |
|---|---|---|---|
| `requirements.txt`, `pyproject.toml`, `Pipfile`, `setup.py` | Python | dep names | django, flask, fastapi, celery, sanic, tornado, aiohttp |
| `package.json` | Node | `dependencies` + `devDependencies` keys | express, nestjs, next, fastify, koa, hapi, remix, nuxt |
| `go.mod` | Go | `require (...)` block | gin, echo, fiber, chi, gorilla |
| `pom.xml` | Java | `<artifactId>` of `<dependency>` | spring-boot, micronaut, quarkus, dropwizard, jersey |
| `build.gradle`, `build.gradle.kts` | Java/Kotlin | `implementation '...'` lines | spring-boot, micronaut, ktor |
| `Gemfile` | Ruby | `gem '...'` lines | rails, sinatra, hanami |
| `Cargo.toml` | Rust | `[dependencies]` table | actix-web, axum, rocket, warp |
| `*.csproj`, `*.sln` | .NET | `<PackageReference Include="...">` | aspnetcore, blazor |
| `composer.json` | PHP | `require` keys | laravel, symfony, slim |
| `mix.exs` | Elixir | `deps/0` function | phoenix |

Use `Read` for the manifest, then either parse with simple shell tools (`grep`, `jq`) or read & inspect line-by-line. For `package.json` use `jq -r '.dependencies, .devDependencies | keys[]' package.json 2>/dev/null` (and same with `.devDependencies` separately if needed).

### 1b. Services (match deps against this table)

A repo can register multiple services across multiple languages — just collect all matches.

| Service | Python | Node | Go | Java | Ruby | Rust | .NET |
|---|---|---|---|---|---|---|---|
| **postgres** | psycopg2*, psycopg, asyncpg | pg, postgres, postgresql | lib/pq, jackc/pgx | postgresql | pg | tokio-postgres, sqlx (postgres feature) | Npgsql |
| **mysql** | pymysql, mysqlclient, aiomysql | mysql, mysql2 | go-sql-driver/mysql | mysql-connector-java | mysql2 | mysql_async, sqlx (mysql feature) | MySql.Data |
| **redis** | redis, aioredis, django-redis | redis, ioredis | go-redis/redis, redis/go-redis | jedis, lettuce-core | redis, redis-rb | redis | StackExchange.Redis |
| **mongodb** | pymongo, motor | mongoose, mongodb | mongo-driver | mongo-java-driver | mongo, mongoid | mongodb | MongoDB.Driver |
| **elasticsearch** | elasticsearch, opensearch-py | @elastic/elasticsearch, @opensearch-project/* | elastic/go-elasticsearch | elasticsearch-rest-client | elasticsearch-ruby | elasticsearch | NEST, Elastic.Clients |
| **kafka** | kafka-python, confluent-kafka, aiokafka | kafkajs | sarama, segmentio/kafka-go | kafka-clients | ruby-kafka | rdkafka | Confluent.Kafka |
| **rabbitmq** | pika, aio-pika | amqplib | streadway/amqp | amqp-client | bunny | lapin | RabbitMQ.Client |
| **aws** | boto3, aiobotocore | aws-sdk, @aws-sdk/* | aws-sdk-go, aws-sdk-go-v2 | software.amazon.awssdk, aws-java-sdk | aws-sdk | aws-sdk-rust | AWSSDK.* |
| **metrics** (prometheus) | prometheus_client, prometheus-flask-exporter | prom-client | prometheus/client_golang | micrometer-registry-prometheus | prometheus-client | prometheus | prometheus-net |
| **logs** (loki) | python-logging-loki, logging-loki | pino-loki, winston-loki | grafana/loki-client-go | loki-logback-appender | loki-logger | tracing-loki | NLog.Targets.Loki |
| **traces** (tempo / otlp) | opentelemetry-exporter-otlp, opentelemetry-instrumentation | @opentelemetry/exporter-trace-otlp-* | go.opentelemetry.io/otel/exporters/otlp | io.opentelemetry:opentelemetry-exporter-otlp | opentelemetry-exporter-otlp | opentelemetry-otlp | OpenTelemetry.Exporter.OpenTelemetryProtocol |

**Auto-include rules**:
- If `aws` detected → include the `localstack` sample
- If `metrics` detected → include the `prometheus-grafana` sample
- If `logs` detected → include the `loki` sample (auto-add Grafana too if not already from metrics)
- If `traces` detected → include the `tempo` sample
- If any framework that typically sends email is detected (django, rails, laravel, spring) → include the `mailhog` sample

### 1c. Env vars — repo-driven discovery (no hardcoded conventions)

The env var list MUST come from the target repo. **Do not invent names. Do not impose conventions** (no assuming `DB_HOST` exists, no assuming `POSTGRES_HOST` is the right key, no assuming the repo uses any specific prefix). The skill mirrors whatever the repo declares.

Combine results from these sources in order — later sources fill gaps left by earlier ones, but earlier sources provide the **default values** that Phase 4 may reuse.

**1. `.env*.example` family** (authoritative when present): read every file matching `.env.example`, `.env.sample`, `.env.template`, `.env.*.example` (e.g., `.env.db.example`, `.env.local.example`) at the repo root. Parse each non-empty, non-comment `KEY=value` line. Keys are taken verbatim. Values are starting defaults (Phase 4 may scrub them).

**2. Framework config modules** (centralize env access — read these BEFORE wide-grep):

| Stack | Files to read |
|---|---|
| Django | `settings.py`, `config/settings.py`, `config/settings/*.py`, `<project>/settings.py` |
| Flask | `config.py`, `app/config.py`, `instance/config.py` |
| FastAPI / Pydantic Settings | files containing `BaseSettings` or `SettingsConfigDict` |
| Generic Python | `config.py`, `settings.py`, `app/core/config.py`, `core/config.py` |
| Node / TS | `src/config.{ts,js}`, `config/*.{ts,js}`, files matching `**/config{,.*}.{ts,js,mjs}` |
| Spring Boot | `application.yml`, `application.properties`, `application-*.yml` — collect `${ENV_VAR}` and `${ENV_VAR:default}` placeholders |
| Go | `internal/config/*.go`, `pkg/config/*.go`, `config/config.go` |
| Rails | `config/application.rb`, `config/environments/*.rb` (skip `*.yml.enc`) |
| .NET | `appsettings.json`, `appsettings.*.json` (any `IConfiguration` keys) |
| PHP / Laravel | `config/*.php`, `bootstrap/app.php` (`env('X', 'default')` calls) |
| Elixir / Phoenix | `config/*.exs` (`System.get_env("X")` calls) |

Reading the canonical config module also tells you which env var has a **framework default** baked in (e.g., Django's `DEBUG=False` if not set). Capture those defaults — they're better starting values than dev-generic guesses.

**3. Wide source scan** (catch one-off references not in config modules): scan source files (extensions `.py .js .ts .tsx .jsx .go .java .kt .rb .rs .cs .php .ex .exs`) for:
- `os.environ["X"]`, `os.environ.get("X")`, `os.getenv("X")` (Python)
- `process.env.X`, `process.env["X"]` (Node/TS)
- `os.Getenv("X")` (Go)
- `System.getenv("X")`, `@Value("${X}")`, `@Value("${X:default}")` (Java)
- `ENV["X"]`, `ENV.fetch("X")` (Ruby)
- `std::env::var("X")` (Rust)
- `Environment.GetEnvironmentVariable("X")` (.NET)
- `getenv('X')`, `env('X')` (PHP / Laravel)
- `System.get_env("X")` (Elixir)

Use `Grep` with a single combined regex across the appropriate glob. Cap implicitly through Grep's result limits.

The final env var set is the **union** of all three sources. In the stack object, annotate each var with its source (`example_file`, `config_module`, `source_grep`) — Phase 4 uses this to pick the right default.

### 1d. Ops files (presence flags only — do NOT modify)

| Path pattern | Flag |
|---|---|
| `Dockerfile`, `Dockerfile.*`, `docker/` | `has_dockerfile` |
| `helm/`, `charts/` | `has_helm` |
| `k8s/`, `kustomization.yaml`, `kustomize/`, `manifests/` | `has_k8s` |
| `terraform/`, `*.tf` | `has_terraform` |
| `Makefile` | `has_makefile` |

### 1e. Stack object

Build this in your head (no need to write to disk):

```json
{
  "languages": ["python"],
  "frameworks": ["django", "celery"],
  "services": ["postgres", "redis", "aws", "metrics"],
  "env_vars": ["DATABASE_URL", "REDIS_URL", "SECRET_KEY", "AWS_ACCESS_KEY_ID", "..."],
  "has_dockerfile": true,
  "has_helm": false,
  "has_k8s": false,
  "has_terraform": false,
  "notes": ["env vars from .env.example"]
}
```

If mode == detect: print this JSON in a fenced block and **stop**.

## Phase 2 — Pick samples

The samples library is at the skill's own directory: `~/.claude/skills/localcraft/samples/`.

| Detected service | Sample file (under `samples/compose/`) |
|---|---|
| postgres | `postgres.yml` |
| mysql | `mysql.yml` |
| redis | `redis.yml` |
| mongodb | `mongodb.yml` |
| elasticsearch | `elasticsearch.yml` |
| kafka | `kafka.yml` |
| rabbitmq | `rabbitmq.yml` |
| aws | `localstack.yml` |
| metrics | `prometheus-grafana.yml` |
| logs | `loki.yml` (+ Grafana from prometheus-grafana sample if not already picked) |
| traces | `tempo.yml` (writes `.localcraft/tempo/tempo.yaml` config file like prometheus does) |
| (auto, conditions in 1b) | `mailhog.yml` |

**User overrides**: for any service `S`, if `samples/compose/S.user.yml` exists, **use that instead** of `S.yml`. This is how the user customizes for their org's conventions (e.g., a postgres image with their seed scripts baked in).

If the user has populated `samples/helm/` or `samples/docker/` with reference files: do NOT auto-emit helm/Dockerfile output in this v0. Mention in the final summary that these references exist and the user can ask "use the helm reference" as a follow-up.

## Phase 3 — Merge into one compose file

Read each picked sample with `Read` and merge:
- All `services:` blocks concatenated (each sample uses unique service names so collisions shouldn't happen)
- All `volumes:` blocks merged (deduplicate by key)
- All `networks:` blocks merged (deduplicate by key) — if none of the samples define `networks:`, omit the block entirely

Top of the merged file:
```yaml
# generated by /localcraft — edit freely
# rerun /localcraft refresh to regenerate
```

If `prometheus-grafana` is in the picked samples, ALSO write `.localcraft/prometheus/prometheus.yml` — see Phase 5.

If `tempo` is in the picked samples, ALSO write `.localcraft/tempo/tempo.yaml` — see Phase 5. (Tempo bind-mounts a local config file just like prometheus does.)

If `loki` is in the picked samples, no extra config file is needed — the bundled loki image runs with its built-in local-config.

## Phase 3b — Optional: migrations & seed init services

If the target repo has a migration tool, add an `init` service that runs migrations after the DB healthcheck passes. If seeds are detected, add a `seed` service after `init`. Detection is **repo-driven** — no framework is assumed; only signals from files in the target repo matter.

### Migration tool detection (first match wins)

| Target repo has | Tool | Init command |
|---|---|---|
| `alembic.ini` or `alembic/` dir | Alembic | `alembic upgrade head` |
| `manage.py` AND django in deps | Django ORM | `python manage.py migrate --noinput` |
| `bin/rails` OR rails gem | Rails | `bundle exec rails db:migrate` |
| `prisma/schema.prisma` | Prisma | `npx prisma migrate deploy` |
| `src/main/resources/db/migration/V*.sql` | Flyway | use `flyway/flyway` image (no app build needed) |
| `src/main/resources/db/changelog/` | Liquibase | use `liquibase/liquibase` image |
| **Go**: `migrations/*.sql` AND any of {`golang-migrate/migrate` in `go.mod`/`go.sum`, `database/migrations` package import, a `Makefile` target named `migrate`/`migrate-up`} | golang-migrate | `migrate -path migrations -database $DATABASE_URL up` |
| **Go**: `migrations/*.sql` AND `goose` in `go.mod`/`go.sum` | goose | `goose up` |
| **Node**: `knexfile.{js,ts}` or `knex/migrations/` OR `knex` in `package.json` deps | Knex | `npx knex migrate:latest` |
| **Node**: `package.json` has `sequelize` dep AND `migrations/` dir OR `sequelize.config.{js,json}` | Sequelize | `npx sequelize-cli db:migrate` |
| **Node**: `package.json` has `typeorm` dep AND (`ormconfig.*`, `typeorm.config.{ts,js}`, or `migrations/` dir) | TypeORM | `npx typeorm migration:run -d <data-source-path>` |
| **Node**: `package.json` has `mikro-orm` dep AND `migrations/` dir | MikroORM | `npx mikro-orm migration:up` |
| `migrations/*.sql` only (no tool detected after the above) | raw SQL | concatenate and pipe to db client via a temp container |

**Migrations-dir without a recognized tool**: if `migrations/` (or `db/migrate/`) exists but **none** of the above detect a tool, note this explicitly in the Phase 5 summary as a `MIGRATION_DETECTION_GAP` rather than silently skipping. The skill should print: `"migrations/ dir found but no migration tool detected (looked for: alembic, django, rails, prisma, flyway, liquibase, golang-migrate, goose, knex, sequelize, typeorm, mikro-orm). Specify manually if you have a custom runner."`

If no tool AND no migrations dir is detected, skip this phase silently. **Never guess.**

### Init service shape (requires `Dockerfile` at the repo root)

```yaml
services:
  init:
    build:
      context: ..
      dockerfile: Dockerfile
    command: ["alembic", "upgrade", "head"]    # ← from the detection table
    env_file: .env.dev
    depends_on:
      <db-service>:
        condition: service_healthy
    restart: "no"
```

If the repo has no Dockerfile: **skip the init service**. Instead, print the migration command in Phase 5's summary so the user can run it manually. Do not invent a generic toolchain image — too fragile across stacks.

### Seed detection (only if init was added)

| Target repo has | Seed command |
|---|---|
| `fixtures/*.json` + Django | `python manage.py loaddata fixtures/*.json` |
| `db/seeds.rb` + Rails | `bundle exec rails db:seed` |
| `seeds/*.sql` or `seed.sql` at root | concatenate and pipe to db client |
| `prisma/seed.{ts,js}` OR `"prisma":{"seed":...}` in package.json | `npx prisma db seed` |
| `knex/seeds/` | `npx knex seed:run` |
| `cmd/seed/main.go` | `go run cmd/seed/main.go` |

Seed service shape: same as init, with `depends_on: { init: { condition: service_completed_successfully } }`.

### Hard rules

- No DB sample in the compose → no init service (nothing to migrate against)
- `restart: "no"` is mandatory (init runs once per `up`)
- Never include destructive migration commands: no `db:reset`, no `migrate:fresh`, no `db:drop`. The skill only adds forward-migrate commands

## Phase 4 — Generate `.env.dev`

For each env var collected in Phase 1c, assign a value using these rules in order:

1. **Framework default from a config module** (Phase 1c source 2): if the canonical config module had a literal default (`os.getenv("DEBUG", "True")`, `${PORT:8080}`, etc.), reuse it.
2. **Value from `.env*.example`** (Phase 1c source 1): if the source line had a value, reuse it **after the safety scrub below**. Skip if the value matches any of these patterns (all case-insensitive):
   - Empty / whitespace only
   - Surrounded by angle brackets: `<...>`
   - Surrounded by template syntax: `${...}`, `%...%`, `{{...}}`
   - **Contains** any of these substrings: `sample`, `placeholder`, `replace`, `your-`, `your_`, `changeme`, `change_me`, `dummy`, `fake`, `example` — this catches `SG.sample_sendgrid_api_key_replace_with_actual` and similar
   - Exact matches: `xxx`, `xxxx`, `todo`, `fixme`, `tbd`, `null`, `none`
3. **Hint table** (first substring match against the var name wins):

**Safety scrub — applied to every value from source 2 before reuse:**

Treat `.env*.example` files as references for the **shape** of variables, not as safe local values. Commit accidents are common — real prod credentials sometimes end up in `.env.example`. Replace these patterns with the hint-table dev placeholder instead of copying verbatim:

- **URL scheme remap** (applied first — independent of key name): if the value is a URL with a known scheme AND the host is `localhost` / `127.0.0.1` / `0.0.0.0` / a placeholder → rewrite the host to the matching docker service name. This catches `CELERY_RESULT_BACKEND=redis://localhost:6379` and similar regardless of key naming.
  | Scheme | Replace host with | Default port |
  |---|---|---|
  | `redis://`, `rediss://` | `redis` | 6379 |
  | `mysql://` | `mysql` | 3306 |
  | `postgres://`, `postgresql://` | `postgres` | 5432 |
  | `mongodb://`, `mongodb+srv://` | `mongodb` | 27017 |
  | `amqp://`, `amqps://` | `rabbitmq` | 5672 |
- **Bare `host:port` broker endpoints** (no scheme — applied second): values matching `<hostname>:<port>` where the port is a well-known service port → remap host to the matching docker service name. Catches `KAFKA_BROKER=kafka.graydev.infra:9092` and `ELASTICSEARCH_HOST=es.internal:9200` patterns. Port-to-service map:
  | Port | Replace host with |
  |---|---|
  | 9092 | `kafka` |
  | 9200 | `elasticsearch` |
  | 27017 | `mongodb` |
  | 6379 | `redis` |
  | 3306 | `mysql` |
  | 5432 | `postgres` |
  | 5672 | `rabbitmq` |
- **Real-looking hostnames** (applied third — DROP the `://` requirement): if the value contains `.amazonaws.com`, `.azure.com`, `.gcp.io`, `.cloud.com`, `.internal`, or any FQDN with ≥ 3 dot-separated segments (and isn't `localhost` / `127.0.0.1` / `0.0.0.0` / a Docker-network service name from this skill's samples) → replace with the matching local mock hostname based on key name (`*_HOST` ending → `mysql`/`postgres`/`mongodb` per detected DB; `*_URL` ending → `http://localhost`). For outbound third-party URLs (`https://...`) where no local mock applies, leave value and prepend a `# TODO: real-looking URL` comment line.
- **Long random-looking secrets** (catches the common case of committed real passwords): value length ≥ 16 AND **(a)** contains a mix of letters + digits + at least one symbol, OR **(b)** is 32/40/64 hex characters (HMAC-shaped signing secrets, SHA-1/SHA-256 digests), OR **(c)** is 24+ char base64 (`[A-Za-z0-9+/=]{24,}`). Replace with `dev-<keyname-lower>`.
- **Real-looking IPs**: any value matching an IPv4 pattern that isn't `127.0.0.1`, `0.0.0.0`, or a private range (10.x, 172.16–31.x, 192.168.x) → replace.
- **Known token shapes**: `xox[bp]-...` (Slack bot/user token), `xoxs-...` (Slack signing), `sk-...` (Stripe/OpenAI), `ghp_...` (GitHub PAT), `eyJ...` (JWT), `AKIA...` / `ASIA...` (AWS access keys), `arn:aws:...` (AWS ARNs), `SG\.[A-Za-z0-9._-]+` (SendGrid), `rzp_(live|test)_...` (Razorpay), `whsec_...` (Stripe webhook), `pk_(live|test)_...` (publishable Stripe keys) → replace with placeholder.

**Detection order matters**: apply URL scheme remap → bare host:port remap → real-FQDN scrub → token shapes → long-random-secret → IP scrub. First match wins per value. If none match, keep as-is.

In the printed summary (Phase 5), note how many values were scrubbed so the user is aware their `.env.example` may need a separate review.

Hint table (first substring match against the var name wins):

| Var name contains | Sample value |
|---|---|
| `DATABASE_URL` | `postgres://localcraft:localcraft@postgres:5432/localcraft` (use mysql URL if mysql detected and postgres not) |
| `POSTGRES_HOST`, `PG_HOST` | `postgres` |
| `POSTGRES_USER`, `PG_USER` | `localcraft` |
| `POSTGRES_PASSWORD`, `PG_PASSWORD` | `localcraft` |
| `POSTGRES_DB`, `PG_DATABASE` | `localcraft` |
| `MYSQL_HOST` | `mysql` |
| `MYSQL_USER` | `localcraft` |
| `MYSQL_PASSWORD` | `localcraft` |
| `MYSQL_DATABASE` | `localcraft` |
| `DB_HOST` | `postgres` if postgres detected, else `mysql` if mysql detected, else `localhost` |
| `DB_PORT` | `5432` if postgres, else `3306` if mysql |
| `DB_NAME`, `DB_USER`, `DB_PASS*` | `localcraft` |
| `REDIS_URL` | `redis://redis:6379/0` |
| `REDIS_HOST` | `redis` |
| `REDIS_PORT` | `6379` |
| `MONGO_URL`, `MONGODB_URL` | `mongodb://mongodb:27017/localcraft` |
| `ELASTICSEARCH_URL`, `ES_URL` | `http://elasticsearch:9200` |
| `KAFKA_BROKERS`, `KAFKA_BOOTSTRAP_SERVERS` | `kafka:9092` |
| `RABBITMQ_URL`, `AMQP_URL` | `amqp://localcraft:localcraft@rabbitmq:5672/` |
| `AWS_ACCESS_KEY_ID` | `test` |
| `AWS_SECRET_ACCESS_KEY` | `test` |
| `AWS_REGION`, `AWS_DEFAULT_REGION` | `us-east-1` |
| `AWS_ENDPOINT_URL`, `S3_ENDPOINT`, `*_ENDPOINT_URL` | `http://localstack:4566` |
| `S3_BUCKET` | `localcraft-bucket` |
| `SQS_URL` | `http://localstack:4566/000000000000/localcraft-queue` |
| `SMTP_HOST`, `EMAIL_HOST`, `MAIL_HOST` | `mailhog` |
| `SMTP_PORT`, `EMAIL_PORT`, `MAIL_PORT` | `1025` |
| `SMTP_USER`, `EMAIL_USER` | `` (empty — mailhog needs no auth) |
| `SECRET_KEY`, `SECRET_KEY_BASE` | `dev-secret-do-not-use-in-prod` |
| `JWT_SECRET`, `JWT_*KEY*` | `dev-jwt-secret` |
| `*PASSWORD*` | `dev-password` |
| `*_API_KEY`, `*_TOKEN` | `dev-{varname-lowercase}` |
| `DEBUG` | `True` |
| `ALLOWED_HOSTS` | `*` |
| `CORS_*` | `*` |
| `LOG_LEVEL` | `DEBUG` |
| `PORT` | `8000` (Python), `3000` (Node), `8080` (Go/Java) — pick by detected language |
| `NODE_ENV` | `development` |
| `RAILS_ENV`, `RACK_ENV` | `development` |
| `SPRING_PROFILES_ACTIVE` | `local` |
| `DJANGO_SETTINGS_MODULE` | leave value empty with comment `# TODO: set explicitly` |
| (no match) | `dev-{varname-lowercase}` |

Top of `.env.dev`:
```
# generated by localcraft — sample-only secrets, NOT for production
# rotate any value before sharing this file outside your machine
```

## Phase 5 — Write & print

**Naming convention**: every output file uses a `.dev` suffix and lives under `<repo>/.localcraft/`. The skill **never** writes to the repo root and **never** modifies existing files (only appends one line to `.gitignore`). This way the developer's existing `Dockerfile`, `docker-compose.yml`, `Makefile`, etc. are untouched and the dev-only files clearly self-identify.

Output dir: `<repo>/.localcraft/` (create with `mkdir -p`).

Files to write (compose mode — EKS mode adds more, see Phase 6):

| File | When | Content |
|---|---|---|
| `.localcraft/docker-compose.dev.yml` | always | merged compose from Phase 3 |
| `.localcraft/.env.dev` | always | env vars from Phase 4 |
| `.localcraft/Dockerfile.dev` | only if target repo has **no** `Dockerfile` at root AND a buildable stack was detected | per-stack multi-stage Dockerfile, see "Dockerfile.dev generation" below |
| `.localcraft/Makefile.dev` | always | runnable targets, see "Makefile.dev generation" below |
| `.localcraft/README.dev.md` | always | quickstart + manual-command reference |
| `.localcraft/prometheus/prometheus.yml` | only if metrics sample picked | scrape config (default `host.docker.internal:8000`) |
| `.localcraft/tempo/tempo.yaml` | only if traces sample picked | minimal Tempo config (OTLP receiver on 4317/4318, local storage) |

### Dockerfile.dev generation

Generate only if the target repo does NOT already have a `Dockerfile` at root. **Auto-discover the runtime version from multiple signals** — do NOT rely only on the manifest:

| Stack | Version-detection chain (first match wins) | Fallback |
|---|---|---|
| Python | `.python-version` → `runtime.txt` → `pyproject.toml` `[project] requires-python` → `pyproject.toml` `[tool.poetry.dependencies] python` → `Pipfile` `[requires] python_version` → `setup.py` `python_requires=` → `setup.cfg` `python_requires` | `3.11` |
| Node / TS | `.nvmrc` → `package.json` `engines.node` → `Dockerfile`-style FROM hints in CI config | `20` |
| Go | `go.mod` `go <version>` directive → `go.mod` `toolchain go<version>` → `.go-version` | `1.22` |
| Java / Kotlin | `pom.xml` `<maven.compiler.source>` → `pom.xml` `<java.version>` → `build.gradle` `sourceCompatibility` → `.java-version` | `21` |
| Ruby | `.ruby-version` → `Gemfile` `ruby '...'` | `3.3` |
| Rust | `rust-toolchain.toml` → `Cargo.toml` `rust-version` | `1.78` |
| .NET | `global.json` `sdk.version` → `<TargetFramework>` in `.csproj` | `8.0` |
| PHP | `composer.json` `require.php` | `8.3` |
| Elixir | `.tool-versions` → `mix.exs` `elixir:` | `1.16` |

**Template selection — prefer the curated sample over the inline fallback.**

For each detected stack, look for a matching template in the skill's bundled library at `~/.claude/skills/localcraft/samples/docker/`. If found, copy that file to `<repo>/.localcraft/Dockerfile.dev` after substituting placeholders. If not found, fall back to the inline template shown later in this section.

| Detected stack | Preferred sample (check first) | Placeholders to substitute |
|---|---|---|
| Python + Django (`manage.py` + django dep) | `python-django.Dockerfile` | `{PYTHON_VERSION}`, `{APP_PORT}`, `{EXTRA_APT_BUILD}`, `{EXTRA_APT_RUNTIME}` |
| Python + FastAPI (fastapi dep, no `manage.py`) | `python-fastapi.Dockerfile` | `{PYTHON_VERSION}`, `{APP_PORT}`, `{APP_MODULE}`, `{EXTRA_APT_BUILD}`, `{EXTRA_APT_RUNTIME}` |
| Go (`go.mod` present) | `go.Dockerfile` | `{GO_VERSION}`, `{APP_NAME}`, `{APP_PORT}`, `{ENTRYPOINT_PKG}` |
| Node services (`package.json` with non-frontend deps) | `node.Dockerfile` | `{NODE_VERSION}`, `{APP_NAME}`, `{APP_PORT}`, `{DEV_CMD}` |

**User overrides**: if `samples/docker/<stack>.user.Dockerfile` exists, prefer it over the bundled `<stack>.Dockerfile` (same convention as `samples/compose/<svc>.user.yml`). This is how an org swaps in their own base image, internal CA, audit log paths, etc.

**How to fill the placeholders:**
- `{PYTHON_VERSION}` / `{GO_VERSION}` / `{NODE_VERSION}` — from the version-detection chain in the table above
- `{APP_NAME}` — repo dir name (e.g. `gqinstitute_backend`)
- `{APP_PORT}` — detected port (see below) or per-language default (Python 8000, Go 8080, Node 3000)
- `{APP_MODULE}` — for FastAPI: scan source for `FastAPI()` constructor location → emit `<module>:<varname>` (e.g. `main:app`, `app.main:app`); fall back to `main:app`
- `{ENTRYPOINT_PKG}` — for Go: try `./cmd/<repo-name>` → `./cmd/server` → `./cmd/main` → `.`; first that exists wins
- `{DEV_CMD}` — for Node: read `package.json.scripts.dev` → `scripts.start`; emit as JSON-array CMD form (e.g. `["npm", "run", "dev"]`); fall back to `["node", "index.js"]`
- `{EXTRA_APT_BUILD}` / `{EXTRA_APT_RUNTIME}` — derived from detected Python C-extension deps:
  | Detected dep | Add to `EXTRA_APT_BUILD` | Add to `EXTRA_APT_RUNTIME` |
  |---|---|---|
  | `mysqlclient` | `default-libmysqlclient-dev pkg-config` | `default-libmysqlclient-dev` |
  | `psycopg2` (NOT `-binary`) | `libpq-dev` | `libpq5` |
  | `cryptography` | `libssl-dev libffi-dev` | (none) |
  | `lxml` | `libxml2-dev libxslt-dev` | `libxml2 libxslt1.1` |
  | `pillow` | `libjpeg-dev zlib1g-dev` | `libjpeg62-turbo zlib1g` |
  | `pycurl` | `libcurl4-openssl-dev libssl-dev` | `libcurl4` |
  Combine with spaces. Empty if no native deps detected.

**Use the inline template (below) only when** no sample file exists for the detected stack — currently always for Java/Spring, Ruby, Rust, .NET, PHP, Elixir; for Python/Node/Go it's the rare case of a missing sample file.

---

Inline fallback templates per stack (multi-stage where applicable, substitute `{VERSION}` from detection chain):

```dockerfile
# Python (Django/Flask/FastAPI/generic)
FROM python:{VERSION}-slim AS builder
WORKDIR /app
COPY requirements*.txt pyproject.toml* poetry.lock* Pipfile* ./
RUN pip install --no-cache-dir --user -r requirements.txt 2>/dev/null \
 || pip install --no-cache-dir --user .

FROM python:{VERSION}-slim
WORKDIR /app
COPY --from=builder /root/.local /root/.local
ENV PATH=/root/.local/bin:$PATH PYTHONUNBUFFERED=1
COPY . .
EXPOSE {DETECTED_PORT_OR_8000}
CMD ["{DETECTED_CMD}"]
```

`{DETECTED_CMD}` rules:
- Django (`manage.py` + django in deps) → `python manage.py runserver 0.0.0.0:8000`
- FastAPI (uvicorn/hypercorn in deps + `main.py` or `app.py`) → `uvicorn main:app --host 0.0.0.0 --port 8000 --reload`
- Flask (`flask` in deps + `app.py`) → `flask --app app run --host 0.0.0.0 --port 5000`
- Celery worker (no web framework, just celery) → `celery -A <module> worker --loglevel=info`
- Generic Python → `python -m <package>` if `__main__` exists, else `python main.py`

```dockerfile
# Node / TS (Express/Nest/Next/etc.)
FROM node:{VERSION}-alpine AS builder
WORKDIR /app
COPY package*.json yarn.lock* pnpm-lock.yaml* ./
RUN npm ci 2>/dev/null || yarn install --frozen-lockfile 2>/dev/null || pnpm install --frozen-lockfile
COPY . .
RUN npm run build 2>/dev/null || true

FROM node:{VERSION}-alpine
WORKDIR /app
COPY --from=builder /app .
ENV NODE_ENV=development
EXPOSE {DETECTED_PORT_OR_3000}
CMD ["{DETECTED_CMD}"]
```

`{DETECTED_CMD}`: read `package.json.scripts.dev` → `scripts.start` → fallback `node index.js`.

```dockerfile
# Go
FROM golang:{VERSION}-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o /out/app {DETECTED_ENTRYPOINT}

FROM alpine:latest
RUN apk add --no-cache ca-certificates
WORKDIR /app
COPY --from=builder /out/app .
EXPOSE {DETECTED_PORT_OR_8080}
CMD ["./app"]
```

`{DETECTED_ENTRYPOINT}` chain: `./cmd/<repo-name>` → `./cmd/server` → `./cmd/main` → `.`

```dockerfile
# Java (Spring Boot via Maven or Gradle)
FROM eclipse-temurin:{VERSION}-jdk AS builder
WORKDIR /app
COPY pom.xml* gradlew* build.gradle* settings.gradle* ./
COPY .mvn .mvn 2>/dev/null || true
COPY gradle gradle 2>/dev/null || true
RUN ([ -f pom.xml ] && ./mvnw -B dependency:go-offline) || ([ -f build.gradle ] && ./gradlew --no-daemon dependencies)
COPY . .
RUN ([ -f pom.xml ] && ./mvnw -B -DskipTests package) || ./gradlew --no-daemon -x test bootJar

FROM eclipse-temurin:{VERSION}-jre
WORKDIR /app
COPY --from=builder /app/target/*.jar /app/build/libs/*.jar app.jar
EXPOSE 8080
CMD ["java", "-jar", "app.jar"]
```

Skip Dockerfile.dev generation for: Ruby, Rust, .NET, PHP, Elixir in v0.3 — print a note in the summary that auto-Dockerfile isn't yet supported for those stacks. Add them in later versions.

### Makefile.dev generation

Always generate. Variables and targets adapt to detected services. Use this skeleton — substitute `{...}` per detection:

```makefile
# Generated by /localcraft — edit if you want changes to persist across refresh runs.
# Run from .localcraft/ : `make -f Makefile.dev up` (or from repo root with `-C .localcraft`).

COMPOSE       := docker compose -f docker-compose.dev.yml --env-file .env.dev
APP_SERVICE   := {APP_SERVICE_OR_EMPTY}

.PHONY: up down logs ps restart clean reset help \
        {DB_SHELL_TARGETS} {APP_TARGETS} {MIGRATION_TARGETS}

help:           ## show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2}'

up:             ## bring all containers up
	$(COMPOSE) up -d
	@echo ""
	@echo "Services:"
	@$(COMPOSE) ps --format "  {{.Name}}\t{{.Status}}\t{{.Ports}}"

down:           ## stop all containers (keeps volumes)
	$(COMPOSE) down

logs:           ## follow logs from all services
	$(COMPOSE) logs -f --tail=100

ps:             ## list running services
	$(COMPOSE) ps

restart:        ## restart all services
	$(COMPOSE) restart

clean:          ## stop containers and remove volumes
	$(COMPOSE) down -v

reset: clean up ## clean + up (full reset)
```

Add per-detected-service shell targets. Examples:
```makefile
mysql-shell:    ## open mysql client
	$(COMPOSE) exec mysql mysql -u localcraft -plocalcraft localcraft

psql-shell:     ## open psql client
	$(COMPOSE) exec postgres psql -U localcraft -d localcraft

mongo-shell:    ## open mongosh
	$(COMPOSE) exec mongodb mongosh

redis-cli:      ## open redis-cli
	$(COMPOSE) exec redis redis-cli
```

Add migration / seed targets if Phase 3b detected them:
```makefile
migrate:        ## run migrations against the dev DB
	{MIGRATION_COMMAND}

seed:           ## load seed data
	{SEED_COMMAND}
```

If `Dockerfile.dev` was generated, add:
```makefile
build-app:      ## build the app image from Dockerfile.dev
	docker build -t {REPO_NAME}-dev -f Dockerfile.dev ..

shell:          ## shell into the app container
	$(COMPOSE) exec $(APP_SERVICE) sh
```

### README.dev.md generation

Single page with these sections (write all of them):

1. **TL;DR** — one block:
   ```
   make -f Makefile.dev up    # or: cd .localcraft && docker compose -f docker-compose.dev.yml --env-file .env.dev up
   ```
2. **Stack detected** — bullets: languages, frameworks, services, env-var count
3. **Services & ports** — table of every container with its localhost port and credentials (e.g., `mysql · localhost:3306 · localcraft/localcraft/localcraft`)
4. **Common make targets** — list every target from Makefile.dev with one-line descriptions
5. **Manual command reference** (for users who want to run things step-by-step instead of via make):
   - Start one service: `docker compose -f docker-compose.dev.yml up -d <service>`
   - Connect to MySQL/Postgres/Mongo/Redis (full command lines per service)
   - Run migrations manually (the detected command)
   - Seed manually (the detected command)
   - Tail logs from one service
   - Tear down completely
6. **Troubleshooting** — short list: port conflicts, container OOM, healthcheck stuck, how to nuke volumes
7. **What was scrubbed** — count of scrubbed values + note to review `.env.dev` before sharing
8. **Refresh** — how to regenerate (`/localcraft refresh`) and what survives (user samples in `samples/*.user.yml`)

### Existing-file check

If `.localcraft/` already exists AND the user did NOT say `refresh`/`regenerate`/`force`, prompt once:
```
.localcraft/ already exists. Overwrite? [y/N]
```
`y` → overwrite all files. `n` or empty → abort cleanly without writing anything.

### .gitignore guard

Read the repo's `.gitignore`. If it does not already cover `.localcraft/`, append:
```
# localcraft
.localcraft/
```
(Sample secrets in `.env.dev` are still secret-shaped — never let them get committed.)

### Final printed summary

```
✓ localcraft setup written to .localcraft/

Stack:    <languages joined with " · "> · <frameworks joined with ", ">
Services: <services joined with ", ">
Env vars: <count> (<N> scrubbed for safety, <M> kept-with-TODO)
Dockerfile.dev: <generated|skipped: repo has its own Dockerfile|skipped: unsupported stack>
Migrations: <init service added|manual: "<command>"|none detected>

Run:
  make -f .localcraft/Makefile.dev up

Or step-by-step:
  cd .localcraft && docker compose -f docker-compose.dev.yml --env-file .env.dev up

Other commands:
  /localcraft detect        — print stack only, no files written
  /localcraft refresh       — regenerate everything
  /localcraft add metrics   — add prometheus + grafana to existing setup
  /localcraft eks           — also generate EKS/Helm dev deployment (Phase 6)
```

## Phase 6 — EKS / Helm mode (runs only when triggered)

Activate when the user message contains any of: `eks`, `k8s`, `kubernetes`, `rancher`, `helm`. Generates a Kubernetes/Helm deployment package under `.localcraft/k8s/` that mirrors the production EKS shape but runs against a local Kubernetes cluster (Rancher Desktop's k3s, kind, minikube, or any kubectl-reachable cluster).

This phase runs **in addition to** Phases 1–5 (compose mode is still generated — the user can run either or both).

### 6a. Locate the helm chart

The repo may not have `helm/` on the currently checked-out branch. Try in order:

1. **Local `helm/` or `charts/` dir** in the current branch's working tree
2. **Origin `feature/helm` branch** — fetch tree via `gh api repos/<owner>/<repo>/git/trees/feature/helm?recursive=1`
3. **Origin `helm/production` branch** — same via `gh api .../tree/helm/production?recursive=1`
4. **None found** → print a note in the summary that EKS mode needs a helm chart somewhere; do NOT fabricate one. Skip the rest of Phase 6.

When found via a remote branch, download just the `helm/` subtree (or `charts/`) into `.localcraft/k8s/chart/` via `gh api repos/.../tarball/<branch>` + `tar -xz --strip-components=1 --wildcards '*/helm/*' '*/helm'`.

### 6b. Generate `values.dev.yaml` — override production assumptions

Read the chart's `values.yaml` to learn what knobs exist. Then write `.localcraft/k8s/values.dev.yaml` that overrides production-only settings. Use **only keys that exist in the chart's values.yaml** — do not invent. Common overrides (set each ONLY if the key is present in the upstream values.yaml):

```yaml
# .localcraft/k8s/values.dev.yaml — generated by /localcraft eks
# overrides ./chart/values.yaml for local k3s / rancher-desktop

replicaCount: 1

image:
  repository: localhost:5000/{REPO_NAME}-dev   # or registry.localhost depending on rancher config
  tag: dev
  pullPolicy: IfNotPresent

resources:
  requests: { cpu: 100m, memory: 256Mi }
  limits:   { cpu: 500m, memory: 512Mi }

# disable production-only machinery for local
externalSecrets:
  enabled: false
serviceMonitor:
  enabled: false
podDisruptionBudget:
  enabled: false
autoscaling:
  enabled: false
ingress:
  enabled: false

# point at in-cluster mock services (installed via dep-charts.dev.sh)
# the actual env-var names come from .env.dev (see secret.dev.yaml)
configmap:
  enabled: true
```

For each override key, check the upstream `values.yaml` first via `Read` — if the key path doesn't exist, **don't include it** (Helm will error on unused values in strict mode). Note in the file's top comment which overrides were skipped because the upstream chart doesn't expose that knob.

### 6c. Generate `secret.dev.yaml` and `configmap.dev.yaml` from `.env.dev`

The production chart uses `envFrom: secretRef:` with the secret name populated by External Secrets Operator. In dev mode that's replaced by a hand-built Secret. Generate:

```yaml
# .localcraft/k8s/secret.dev.yaml
apiVersion: v1
kind: Secret
metadata:
  name: {REPO_NAME}-secret      # match the name the chart's Deployment expects
  namespace: {DETECTED_NAMESPACE_OR_default}
type: Opaque
stringData:
  KEY1: "value1"                # populated from .env.dev (already scrubbed by Phase 4)
  KEY2: "value2"
  ...
```

Split keys: anything that **looks like a secret** (matched any safety-scrub rule from Phase 4, or contains `PASSWORD`/`SECRET`/`KEY`/`TOKEN` in the name) → `secret.dev.yaml`. Everything else → `configmap.dev.yaml` with the same structure (`kind: ConfigMap`, `data:` instead of `stringData:`). The chart's Deployment usually does `envFrom: [{ configMapRef: ... }, { secretRef: ... }]` — both must exist for `envFrom` to resolve.

### 6d. Generate `dep-charts.dev.sh` — install mock dependencies into k8s

For each detected service in Phase 1b, install the matching public Helm chart (Bitnami is the de facto standard). Generate a shell script the user runs once:

```bash
#!/bin/bash
# .localcraft/k8s/dep-charts.dev.sh — install mock dependencies into the current kube context
set -euo pipefail
NS=localcraft-dev
kubectl create namespace $NS --dry-run=client -o yaml | kubectl apply -f -

helm repo add bitnami https://charts.bitnami.com/bitnami --force-update
helm repo add localstack https://localstack.github.io/helm-charts --force-update
helm repo add grafana https://grafana.github.io/helm-charts --force-update
helm repo update

# only the helm install lines for services actually detected — see Phase 1b
# NOTE: no --wait flag here. helm returns as soon as manifests are applied;
# the separate `wait-deps` target in Makefile.dev polls pod readiness.
# (Rationale: Bitnami charts on first install can take 6-10 min for image
# pull + initdb on slow networks. helm's default 5-min --wait timeout
# fires too aggressively; failing the whole script when resources are
# actually fine. Splitting install from wait makes failures unambiguous
# and lets the wait step have its own generous timeout.)
helm upgrade --install mysql    bitnami/mysql    -n $NS \
  --set auth.rootPassword=localcraft --set auth.database=localcraft \
  --set auth.username=localcraft --set auth.password=localcraft \
  --set primary.persistence.enabled=false

helm upgrade --install redis    bitnami/redis    -n $NS \
  --set auth.enabled=false --set master.persistence.enabled=false

helm upgrade --install mongodb  bitnami/mongodb  -n $NS \
  --set auth.rootUser=localcraft --set auth.rootPassword=localcraft \
  --set persistence.enabled=false

helm upgrade --install localstack localstack/localstack -n $NS \
  --set services="s3,sqs,sns,secretsmanager,dynamodb,kms"

# kube-prometheus-stack covers prometheus + grafana + (optionally) loki + tempo via separate charts
# include only when metrics/logs/traces were detected
```

The script is template — write only the `helm upgrade --install` lines for services that Phase 1b actually detected. Don't install kafka/rabbitmq/elasticsearch helm charts blindly; only when detected. For Kafka, prefer `bitnami/kafka` in KRaft mode. For Loki/Tempo, use `grafana/loki` and `grafana/tempo` (or `grafana/loki-stack` which bundles them).

Apply order in dep-charts.dev.sh: stateful infra first (mysql/postgres/mongo), then queues (kafka/rabbitmq), then mocks (localstack/mailhog), then observability (prometheus/grafana/loki/tempo). All commands run fast and return immediately — readiness is enforced by `make wait-deps` separately.

### 6e. Generate `.localcraft/k8s/Makefile.dev` for k8s ops

```makefile
NS := localcraft-dev
APP := {REPO_NAME}

.PHONY: k8s-up k8s-down deps wait-deps app port-forward logs helm-template clean help status

help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS=":.*?## "}; {printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2}'

deps:           ## install mock dep charts (returns fast; doesn't wait for ready)
	bash dep-charts.dev.sh

# Emit ONE wait-deps line per service actually picked in Phase 6d.
# Use kubectl rollout status for Deployments (redis-master, localstack)
# and kubectl wait for StatefulSets (mysql, postgres, mongodb).
# Generous timeouts — first install can take 10+ min on cold image pull.
wait-deps:      ## block until all installed dep pods are Ready
	@echo "waiting for mock dependencies to become ready..."
	kubectl rollout status statefulset/mysql        -n $(NS) --timeout=15m
	kubectl rollout status statefulset/mongodb      -n $(NS) --timeout=10m
	kubectl rollout status statefulset/redis-master -n $(NS) --timeout=10m || \
	  kubectl rollout status deployment/redis-master -n $(NS) --timeout=10m
	kubectl rollout status deployment/localstack    -n $(NS) --timeout=10m
	@echo "all dep services Ready."

app: configmap secret  ## install the app helm chart with values.dev.yaml
	helm upgrade --install $(APP) ./chart -n $(NS) -f values.dev.yaml

configmap:      ## apply the dev configmap
	kubectl apply -n $(NS) -f configmap.dev.yaml

secret:         ## apply the dev secret
	kubectl apply -n $(NS) -f secret.dev.yaml

k8s-up: deps wait-deps app  ## install deps → wait for deps Ready → install app
	@echo ""
	@echo "Stack is up. Smoke test:"
	@echo "  make -f Makefile.dev port-forward   # in another shell"
	@echo "  curl http://localhost:8000/"

k8s-down:       ## remove the app release (deps stay)
	helm uninstall $(APP) -n $(NS) || true
	kubectl delete -n $(NS) -f configmap.dev.yaml -f secret.dev.yaml --ignore-not-found

status:         ## show what's running in the namespace
	@kubectl get pods,svc -n $(NS)

port-forward:   ## forward the app service to localhost:8000
	kubectl port-forward -n $(NS) svc/$(APP) 8000:{DETECTED_SERVICE_PORT}

logs:           ## tail app logs
	kubectl logs -n $(NS) -l app.kubernetes.io/name=$(APP) -f --tail=100

helm-template:  ## render the chart locally for inspection (no apply)
	helm template $(APP) ./chart -f values.dev.yaml

clean:          ## remove the entire namespace (deps + app + everything)
	kubectl delete namespace $(NS) --ignore-not-found
```

**`wait-deps` is per-repo dynamic** — emit only the lines for services actually installed in Phase 6d. Use `kubectl rollout status` so the command supports both Deployments and StatefulSets cleanly (`kubectl wait` works for pods but doesn't follow controller-level rollouts). For services that may be packaged as Deployment OR StatefulSet across chart versions (redis), use the `|| fallback` form shown above.

### 6f. Final EKS-mode print

After running, the summary appended to Phase 5's output should also include:

```
EKS/Helm package written to .localcraft/k8s/
  chart/                  # copy of the repo's helm chart (from <branch-source>)
  values.dev.yaml         # local-friendly overrides
  configmap.dev.yaml      # non-secret keys from .env.dev
  secret.dev.yaml         # secret-shaped keys from .env.dev
  dep-charts.dev.sh       # one-time mock-dep installer
  Makefile.dev            # `make -f .localcraft/k8s/Makefile.dev k8s-up` to bring everything up

Quickstart for k3s / rancher-desktop:
  make -f .localcraft/k8s/Makefile.dev k8s-up        # full bring-up (deps + app)
  make -f .localcraft/k8s/Makefile.dev port-forward  # in another shell
  curl http://localhost:8000/                        # smoke test
```

### 6g. Hard rules for EKS mode

- Read the chart's `values.yaml` **before** writing `values.dev.yaml` — only override keys that exist upstream
- Never modify the original chart in `.localcraft/k8s/chart/` — overrides go in `values.dev.yaml`
- Don't `helm install` from the skill — only generate the script and `make` targets
- Don't push images, don't change kube context, don't apply manifests on the user's behalf
- The skill requires the user's active kube context to be a local cluster (k3s / kind / minikube / docker-desktop). Don't run against a real EKS — print a refusal if the context name matches `^arn:aws:eks:` or contains `prod`/`production`/`stage`/`staging`

## Hard rules

1. **Never invent env var names.** They come from `.env.example` (verbatim) or from a real grep hit in source. Do not add an env var because "Django apps usually have it."
2. **Never invent service ports.** Use the ports from the sample compose files exactly as written.
3. **User samples beat defaults.** Always check for `<service>.user.yml` first.
4. **Never modify the repo's existing files** — except appending to `.gitignore` (see Phase 5). No edits to `Dockerfile`, `helm/`, `k8s/`, `.env`, source code, anything else.
5. **Never run `docker compose up` or `helm install` yourself.** Print the command. The user runs it.
6. **`.env.dev` is secret-shaped.** Always confirm `.gitignore` covers `.localcraft/` before writing.
7. **One sample = one service.** When adding new samples to the library, do not bundle multiple services. Merge logic depends on this.
8. **Detect mode never writes files.** If the user says "detect", "what stack", or "analyze", print JSON and stop — even if `.localcraft/` does not exist.
9. **EKS mode never targets real clusters.** Refuse if the active kube context name suggests a real environment (contains `prod`, `production`, `staging`, `stage`, or matches an `arn:aws:eks:` pattern).
