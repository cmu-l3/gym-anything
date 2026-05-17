#!/bin/bash
# Post-install configuration for Notion.
#
# Pre-creates the directories Notion writes into on first launch so the app
# code doesn't trip on missing paths. Doesn't open the app — that's the
# per-task pre_task's job (per the cua_world convention).
#
# Notion has no headless/CLI config story — its preferences are managed
# entirely via the Electron app UI after login, and almost everything useful
# is gated on auth. So this script is intentionally minimal.
set -eu

# Bundle ID is `notion.id` for the desktop app (Electron). Caches and
# application support live under the app name, not the bundle id, in some
# directories.
mkdir -p "$HOME/Library/Application Support/Notion"
mkdir -p "$HOME/Library/Caches/notion.id"
mkdir -p "$HOME/Library/Preferences"

# Make sure ~/Documents and ~/Desktop exist (used by screenshot tasks).
mkdir -p "$HOME/Documents" "$HOME/Desktop"

echo "[setup] Notion state dirs prepared under $HOME/Library"
echo "[setup] verifying app bundle"
ls -d /Applications/Notion.app >/dev/null
echo "[setup] OK"
