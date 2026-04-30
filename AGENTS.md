# OpenProject Klaos — Development Guidelines

## 🛡️ Diretiva crítica de fork — JAMAIS perder upstream NEM customs

Este repo é um **fork de openproject-docker-compose upstream** (`opf/openproject-docker-compose`).
Versão upstream rastreada em `UPSTREAM` (atualmente `stable/17 @ cb8ba0044387`).

A camada de customização Klaos vive em **`packages/src/klaos-*/`** como
**OpenProject Plugins (Rails Engines)** — sistema oficial OP de extensão.

```
packages/
  src/
    klaos-branding/             ← engine: branding (logo, cores, footer)
      config/
    klaos-enterprise-unlock/    ← engine: bypass EnterpriseToken (NÃO é monkey-patch direto)
      config/

scripts/klaos-init.sh           ← roda OpenProject::Plugins::Loader no boot
control/                        ← Klaos control plane scripts
proxy/                          ← Nginx proxy custom
```

### Regra de ouro

1. **NUNCA edite código fora de `packages/src/klaos-*/`, `scripts/`, `control/`, `proxy/`** sem justificativa.
2. Bug fix Klaos-specific? **Crie ou estende um Rails engine** em `packages/src/klaos-*/`.
3. Bug em código core do OpenProject (Ruby/Vue/Angular)?
   - **Esse repo NÃO contém o source code do OP** — só o docker-compose + plugins. O source é a image `openproject/community:17` puxada do Docker Hub.
   - Pra "fix" no core, opções (em ordem de preferência):
     1. **Plugin com `prepend_mod_with`** ou similar (carregar via `OPENPROJECT_PLUGINS_FROM_GEMFILE_PLUGIN`).
     2. **Patch via initializer dentro do plugin** (`packages/src/klaos-fix-X/config/initializers/patch.rb`).
     3. Última opção: fork do OP source code, build de imagem custom, push em registry. Documente custo (manutenção contínua).
   - Marque verdict com `upstream_patch_justified: true` se for opção 3.

### Por que isso importa

OP upstream lança releases mensais (stable/17, stable/18 etc). Sem isolamento,
cada upgrade requer auditoria de dezenas de patches. **Plugins são first-class
no OP** e sobrevivem upgrades por design.

### Padrão de criar engine Klaos

```ruby
# packages/src/klaos-<feature>/lib/klaos/<feature>/engine.rb
module Klaos
  module <Feature>
    class Engine < ::Rails::Engine
      isolate_namespace Klaos::<Feature>
      config.to_prepare do
        # extends/prepends aqui
        WorkPackage.prepend(Klaos::<Feature>::WorkPackagePatch) if defined?(WorkPackage)
      end
    end
  end
end
```

Carregamento: `klaos-init.sh` ou via `OPENPROJECT_PLUGINS` env var.

### O caso `klaos-enterprise-unlock`

Bypass do EnterpriseToken **NÃO** é monkey-patch direto no core — é plugin que
faz `prepend` na classe Token. Isso significa que upgrades de OP não quebram o
unlock (o prepend re-aplica em qualquer versão da classe upstream).

**Use esse padrão como referência** ao adicionar novos overrides.

---

## Storage / MinIO

OP attachments rodam via Fog/S3 contra MinIO em Railway (`KLaOS Projetos` project).
Endpoint: `https://minio-production-dbbc.up.railway.app`.
Bucket: `op-attachments`.

Se modificar comportamento de upload, garanta backward-compat com Fog AWS S3
(MinIO suporta), e teste GET `/api/v3/attachments/<id>/content` pra confirmar
roundtrip.

---

## Deploy

Container roda via Railway (KLaOS Projetos project, service `web`).
Boot pega image OP slim → mounta volume → roda `entrypoint-slim.sh` → carrega plugins.

---

## Código source-of-truth

- AGENTES de fix automático (klaos-agent-runner) leem ESTE arquivo via `loadRepoContext`.
- Mude regras aqui se a estratégia evoluir.
