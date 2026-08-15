#!/usr/bin/env bash
# =============================================================================
# SCROW — regenerate installer-core.tar.gz
# =============================================================================
# The one-line bootstrap fetches exactly ONE small archive from
# raw.githubusercontent.com. This script rebuilds that archive from the
# repository so the bootstrap core always matches the committed installer.
# Run it from the repository root after changing any installer/*.sh file:
#
#   ./make-bootstrap-core.sh
#
# The archive is committed to the repository and served via
#   https://raw.githubusercontent.com/midn8crow/scrow/main/installer-core.tar.gz
# =============================================================================

set -euo pipefail

cd "$(dirname "$0")"

for f in install.sh VERSION installer/scrow installer/core.sh installer/state.sh \
         installer/config.sh installer/backup.sh installer/sysd.sh \
         installer/package.sh installer/components.sh installer/ownership.sh \
         installer/engine.sh installer/menu.sh; do
    [[ -s "$f" ]] || { echo "missing installer core file: $f" >&2; exit 1; }
done

tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner \
    -czf installer-core.tar.gz install.sh VERSION installer

echo "regenerated installer-core.tar.gz ($(du -h installer-core.tar.gz | cut -f1))"
