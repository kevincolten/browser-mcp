#!/usr/bin/env bash
#
# Start @playwright/mcp in HTTP transport mode, attached to the already-running
# Chrome over CDP.
#
set -euo pipefail

CDP_PORT="${CDP_PORT:-9222}"
MCP_PORT="${MCP_PORT:-8931}"

# --allowed-hosts is a DNS-rebinding guard. It defaults to the host the server
# is bound to -- so binding 0.0.0.0 and then reaching it through a reverse
# proxy that forwards `Host: your.public.domain` fails the check and the
# server returns 403 on every request. That 403 is passed straight through by
# the proxy and looks exactly like an authorization failure, which it isn't.
#
# '*' is safe in this deployment: 8931 is never published to the host and is
# only reachable from the auth proxy on the internal compose network. Narrow
# it to your FQDN if you expose the port some other way.
ALLOWED_HOSTS="${MCP_ALLOWED_HOSTS:-*}"

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
#
# --shared-browser-context is REQUIRED in CDP mode. Without it playwright-mcp
# attaches to Chrome per HTTP session and disconnects on session teardown --
# but the CDP connection is shared, so one session ending kills any other
# session's in-flight call with:
#   "Target page, context or browser has been closed"
# Clients routinely hold more than one session open, so this is not an edge
# case; it fires the moment two tool calls overlap.
echo "[mcp] starting on :${MCP_PORT} (allowed-hosts=${ALLOWED_HOSTS})"
exec playwright-mcp \
  --config /app/mcp-config.json \
  --port "${MCP_PORT}" \
  --host 0.0.0.0 \
  --allowed-hosts "${ALLOWED_HOSTS}" \
  --shared-browser-context
