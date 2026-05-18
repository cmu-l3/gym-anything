#!/bin/bash
# Post-install configuration for Raycast.
#
# Pre-creates the directories Raycast writes into on first launch so the app
# doesn't trip on missing paths. Doesn't open the app \u2014 that's the per-task
# pre_task's job (per the cua_world convention).
#
# Raycast's preferences and state live under `com.raycast.macos`:
#   ~/Library/Application Support/com.raycast.macos/   (mixed; SQLite + JSON)
#   ~/Library/Preferences/com.raycast.macos.plist      (binary plist)
#   ~/Library/Caches/com.raycast.macos/                (binary cache)
#
# Most onboarding choices (sign-in, hotkey, permission grants) are managed
# through the Electron-style window UI on first launch and can't be reliably
# pre-set via `defaults write`; those are agent-driven.
set -eu

# Bundle ID for Raycast.app
mkdir -p "$HOME/Library/Application Support/com.raycast.macos"
mkdir -p "$HOME/Library/Caches/com.raycast.macos"
mkdir -p "$HOME/Library/Preferences"

# Make sure ~/Documents and ~/Desktop exist (used by potential future tasks).
mkdir -p "$HOME/Documents" "$HOME/Desktop"

echo "[setup] Raycast state dirs prepared under $HOME/Library"
echo "[setup] verifying app bundle"
ls -d /Applications/Raycast.app >/dev/null
echo "[setup] OK"
