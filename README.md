# browser-mcp

A self-hosted **headed Google Chrome** with a persistent, logged-in profile, exposed to Claude (or any MCP client) as a remote MCP server over Streamable HTTP.

Built for one specific annoyance: asking Claude a question and watching it bounce off a paywall, a login wall, or a Cloudflare interstitial. This gives it a real browser, on your residential IP, already signed in to the sites you care about.

**Not** a scraping farm. Low-volume, interactive, single-user. Read [Scope & limits](#scope--limits) before you point it at anything serious.

---

## What's in the box

| Piece | Why |
|---|---|
| Real **Google Chrome stable** | Chromium's UA, codecs and branding differ from Chrome and get fingerprinted. Genuine stable build removes that class of tell. |
| **Xvfb** (headed, 1920x1080) | Headless Chrome -- even the new mode -- still leaks. A real windowed browser on a virtual display doesn't. |
| **CDP attach**, not Playwright launch | Chrome is started by us with no `--enable-automation`. Playwright connects after the fact, so `navigator.webdriver` stays false and no automation infobar appears. Browser stays warm between sessions. |
| **Persistent profile on a volume** | Your logins survive redeploys. This is the single biggest "beat the blocker" win -- most walls are auth walls, not bot detection. |
| **x11vnc + noVNC** | Watch the browser. Log in by hand once. Click the occasional CAPTCHA yourself. |
| **`@playwright/mcp`** over HTTP | Accessibility-tree snapshots -- token-efficient and far better for reading than raw HTML. |
| **Caddy** token gate | Nothing reaches the browser without the bearer token. |
| Font packs, software WebGL, correct TZ/locale | Missing fonts and absent WebGL are louder signals than most people realise. |

---

## Deploy on Coolify

1. **New Resource -> Docker Compose -> Public/Private Repository**, point at this repo. Coolify picks up `docker-compose.yaml`.

2. Set environment variables (copy from `.env.example`):

   ```
   MCP_TOKEN=<openssl rand -hex 32>
   TZ=America/Los_Angeles
   ```

   `MCP_TOKEN` is required -- compose refuses to start without it.

3. Point the Coolify domain at the **`gateway`** service, port **8080**.

4. Deploy. First build pulls Chrome and takes a few minutes.

5. Check it's alive:

   ```bash
   curl -H "Authorization: Bearer $MCP_TOKEN" https://browser.yourdomain.com/healthz
   ```

### Cloudflare Tunnel

Run `cloudflared` against the gateway (`http://gateway:8080` on the compose network, or the host port). Then -- and this is the part worth doing -- put **Cloudflare Access** in front of the hostname with a service token or your email as the only allowed identity. The bearer token in Caddy is defense-in-depth, not the front door.

**Never** tunnel port 6080 (noVNC) or 9222 (CDP). See below.

---

## First login

This is the step that actually makes the thing useful.

noVNC is bound to `127.0.0.1:6080` on the Docker host on purpose. Reach it over your tailnet:

```
http://<coolify-machine>.<your-tailnet>.ts.net:6080/vnc.html
```

(or `ssh -L 6080:127.0.0.1:6080 you@coolify-box` and hit `localhost:6080`)

You'll get a live Chrome window. Now:

- Sign in to the sites you want readable -- your news subscriptions, docs portals, whatever.
- Set Chrome's own settings if you like (block notifications, etc.).
- Leave it. Cookies land in the `chrome-profile` volume and persist across redeploys.

Do this once. Re-do it only when sessions expire.

---

## Connect Claude

Settings -> Connectors -> **Add custom connector**:

```
https://browser.yourdomain.com/mcp?token=<MCP_TOKEN>
```

If your client can set headers, prefer `Authorization: Bearer <MCP_TOKEN>` and drop the query param -- URLs leak into logs and history.

Works from the mobile app too, which is the whole point of hosting it rather than using a local browser extension.

---

## Security -- read this part

You are exposing a browser that holds live authenticated sessions, to a system that reads untrusted web pages. Those two facts interact badly.

**A page Claude reads can contain text crafted to look like instructions.** Prompt injection against a browsing agent is a real, demonstrated attack, and the browser it would be driving is one with your cookies in it. Upstream is blunt about the boundary: *Playwright MCP is not a security boundary.*

Practical rules:

1. **Use a dedicated throwaway Google account.** Not your main one.
2. **Never log into email, banking, cloud consoles, or anything with a saved payment method.** If compromise of this profile would be a bad day, it doesn't belong in this profile.
3. **Keep CDP (9222) on loopback.** It's bound to `127.0.0.1` inside the container and never published. Anyone reaching 9222 owns the browser completely, no token required.
4. **Keep noVNC off the public tunnel.** Tailnet or SSH tunnel only. It has no password.
5. **Rotate `MCP_TOKEN`** if you ever paste a `?token=` URL somewhere you shouldn't have.
6. Consider `network.blockedOrigins` in `mcp-config.json` to blocklist anything sensitive on your LAN -- this container sits inside your office network.

---

## Scope & limits

**What the anti-detection here actually buys you:** it stops you failing the *easy* checks -- `navigator.webdriver`, Chromium branding, missing fonts, absent WebGL, headless UA, automation infobar. Combined with a residential IP and real cookies, that clears the overwhelming majority of what blocks a naive fetch.

**What it does not buy you:** immunity. Sophisticated fingerprinting (DataDome, PerimeterX, Kasada) does behavioural and TLS-layer analysis this doesn't address. If you need that, you're in nodriver/Camoufox territory and a different repo.

**The residual tell** is GPU. Software SwiftShader rendering under Xvfb reports a WebGL vendor string no consumer machine has. Nothing to be done about it on a headless server short of passing through a real GPU. It's rarely load-bearing on its own.

**Velocity is your real risk.** You're on a static residential IP that you cannot rotate away from. If you burn its reputation, everyone on that office network eats CAPTCHAs -- your family, your work, your Slack. Keep it interactive and human-paced. That's not caution theatre; it's the actual asymmetry that matters here.

**One browser, one tab context.** This is deliberately single-session. Don't parallelise it.

**Terms of service.** Using your own subscriptions to read pages you pay for is fine. Automating past access controls on sites you don't have a relationship with is not, and this repo doesn't change that.

---

## Tuning

Route hostile targets through a proxy without touching the rest:

```
CHROME_EXTRA_ARGS=--proxy-server=http://user:pass@residential.example:8080
```

Pin the MCP version once you have a green deploy:

```
PLAYWRIGHT_MCP_VERSION=0.0.41
```

Load an extension (uBlock cuts noise and page weight considerably):

```
CHROME_EXTRA_ARGS=--load-extension=/data/extensions/ublock
```

---

## Troubleshooting

**Chrome won't start / restart loops** -- usually a stale `SingletonLock`. `start-chrome.sh` clears it, but if the volume is badly corrupted, wipe `chrome-profile` and log in again.

**MCP returns "no browser"** -- CDP wasn't up yet. `start-mcp.sh` waits 120s; check `docker compose logs browser` for Chrome crashes.

**Blank/black VNC** -- Xvfb up but Chrome down. Same logs.

**Pages die on media-heavy sites** -- raise `shm_size` above 2gb.

**Still getting blocked** -- check in this order: (1) are you actually logged in, via VNC; (2) is the site fingerprinting or just rate-limiting you; (3) only then reach for a proxy. Nine times out of ten it's (1).
