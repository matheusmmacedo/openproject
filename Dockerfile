# KLaOS Projects — OpenProject image with our customizations staged.
# All OpenProject service variants (web, worker, cron, seeder) share the
# same image; the command (./docker/prod/<name>) selects the role.
#
# Branding/translation customizations are applied at runtime via env vars
# and SQL seeds (see packages/src/) — OpenProject doesn't have a .zpm
# package system like Zammad.

ARG OPENPROJECT_VERSION=17-slim
FROM openproject/openproject:${OPENPROJECT_VERSION}

# Stage point for any custom seeds/branding assets we want available
# inside the container at deploy time. Mirrors the convention used in
# the sister Zammad repo's auto_install/ directory.
USER root
RUN mkdir -p /opt/klaos/assets && chown -R 1000:1000 /opt/klaos/assets
USER 1000:1000

COPY --chown=1000:1000 packages/src/klaos-branding/ /opt/klaos/assets/
