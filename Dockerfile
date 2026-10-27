FROM node:20-alpine
WORKDIR /app
COPY package.json ./
COPY src ./src
COPY test ./test
# The commit SHA is baked in at build time so /api/version shows what is deployed
ARG GIT_COMMIT=dev
ENV APP_COMMIT=$GIT_COMMIT NODE_ENV=production PORT=3000
USER node
EXPOSE 3000
HEALTHCHECK --interval=10s --timeout=3s --retries=3 \
  CMD wget -qO- http://localhost:3000/api/health || exit 1
CMD ["node", "src/server.js"]
