#!/usr/bin/env bash
#
# Start @playwright/mcp in HTTP transport mode, attached to the already-running
# Chrome over CDP.
#
set -euo pipefail

CDP_PORT="${CDP_PORT:-9222}"
MCP_PORT="${MCP_PORT:-8931}"

echo "[mcp] waiting for Chrome CDP on 127.0.0.1:${CDP_PORT} ..."
for _ in $(seq 1 120); do
  if curl -fsS "http://127.0.0.1:${CDP_PORT}/json/version" >/dev/null 2>&1; then
    echo "[mcp] CDP is up"
    break
  fi
  sleep 1
done

# --host 0.0.0.0 so the gateway container (and your tailnet) can reach it.
# This port is NOT published to the internet by docker-compose; the Caddy
# gateway is the only public entrypoint. See README.
exec mcp-server-playwright \
  --config /app/mcp-config.json \
  --port "${MCP_PORT}" \
  --host 0.0.0.0
