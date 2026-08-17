FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=America/Los_Angeles \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8 \
    DISPLAY=:99 \
    SCREEN_WIDTH=1920 \
    SCREEN_HEIGHT=1080 \
    CDP_PORT=9222 \
    MCP_PORT=8931 \
    CHROME_PROFILE_DIR=/data/chrome-profile

# ---------------------------------------------------------------------------
# THE 5-SECOND CLIFF -- read this before changing anything below.
#
# playwright-mcp's Streamable HTTP endpoint (/mcp) runs a heartbeat: it pings
# the client every 3s and calls server.close() if a ping goes unanswered for
# 5000ms. Closing deletes the session, drops the shared CDP connection, and
# kills any in-flight tool call with the wildly misleading:
#     "Target page, context or browser has been closed"
# ...at ~5.1s, on any page, regardless of what is loading.
#
# Server->client pings ride the SSE stream. Clients that don't answer them
# (Claude's connector, and curl, which cannot) hit this on every call over 5s.
# Light pages finish under the limit and appear to work, which makes this look
# like a connectivity or page problem for a very long time.
#
# Upstream gates it on PLAYWRIGHT_MCP_PING_TIMEOUT_MS and startHeartbeat()
# returns early when the value is <= 0, so 0 disables it outright. From
# playwright-core/lib/coreBundle.js:
#     defaultPingTimeout = 5e3;
#     pingTimeout = () => { const v = process.env.PLAYWRIGHT_MCP_PING_TIMEOUT_MS; ... }
#     startHeartbeat = (server) => { const timeout = pingTimeout();
#                                    if (timeout <= 0) return; ... }
#
# The legacy /sse endpoint passes runHeartbeat=false and never had this issue,
# but /sse is the deprecated transport, so we stay on /mcp and kill the ping.
#
# Cost: dead sessions are no longer reaped by ping, only on transport close.
# Negligible for a single-user deployment.
# ---------------------------------------------------------------------------
ENV PLAYWRIGHT_MCP_PING_TIMEOUT_MS=0

# ---------------------------------------------------------------------------
# Base packages
#   - xvfb / x11vnc / novnc : headed browser on a virtual display, viewable
#   - fonts-*               : missing fonts are a fingerprinting tell
#   - mesa/libgl            : software GL so WebGL doesn't hard-fail
# ---------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl gnupg wget locales tzdata supervisor \
      xvfb x11vnc x11-utils xauth novnc websockify \
      libgl1 libglx-mesa0 libgl1-mesa-dri mesa-vulkan-drivers \
      dbus-x11 procps \
      fonts-liberation fonts-noto fonts-noto-color-emoji fonts-noto-cjk \
      fonts-dejavu-core fonts-freefont-ttf \
    && locale-gen en_US.UTF-8 \
    && ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# Real Google Chrome (stable) -- NOT Chromium.
# Chromium's UA, codec set and branding differ from Chrome and are trivially
# fingerprinted. Using the genuine stable build removes that entire class.
# Also: do NOT let Playwright launch the browser -- it sets navigator.webdriver
# and the automation switches. We launch Chrome ourselves and attach over CDP.
# ---------------------------------------------------------------------------
RUN curl -fsSL https://dl.google.com/linux/linux_signing_key.pub \
      | gpg --dearmor -o /usr/share/keyrings/google-chrome.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] https://dl.google.com/linux/chrome/deb/ stable main" \
      > /etc/apt/sources.list.d/google-chrome.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends google-chrome-stable \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# Node 22 (for @playwright/mcp)
# ---------------------------------------------------------------------------
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

ARG PLAYWRIGHT_MCP_VERSION=latest
RUN npm install -g @playwright/mcp@${PLAYWRIGHT_MCP_VERSION} \
    && npm cache clean --force \
    && command -v playwright-mcp \
    && grep -rq PLAYWRIGHT_MCP_PING_TIMEOUT_MS /usr/lib/node_modules \
    && echo 'ping-timeout env var present'

WORKDIR /app
COPY scripts/ /app/scripts/
COPY mcp-config.json /app/mcp-config.json
COPY supervisord.conf /etc/supervisor/supervisord.conf
RUN chmod +x /app/scripts/*.sh

# Profile lives on a volume so logins survive redeploys.
VOLUME ["/data"]

# 8931 = MCP (streamable HTTP)   6080 = noVNC
EXPOSE 8931 6080

# Probe BOTH Chrome's CDP and the MCP listener. Checking only CDP hides a dead
# MCP process behind a green healthcheck -- which is exactly what happened.
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD sh -c 'curl -fsS --max-time 5 http://127.0.0.1:9222/json/version >/dev/null && curl -s -o /dev/null --max-time 5 http://127.0.0.1:8931/mcp'

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/supervisord.conf"]
