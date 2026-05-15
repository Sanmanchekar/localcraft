# Reference Dockerfile.dev for Go services.
# Pattern derived from production Dockerfiles in the source org.
# Multi-stage: golang builder → alpine runtime with non-root user + healthcheck.
#
# Placeholders:
#   {GO_VERSION}      e.g. 1.22
#   {APP_NAME}        target repo dir name
#   {APP_PORT}        detected port; default 8080
#   {ENTRYPOINT_PKG}  Go package path to build (e.g. ./cmd/server, ./cmd/<app>, .)

# ---- builder ----
FROM golang:{GO_VERSION}-alpine AS builder

WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download

COPY . .
# CGO disabled → static binary that runs on alpine without glibc
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" \
    -o /out/{APP_NAME} {ENTRYPOINT_PKG}

# ---- runtime ----
FROM alpine:latest

RUN apk --no-cache add ca-certificates tzdata wget

# non-root user
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

WORKDIR /app
COPY --from=builder --chown=appuser:appgroup /out/{APP_NAME} ./{APP_NAME}

USER appuser

EXPOSE {APP_PORT}

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:{APP_PORT}/health || exit 1

CMD ["./{APP_NAME}"]
