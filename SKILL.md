---
name: localcraft
description: Generate a complete local dev setup (docker-compose.local.yml + .env.local + mocked external deps) for the current repo. Detects the stack — language, framework, databases, caches, queues, cloud SDKs, metrics, env vars — by scanning manifests (package.json, requirements.txt, go.mod, pom.xml, Gemfile, Cargo.toml, *.csproj, build.gradle, composer.json, mix.exs), Dockerfile, helm/, k8s/, and source code. Stitches matching sample compose snippets from the bundled samples/ library into one working setup, generates .env.local with sample-secret values, and prints the docker compose command to start everything. Use when the user types /localcraft, asks to "set up local dev", "spin up dependencies", "mock the database/redis/aws", "make this repo runnable locally", "bootstrap this repo", or wants metrics/grafana mocked.
---

# localcraft

Generate a runnable local dev setup for the current repo:
**detect stack → pick matching samples → write `.localcraft/` → print run command.**

## Modes

Default action: full **init** flow (Phase 1 → 5 below).

If the user message contains:
- `detect`, `what stack`, `analyze` → run **Phase 1 only**, print the stack JSON, do NOT write files
- `refresh`, `regenerate`, `redo`, `force` → run init, **overwrite** any existing `.localcraft/`
- `add metrics`, `add grafana` → load existing `.localcraft/docker-compose.local.yml`, add the prometheus-grafana sample, write back

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

**Auto-include rules**:
- If `aws` detected → include the `localstack` sample
- If `metrics` detected → include the `prometheus-grafana` sample
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

If `prometheus-grafana` is in the picked samples, ALSO write `.localcraft/prometheus/prometheus.yml` — see Phase 4.

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
| `migrations/*.sql` + go-migrate import in go.mod | golang-migrate | `migrate -path migrations -database $DATABASE_URL up` |
| `knexfile.{js,ts}` or `knex/migrations/` | Knex | `npx knex migrate:latest` |
| `node_modules/typeorm` + `ormconfig.*` or migrations dir | TypeORM | `npx typeorm migration:run` |
| `migrations/*.sql` only (no tool detected) | raw SQL | concatenate and pipe to db client via a temp container |

If no tool is detected, skip this phase. **Never guess.**

### Init service shape (requires `Dockerfile` at the repo root)

```yaml
services:
  init:
    build:
      context: ..
      dockerfile: Dockerfile
    command: ["alembic", "upgrade", "head"]    # ← from the detection table
    env_file: .env.local
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

## Phase 4 — Generate `.env.local`

For each env var collected in Phase 1c, assign a value using these rules in order:

1. **Framework default from a config module** (Phase 1c source 2): if the canonical config module had a literal default (`os.getenv("DEBUG", "True")`, `${PORT:8080}`, etc.), reuse it.
2. **Value from `.env*.example`** (Phase 1c source 1): if the source line had a value, reuse it **after the safety scrub below**. Skip if the value looks like a placeholder (empty, `<...>`, `your-...`, `xxx`, `changeme`, `replace-me`, `TODO`, `FIXME`, `${...}`).
3. **Hint table** (first substring match against the var name wins):

**Safety scrub — applied to every value from source 2 before reuse:**

Treat `.env*.example` files as references for the **shape** of variables, not as safe local values. Commit accidents are common — real prod credentials sometimes end up in `.env.example`. Replace these patterns with the hint-table dev placeholder instead of copying verbatim:

- **Long random-looking secrets**: value length ≥ 16 AND contains a mix of letters, digits, and at least one symbol → looks like a real secret. Replace.
- **Real-looking hostnames**: value contains `.amazonaws.com`, `.azure.com`, `.gcp.io`, `.cloud.com`, or any FQDN with ≥ 3 dot-separated segments that isn't `localhost`/`127.0.0.1`/`0.0.0.0`/Docker-network names from this skill's samples → replace with the local mock hostname.
- **Real-looking IPs**: any value matching an IPv4 pattern that isn't `127.0.0.1`, `0.0.0.0`, or a private range (10.x, 172.16–31.x, 192.168.x) → replace.
- **Known token shapes**: `xox[bp]-...` (Slack), `sk-...` (Stripe/OpenAI), `ghp_...` (GitHub PAT), `eyJ...` (JWT), `AKIA...` (AWS access key), `arn:aws:...` (AWS ARNs) → replace with placeholder.

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

Top of `.env.local`:
```
# generated by localcraft — sample-only secrets, NOT for production
# rotate any value before sharing this file outside your machine
```

## Phase 5 — Write & print

Output dir: `<repo>/.localcraft/` (create with `mkdir -p`).

Files to write:
- `.localcraft/docker-compose.local.yml` — merged compose
- `.localcraft/.env.local` — env vars with sample values
- `.localcraft/README.md` — one-page run instructions (services, ports, mock notes)
- `.localcraft/prometheus/prometheus.yml` — only if metrics included; content:
  ```yaml
  global:
    scrape_interval: 15s
  scrape_configs:
    - job_name: app
      static_configs:
        - targets: ['host.docker.internal:8000']  # adjust to your app's port
  ```

**Existing-file check**: if any of these files already exist and the user did NOT use a refresh keyword, ask once: `"`.localcraft/` already exists. Overwrite? [y/N]"`. If they say no, abort cleanly.

**.gitignore guard**: read the repo's `.gitignore`. If it does not already cover `.env.local` or `.localcraft/`, append:
```
# localcraft
.localcraft/
```
to the end. (Sample secrets are still secrets-shaped — never let them get committed.)

Final printed summary (this exact shape):

```
✓ localcraft setup written to .localcraft/

Stack:    <languages joined with " · "> · <frameworks joined with ", ">
Services: <services joined with ", ">
Env vars: <count> (filled with sample values; review .env.local before sharing)

Run:
  cd .localcraft && docker compose -f docker-compose.local.yml --env-file .env.local up

Other commands:
  /localcraft detect        — print stack only, no files written
  /localcraft refresh       — regenerate everything
  /localcraft add metrics   — add prometheus + grafana to an existing setup
```

## Hard rules

1. **Never invent env var names.** They come from `.env.example` (verbatim) or from a real grep hit in source. Do not add an env var because "Django apps usually have it."
2. **Never invent service ports.** Use the ports from the sample compose files exactly as written.
3. **User samples beat defaults.** Always check for `<service>.user.yml` first.
4. **Never modify the repo's existing files** — except appending to `.gitignore` (see Phase 5). No edits to `Dockerfile`, `helm/`, `k8s/`, `.env`, source code, anything else.
5. **Never run `docker compose up` yourself.** Print the command. The user runs it.
6. **`.env.local` is secret-shaped.** Always confirm `.gitignore` covers it before writing.
7. **One sample = one service.** When adding new samples to the library, do not bundle multiple services. Merge logic depends on this.
8. **Detect mode never writes files.** If the user says "detect", "what stack", or "analyze", print JSON and stop — even if `.localcraft/` does not exist.
