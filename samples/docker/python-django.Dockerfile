# Reference Dockerfile.dev for Python / Django services.
# Pattern derived from production Dockerfiles in the source org, dev-flavored
# (uses runserver for hot-reload, single non-root user, multi-stage).
#
# Placeholders the skill substitutes when copying this into a target repo:
#   {PYTHON_VERSION}     e.g. 3.11
#   {APP_NAME}           target repo dir name
#   {APP_PORT}           detected port; default 8000
#   {EXTRA_APT_BUILD}    extra apt build deps (e.g. default-libmysqlclient-dev pkg-config)
#   {EXTRA_APT_RUNTIME}  extra apt runtime deps (e.g. default-libmysqlclient-dev)
#
# Build context = repo root: cd .localcraft && docker build -f Dockerfile.dev ..

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
    PATH=/home/appuser/.local/bin:$PATH

RUN apt-get update && apt-get install -y --no-install-recommends \
      curl {EXTRA_APT_RUNTIME} \
 && rm -rf /var/lib/apt/lists/*

# non-root user
RUN groupadd -r appuser && useradd -r -g appuser -m appuser
WORKDIR /app
COPY --from=builder --chown=appuser:appuser /root/.local /home/appuser/.local
COPY --chown=appuser:appuser . .
USER appuser

EXPOSE {APP_PORT}

# Dev: runserver gives hot-reload on file changes. Swap for gunicorn in prod.
CMD ["python", "manage.py", "runserver", "0.0.0.0:{APP_PORT}"]
