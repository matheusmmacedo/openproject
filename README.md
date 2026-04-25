# openproject

OpenProject self-hosted deployment for **KLaOS Projects** (`https://project.klaos.ai`) — the project management half of the Klaos triad (Zammad helpdesk + OpenProject PM + Slack notifications).

Sister repository: [`matheusmmacedo/zammad`](https://github.com/matheusmmacedo/zammad) (KLaOS Helpdesk).

## Architecture

- **Upstream**: [`opf/openproject-docker-compose`](https://github.com/opf/openproject-docker-compose) branch `stable/17` — `docker-compose.yml`, `docker-compose.control.yml`, `proxy/`, `control/` are verbatim copies, rebased via `scripts/update-upstream.sh`. The currently tracked commit is pinned in `UPSTREAM`.
- **Customizations**: branding/translations/integrations live in `packages/src/<name>/` (mirrors the pattern from the sister Zammad repo). OpenProject doesn't have a `.zpm` system like Zammad — branding is applied at deploy time via env vars (`OPENPROJECT_DEFAULT__THEME`, custom logo upload) and SQL `Setting` rows.
- **Deploy**: Railway project `KLaOS Projetos` (production). On Railway we **skip the bundled Caddy proxy** (Railway terminates TLS itself) and the **autoheal sidecar** (it requires the docker socket).

## Layout

```
docker-compose.yml              1:1 from upstream stable/17
docker-compose.control.yml      idem
control/                        upstream backup/upgrade helpers (reference)
proxy/                          Caddy reverse proxy build (used in dev, skipped on Railway)
.env.example                    upstream env template
packages/
  src/                          our customizations (1 folder per module)
scripts/
  update-upstream.sh            git pull from opf/openproject-docker-compose stable/17
.github/workflows/              CI: image build & publish, weekly upstream check
DEPLOY.md                       Railway+Rails playbook (carried over from the Zammad repo)
UPSTREAM                        currently tracked upstream branch + commit SHA
LICENSE                         GPLv3 (inherited from OpenProject)
README.upstream.md              original upstream README
```

## Workflows

### Bump upstream

```bash
./scripts/update-upstream.sh              # show diff vs current pinned commit
./scripts/update-upstream.sh --apply      # apply latest stable/17 HEAD
git diff
git add docker-compose.yml control proxy UPSTREAM
git commit -m "chore: bump openproject-docker-compose to <sha>"
git push
```

GitHub Actions workflow `.github/workflows/sync-upstream.yml` opens a PR weekly when the upstream `stable/17` HEAD has moved.

### New customization

```bash
mkdir -p packages/src/klaos-branding
# add CSS, logos, SQL seeds, or migration scripts
git add packages
git commit -m "feat(klaos-branding): logo + brand colors"
git push
```

## License

This repository is [GPLv3](LICENSE), inherited from OpenProject. **No secrets in this repository** — all runtime configuration (DB credentials, S3 keys, OAuth) lives in Railway environment variables.
