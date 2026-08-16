#!/usr/bin/env bash
#
# Launch real Google Chrome, headed, on the Xvfb display.
#
# Chrome is started by *us*, not by Playwright. Playwright then attaches over
# CDP (see mcp-config.json). This matters:
#   - no --enable-automation switch is ever set, so navigator.webdriver stays
#     false and the "Chrome is being controlled by automated test software"
#     infobar never appears
#   - the browser stays warm between MCP sessions, so cookies/logins/tabs
#     persist even when no client is connected
#
set -euo pipefail

PROFILE_DIR="${CHROME_PROFILE_DIR:-/data/chrome-profile}"
CDP_PORT="${CDP_PORT:-9222}"
SCREEN_W="${SCREEN_WIDTH:-1920}"
SCREEN_H="${SCREEN_HEIGHT:-1080}"

mkdir -p "$PROFILE_DIR"

# Chrome refuses to start on a stale lock after an unclean shutdown.
rm -f "$PROFILE_DIR/SingletonLock" \
      "$PROFILE_DIR/SingletonSocket" \
      "$PROFILE_DIR/SingletonCookie" 2>/dev/null || true

echo "[chrome] waiting for X display ${DISPLAY} ..."
for _ in $(seq 1 60); do
  if xdpyinfo -display "${DISPLAY}" >/dev/null 2>&1; then
    echo "[chrome] display ready"
    break
  fi
  sleep 0.5
done

FLAGS=(
  # --- remote control surface (bound to loopback ONLY; see README) ---
  "--remote-debugging-address=127.0.0.1"
  "--remote-debugging-port=${CDP_PORT}"

  # --- identity / persistence ---
  "--user-data-dir=${PROFILE_DIR}"
  "--lang=en-US"
  "--window-size=${SCREEN_W},${SCREEN_H}"
  "--window-position=0,0"

  # --- anti-detection ---
  # Removes the CDP-injected AutomationControlled blink feature, which is what
  # sets navigator.webdriver=true when a debugger attaches.
  "--disable-blink-features=AutomationControlled"
  "--disable-features=Translate,OptimizationHints,MediaRouter,InterestFeedContentSuggestions,CalculateNativeWinOcclusion"
  "--no-first-run"
  "--no-default-browser-check"
  "--no-service-autorun"
  "--disable-infobars"
  "--disable-session-crashed-bubble"
  "--hide-crash-restore-bubble"

  # --- headless container plumbing ---
  # Software GL. Without this WebGL is absent entirely, which is a louder
  # signal than SwiftShader being present. See README for the GPU caveat.
  "--enable-unsafe-swiftshader"
  "--use-gl=angle"
  "--use-angle=swiftshader"
  "--disable-dev-shm-usage"
  "--password-store=basic"
  "--use-mock-keychain"
)

# Chrome's setuid sandbox needs privileges most container runtimes withhold.
# Set CHROME_ENABLE_SANDBOX=true if your host allows it (see README).
if [[ "${CHROME_ENABLE_SANDBOX:-false}" != "true" ]]; then
  FLAGS+=("--no-sandbox")
fi

EXTRA=()
if [[ -n "${CHROME_EXTRA_ARGS:-}" ]]; then
  read -r -a EXTRA <<< "${CHROME_EXTRA_ARGS}"
fi

echo "[chrome] launching google-chrome-stable"
exec google-chrome-stable "${FLAGS[@]}" "${EXTRA[@]}" about:blank
