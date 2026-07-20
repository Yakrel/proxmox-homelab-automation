FROM node:latest

ARG AGENTMEMORY_VERSION=latest

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl gosu tini \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/agentmemory
RUN printf '{"name":"agentmemory-deploy","version":"1.0.0","private":true}\n' > package.json \
 && npm install "@agentmemory/agentmemory@${AGENTMEMORY_VERSION}" --no-fund --no-audit \
 && ln -s /opt/agentmemory/node_modules/.bin/agentmemory /usr/local/bin/agentmemory \
 && install -d -o node -g node /opt/agentmemory/node_modules/@xenova/transformers/.cache

ENV TINI_SUBREAPER=1

COPY --chmod=0755 entrypoint.sh /usr/local/bin/agentmemory-entrypoint.sh

EXPOSE 3111 3113

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD curl -fsS http://127.0.0.1:3111/agentmemory/livez || exit 1

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/agentmemory-entrypoint.sh"]
