#!/bin/bash
# Copy this checkout into the shell's plugin folder (development only; the
# finished plugin is installed with `omarchy plugin add`).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$HOME/.config/omarchy/plugins/io.github.dankestrick.omajournal"
mkdir -p "$DEST"
rsync -a --delete --exclude .git --exclude __pycache__ --exclude scripts "$ROOT/" "$DEST/"
echo "Copied to $DEST"
