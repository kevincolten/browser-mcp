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

# NOTE: the bin shipped by @playwright/mcp is `playwright-mcp` (cli.js).
# It is NOT `mcp-server-playwright` -- that name silently restart-loops.
exec playwright-mcp \
  --config /app/mcp-config.json \
  --port "${MCP_PORT}" \
  --host 0.0.0.0
