#!/bin/bash
# pre_task hook for ntfs_automount_agent.
#
# Responsibilities:
#   1. Clean slate — delete any pre-existing scripts, plist, and log files so
#      a do-nothing agent cannot get credit from leftover state and so an
#      "update-style" baseline (Anti-Pattern 7) cannot accidentally hand
#      points to an agent that does nothing.
#   2. Record an authoritative task-start Unix timestamp so the verifier /
#      export script can gate freshness if needed (mtime > task_start).
#   3. Make sure the per-user LaunchAgents directory exists (it is missing on
#      a fresh sandbox) so the agent never has to create that directory
#      itself just to drop a plist.
#   4. Launch Terminal so the agent has a CLI workspace (this task is a
#      sysadmin / shell scripting task — Terminal is its natural surface,
#      consistent with the pre_task-launches-the-app convention in
#      12_macos_environments.md).
#   5. Take a start-state screenshot for the trajectory archive.
#
# Do NOT echo any ground-truth values, ntfs-3g paths, or plist key names
# the agent is supposed to discover from the task description / docs.
set -eu

echo "=== Setting up ntfs_automount_agent ==="

USER_HOME="$HOME"

# 1) Clean slate
rm -f "$USER_HOME/Documents/ntfs-automount.sh" 2>/dev/null || true
rm -f "$USER_HOME/Documents/ntfs-unmount.sh"   2>/dev/null || true
rm -f "$USER_HOME/Documents/ntfs-automount.log" 2>/dev/null || true
rm -f "$USER_HOME/Documents/ntfs-automount.err" 2>/dev/null || true

# LaunchAgent plist — unload first if it happens to be already loaded, then
# remove the file. `launchctl unload` of a non-existent plist fails harmlessly.
/bin/launchctl unload "$USER_HOME/Library/LaunchAgents/com.lume.ntfs-automount.plist" 2>/dev/null || true
rm -f "$USER_HOME/Library/LaunchAgents/com.lume.ntfs-automount.plist" 2>/dev/null || true

# Ensure parent directories exist.
mkdir -p "$USER_HOME/Documents"
mkdir -p "$USER_HOME/Library/LaunchAgents"

# 2) Task-start timestamp
date +%s > /tmp/ntfs_automount_agent_task_start_timestamp
echo "task_start_unix=$(cat /tmp/ntfs_automount_agent_task_start_timestamp)"

# 3) Launch Terminal (idempotent)
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

# Settle so the Terminal window's prompt finishes painting.
sleep 3

# 4) Start-state screenshot for trajectory archive (best-effort).
/usr/sbin/screencapture -x /tmp/ntfs_automount_agent_task_start.png 2>/dev/null || true

echo "=== ntfs_automount_agent setup complete ==="
echo "Terminal is running. Agent should install Homebrew + ntfs-3g and configure the automount system."
