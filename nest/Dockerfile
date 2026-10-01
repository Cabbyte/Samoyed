FROM node:24-bookworm-slim AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --ignore-scripts
COPY src ./src
COPY drizzle ./drizzle
COPY auth-migrations ./auth-migrations
COPY web ./web
COPY scripts/build-node.mjs ./scripts/build-node.mjs
RUN node scripts/build-node.mjs

FROM build AS test
COPY test ./test
COPY contracts ./contracts
CMD ["node", "--import", "tsx", "--test", "--test-concurrency=1", "test/auth.test.ts", "test/routines.test.ts", "test/sync.test.ts"]

FROM build AS dependencies
RUN npm prune --omit=dev --ignore-scripts

FROM node:24-bookworm-slim
WORKDIR /app
COPY --from=dependencies /app/node_modules ./node_modules
COPY --from=build /app/package.json ./package.json
COPY --from=build /app/dist-node ./dist-node
RUN mkdir -p /data /backups && chown node:node /data /backups
USER node
ENV NEST_DATABASE=/data/nest.sqlite
ENV NEST_LISTEN_HOST=0.0.0.0
ENV NODE_ENV=production
ENV NODE_OPTIONS=--max-old-space-size=160
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 CMD node -e "fetch('http://127.0.0.1:8787/readyz').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
CMD ["node", "dist-node/src/node.js"]
