#!/usr/bin/env bash
#
# Start x11vnc, optionally with password auth.
#
# Set VNC_PASSWORD to require a password. Leave it unset for passwordless
# access -- only acceptable when the published port is bound to a trusted
# interface (loopback or a tailnet IP), NEVER 0.0.0.0 and never through the
# Cloudflare tunnel. Anyone who reaches this port gets full control of a
# browser holding your logged-in cookies.
#
set -euo pipefail

echo "[vnc] waiting for X display ${DISPLAY} ..."
for _ in $(seq 1 60); do
  if xdpyinfo -display "${DISPLAY}" >/dev/null 2>&1; then break; fi
  sleep 0.5
done

ARGS=(-display "${DISPLAY}" -forever -shared -rfbport 5900 -quiet -noxdamage)

if [[ -n "${VNC_PASSWORD:-}" ]]; then
  mkdir -p /data/.vnc
  x11vnc -storepasswd "${VNC_PASSWORD}" /data/.vnc/passwd >/dev/null 2>&1
  chmod 600 /data/.vnc/passwd
  ARGS+=(-rfbauth /data/.vnc/passwd)
  echo "[vnc] password auth ENABLED"
else
  ARGS+=(-nopw)
  echo "[vnc] WARNING: passwordless (VNC_PASSWORD unset) -- keep this port off public interfaces"
fi

exec x11vnc "${ARGS[@]}"
