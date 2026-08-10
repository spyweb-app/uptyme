# PULSE - Periodic Uptime Live Status Engine

<p align="center">
  <img alt="Lua" src="https://img.shields.io/badge/Lua-scripting-000080?style=flat-square&logo=lua"/>
  <img alt="TypeScript" src="https://img.shields.io/badge/TypeScript-frontend-3178c6?style=flat-square&logo=typescript&logoColor=white"/>
  <img alt="Vue" src="https://img.shields.io/badge/Vue-3-42b883?style=flat-square&logo=vuedotjs&logoColor=white"/>
  <img alt="SQLite" src="https://img.shields.io/badge/SQLite-storage-003B57?style=flat-square&logo=sqlite&logoColor=white"/>
  <img alt="Vite" src="https://img.shields.io/badge/Vite-build-646cff?style=flat-square&logo=vite&logoColor=white"/>
  <img alt="UnoCSS" src="https://img.shields.io/badge/UnoCSS-atomic-333333?style=flat-square&logo=unocss&logoColor=white"/>
  <img alt="License" src="https://img.shields.io/badge/License-MIT-green?style=flat-square"/>
</p>

A self-hosted website uptime monitoring dashboard built on <a href="https://github.com/spyweb-app/spyweb" target="_blank" rel="noopener noreferrer">SpyWeb</a>. Monitors your websites and APIs at regular intervals and alerts you when they go down.

<p align="center">
  <img src="https://pulse.spyweb.app/pulse-monitors.jpeg" alt="Monitors Dashboard" width="49%" />
  <img src="https://pulse.spyweb.app/pulse-monitor.jpeg" alt="Monitor Detail" width="49%" />
</p>

## Demo

