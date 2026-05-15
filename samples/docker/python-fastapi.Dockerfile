# Reference Dockerfile.dev for Python / FastAPI services.
# Pattern derived from production Dockerfiles in the source org, dev-flavored
# (uvicorn --reload for hot-reload, multi-stage, non-root user, healthcheck).
#
# Placeholders:
#   {PYTHON_VERSION}     e.g. 3.12
#   {APP_NAME}           target repo dir name
#   {APP_PORT}           detected port; default 8000
#   {APP_MODULE}         python module path of the app (e.g. main:app, app.main:app)
#   {EXTRA_APT_BUILD}    extra apt build deps (libpq-dev for psycopg2, etc.)
#   {EXTRA_APT_RUNTIME}  extra apt runtime deps (libpq5, postgresql-client, etc.)

# ---- builder ----
FROM python:{PYTHON_VERSION}-slim AS builder

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential {EXTRA_APT_BUILD} \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY requirements*.txt pyproject.toml* poetry.lock* Pipfile* ./
RUN pip install --user --no-cache-dir -r requirements.txt 2>/dev/null \
 || pip install --user --no-cache-dir .

# ---- runtime ----
FROM python:{PYTHON_VERSION}-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app \
    PATH=/home/appuser/.local/bin:$PATH

RUN apt-get update && apt-get install -y --no-install-recommends \
      curl {EXTRA_APT_RUNTIME} \
 && rm -rf /var/lib/apt/lists/*

RUN groupadd -r appuser && useradd -r -g appuser -m appuser
WORKDIR /app
COPY --from=builder --chown=appuser:appuser /root/.local /home/appuser/.local
COPY --chown=appuser:appuser . .

# log dir under app (no /var/log paths — easier to bind-mount in dev)
RUN mkdir -p /app/logs && chown -R appuser:appuser /app/logs

USER appuser

EXPOSE {APP_PORT}

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD curl -fsS http://localhost:{APP_PORT}/health || exit 1

# Dev: --reload watches source files and restarts on change
CMD ["uvicorn", "{APP_MODULE}", "--host", "0.0.0.0", "--port", "{APP_PORT}", "--reload"]
