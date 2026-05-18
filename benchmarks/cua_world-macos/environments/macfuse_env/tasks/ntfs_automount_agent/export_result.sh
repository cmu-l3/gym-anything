#!/bin/bash
# post_task hook for ntfs_automount_agent.
#
# Produces /tmp/ntfs_automount_agent_result.json containing every signal the
# host-side verifier needs:
#   - Homebrew binary present?
#   - ntfs-3g binary present (probe Intel + Apple Silicon Homebrew prefixes)?
#   - ntfs-automount.sh existence, executability, contains diskutil, contains
#     NTFS detection, contains a mount command?
#   - ntfs-unmount.sh existence and executability?
#   - LaunchAgent plist existence + Label + WatchPaths array contents (parsed
#     by converting the plist to JSON via `plutil -convert json -o -`)?
#
# Every Python heredoc that emits JSON has try/except around its main logic
# and prints a safe default on failure, so the verifier always reads valid
# JSON (Anti-Pattern 12 safety).
set -u   # NOT set -e — we want to continue even if any individual stage fails.

echo "=== Exporting ntfs_automount_agent results ==="

/usr/sbin/screencapture -x /tmp/ntfs_automount_agent_task_end.png 2>/dev/null || true

TASK_START=$(cat /tmp/ntfs_automount_agent_task_start_timestamp 2>/dev/null || echo "0")
echo "task_start_unix=$TASK_START"

USER_HOME="$HOME"
AUTOMOUNT_SH="$USER_HOME/Documents/ntfs-automount.sh"
UNMOUNT_SH="$USER_HOME/Documents/ntfs-unmount.sh"
PLIST_PATH="$USER_HOME/Library/LaunchAgents/com.lume.ntfs-automount.plist"

# -------------------------------------------------------------------- C1: brew
BREW_PATH=""
for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew "$USER_HOME/.linuxbrew/bin/brew" /home/linuxbrew/.linuxbrew/bin/brew; do
  if [ -x "$candidate" ]; then
    BREW_PATH="$candidate"
    break
  fi
done
if [ -z "$BREW_PATH" ]; then
  # Last resort: ask PATH, in case the agent's install dropped brew somewhere
  # nonstandard but added it to a login dotfile we are reading via bash -lc.
  BREW_PATH=$(/usr/bin/env bash -lc 'command -v brew 2>/dev/null' 2>/dev/null || echo "")
fi
BREW_PRESENT=0
if [ -n "$BREW_PATH" ] && [ -x "$BREW_PATH" ]; then
  BREW_PRESENT=1
fi
echo "brew: present=$BREW_PRESENT path=$BREW_PATH"

# -------------------------------------------------------------------- C2: ntfs-3g
NTFS3G_PATH=""
for candidate in \
    /usr/local/sbin/mount_ntfs \
    /usr/local/bin/ntfs-3g \
    /usr/local/sbin/ntfs-3g \
    /opt/homebrew/sbin/mount_ntfs \
    /opt/homebrew/bin/ntfs-3g \
    /opt/homebrew/sbin/ntfs-3g \
    /opt/homebrew/opt/ntfs-3g-mac/sbin/mount_ntfs \
    /opt/homebrew/opt/ntfs-3g-mac/bin/ntfs-3g \
    /usr/local/opt/ntfs-3g-mac/sbin/mount_ntfs \
    /usr/local/opt/ntfs-3g-mac/bin/ntfs-3g; do
  if [ -x "$candidate" ]; then
    NTFS3G_PATH="$candidate"
    break
  fi
done
NTFS3G_PRESENT=0
if [ -n "$NTFS3G_PATH" ]; then
  NTFS3G_PRESENT=1
fi
echo "ntfs3g: present=$NTFS3G_PRESENT path=$NTFS3G_PATH"

