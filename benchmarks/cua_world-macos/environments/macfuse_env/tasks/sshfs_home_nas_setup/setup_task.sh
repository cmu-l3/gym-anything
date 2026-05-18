#!/bin/bash
# pre_task hook for sshfs_home_nas_setup.
#
# Responsibilities:
#   1. Delete any pre-existing artifacts (mount_nas.sh, LaunchAgent plist,
#      ~/NAS/ directory) so a do-nothing agent can't get credit from a
#      leftover state.
#   2. Strip any existing `Host homeserver` stanza from ~/.ssh/config
#      while preserving the rest of the file (so the baseline is "no
#      homeserver entry" without nuking the user's other ssh hosts).
#   3. Record an authoritative task-start Unix timestamp at
#      /tmp/sshfs_home_nas_setup_start_ts so the verifier can gate on
#      artifact freshness if it wants to.
#   4. Launch Terminal so the agent has a CLI surface — macFUSE has no
#      GUI app, and this task is a pure command-line config job.
#   5. Take a start-state screenshot.
#
# Does NOT echo any of the expected commands the agent should run.
set -eu

echo "=== Setting up sshfs_home_nas_setup ==="

HOME_DIR="/Users/lume"
MOUNT_POINT="$HOME_DIR/NAS"
MOUNT_SCRIPT="$HOME_DIR/Documents/mount_nas.sh"
LAUNCHAGENT_PLIST="$HOME_DIR/Library/LaunchAgents/com.lume.sshfs.homeserver.plist"
SSH_CONFIG="$HOME_DIR/.ssh/config"

# 1) Clean slate on the deliverable artifacts.
rm -f "$MOUNT_SCRIPT" 2>/dev/null || true
rm -f "$LAUNCHAGENT_PLIST" 2>/dev/null || true
# Remove the mount point directory (best-effort — it may not exist, may
# have content from a previous run). Don't fail setup if rmdir refuses.
if [ -d "$MOUNT_POINT" ]; then
  rm -rf "$MOUNT_POINT" 2>/dev/null || true
fi

# Ensure parent dirs the agent will need.
mkdir -p "$HOME_DIR/Documents"
mkdir -p "$HOME_DIR/Library/LaunchAgents"
mkdir -p "$HOME_DIR/Library/Logs"
mkdir -p "$HOME_DIR/.ssh"
/bin/chmod 700 "$HOME_DIR/.ssh" 2>/dev/null || true

# 2) Strip any `Host homeserver` stanza from ~/.ssh/config without
#    discarding the rest of the file. A stanza runs from a line
#    matching `^Host homeserver(\s|$)` up to (but not including) the next
#    `Host ` line or end-of-file.
if [ -f "$SSH_CONFIG" ]; then
  /usr/bin/python3 - "$SSH_CONFIG" << 'PYEOF' || true
import sys, re
path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        lines = f.readlines()
except Exception:
    sys.exit(0)
out = []
skip = False
host_re = re.compile(r"^\s*Host\s+(.+?)\s*$", re.IGNORECASE)
for line in lines:
    m = host_re.match(line)
    if m:
        # New Host stanza begins. If it's `homeserver`, start skipping;
        # else stop skipping and keep the line.
        names = m.group(1).split()
        if "homeserver" in names:
            skip = True
            continue
        else:
            skip = False
            out.append(line)
            continue
    if not skip:
        out.append(line)
try:
    with open(path, "w", encoding="utf-8") as f:
        f.writelines(out)
except Exception:
    sys.exit(0)
PYEOF
fi

# 3) Task-start timestamp.
date +%s > /tmp/sshfs_home_nas_setup_start_ts
echo "task_start_unix=$(/bin/cat /tmp/sshfs_home_nas_setup_start_ts)"

# 4) Launch Terminal so the agent has a CLI workspace. Idempotent.
if ! /usr/bin/pgrep -x Terminal >/dev/null; then
  echo "[pre_task] launching Terminal"
  /usr/bin/open -a Terminal
fi

for i in $(seq 1 30); do
  if /usr/bin/lsappinfo list 2>/dev/null | /usr/bin/grep -qE '"Terminal"'; then
    echo "[pre_task] Terminal window registered after ${i}s"
    break
  fi
  sleep 1
done

# Settle so the Terminal window finishes painting before the screenshot.
sleep 3

# 5) Start-state screenshot for the trajectory archive (best-effort).
/usr/sbin/screencapture -x /tmp/sshfs_home_nas_setup_start.png 2>/dev/null || true

echo "=== Setup Complete ==="
echo "Terminal is running. Agent should install the SSHFS toolchain, configure SSH, write the mount script, and install the LaunchAgent plist."
