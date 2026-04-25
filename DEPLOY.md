> **Note for OpenProject readers:** this file was first written for the
> sister `matheusmmacedo/zammad` repo. The traps catalogued here are
> Railway-and-Rails-monolith generic, so they apply here too. Specific
> OpenProject quirks will be added as they're discovered. Service names,
> IDs, and command shapes below refer to the Zammad install — translate
> mentally (e.g. `zammad-railsserver` ≈ OpenProject `web`).

# Deploying on Railway

Notes and workarounds from getting this Zammad fork live on Railway (`helpdesk.klaos.ai`, April 2026). Written as reference for the next time somebody deploys a Rails-monolith-with-worker-fleet on Railway — or for when we do the same for OpenProject.

**TL;DR:** Railway's private network is IPv6-only. The upstream Zammad docker-entrypoint assumes IPv4. Working around that is 80% of the pain.

---

## Architecture

Railway project: **KLaOS Helpdesk** (ID `bf5c2868-0e4d-4870-a5ad-f7dc7aa86702`), single `production` environment, 9 services:

| Service | Image | Command | Volume |
|---|---|---|---|
| `zammad-postgresql` | `postgres:17-alpine` | default | `/var/lib/postgresql/data` |
| `zammad-redis` | `redis:7-alpine` | default | — |
| `zammad-memcached` | `memcached:alpine` | default | — |
| `zammad-elasticsearch` | `elasticsearch:8.19.8` | default | `/usr/share/elasticsearch/data` |
| `zammad-init` | `ghcr.io/zammad/zammad:<ver>` | `/opt/zammad/bin/docker-entrypoint zammad-init` | — |
| `zammad-railsserver` | same | `/opt/zammad/bin/docker-entrypoint zammad-railsserver` | — |
| `zammad-websocket` | same | `/opt/zammad/bin/docker-entrypoint zammad-websocket` | — |
| `zammad-scheduler` | same | `/opt/zammad/bin/docker-entrypoint zammad-scheduler` | — |
| `zammad-nginx` | same | see "nginx resolver fix" below | — |

Public HTTP traffic → `zammad-nginx` (custom domain `helpdesk.klaos.ai`, port 8080).
`zammad-nginx` → proxies to `zammad-railsserver:3000` and `zammad-websocket:6042` via the Railway private network.

Attachment storage: Cloudflare R2 (S3-compatible) via `S3_URL` env var on each Zammad service. Avoids the Railway "one volume per service" limitation (web + scheduler + websocket all need to read/write the same blob store).

---

## The recurring traps

### 1. Railway private network is IPv6-only

Every service-to-service call on Railway uses `<service-name>.railway.internal` which resolves **only to IPv6** (`fd12::…` ULA space). Anything that binds to `0.0.0.0` (IPv4-only) won't be reachable from sibling services.

