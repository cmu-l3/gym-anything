#!/bin/bash
# Setup: raycast_hotkey_conflict_modifiers
#
# Registers a macOS-system keyboard shortcut at id 64 ("Move focus to next
# window") = Cmd+` so the verifier can confirm the agent didn't trample it.
# Wipes any stale rayconfig export. Captures the initial Raycast WAL size
# so the verifier can compute a delta proving the agent edited settings.

set -euo pipefail
echo "=== Setup: raycast_hotkey_conflict_modifiers ==="

EXPORT_FILE="/Users/lume/Desktop/raycast_hotkey_export.rayconfig"

# --- 1. Ensure Raycast running + dismiss permission dialogs ---
if ! pgrep -x "Raycast" > /dev/null 2>&1; then
    open -a "Raycast" 2>/dev/null || true
    for i in $(seq 1 15); do
        if pgrep -x "Raycast" > /dev/null 2>&1; then break; fi
        sleep 2
    done
fi
sleep 3
for _i in $(seq 1 4); do
    osascript << 'APPLEOF' 2>/dev/null || true
tell application "System Events"
    try
        repeat with proc in (every application process whose frontmost is true)
            tell proc
                if exists button "Allow" of front window then click button "Allow" of front window
                if exists button "OK" of front window then click button "OK" of front window
            end tell
        end repeat
    end try
end tell
APPLEOF
    sleep 1
done

# --- 2. Wipe stale export file ---
rm -f "$EXPORT_FILE" 2>/dev/null || true

# --- 3. Register a macOS system keyboard shortcut at id 64 (Cmd+`) ---
# This is the "Move focus to next window" symbolichotkey. We set it to a known
# value so the verifier can confirm it wasn't trampled by the agent.
# Format: parameters = (key code, key char code, modifier flags); modifier 1048576 = Command.
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 64 \
    '{enabled = 1; value = { parameters = (96, 50, 1048576); type = "standard"; }; }' \
    2>/dev/null || true
# Read back the exact value we just wrote so the verifier can compare
INITIAL_HOTKEY_64=$(defaults read com.apple.symbolichotkeys AppleSymbolicHotKeys 2>/dev/null | grep -A4 "    64 =" | tr -d '\n ' || echo "")

# --- 4. Capture initial Raycast WAL size ---
RAYCAST_DB_WAL="/Users/lume/Library/Application Support/com.raycast.macos/raycast-enc.sqlite-wal"
INITIAL_WAL_SIZE=$(stat -f%z "$RAYCAST_DB_WAL" 2>/dev/null || echo "0")

# --- 5. Record baseline ---
date +%s              > /tmp/raycast_hotkey_conflict_modifiers_start_ts
echo "$INITIAL_HOTKEY_64" > /tmp/raycast_hotkey_conflict_modifiers_hotkey64_initial
echo "$INITIAL_WAL_SIZE"  > /tmp/raycast_hotkey_conflict_modifiers_wal_initial

echo "Initial WAL size: $INITIAL_WAL_SIZE bytes"
echo "Initial hotkey 64: $INITIAL_HOTKEY_64"
echo "=== Setup complete ==="