# -------------------------------------------------------------------- C3..C5: automount.sh
AUTOMOUNT_EXISTS=0
AUTOMOUNT_EXEC=0
AUTOMOUNT_HAS_DISKUTIL=0
AUTOMOUNT_HAS_NTFS_CHECK=0
AUTOMOUNT_HAS_MOUNT_CMD=0
if [ -f "$AUTOMOUNT_SH" ]; then
  AUTOMOUNT_EXISTS=1
  if [ -x "$AUTOMOUNT_SH" ]; then
    AUTOMOUNT_EXEC=1
  fi

  # Substring checks — use the same script content the verifier reasons about.
  if /usr/bin/grep -q "diskutil" "$AUTOMOUNT_SH" 2>/dev/null; then
    AUTOMOUNT_HAS_DISKUTIL=1
  fi
  # NTFS detection — accept either the verbose `Windows_NTFS` token from
  # `diskutil info` ("File System Personality: Windows_NTFS") or a bare
  # "NTFS" match. Case-sensitive — diskutil emits these in capitals.
  if /usr/bin/grep -qE '(Windows_NTFS|NTFS)' "$AUTOMOUNT_SH" 2>/dev/null; then
    AUTOMOUNT_HAS_NTFS_CHECK=1
  fi
  # Mount command — accept either ntfs-3g or mount_ntfs invocation.
  if /usr/bin/grep -qE '(ntfs-3g|mount_ntfs)' "$AUTOMOUNT_SH" 2>/dev/null; then
    AUTOMOUNT_HAS_MOUNT_CMD=1
  fi
fi
echo "automount.sh: exists=$AUTOMOUNT_EXISTS exec=$AUTOMOUNT_EXEC " \
     "diskutil=$AUTOMOUNT_HAS_DISKUTIL ntfs=$AUTOMOUNT_HAS_NTFS_CHECK mount=$AUTOMOUNT_HAS_MOUNT_CMD"

# -------------------------------------------------------------------- C6: unmount.sh
UNMOUNT_EXISTS=0
UNMOUNT_EXEC=0
if [ -f "$UNMOUNT_SH" ]; then
  UNMOUNT_EXISTS=1
  if [ -x "$UNMOUNT_SH" ]; then
    UNMOUNT_EXEC=1
  fi
fi
echo "unmount.sh: exists=$UNMOUNT_EXISTS exec=$UNMOUNT_EXEC"

# -------------------------------------------------------------------- C7: plist
PLIST_EXISTS=0
PLIST_LABEL=""
PLIST_WATCHPATHS_HAS_VOLUMES=0
PLIST_HAS_WATCHPATHS_KEY=0
PLIST_PROGRAM_OK=0
PLIST_VALID=0
if [ -f "$PLIST_PATH" ]; then
  PLIST_EXISTS=1
  # Convert the plist to JSON (plutil works for both binary and XML plists
  # and is available on every modern macOS). Pipe the JSON into Python and
  # extract the keys we care about.
  PLIST_JSON=$(/usr/bin/plutil -convert json -o - "$PLIST_PATH" 2>/dev/null || echo "")
  if [ -n "$PLIST_JSON" ]; then
    PLIST_PARSE=$(/usr/bin/python3 - "$PLIST_JSON" << 'PYEOF'
import json, sys
out = {
    "valid": False,
    "label": "",
    "has_watchpaths_key": False,
    "watchpaths_has_volumes": False,
    "program_args_ok": False,
}
try:
    data = json.loads(sys.argv[1])
    if isinstance(data, dict):
        out["valid"] = True
        label = data.get("Label", "")
        if isinstance(label, str):
            out["label"] = label
        wp = data.get("WatchPaths", None)
        if wp is not None:
            out["has_watchpaths_key"] = True
            if isinstance(wp, list) and any(
                isinstance(p, str) and p.strip().rstrip("/") == "/Volumes"
                for p in wp
            ):
                out["watchpaths_has_volumes"] = True
        # Confirm ProgramArguments references the automount script — used
        # only to enrich feedback, not for scoring.
        pa = data.get("ProgramArguments", None)
        if isinstance(pa, list) and any(
            isinstance(a, str) and "ntfs-automount.sh" in a
            for a in pa
        ):
            out["program_args_ok"] = True
except Exception as exc:
    out["parse_error"] = f"{type(exc).__name__}: {exc}"
print(json.dumps(out))
PYEOF
)
    if [ -n "$PLIST_PARSE" ]; then
      PLIST_VALID=$(/usr/bin/python3 -c "import json,sys; print(int(bool(json.loads(sys.argv[1]).get('valid'))))" "$PLIST_PARSE" 2>/dev/null || echo "0")
      PLIST_LABEL=$(/usr/bin/python3 -c "import json,sys; print(json.loads(sys.argv[1]).get('label',''))" "$PLIST_PARSE" 2>/dev/null || echo "")
      PLIST_HAS_WATCHPATHS_KEY=$(/usr/bin/python3 -c "import json,sys; print(int(bool(json.loads(sys.argv[1]).get('has_watchpaths_key'))))" "$PLIST_PARSE" 2>/dev/null || echo "0")
      PLIST_WATCHPATHS_HAS_VOLUMES=$(/usr/bin/python3 -c "import json,sys; print(int(bool(json.loads(sys.argv[1]).get('watchpaths_has_volumes'))))" "$PLIST_PARSE" 2>/dev/null || echo "0")
      PLIST_PROGRAM_OK=$(/usr/bin/python3 -c "import json,sys; print(int(bool(json.loads(sys.argv[1]).get('program_args_ok'))))" "$PLIST_PARSE" 2>/dev/null || echo "0")
    fi
  fi