**Symptoms we hit:**
- `zammad-init waiting for elasticsearch server to be ready…` forever (bash `/dev/tcp` couldn't reach ES on IPv4).
- nginx upstream `Connection timed out` when proxying to `zammad-railsserver:3000`.

**Fix:** set the bind address on services that have it tunable.

- **Elasticsearch:** `network.host="::"` and `http.host="::"`. Values **must be quoted**, because raw `::` is invalid YAML (mapping-value indicator).
- **Puma (railsserver):** Zammad already binds `tcp://[::]:3000` in the default entrypoint. No action.
- **Redis/Memcached/Postgres:** default binds include IPv6 on their alpine images. No action.

### 2. nginx `resolver.conf` generated without IPv6 brackets

Zammad's nginx entrypoint (`/opt/zammad/bin/docker-entrypoint`, `zammad-nginx` branch) does:

```bash
NAMESERVER=$(grep "^nameserver" --max-count 1 < /etc/resolv.conf | awk '{print $2}')
echo "resolver $NAMESERVER valid=5s;" > /etc/nginx/conf.d/resolver.conf
```

On Railway `/etc/resolv.conf` has an IPv6 nameserver like `fd12::10`, which nginx rejects because the address needs brackets (`[fd12::10]`).

**Symptom:** nginx crash-loops with `[emerg] invalid port in resolver "fd12::10" in /etc/nginx/conf.d/resolver.conf:1`.

**Fix:** patch the generated `resolver.conf` by copying the entrypoint, removing the offending line via `sed`, and substituting our own version that knows about brackets. This lives in the `startCommand` of the `zammad-nginx` service:

```sh
sh -c 'NS=$(grep "^nameserver" /etc/resolv.conf | head -1 | cut -d" " -f2); case "$NS" in *:*) NS="[$NS]";; esac; echo "resolver $NS valid=5s;" > /tmp/rc.fix; sed "s|echo \"resolver \$NAMESERVER valid=5s;\" > /etc/nginx/conf.d/resolver.conf|cp /tmp/rc.fix /etc/nginx/conf.d/resolver.conf|" /opt/zammad/bin/docker-entrypoint > /tmp/e; chmod +x /tmp/e; exec /tmp/e zammad-nginx'
```

### 3. `startCommand` replaces ENTRYPOINT too (not just CMD)

The Zammad image's `Dockerfile` uses:

```dockerfile
ENTRYPOINT ["/opt/zammad/bin/docker-entrypoint"]
CMD ["zammad-railsserver"]  # varies per image flavor
```

In upstream `docker-compose.yml`, services set `command: ["zammad-init"]` — Docker passes that as the argv to the entrypoint, which is the dispatcher. On **Railway**, `startCommand` replaces both ENTRYPOINT and CMD, so `startCommand: zammad-init` tries to exec a binary named `zammad-init` and fails with `The executable 'zammad-init' could not be found.`

**Fix:** invoke the entrypoint explicitly:

```
/opt/zammad/bin/docker-entrypoint zammad-init
/opt/zammad/bin/docker-entrypoint zammad-railsserver
/opt/zammad/bin/docker-entrypoint zammad-websocket
/opt/zammad/bin/docker-entrypoint zammad-scheduler
```

### 4. Service name = DNS name = must match upstream compose

The upstream Zammad nginx template has:

```nginx
upstream zammad-railsserver { server 127.0.0.1:3000; }
upstream zammad-websocket   { server 127.0.0.1:6042; }
```

The entrypoint rewrites `127.0.0.1` with `$ZAMMAD_RAILSSERVER_HOST` (default `zammad-railsserver`). On Railway the actual hostname is `<service-name>.railway.internal`, so we set the env var:

```
ZAMMAD_RAILSSERVER_HOST=zammad-railsserver.railway.internal
ZAMMAD_WEBSOCKET_HOST=zammad-websocket.railway.internal
```

**Trap:** we initially created the web service as `zammad-railway` (compose nickname for the backend) and only later noticed the command is `zammad-railsserver`. Service name and command name **must** match upstream — rename before wasting time setting env vars.

### 5. `volume_create` can time out but still create the volume

Railway API returned HTTP 504 on a `POST /volumes` call that actually succeeded. Retrying created a **second** volume, which deadlocked the Postgres service (`Container failed to start` with no logs).

**Fix before creating a volume:** `volume_list` first. After a 504, `volume_list` again before retrying.

### 6. `service_update` doesn't trigger a redeploy

Setting `startCommand` on an existing service via `service_update` changes the config but doesn't rebuild. A restart ran the **old** deployment. To force a fresh deploy, add/flip a dummy env var (e.g. `RAILWAY_DEPLOY_TRIGGER=1`) after the `service_update`.

### 7. Railway `domain_create` rejects custom domains via API

Calling `domain_create` with `domain: "helpdesk.klaos.ai"` returned `Invalid domain` even after the CNAME was globally propagated. The dashboard UI accepts it fine. Probably an MCP / API-surface bug — just add custom domains manually in the dashboard.

### 8. Settings via SQL need `state_current` as YAML (or JSON — Zammad takes both)

Zammad stores settings as a YAML-serialized `{ value: ... }` hash:

```yaml
---
value: helpdesk.klaos.ai
```

JSON (`{"value":"..."}`) also parses and writes cleanly, which is what `scripts/apply-branding.mjs` uses. After any direct SQL update, **restart zammad-railsserver** to bust the memcached settings cache.

### 9. Elasticsearch 8.x doesn't like the env-var-to-YAML path

`elasticsearch:8.19.8` reads env vars, converts them into its `elasticsearch.yml`, and then its own YAML parser chokes on `network.host: ::` (the bare `::` is YAML mapping-value). Quoting didn't help in our tests; the actual stack trace lives in `/usr/share/elasticsearch/logs/zammad.log` which Railway's log stream doesn't surface.

**What worked:** downgrade to `docker.elastic.co/elasticsearch/elasticsearch:7.17.25` with:

```
discovery.type=single-node
xpack.security.enabled=false
bootstrap.memory_lock=false
cluster.name=zammad
node.name=zammad-es-1
network.host="::"
http.host="::"
ES_JAVA_OPTS=-Xms256m -Xmx256m
```

7.17 accepts the quoted `"::"` cleanly. **Don't set `network.host=0.0.0.0,::`** — ES refuses to bind a wildcard mixed with a specific family (`bind address: {0.0.0.0} is wildcard, but multiple addresses specified`). `::` alone is enough because dual-stack sockets accept IPv4-mapped connections.

**Triggering the index rebuild on first connect:** set `ELASTICSEARCH_REINDEX=true` on `zammad-init`, redeploy, then remove the var so subsequent inits don't rebuild again.

---

## Replication checklist (for the next deploy)

1. **Create Railway project** (`KLaOS Projetos` for OpenProject, etc.). Single `production` environment unless you need staging.
2. **Provision services from Docker images** with the right **service names** that match upstream compose (DNS matters).
3. **Volumes:** `volume_list` before creating. Handle 504s carefully.
4. **Env vars per service:**
   - `<UPSTREAM>_HOST` vars point to `<service>.railway.internal`.
   - ES-like services need `network.host="::"` (quoted).
   - Set `ZAMMAD_FQDN` / equivalent to your custom domain.
5. **startCommand with explicit entrypoint** when the upstream image has a dispatcher.
6. **Flip `RAILWAY_DEPLOY_TRIGGER`** after any `service_update` to force a redeploy.
7. **For nginx-in-frontend services:** patch the resolver generation to bracket IPv6 (see §2).
8. **Custom domain:** add in the **dashboard**, not via API.
9. **Storage:** prefer S3-compatible (R2, B2) over Railway volumes when multiple services need the same blobs.
10. **Post-deploy settings via SQL:** YAML-serialized state + restart the main app service.

---

## Reference IDs (KLaOS Helpdesk)

- Project: `bf5c2868-0e4d-4870-a5ad-f7dc7aa86702`
- Environment (production): `b7b42abd-39c4-449b-b3ce-42c421c25780`
- Custom domain: `helpdesk.klaos.ai` (CNAME → `zammad-nginx-production.up.railway.app`)
- Notification sender: `KLaOS Helpdesk <noreply@klaos.ai>` via Resend SMTP (`smtp.resend.com:465`, user `resend`)

Secrets (API tokens, DB passwords) live exclusively in Railway env vars — never in this repo.
