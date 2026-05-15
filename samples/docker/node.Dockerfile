# Reference Dockerfile.dev for Node services (Express / Nest / Fastify / etc.).
# Single-stage in dev mode (need source for hot-reload). For frontend builds
# (React/Next/Vite static), use node-frontend.Dockerfile instead — that pattern
# is multi-stage with nginx serving the build output.
#
# Placeholders:
#   {NODE_VERSION}  e.g. 20
#   {APP_NAME}      target repo dir name
#   {APP_PORT}      detected port; default 3000
#   {DEV_CMD}       detected dev command from package.json scripts (e.g. "npm run dev")

FROM node:{NODE_VERSION}-alpine

ENV NODE_ENV=development \
    PATH=/app/node_modules/.bin:$PATH

# non-root user (node user already exists in the image)
WORKDIR /app
RUN chown -R node:node /app

# install deps as root (cache-friendly), then drop to node user
COPY --chown=node:node package*.json yarn.lock* pnpm-lock.yaml* ./
RUN if [ -f yarn.lock ]; then yarn install --frozen-lockfile; \
    elif [ -f pnpm-lock.yaml ]; then npm i -g pnpm && pnpm install --frozen-lockfile; \
    else npm ci; fi

COPY --chown=node:node . .

USER node

EXPOSE {APP_PORT}

# Dev: relies on the script in package.json (typically nodemon / ts-node-dev / next dev)
CMD {DEV_CMD}
