#!/bin/bash
# pre_task hook for gocryptfs_personal_vault.
#
# Responsibilities:
#   1. Wipe any pre-existing vault artifacts so a do-nothing agent can't be
#      credited for state left over from a previous run.
#   2. Best-effort unload + remove of a pre-existing LaunchAgent plist so the
#      `launchctl list` check is meaningful (the verifier requires the agent
#      to have run `launchctl load` THIS attempt).
#   3. Record an authoritative task-start Unix timestamp the verifier can use
#      to confirm freshness on the agent-produced artifacts.
#   4. Launch Terminal so the agent has a CLI workspace (consistent with the
#      pre_task-launches-the-app convention from 12_macos_environments.md;
#      for macFUSE / gocryptfs the "app" is Terminal because gocryptfs is a
#      CLI tool with no UI window).
#
# Per Anti-Pattern guidance: do NOT echo the expected passphrase, plist
# contents, or commands here; the agent must produce all of those.
set -eu

echo "=== Setting up gocryptfs_personal_vault ==="

LABEL="com.lume.gocryptfs.vault"
PLIST_PATH="$HOME/Library/LaunchAgents/${LABEL}.plist"

# 1) Best-effort: unload any previously-registered LaunchAgent so we start
#    from a clean launchctl state. `launchctl unload` returns non-zero if
#    the label isn't registered — swallow that.
if [ -f "$PLIST_PATH" ]; then
  echo "[pre_task] unloading stale LaunchAgent ${LABEL}"
  /bin/launchctl unload "$PLIST_PATH" 2>/dev/null || true
fi
# Belt-and-braces: `bootout` for newer launchd semantics. Ignore errors.
/bin/launchctl bootout "gui/$(id -u)/${LABEL}" 2>/dev/null || true

# 2) Wipe vault directories and helper scripts from any previous attempt.
rm -rf "$HOME/Documents/vault.enc" "$HOME/Documents/vault.plain" 2>/dev/null || true
rm -f  "$HOME/Documents/mount_vault.sh" "$HOME/Documents/umount_vault.sh" 2>/dev/null || true
rm -f  "$PLIST_PATH" 2>/dev/null || true

# 3) Ensure the ancestor dirs the agent needs exist (these are normal
#    user dirs and would already exist on a fresh sandbox, but be explicit).
mkdir -p "$HOME/Documents"
mkdir -p "$HOME/Library/LaunchAgents"
mkdir -p "$HOME/Library/Logs"

# 4) Task-start timestamp (Unix epoch, seconds). The verifier checks mtimes
#    against this to confirm the agent produced fresh artifacts.
date +%s > /tmp/gocryptfs_personal_vault_task_start_timestamp
echo "task_start_unix=$(cat /tmp/gocryptfs_personal_vault_task_start_timestamp)"

# 5) Launch Terminal. Idempotent — if already running, skip the open.
if ! pgrep -x Terminal >/dev/null; then
  echo "[pre_task] launching Terminal"
  open -a Terminal
fi

for i in $(seq 1 30); do
  if /usr/bin/lsappinfo list 2>/dev/null | grep -qE '"Terminal"'; then
    echo "[pre_task] Terminal window registered after ${i}s"
    break
  fi
  sleep 1
done

# Settle: let the Terminal window's prompt finish painting before screenshots.
sleep 3

# Start-state screenshot for the trajectory archive (best-effort).
/usr/sbin/screencapture -x /tmp/gocryptfs_personal_vault_task_start.png 2>/dev/null || true

echo "=== gocryptfs_personal_vault setup complete ==="
echo "Terminal is running. Agent should install gocryptfs-mac, initialize an"
echo "encrypted vault, write mount/umount scripts, configure and load a"
echo "LaunchAgent."
