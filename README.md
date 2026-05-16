# localcraft

A Claude Code skill that bootstraps a complete local dev setup for any repo: detects the stack, picks matching mock dependencies (Postgres / Redis / Kafka / LocalStack / Prometheus+Grafana / Mailhog / …), generates a working `docker-compose.local.yml` + `.env.local` with sample-secret values, and prints the run command.

No binary, no install step beyond a symlink. The "detector" is Claude reading your repo via the skill instructions; the "synthesizer" is Claude stitching sample compose snippets from `samples/`.

## Install

One-liner (clones + symlinks):

```sh
git clone https://github.com/Sanmanchekar/localcraft ~/code/localcraft && \
  mkdir -p ~/.claude/skills && \
  ln -s ~/code/localcraft ~/.claude/skills/localcraft
```

Open any repo in Claude Code and type `/localcraft`.

## Update

Pick one — both pull `origin/main` into your local clone and update the skill in place (no symlink rewiring, no Claude Code restart):

```sh
# (a) bundled update script — works anywhere
bash ~/.claude/skills/localcraft/update.sh

# (b) shell function — see "Optional shell function" below
localcraft update

# (c) raw git
(cd "$(readlink ~/.claude/skills/localcraft)" && git pull)
```

After updating, regen any existing target-repo output with the new spec:
```sh
cd <your-repo> && claude -p "/localcraft refresh"
```

## Use

```
/localcraft                # detect + generate .localcraft/ + print run command
/localcraft eks            # also generate EKS/Helm package under .localcraft/k8s/
/localcraft detect         # print detected stack JSON; write nothing
/localcraft refresh        # regenerate, overwriting existing .localcraft/
/localcraft add metrics    # add prometheus+grafana to an existing setup
```

Then in the target repo:

```sh
make -f .localcraft/Makefile.dev up         # compose stack
make -f .localcraft/k8s/Makefile.dev k8s-up # EKS / k3s stack (after /localcraft eks)
```

## Optional shell function

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
localcraft                            # run in current dir
localcraft ~/code/some-repo           # run against a different repo
localcraft . eks                      # run with eks mode
localcraft update                     # pull latest skill
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
