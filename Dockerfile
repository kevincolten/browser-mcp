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

# Pin the MCP server so a bad upstream release can't break your deploy.
ARG PLAYWRIGHT_MCP_VERSION=latest
RUN npm install -g @playwright/mcp@${PLAYWRIGHT_MCP_VERSION} \
    && npm cache clean --force \
    # Fail the build loudly if the bin name ever changes again.
    && command -v playwright-mcp

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
# curl without -f returns 0 on 4xx, so any HTTP reply on 8931 counts as alive;
# connection-refused exits non-zero.
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD sh -c 'curl -fsS --max-time 5 http://127.0.0.1:9222/json/version >/dev/null && curl -s -o /dev/null --max-time 5 http://127.0.0.1:8931/mcp'

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/supervisord.conf"]
