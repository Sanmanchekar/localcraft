# 🛠️ localcraft

### Local Dev Environment Bootstrapper for Any Repo — Compose + EKS, Powered by Claude Code

[![MIT License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-0.11-brightgreen.svg)](https://github.com/Sanmanchekar/localcraft/releases)
[![Claude Code](https://img.shields.io/badge/built%20for-Claude%20Code-orange.svg)](https://claude.ai/code)
[![Languages](https://img.shields.io/badge/stacks-9%20supported-purple.svg)](#supported-stacks)
[![GitHub Stars](https://img.shields.io/github/stars/Sanmanchekar/localcraft?style=social)](https://github.com/Sanmanchekar/localcraft)

**12 mock services · 4 Dockerfile templates · 1 production-shape Helm archetype.** Auto-detects your stack, generates a working local dev setup (`docker-compose` OR `helm`/`k3s`), and scrubs real-looking secrets before they land in your `.env`. One symlink to install, one slash command to run.

[Quick Start](#-quick-start) · [Install](#-install) · [Update](#-update) · [Use](#-use) · [Modes](#-modes) · [Supported Stacks](#-supported-stacks) · [EKS / Rancher](#-eks--rancher-desktop) · [Extending](#-extending) · [Architecture](#-architecture)

---

## ⚡ Quick Start

```sh
# 1. install (one-liner)
git clone https://github.com/Sanmanchekar/localcraft ~/code/localcraft && \
  mkdir -p ~/.claude/skills && \
  ln -s ~/code/localcraft ~/.claude/skills/localcraft

# 2. in any repo
cd ~/code/some-service
claude -p "/localcraft"           # generates .localcraft/

# 3. bring everything up
make -f .localcraft/Makefile.dev up
```

That's the entire loop. The skill detects what you have (Python/Node/Go/Java/Ruby/…) and stitches the right mock services (MySQL, Redis, MongoDB, Kafka, LocalStack, Prometheus+Grafana, Loki, Tempo, Mailhog, …) into a runnable `docker-compose.dev.yml` with a generated `Makefile.dev`, `Dockerfile.dev`, scrubbed `.env.dev`, and a one-page `README.dev.md`.

---

## 📦 Install

One-liner (clones + symlinks):

```sh
git clone https://github.com/Sanmanchekar/localcraft ~/code/localcraft && \
  mkdir -p ~/.claude/skills && \
  ln -s ~/code/localcraft ~/.claude/skills/localcraft
```

Verify:
```sh
test -f ~/.claude/skills/localcraft/SKILL.md && echo "installed OK"
```

Then open any repo in Claude Code and type `/localcraft`.

---

## 🔄 Update

Pick one — all three pull `origin/main` into your local clone, no symlink rewiring or Claude Code restart needed:

```sh
# (a) bundled update script — works anywhere
bash ~/.claude/skills/localcraft/update.sh

# (b) shell function — see Optional Shell Function below
localcraft update

# (c) raw git
(cd "$(readlink ~/.claude/skills/localcraft)" && git pull)
```

After updating, regen target-repo output with the new spec:
```sh
cd <your-repo> && claude -p "/localcraft refresh"
```

---

## 🚀 Use

```
/localcraft                # detect + generate .localcraft/ + print run command
/localcraft eks            # also generate EKS/Helm package under .localcraft/k8s/
/localcraft detect         # print detected stack JSON; write nothing
/localcraft refresh        # regenerate, overwriting existing .localcraft/
/localcraft add metrics    # add prometheus+grafana to an existing setup
```

In the target repo after generation:

```sh
make -f .localcraft/Makefile.dev help        # see all targets
make -f .localcraft/Makefile.dev up          # docker compose stack
make -f .localcraft/k8s/Makefile.dev k8s-up  # k3s/EKS stack (after /localcraft eks)
```

---

## 🎛️ Modes

| Mode | Trigger | Output |
|---|---|---|
| **Compose** (default) | `/localcraft` | `.localcraft/docker-compose.dev.yml`, `.env.dev`, `Dockerfile.dev`, `Makefile.dev`, `README.dev.md` |
| **EKS / Helm** | `/localcraft eks` (or `k8s`, `kubernetes`, `rancher`, `helm`) | All of compose mode **+** `.localcraft/k8s/chart/`, `values.dev.yaml`, `configmap.dev.yaml`, `secret.dev.yaml`, `dep-charts.dev.sh`, `Makefile.dev` |
| **Detect-only** | `/localcraft detect` | Stack JSON printed to stdout, no files written |
| **Refresh** | `/localcraft refresh` (or `regenerate`, `force`) | Overwrites existing `.localcraft/` without asking |
| **Add metrics** | `/localcraft add metrics` | Appends prometheus+grafana to an existing `docker-compose.dev.yml` |

---

## 🧱 Supported Stacks

| Languages (9) | Frameworks auto-detected | Mock services (12) |
|---|---|---|
| Python, Node/TS, Go, Java/Kotlin, Ruby, Rust, .NET, PHP, Elixir | Django, Flask, FastAPI, Celery, Express, NestJS, Next, Fastify, Gin, Echo, Fiber, Chi, Spring Boot, Rails, Laravel, Phoenix, … | MySQL, Postgres, Redis, MongoDB, Elasticsearch, Kafka (Redpanda), RabbitMQ, LocalStack (AWS), Prometheus+Grafana, Loki, Tempo, Mailhog |

Migration tools auto-detected: Alembic, Django ORM, Rails, Prisma, Flyway, Liquibase, golang-migrate, goose, Knex, Sequelize, TypeORM, MikroORM, raw SQL.

The full detection logic lives in `SKILL.md` — that file IS the skill.

---

## ☸️ EKS / Rancher Desktop

`/localcraft eks` produces a Kubernetes deployment package that mirrors a production EKS shape but runs on any local cluster (Rancher Desktop, kind, minikube, docker-desktop). It refuses to run if your kube context looks like a real cluster (`arn:aws:eks:`, contains `prod`/`staging`).

```sh
cd .localcraft/k8s
make -f Makefile.dev k8s-up        # deps → wait-deps → app
make -f Makefile.dev status        # kubectl get pods,svc -n localcraft-dev
make -f Makefile.dev port-forward  # localhost:8000
make -f Makefile.dev logs          # tail
make -f Makefile.dev clean         # nuke the namespace
```

`dep-charts.dev.sh` installs Bitnami MySQL/Postgres/MongoDB/Redis + LocalStack (+ kube-prometheus-stack if metrics detected). `values.dev.yaml` overrides production-only knobs (ExternalSecret, HPA, PDB, ServiceMonitor) for local. `secret.dev.yaml` + `configmap.dev.yaml` replace the AWS Secrets Manager → External Secrets Operator pattern with hand-built k8s Secret/ConfigMap from your `.env.dev`.

---

## 🧰 Optional Shell Function

Drop in `~/.zshrc` or `~/.bashrc` for one-word invocation:

```sh
localcraft() {
  if [ "$1" = "update" ]; then
    bash "$HOME/.claude/skills/localcraft/update.sh"
    return
  fi
  local dir="${1:-$PWD}"
  shift 2>/dev/null
  (cd "$dir" && claude -p "/localcraft $*")
}
```

Then anywhere:
```sh
localcraft                          # run in current dir
localcraft ~/code/some-repo         # run against a different repo
localcraft . eks                    # eks mode in current dir
localcraft update                   # pull latest
```

---

## 🔌 Extending

**Add a new mock service:**
1. Drop `samples/compose/<service>.yml` (one service per file, self-contained).
2. Add a row to the service-detection table in `SKILL.md` (which dep names map to it, per language).
3. Add env-var hints to the value table in `SKILL.md` if the service introduces conventional env names.

**Override a bundled default for your org:**

Same `.user.*` convention across all three sample libraries — the skill picks `.user.*` over the default whenever it exists:

```
samples/compose/<service>.user.yml        # custom compose snippet
samples/docker/<stack>.user.Dockerfile    # custom Dockerfile template
samples/helm/<archetype>.user/            # custom helm chart archetype dir
```

Useful for: golden base images, internal CA certs, image-with-seed-baked-in for tests, internal package mirrors, audit log paths, etc. Keep your `.user.*` overrides out of any public fork.

**Reference Helm chart archetypes** — bundled `samples/helm/web-service/` is a full production-shape chart (Deployment + Service + Ingress + HPA + PDB + RBAC + ExternalSecret + ServiceMonitor). Used as fallback when the target repo has no chart on `feature/helm` or `helm/production` branches.

**Reference Dockerfiles** — bundled `samples/docker/{python-django,python-fastapi,go,node}.Dockerfile` with placeholder substitution (`{PYTHON_VERSION}`, `{APP_PORT}`, `{APP_MODULE}`, `{EXTRA_APT_BUILD}`/`{EXTRA_APT_RUNTIME}` derived from C-extension deps).

---

## 🏗️ Architecture

```
┌────────────────────────────────────────────────────────────────┐
│  Claude Code session in <target repo>                          │
│  User types /localcraft                                        │
└────────────────────┬───────────────────────────────────────────┘
                     │
                     ▼
        ┌────────────────────────┐
        │ ~/.claude/skills/      │  ← symlink to your clone
        │  localcraft/SKILL.md   │     of this repo
        └────────────┬───────────┘
                     │ Claude reads SKILL.md and follows it
                     ▼
┌────────────────────────────────────────────────────────────────┐
│  Phase 1 — Detect                                              │
│    • language(s) from manifests                                │
│    • framework + service drivers from deps                     │
│    • env vars from .env*.example + framework config + grep     │
│    • migration tool + Dockerfile + helm presence               │
│                                                                │
│  Phase 2 — Pick samples from ~/.claude/skills/localcraft/      │
│    samples/compose/<service>.yml (or .user.yml)                │
│                                                                │
│  Phase 3 — Merge into one docker-compose.dev.yml               │
│  Phase 3b — Add migration init service if Dockerfile + tool    │
│  Phase 4 — Scrub real-looking secrets, generate .env.dev       │
│  Phase 5 — Write Dockerfile.dev + Makefile.dev + README.dev.md │
│  Phase 6 — (EKS mode only) Generate .localcraft/k8s/           │
└────────────────────────────────────────────────────────────────┘
                     │
                     ▼
        ┌────────────────────────┐
        │  <target repo>/        │
        │   .localcraft/         │  ← isolated dir, .gitignore'd
        │   ├── docker-compose…  │
        │   ├── .env.dev         │
        │   ├── Dockerfile.dev   │
        │   ├── Makefile.dev     │
        │   ├── README.dev.md    │
        │   └── k8s/             │  ← only with /localcraft eks
        └────────────────────────┘
```

Hard rules baked in: never modify the target repo's existing files (only appends one line to `.gitignore`); never invent env var names (mirrors what the repo actually declares); never `docker compose up` or `helm install` on the user's behalf (prints the command); never target a real cluster in EKS mode (refuses contexts matching `arn:aws:eks:` or names containing `prod`/`staging`).

---

## 📁 Files

```
SKILL.md                          # the entire detector + synthesizer (Claude reads this)
update.sh                         # one-command updater (bash ~/.claude/skills/localcraft/update.sh)
samples/
  compose/*.yml                   # 12 mock service snippets — one per file
  env/*.env                       # reference env files per framework (fallback if no .env.example)
  docker/*.Dockerfile             # 4 dev-flavored reference Dockerfiles (python-django/fastapi, go, node)
  helm/web-service/               # production-shape Helm chart archetype
```

---

## 📜 License

MIT — see [LICENSE](LICENSE).

## 🤝 Contributing

Issues and PRs welcome. The skill spec lives in `SKILL.md` (Markdown, not code). Adding a new mock service or stack typically means: drop a sample file + add one row to a detection table. See [Extending](#-extending) above.

Built with [Claude Code](https://claude.ai/code).
