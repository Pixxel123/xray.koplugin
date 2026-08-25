# KOReader X-Ray — Cloudflare Worker Setup Relay

An ephemeral, zero-knowledge pairing relay that allows users to configure their API keys on their KOReader e-reader from any smartphone or PC.

## Features
- **Works Everywhere**: Outbound HTTPS polling bypasses guest Wi-Fi isolation, cellular 5G data, WSL emulators, and local firewalls.
- **Zero-Knowledge End-to-End Encryption (E2EE)**: Keys are encrypted in the browser using Web Crypto (`AES-256-GCM`) with a client-generated secret in the URL hash fragment (`#<secret>`). Plaintext keys are never visible to Cloudflare.
- **Single-File Zero Dependency**: Serves both the mobile web UI and ephemeral pairing endpoints in a single `worker.js` file.
- **100% Free**: Operates entirely within Cloudflare's free tier (100,000 requests/day).

---

## Deployment (1-Click)

### Method 1: Cloudflare Dashboard (No CLI required)
1. Log in to [Cloudflare Dashboard](https://dash.cloudflare.com) and go to **Workers & Pages**.
2. Click **Create Application** → **Create Worker**.
3. Name it (e.g. `koreader-xray-setup`) and click **Deploy**.
4. Click **Edit Code**, paste the entire contents of `worker.js`, and click **Deploy**.
5. Your worker URL will be `https://koreader-xray-setup.<your-subdomain>.workers.dev`.

### Method 2: Wrangler CLI
```bash
npm install -g wrangler
wrangler login
wrangler deploy
```
