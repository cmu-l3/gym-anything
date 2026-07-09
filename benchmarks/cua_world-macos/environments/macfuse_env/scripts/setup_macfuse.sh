#!/bin/bash
# post_start hook for macfuse_env.
#
# macFUSE has no user-facing preferences via `defaults write` — it's a
# kernel-level filesystem framework, not a UI app. setup is therefore minimal:
#   1. Ensure standard user dirs exist (tasks write reports under ~/Documents).
#   2. Probe macFUSE installation state and emit a one-liner audit so cold-boot
#      logs make it obvious whether install succeeded.
#   3. Force LaunchServices not to fight us about the macFUSE bundle (it's a
#      filesystem bundle, not an app, but it sits in /Library/Filesystems/ —
#      occasionally LS re-scans those).
set -eu

echo "[setup] macFUSE post-install configuration"

# 1) User directories
mkdir -p "$HOME/Documents" "$HOME/Downloads"

# 2) Probe install state
BUNDLE="/Library/Filesystems/macfuse.fs"
if [ -d "$BUNDLE" ]; then
  VER=$(/usr/bin/defaults read "$BUNDLE/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "unknown")
  echo "[setup] macFUSE installed: version $VER at $BUNDLE"
else
  echo "[setup] WARNING — macFUSE bundle not found at $BUNDLE" >&2
fi

# 3) Probe kext / system extension load state (informational only — likely
# unloaded in this sandbox, see env description). Don't fail on this.
echo "[setup] kext probe:"
/usr/sbin/kextstat 2>/dev/null | grep -i fuse || echo "  no macFUSE kext loaded (expected in sandbox)"
echo "[setup] systemextensionsctl list:"
/usr/bin/systemextensionsctl list 2>/dev/null | head -20 || true

echo "[setup] done"
