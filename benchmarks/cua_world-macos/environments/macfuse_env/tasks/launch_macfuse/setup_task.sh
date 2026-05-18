#!/bin/bash
# Pre-task hook for launch_macfuse smoke task.
#
# macFUSE is a kernel framework with no app process, so there's nothing to
# launch. We just sanity-check the install landed where the verifier will
# look and surface the version, so logs are self-explanatory.
set -eu

BUNDLE="/Library/Filesystems/macfuse.fs"

if [ -d "$BUNDLE" ]; then
  VER=$(/usr/bin/defaults read "$BUNDLE/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "unknown")
  echo "[pre_task] macFUSE present: version $VER at $BUNDLE"
else
  echo "[pre_task] macFUSE NOT present at $BUNDLE — install must have failed" >&2
fi

# Brief settle so a follow-up screenshot of the desktop is stable.
sleep 1