Try the live demo at **[https://pulse.spyweb.app/](https://pulse.spyweb.app/)**.

**API key:** `im-a-secure-key`

## Features

| | |
|---|---|
| 🖥️ **Cross-platform** | Linux, macOS (Intel & Apple Silicon), Windows |
| 📦 **Zero dependencies** | ~7MB binary, no runtime required |
| 🌐 **Monitor any URL** | HEAD, GET, POST with configurable intervals |
| 🔍 **Content checking** | Verify specific text exists in response body |
| 🔒 **TLS certificate monitoring** | Probe certificate expiry, alert before expiration |
| 📊 **Uptime tracking** | 24h, 7d, 30d percentages with response time history |
| 🔔 **Notification channels** | Discord, Slack, ntfy, webhooks, email (ON/OFF per channel) |
| 💻 **System notifications** | Native OS alerts when monitors go down |
| 🌍 **Multi-node cluster** | Central + checker roles, cross-location consensus to reduce false positives |
| 📥 **Import/Export** | Bulk import monitors from JSON or CSV files |
| 🌙 **Dark theme** | Clean, responsive dashboard UI |
| ⚡ **Dual binary** | CLI for servers, tray app for desktop background runs |
| 💾 **SQLite storage** | Queryable database for monitor history and settings |
| 🧹 **Automatic cleanup** | Old records purged daily based on retention settings |

## Setup

### Quick start

**Mac / Linux:**

```bash
curl -sSf https://pulse.spyweb.app/setup | bash
```

**Windows (PowerShell):**

```powershell
irm https://pulse.spyweb.app/setup-win | iex
```

This downloads project files and the SpyWeb binary ( auto detect your OS) to a `./pulse` directory.

### Manual

**Clone the repo:**
```bash
git clone https://github.com/spyweb-app/pulse
```

Or grab the <a href="https://github.com/spyweb-app/pulse/releases/latest" target="_blank" rel="noopener noreferrer">latest release</a> and extract it.

Then download the SpyWeb binary (<a href="https://docs.spyweb.app/getting-started" target="_blank" rel="noopener noreferrer">SQLite variant</a>) for your OS:

Extract `spyweb` and `spyweb-tray` to the project root

If you cloned the repo, run `./run` to install dependencies, build the dashboard, and start SpyWeb. If you downloaded a release, the dashboard is already built, you can just `./spyweb start`.

## Start

```bash
cd pulse
./run            # install deps, build dashboard, start SpyWeb

# or manually:
./spyweb start

# or with port:
# ./spyweb start --port 7979
```

Then open <a href="http://localhost:7979" target="_blank" rel="noopener noreferrer">http://localhost:7979</a>.

**Desktop users:** Run `spyweb-tray` instead of `spyweb` to run silently in the background with a system tray icon. Right-click the tray icon to open the dashboard or quit.

### API Key (optional)

Set an API key to protect your dashboard:

```bash
SPYWEB_API_KEY=your-undeniably-very-secure-secret ./spyweb start
```

The dashboard prompts for this key on first load and stores it in localStorage.

## Adding Monitors

### Via the dashboard

Click **Add Monitor** on the dashboard to create a monitor:

| Field | Description | Default |
|-------|-------------|---------|
| **Name** | Display name for the monitor | (required) |
| **URL** | The URL to check | (required) |
| **Method** | HTTP method: `GET`, `HEAD`, or `POST` | `HEAD` |
| **Interval** | Check frequency in seconds (10 - 86400) | `300` (5 min) |
| **Timeout** | Request timeout in milliseconds (1000 - 60000) | `10000` (10s) |
| **Content Check** | Text that must be present in the response body | (empty) |
| **Check Certificate** | Probe TLS certificate expiry (HTTPS only) | off |
| **Cert Threshold** | Days before expiry to alert (when cert check enabled) | `14` |
| **System Notify** | Show native OS notification when monitor goes down | off |

### Via import

Use the **Import** button to bulk-import monitors from JSON or CSV.

#### JSON format

See [`monitor.json.example`](monitor.json.example):

```json
[
  {
    "name": "My Website",
    "url": "https://example.com",
    "method": "HEAD",
    "interval_sec": 300,
    "timeout_ms": 10000
  },
  {
    "name": "Cert Monitor",
    "url": "https://example.com",
    "check_cert": 1,
    "cert_threshold_days": 14
  }
]
```

#### CSV format

See [`monitor.csv.example`](monitor.csv.example):

```csv
name,url,method,interval_sec,timeout_ms,check_value,enabled,check_cert,cert_threshold_days
My Website,https://example.com,HEAD,300,10000,,1,0,14
Cert Monitor,https://example.com,HEAD,3600,10000,,1,1,14
```

**CSV column reference:**

| Column | Required | Values |
|--------|----------|--------|
| `name` | yes | Any string |
| `url` | yes | Full URL with protocol |
| `method` | no | `GET`, `HEAD`, `POST` (default: `HEAD`) |
| `interval_sec` | no | 10 - 86400 (default: `300`) |
| `timeout_ms` | no | 1000 - 60000 (default: `10000`) |
| `check_value` | no | Text to search for in response body |
| `enabled` | no | `1` = enabled, `0` = disabled (default: `1`) |
| `check_cert` | no | `1` = check certificate, `0` = skip (default: `0`) |
| `cert_threshold_days` | no | Days before expiry to alert (default: `14`) |

## TLS Certificate Monitoring

Enable **Check certificate** on HTTPS monitors to probe TLS certificate expiry. Runs once per day (after the HTTP check), regardless of the monitor's check interval.

**How it works:**
1. Enable "Check certificate" on an HTTPS monitor
2. Set a threshold (default: 14 days)
3. Alert triggers when certificate expires within threshold
4. Certificate info stored and visible in monitor detail

**Global threshold:** Set a default in Settings.

## Notification Channels

Set up notification channels to receive alerts when monitors go down:

- **Discord** - Webhook URL for a Discord channel
- **Slack** - Webhook URL for a Slack channel
- **ntfy** - ntfy topic for push notifications
- **Webhook** - Generic HTTP POST webhook
- **Email** - SMTP email notifications (SendGrid)

Test channels from the Notifications page before assigning them to monitors.

**ON/OFF toggle:** Each channel has a global ON/OFF switch. Turning OFF silences all alerts across every assigned monitor without breaking the assignments.

## Monitor Settings

| Setting | Description |
|---------|-------------|
| **Content Check** | When set, the monitor fetches the URL with GET and checks if the text exists in the response body. If not found, the monitor is marked DOWN. |
| **Certificate Check** | Probe TLS certificate expiry. Runs once per day. Alerts when certificate expires within threshold. |
| **Status Codes** | 2xx and 3xx are UP. 4xx is marked BLOCKED (shown in amber). 5xx and connection errors are DOWN. |
| **Uptime Calculation** | Uptime percentage = (successful checks / total checks) x 100. Color-coded: green >= 99%, yellow >= 95%, red < 95%. |

## SpyWeb Configuration

PULSE runs on SpyWeb's engine. Two settings in `jobs/uptime-monitor/config.toml` you might want to adjust:

```toml
interval = 60    # How often SpyWeb checks for due monitors (seconds)
workers = 2      # How many monitors can be checked concurrently
```

**`interval`** - How often SpyWeb checks for due monitors. Default `60` means checks happen at most once per minute. A monitor with 5-second interval won't check that often unless you lower this.

**`workers`** - Concurrent HTTP requests. Keep this <= `SPYWEB_THREADS` (defaults to 2 if unset). More workers = more parallel checks, but needs more threads. `2` works on a 1 CPU VPS.

Set `SPYWEB_THREADS` to match your CPU cores:

```bash
SPYWEB_THREADS=2 ./spyweb start
```

Docs: <a href="https://docs.spyweb.app/job-configuration/toml-config//#behavior" target="_blank" rel="noopener noreferrer">TOML config</a>, <a href="https://docs.spyweb.app/job-configuration/multi-worker/#concurrency-settings" target="_blank" rel="noopener noreferrer">concurrency settings</a>.

## Multi-node / Cluster

Run PULSE from multiple locations and combine results into a single consensus — central only alerts when enough independent nodes agree a target is actually down. Checkers only alert when they lose contact with central.

One **central** node owns monitors and evaluates consensus. One or more **checker** nodes probe targets from different networks and report back.

See [`MULTI_NODE.md`](MULTI_NODE.md) for the full setup guide (central + checker bootstrap, token onboarding, consensus tuning, security).

## Retention & Storage

Check history grows over time. **Retention Days** (Settings, default: 90) controls how long records are kept.

**Storage considerations:**

| Interval | Retention | Records per monitor |
|----------|-----------|---------------------|
| 5 min | 90 days | ~25,920 |
| 1 min | 90 days | ~129,600 |
| 5 min | 365 days | ~105,120 |
| 1 min | 365 days | ~525,600 |

With 100 monitors at 1-minute intervals and 90-day retention, you'd have ~12.9 million records. SQLite handles it, but the database file will grow.

**Automatic cleanup:** Runs once per day after a check cycle, deleting records older than the retention period.

## Project Structure

```
pulse/
  spyweb              # SpyWeb binary (downloaded at install)
  spyweb-tray         # SpyWeb tray binary (optional)
  run                 # Run tests, build, start (bash)
  watch               # Dev mode: SpyWeb + Vite hot reload (bash)
  dashboard/          # Vue 3 + Vite frontend (source)
    src/
      api.ts          # API client and type definitions
      stores/         # Pinia stores (monitors, channels, auth, app)
      components/     # Vue components
      pages/          # Dashboard, Notifications, Settings pages
      layouts/        # Layout wrapper
  ui/                 # Pre-built dashboard (served by SpyWeb)
  server/             # SpyWeb Lua API handlers
    init.lua          # Route definitions
    handlers/         # Monitor, channel, settings, health handlers
  lib/                # Shared Lua libraries
    db.lua            # Database schema and queries
    check.lua         # Status classification
    notifier/         # Discord, Slack, ntfy, webhook, email
  jobs/               # SpyWeb job configurations
    uptime-monitor/   # Main monitoring job
  data                # SQLite database (created on first run)
```

## Development

Only needed if you modify the dashboard UI.

> **Note:** `./run` and `./watch` are bash scripts and don't work on Windows. Use WSL, Git Bash, or run commands manually.

```bash
./run                 # Run tests, build dashboard, start SpyWeb
./watch               # Start SpyWeb + Vite dev server with hot reload
```

Or manually:

```bash
# Terminal 1
./spyweb start --port 8000

# Terminal 2
cd dashboard
npm install
npm run dev          # Vite dev server on port 5173 (proxies API to 8000)
```

## Deployment

PULSE is just a binary + static files. Run it however you run background services.

**Linux:** Use systemd to auto-start on boot and restart on crash. See the <a href="https://docs.spyweb.app/api-and-server/deployment/" target="_blank" rel="noopener noreferrer">SpyWeb deployment guide</a> for the full setup.

**Docker / PM2 / supervisord:** Any process manager works. Just run `./spyweb start`.

**Remote access:** Use SSH tunnel, Nginx reverse proxy, or Caddy. See the <a href="https://docs.spyweb.app/api-and-server/deployment/#5-accessing-the-ui-securely" target="_blank" rel="noopener noreferrer">SpyWeb deployment guide</a>.

## License

MIT