fi
echo "plist: exists=$PLIST_EXISTS valid=$PLIST_VALID label='$PLIST_LABEL' " \
     "wp_key=$PLIST_HAS_WATCHPATHS_KEY wp_volumes=$PLIST_WATCHPATHS_HAS_VOLUMES program_ok=$PLIST_PROGRAM_OK"

# Whether the LaunchAgent is currently loaded — informational only, not scored
# because `launchctl load` requires the agent's user session domain, which
# may behave unpredictably under sshd-keygen-wrapper responsibility chain.
PLIST_LOADED=0
if /bin/launchctl list 2>/dev/null | /usr/bin/grep -q "com.lume.ntfs-automount"; then
  PLIST_LOADED=1
fi
echo "plist: loaded=$PLIST_LOADED"

# -------------------------------------------------------------------- Emit JSON
/usr/bin/python3 - \
  "$TASK_START" \
  "$BREW_PRESENT" "$BREW_PATH" \
  "$NTFS3G_PRESENT" "$NTFS3G_PATH" \
  "$AUTOMOUNT_EXISTS" "$AUTOMOUNT_EXEC" \
  "$AUTOMOUNT_HAS_DISKUTIL" "$AUTOMOUNT_HAS_NTFS_CHECK" "$AUTOMOUNT_HAS_MOUNT_CMD" \
  "$UNMOUNT_EXISTS" "$UNMOUNT_EXEC" \
  "$PLIST_EXISTS" "$PLIST_VALID" "$PLIST_LABEL" \
  "$PLIST_HAS_WATCHPATHS_KEY" "$PLIST_WATCHPATHS_HAS_VOLUMES" "$PLIST_PROGRAM_OK" \
  "$PLIST_LOADED" \
  << 'PYEOF'
import json, sys

def to_int(s):
    try: return int(s)
    except Exception: return 0

def to_bool(s):
    return bool(to_int(s))

(
    _, task_start,
    brew_present, brew_path,
    ntfs3g_present, ntfs3g_path,
    automount_exists, automount_exec,
    automount_has_diskutil, automount_has_ntfs, automount_has_mount,
    unmount_exists, unmount_exec,
    plist_exists, plist_valid, plist_label,
    plist_has_wp_key, plist_wp_volumes, plist_program_ok,
    plist_loaded,
) = sys.argv

result = {
    "task_start": to_int(task_start),

    "brew_present": to_bool(brew_present),
    "brew_path": brew_path,

    "ntfs3g_present": to_bool(ntfs3g_present),
    "ntfs3g_path": ntfs3g_path,

    "automount_sh_exists": to_bool(automount_exists),
    "automount_sh_executable": to_bool(automount_exec),
    "automount_sh_has_diskutil": to_bool(automount_has_diskutil),
    "automount_sh_has_ntfs_check": to_bool(automount_has_ntfs),
    "automount_sh_has_mount_cmd": to_bool(automount_has_mount),

    "unmount_sh_exists": to_bool(unmount_exists),
    "unmount_sh_executable": to_bool(unmount_exec),

    "plist_exists": to_bool(plist_exists),
    "plist_valid": to_bool(plist_valid),
    "plist_label": plist_label,
    "plist_label_correct": plist_label.strip() == "com.lume.ntfs-automount",
    "plist_has_watchpaths_key": to_bool(plist_has_wp_key),
    "plist_watchpaths_has_volumes": to_bool(plist_wp_volumes),
    "plist_program_args_ok": to_bool(plist_program_ok),
    "plist_loaded": to_bool(plist_loaded),
}

with open("/tmp/ntfs_automount_agent_result.json", "w") as f:
    json.dump(result, f, indent=2)
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="
