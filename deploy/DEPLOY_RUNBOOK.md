# PeakSell Studio — "deploy it" runbook

**Trigger:** the user sends `deploy it` (any casing, maybe nothing else). That
means: move PeakSell Studio from the Windows PC to the newly paid VPS, with no
downtime beyond a few minutes and no app re-registration. Follow this file top
to bottom. Ask the user only for what is marked **ASK**.

## What exists already (prepared 2026-11-11)

| Thing | Where |
|---|---|
| Code (fork of BrightBean Studio, rebranded) | `F:\wathab\peak sell content\07_DISTRIBUTION\peaksell-studio`, pushed to `https://github.com/Wathabhamdto/peaksell-studio` (branch `main`) |
| Public URL | `https://studio.peaksell.agency` via a **Cloudflare Tunnel** (remote-managed; token in `.env` as `CLOUDFLARE_TUNNEL_TOKEN`). Tunnel public hostname → `http://caddy:80`. DNS for `peaksell.agency` is on Cloudflare (registrar: name.com). |
| Secrets | `.env` in the repo folder (git-ignored). Holds `SECRET_KEY`, `ENCRYPTION_KEY_SALT` (decrypts stored social tokens — **must move unchanged**), `POSTGRES_PASSWORD`, tunnel token, platform app credentials. |
| Stack command | `docker compose -f docker-compose.yml -f docker-compose.prod.yml -f docker-compose.tunnel.yml …` (call it `DC` below). Services: postgres, migrate, app (gunicorn), worker (publisher), caddy, cloudflared. No public ports. |
| Scripts | `deploy/export_from_pc.ps1`, `deploy/vps_bootstrap.sh`, `deploy/restore_on_vps.sh`, `deploy/backup_cron.sh` |
| Tools on PC | Docker Desktop, git, gh (logged in as Wathabhamdto), Python 3.12, Windows OpenSSH (`ssh`, `scp`) |

Because the hostname lives in the tunnel, moving hosts = stop on PC, start on
VPS with the same `.env`. Meta / Google / TikTok redirect URIs stay valid.

## Golden rules

- **Never run the PC stack and the VPS stack at the same time.** Two workers
  double-publish posts; two tunnel connectors split traffic.
- Never print or paste secrets from `.env` into chat. Never commit `deploy/bundle/`.
- Don't type passwords for the user. SSH access is by key (step 1).
- Confirm with the user before the cutover (step 4), since it pauses publishing.

## Steps

### 0. Pre-flight (PC)
1. `git -C <repo> status` clean and `git log origin/main..main` empty; if not, commit (with the attribution trailer) and push.
2. `.env` has non-empty `CLOUDFLARE_TUNNEL_TOKEN` and `POSTGRES_PASSWORD`; `APP_URL=https://studio.peaksell.agency`.
3. `DC ps` on the PC shows everything running; `curl https://studio.peaksell.agency/health/` → `{"status": "ok"}`.

### 1. **ASK** for the VPS and get SSH access
Ask: VPS public IP, OS (expect Ubuntu 22.04/24.04), SSH user (usually `root`), RAM/CPU (want ≥ 4 GB RAM, 2+ vCPU, 40+ GB disk).
- Create a key if missing: `ssh-keygen -t ed25519 -f $HOME\.ssh\peaksell_vps -N '""' -C peaksell-vps`.
- Have the user authorise it **themselves** (they type the root password) in a terminal tab you open:
  `type $HOME\.ssh\peaksell_vps.pub | ssh root@<IP> "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"`
  (or they paste the `.pub` content into the provider's SSH-key panel and rebuild/reset).
- Verify: `ssh -i $HOME\.ssh\peaksell_vps -o StrictHostKeyChecking=accept-new root@<IP> "uname -a; free -h; df -h /"`.

### 2. Bootstrap the VPS
`scp -i … deploy/vps_bootstrap.sh root@<IP>:/root/` then `ssh … "bash /root/vps_bootstrap.sh"` (Docker, ufw SSH-only, swap, auto-updates, log rotation). Run in background if slow.

### 3. Pre-build on the VPS (no downtime yet)
`ssh … "git clone https://github.com/Wathabhamdto/peaksell-studio.git /opt/peaksell-studio"` then copy `.env` there (`scp` to `/opt/peaksell-studio/.env`, `chmod 600`) and run `cd /opt/peaksell-studio && DC build`. Do **not** `up` yet.

### 4. Cutover (**ASK** the user for a go — publishing pauses ~5–10 min)
Check the PC for posts scheduled in the next 30 min (`DC exec -T postgres psql -U postgres -d peaksell -c "select count(*) from composer_platform_post where status='scheduled' and scheduled_at < now() + interval '30 min';"`). Prefer a quiet window.
1. PC: `powershell -ExecutionPolicy Bypass -File deploy\export_from_pc.ps1` → writes `deploy\bundle\` and stops the PC stack.
2. `scp -i … deploy/bundle/peaksell.dump deploy/bundle/media.tgz deploy/bundle/.env root@<IP>:/root/peaksell-bundle/` (create the dir first, `chmod 700`).
3. VPS: `bash /opt/peaksell-studio/deploy/restore_on_vps.sh /root/peaksell-bundle`.

### 5. Verify (all must pass)
- `curl -fsS https://studio.peaksell.agency/health/` from the PC.
- Cloudflare: Zero Trust → Networks → Tunnels → the tunnel shows **one** connector, origin IP = VPS. (If the user can't check, `DC logs cloudflared` on VPS shows "Registered tunnel connection".)
- `DC logs --tail 50 worker` on the VPS: worker started, no tracebacks.
- Log in at the URL (the user does this); channels still connected; a test post publishes.
- `docker ps` on the PC shows no peaksell containers.

### 6. Hardening & backups
- `install -m 755 /opt/peaksell-studio/deploy/backup_cron.sh /usr/local/bin/peaksell-backup && echo '30 3 * * * root /usr/local/bin/peaksell-backup' > /etc/cron.d/peaksell-backup`, run it once, check `/var/backups/peaksell/`.
- Delete `/root/peaksell-bundle` on the VPS. On the PC, move `deploy\bundle\` to the user's chosen backup location or delete it after a successful day (it holds secrets) — ASK.
- Optional: disable SSH password login (`PasswordAuthentication no`) once key login is confirmed — ASK first.

### 7. Report
Tell the user: URL live from VPS, PC freed (Docker Desktop can be closed), backups nightly 03:30, how to update (`cd /opt/peaksell-studio && git pull && DC up -d --build`). Update the memory file `peaksell-distribution-platform.md` with VPS IP/provider (no secrets).

## Rollback
VPS: `DC down`. PC: copy the bundle `.env` back if changed, `DC up -d` in the repo folder. Data written on the VPS after cutover would be lost unless dumped first (`pg_dump` → restore on PC).

## Troubleshooting
- **Redirect loop / CSRF 403:** Caddy must trust forwarded headers (global `trusted_proxies static private_ranges` in `Caddyfile`); `ALLOWED_HOSTS` must contain `studio.peaksell.agency`.
- **502 from Cloudflare:** tunnel hostname service must be `http://caddy:80`; `DC ps` shows caddy/app healthy.
- **`password authentication failed`** on a reused PC volume: the volume was initialised with password `postgres`; run `DC exec postgres psql -U postgres -c "ALTER USER postgres PASSWORD '<POSTGRES_PASSWORD>';"` (read the value from `.env` without echoing it to chat).
- **Encrypted tokens unreadable after move:** `.env` `ENCRYPTION_KEY_SALT`/`SECRET_KEY` differ from the PC — restore the PC `.env`.
