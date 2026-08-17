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
# only reachable from the auth proxy on the internal compose network.
ALLOWED_HOSTS="${MCP_ALLOWED_HOSTS:-*}"

# THE 5-SECOND CLIFF.
#
# --timeout-action defaults to 5000ms and covers post-navigation work: the
# accessibility snapshot, console capture, settle waits. Navigation itself has
# its own (60s) budget and usually finishes fast, so a page loads fine and then
# the snapshot blows the action budget. The server hangs up mid-request; the
# transport reaps the session, which closes the shared CDP connection, and the
# in-flight call dies with the extremely misleading:
#   "Target page, context or browser has been closed"
#
# Light pages (example.com, ~1.5s) sail under the limit. Real-world pages with
# trackers and third-party scripts never settle and hit it every time -- so the
# server looks broken for exactly the pages you actually want to read.
TIMEOUT_ACTION="${MCP_TIMEOUT_ACTION:-30000}"
TIMEOUT_NAVIGATION="${MCP_TIMEOUT_NAVIGATION:-60000}"

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
# --shared-browser-context: in CDP mode the browser connection is shared, so
# per-session attach/detach lets one session's teardown kill another's
# in-flight call.
echo "[mcp] starting on :${MCP_PORT} (allowed-hosts=${ALLOWED_HOSTS} action-timeout=${TIMEOUT_ACTION}ms)"
exec playwright-mcp \
  --config /app/mcp-config.json \
  --port "${MCP_PORT}" \
  --host 0.0.0.0 \
  --allowed-hosts "${ALLOWED_HOSTS}" \
  --shared-browser-context \
  --timeout-action "${TIMEOUT_ACTION}" \
  --timeout-navigation "${TIMEOUT_NAVIGATION}"
