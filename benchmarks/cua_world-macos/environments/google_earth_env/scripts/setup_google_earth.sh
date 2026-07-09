#!/bin/bash
# Post-install configuration. Pre-creates ~/Library/GoogleEarth so first-run
# dialogs that write into it don't fail. Doesn't open the app — that's the
# task's job.
set -eu

mkdir -p "$HOME/Library/Application Support/Google Earth Pro"
mkdir -p "$HOME/Library/GoogleEarth"

echo "[setup] Google Earth config dirs prepared at $HOME/Library"
echo "[setup] verifying app bundle"
ls -d "/Applications/Google Earth Pro.app" >/dev/null
echo "[setup] OK"
