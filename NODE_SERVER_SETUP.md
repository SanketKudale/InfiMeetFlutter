# CSN Node Backend Setup Guide

This guide explains how to set up the CSN Node.js backend on a new server (VM, VPS, or bare metal).

## 1. Prerequisites

Install the following on your server:

- Node.js `>= 20`
- npm (comes with Node.js)
- PostgreSQL `>= 14`
- Git
- PM2 (recommended for production process management)

Optional but recommended:

- Nginx (reverse proxy + HTTPS)
- Docker + Docker Compose (if you prefer containerized PostgreSQL)

## 2. Clone Backend Project

The backend project path used in your local setup is:

`C:\Users\LENOVO\StudioProjects\iks\CSN`

On server, clone the backend repository to any folder, for example:

```bash
mkdir -p /opt/csn
cd /opt/csn
git clone <your-backend-repo-url> CSN
cd CSN
```

## 3. Install Dependencies

```bash
npm install
```

## 4. Create PostgreSQL Database

Create DB/user and grant access.

Example:

```sql
CREATE USER csn_user WITH PASSWORD 'csn_password';
CREATE DATABASE csn OWNER csn_user;
GRANT ALL PRIVILEGES ON DATABASE csn TO csn_user;
```

If your project has SQL scripts/migrations, run them now.

Important:
- Ensure required tables exist (for example `users`, `rooms`, `call_requests`, memberships, access tables).
- If you get runtime errors like `relation "call_requests" does not exist`, schema setup is incomplete.

## 5. Configure Environment

Copy `.env.example` to `.env`:

```bash
cp .env.example .env
```

Edit `.env` and set all required values.

Minimum required keys:

- `NODE_ENV=production`
- `HOST=0.0.0.0`
- `PORT=6713`
- `DATABASE_URL=postgres://csn_user:csn_password@127.0.0.1:5432/csn`
- `JWT_SECRET=<long-random-secret>`
- `JWT_ISSUER=csn`
- `JWT_AUDIENCE=csn-users`
- `ADMIN_USER_IDS=admin-1`

Media/WebRTC-related keys:

- `MEDIASOUP_ANNOUNCED_IP=<public-or-lan-ip-of-server>`
- `MEDIASOUP_RTP_MIN_PORT=40000`
- `MEDIASOUP_RTP_MAX_PORT=49999`
- `MEDIASOUP_LOG_LEVEL=warn`

Queue/call flow keys:

- `REQUEST_TOKEN_TTL=12h`
- `REQUEST_TIMEOUT_MINUTES=10`
- `REQUEST_ETA_SECONDS_PER_CALL=180`

Push notification keys (optional, only if FCM enabled):

- `FCM_ENABLED=true|false`
- `FCM_SERVICE_ACCOUNT_FILE=/absolute/path/service-account.json`
  or
- `FCM_SERVICE_ACCOUNT_JSON=<json-or-base64-json>`

## 6. Open Firewall Ports

At minimum:

- `6713/tcp` (HTTP/WebSocket API)
- `40000-49999/udp` (mediasoup RTP range, match your env values)

If using HTTPS through Nginx:

- `80/tcp`
- `443/tcp`

## 7. Run in Development (Quick Check)

```bash
npm run dev
```

Verify logs show:

- `Server listening at http://<server-ip>:6713`

Test endpoints:

- `GET http://<server-ip>:6713/health`
- `GET http://<server-ip>:6713/docs`

## 8. Run in Production

### Option A: Node direct

```bash
npm run build
npm run start
```

### Option B: PM2 (recommended)

```bash
npm run build
pm2 start dist/index.js --name csn-backend
pm2 save
pm2 startup
```

Monitor:

```bash
pm2 status
pm2 logs csn-backend
```

## 9. Reverse Proxy + HTTPS (Nginx)

Use Nginx to terminate TLS and proxy HTTP + WebSocket upgrades to Node (`127.0.0.1:6713`).

Example Nginx server block:

```nginx
server {
  listen 80;
  server_name your-domain.com;

  location / {
    proxy_pass http://127.0.0.1:6713;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
  }
}
```

Then issue TLS cert (for example with Certbot) and force HTTPS.

## 10. Production Validation Checklist

- `GET /health` returns `200`
- `/docs` loads from mobile browser
- WebSocket connects at `/ws`
- Admin token generation works (`POST /admin/token`)
- User request works (`POST /requests`)
- Admin queue works (`GET /admin/requests`)
- Accept/decline/end routes work
- Audio/video works both directions
- RTP UDP ports are reachable externally

## 11. Common Issues

1. `Connection refused`
- Node process not running
- wrong IP/PORT in app
- firewall blocking `6713`

2. `WebSocket ... not upgraded` / HTTP 426
- reverse proxy not forwarding `Upgrade` headers
- wrong ws URL path (must be `/ws`)

3. `Missing access token` / `Invalid access token`
- JWT mismatch (secret/issuer/audience)
- token expired

4. `relation "... does not exist"`
- database schema/migrations not applied

5. Remote media not flowing
- wrong `MEDIASOUP_ANNOUNCED_IP`
- UDP RTP range blocked

## 12. Mobile App Configuration

In Flutter app:

- `baseUrl = http://<server-ip>:6713` (or HTTPS domain)
- `wsUrl = ws://<server-ip>:6713/ws` (or `wss://<domain>/ws`)

For physical devices, use LAN/public server IP, not `localhost` or emulator loopback.

## 13. Security Recommendations

- Use strong random `JWT_SECRET`
- Run behind HTTPS in production
- Restrict admin JWT creation/access
- Limit CORS and trusted origins
- Keep Node and dependencies updated
- Rotate FCM service account keys when needed

