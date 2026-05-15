# samples/docker/

Reference Dockerfiles the skill uses when generating `<repo>/.localcraft/Dockerfile.dev`.

When the target repo has **no** `Dockerfile` at root and a buildable stack is detected, the skill prefers a template from this directory over the inline fallback in `SKILL.md`. Templates contain `{PLACEHOLDER}` tokens the skill substitutes per detected stack.

## Bundled templates (v0.6+)

| File | Stack | Detection trigger | Placeholders substituted |
|---|---|---|---|
| `python-django.Dockerfile` | Python + Django | `manage.py` exists AND `django` in deps | `{PYTHON_VERSION}`, `{APP_PORT}`, `{EXTRA_APT_BUILD}`, `{EXTRA_APT_RUNTIME}` |
| `python-fastapi.Dockerfile` | Python + FastAPI | `fastapi` in deps | `{PYTHON_VERSION}`, `{APP_PORT}`, `{APP_MODULE}`, `{EXTRA_APT_BUILD}`, `{EXTRA_APT_RUNTIME}` |
| `go.Dockerfile` | Go | `go.mod` exists | `{GO_VERSION}`, `{APP_NAME}`, `{APP_PORT}`, `{ENTRYPOINT_PKG}` |
| `node.Dockerfile` | Node services (Express/Nest/Fastify) | `package.json` with non-frontend deps | `{NODE_VERSION}`, `{APP_NAME}`, `{APP_PORT}`, `{DEV_CMD}` |

Each template is **dev-flavored**: hot-reload, single non-root user, multi-stage where it makes sense, conservative healthcheck. Production Dockerfiles for the same stacks would swap runserver/--reload for gunicorn/no-reload, drop curl, and add observability sidecars — that's intentionally out of scope for this skill.

## Adding a template

1. Create `<stack>.Dockerfile` here.
2. Use `{PLACEHOLDERS}` for anything the skill should fill in per-target-repo.
3. Add a row to the table above.
4. Add a row to the Phase 5 "Dockerfile.dev generation" table in `SKILL.md` mapping the detection trigger to your new template name.

## Org-specific overrides

To override a bundled template for your org, drop `<stack>.user.Dockerfile` next to the default. The skill picks `.user.Dockerfile` first if present (same convention as `samples/compose/<svc>.user.yml`). Useful for: baked-in CA certs, internal package mirrors, golden base images, audit log paths, etc. Keep your overrides out of any public fork of this skill.

## Variants not yet bundled

- `python-celery.Dockerfile` (Celery worker, no web framework — `CMD ["celery", "-A", ...]`)
- `node-frontend.Dockerfile` (React/Next/Vite static build → nginx multi-stage)
- `java-spring.Dockerfile` (Maven or Gradle wrapper, eclipse-temurin runtime)
- `rails.Dockerfile`
- `dotnet.Dockerfile`

PRs welcome — the skill falls back to its inline templates for these stacks until a file lands here.
