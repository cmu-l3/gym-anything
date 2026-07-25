#!/bin/bash
# post_task hook for gocryptfs_personal_vault.
#
# Produces /tmp/gocryptfs_personal_vault_result.json containing every fact
# the verifier needs: presence of brew, presence + path of gocryptfs binary,
# state of the vault directories, mount/umount script content & permission
# bits, the LaunchAgent plist parsed via plutil, and the launchctl-list
# registration check.
#
# All embedded Python heredocs guard their main logic with try/except and
# write safe defaults on error so the verifier always reads valid JSON
# (Anti-Pattern 12).
set -u   # NOT set -e — we want to keep going even if individual probes fail.

echo "=== Exporting gocryptfs_personal_vault results ==="

# End-state screenshot for the trajectory archive (best-effort).
/usr/sbin/screencapture -x /tmp/gocryptfs_personal_vault_task_end.png 2>/dev/null || true

TASK_START=$(cat /tmp/gocryptfs_personal_vault_task_start_timestamp 2>/dev/null || echo "0")
echo "task_start_unix=$TASK_START"

LABEL="com.lume.gocryptfs.vault"
VAULT_ENC="$HOME/Documents/vault.enc"
VAULT_PLAIN="$HOME/Documents/vault.plain"
MOUNT_SCRIPT="$HOME/Documents/mount_vault.sh"
UMOUNT_SCRIPT="$HOME/Documents/umount_vault.sh"
PLIST_PATH="$HOME/Library/LaunchAgents/${LABEL}.plist"

# --- C1: Homebrew installed -------------------------------------------------
# `brew` may be at /opt/homebrew/bin/brew (Apple Silicon) or
# /usr/local/bin/brew (Intel) and may or may not be on the non-login SSH
# PATH. Probe both standard locations.
BREW_PATH=""
for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
  if [ -x "$candidate" ]; then
    BREW_PATH="$candidate"
    break
  fi
done
if [ -z "$BREW_PATH" ]; then
  # Fallback: ask the shell.
  BREW_PATH=$(command -v brew 2>/dev/null || echo "")
fi
BREW_INSTALLED=0
if [ -n "$BREW_PATH" ] && [ -x "$BREW_PATH" ]; then
  BREW_INSTALLED=1
fi
echo "brew: path='$BREW_PATH' installed=$BREW_INSTALLED"

# --- C2: gocryptfs binary exists --------------------------------------------
# gocryptfs-mac drops `gocryptfs` into the Homebrew bin dir. Check both
# locations + fall back to `command -v`. Many users will source brew shellenv
# into their interactive shell, but our exec context might not have that
# inherited — so explicit absolute paths are safer.
GOCRYPTFS_PATH=""
for candidate in /opt/homebrew/bin/gocryptfs /usr/local/bin/gocryptfs; do
  if [ -x "$candidate" ]; then
    GOCRYPTFS_PATH="$candidate"
    break
  fi
done
if [ -z "$GOCRYPTFS_PATH" ]; then
  # Probe brew's own bin lookup if brew is reachable.
  if [ -n "$BREW_PATH" ]; then
    BREW_PREFIX=$("$BREW_PATH" --prefix 2>/dev/null || echo "")
    if [ -n "$BREW_PREFIX" ] && [ -x "$BREW_PREFIX/bin/gocryptfs" ]; then
      GOCRYPTFS_PATH="$BREW_PREFIX/bin/gocryptfs"
    fi
  fi
fi
if [ -z "$GOCRYPTFS_PATH" ]; then
  GOCRYPTFS_PATH=$(command -v gocryptfs 2>/dev/null || echo "")
fi
GOCRYPTFS_INSTALLED=0
if [ -n "$GOCRYPTFS_PATH" ] && [ -x "$GOCRYPTFS_PATH" ]; then
  GOCRYPTFS_INSTALLED=1
fi
echo "gocryptfs: path='$GOCRYPTFS_PATH' installed=$GOCRYPTFS_INSTALLED"

# --- C3: vault.enc initialized ---------------------------------------------
VAULT_ENC_EXISTS=0
VAULT_ENC_CONF_EXISTS=0
VAULT_ENC_DIRIV_EXISTS=0
if [ -d "$VAULT_ENC" ]; then
  VAULT_ENC_EXISTS=1
fi
if [ -f "$VAULT_ENC/gocryptfs.conf" ]; then
  VAULT_ENC_CONF_EXISTS=1
fi
if [ -f "$VAULT_ENC/gocryptfs.diriv" ]; then
  VAULT_ENC_DIRIV_EXISTS=1
fi
echo "vault.enc: exists=$VAULT_ENC_EXISTS conf=$VAULT_ENC_CONF_EXISTS diriv=$VAULT_ENC_DIRIV_EXISTS"

# --- C4: vault.plain mountpoint --------------------------------------------
VAULT_PLAIN_EXISTS=0
if [ -d "$VAULT_PLAIN" ]; then
  VAULT_PLAIN_EXISTS=1
fi
echo "vault.plain: exists=$VAULT_PLAIN_EXISTS"

# --- C5: mount_vault.sh complete -------------------------------------------
MOUNT_EXISTS=0
MOUNT_EXECUTABLE=0
MOUNT_HAS_GOCRYPTFS=0
MOUNT_CONTENT=""
if [ -f "$MOUNT_SCRIPT" ]; then
  MOUNT_EXISTS=1
  if [ -x "$MOUNT_SCRIPT" ]; then
    MOUNT_EXECUTABLE=1
  fi
  if /usr/bin/grep -q "gocryptfs" "$MOUNT_SCRIPT" 2>/dev/null; then
    MOUNT_HAS_GOCRYPTFS=1
  fi
  # Capture content for verifier debug context (capped at 4 KB to be safe).
  MOUNT_CONTENT=$(/usr/bin/head -c 4096 "$MOUNT_SCRIPT" 2>/dev/null || echo "")
fi
echo "mount_vault.sh: exists=$MOUNT_EXISTS exec=$MOUNT_EXECUTABLE gocryptfs=$MOUNT_HAS_GOCRYPTFS"

# --- C6: umount_vault.sh complete ------------------------------------------
UMOUNT_EXISTS=0
UMOUNT_EXECUTABLE=0
UMOUNT_HAS_UNMOUNT=0
UMOUNT_CONTENT=""
if [ -f "$UMOUNT_SCRIPT" ]; then
  UMOUNT_EXISTS=1
  if [ -x "$UMOUNT_SCRIPT" ]; then
    UMOUNT_EXECUTABLE=1
  fi
  # Accept either `umount` or `diskutil unmount` (both work on macOS).
  if /usr/bin/grep -qE '(\bumount\b|diskutil[[:space:]]+unmount)' "$UMOUNT_SCRIPT" 2>/dev/null; then
    UMOUNT_HAS_UNMOUNT=1
  fi
  UMOUNT_CONTENT=$(/usr/bin/head -c 4096 "$UMOUNT_SCRIPT" 2>/dev/null || echo "")
fi
echo "umount_vault.sh: exists=$UMOUNT_EXISTS exec=$UMOUNT_EXECUTABLE umount=$UMOUNT_HAS_UNMOUNT"

# --- C7: LaunchAgent plist correct -----------------------------------------
# Parse the plist via `plutil -convert json -o - <path>` and analyze with
# Python. We score four sub-conditions:
#   - parses as JSON-convertible plist  (1)
#   - Label == com.lume.gocryptfs.vault (1)
#   - RunAtLoad is boolean true         (1)
#   - StandardOutPath AND StandardErrorPath both present as non-empty
#     strings, AND ProgramArguments references the mount script (1)
PLIST_EXISTS=0
PLIST_ANALYSIS='{"plist_parses": false, "label_matches": false, "run_at_load_true": false, "log_paths_set": false, "program_args_invokes_mount": false}'
if [ -f "$PLIST_PATH" ]; then
  PLIST_EXISTS=1
  # plutil writes the JSON conversion to a temp file (cleaner than piping
  # because the JSON may contain quotes / shell metacharacters that we don't
  # want the shell to interpret).
  PLIST_JSON_FILE="/tmp/gocryptfs_personal_vault_plist.json"
  rm -f "$PLIST_JSON_FILE"
  /usr/bin/plutil -convert json -o "$PLIST_JSON_FILE" "$PLIST_PATH" 2>/dev/null || true
  if [ -s "$PLIST_JSON_FILE" ]; then
    PY_OUT=$(/usr/bin/python3 - "$LABEL" "$MOUNT_SCRIPT" "$PLIST_JSON_FILE" << 'PYEOF'
import json, sys

label_expected = sys.argv[1]
mount_script_path = sys.argv[2]
plist_json_file = sys.argv[3]

out = {
    "plist_parses": False,
    "label_matches": False,
    "run_at_load_true": False,
    "log_paths_set": False,
    "program_args_invokes_mount": False,
}
try:
    with open(plist_json_file, "r", encoding="utf-8") as f:
        data = json.load(f)
    out["plist_parses"] = isinstance(data, dict)
    if isinstance(data, dict):
        label = data.get("Label")
        out["label_matches"] = isinstance(label, str) and label.strip() == label_expected
        ral = data.get("RunAtLoad")
        # plutil -convert json emits real JSON booleans for plist bools.
        out["run_at_load_true"] = isinstance(ral, bool) and ral is True
        out_path = data.get("StandardOutPath")
        err_path = data.get("StandardErrorPath")
        out["log_paths_set"] = (
            isinstance(out_path, str) and bool(out_path.strip())
            and isinstance(err_path, str) and bool(err_path.strip())
        )
        prog_args = data.get("ProgramArguments")
        if isinstance(prog_args, list):
            joined = " ".join(str(a) for a in prog_args)
            out["program_args_invokes_mount"] = mount_script_path in joined
except Exception as exc:
    out["error"] = f"{type(exc).__name__}: {exc}"
print(json.dumps(out))
PYEOF
)
    if [ -n "$PY_OUT" ]; then
      PLIST_ANALYSIS="$PY_OUT"
    fi
  fi
fi
echo "plist: exists=$PLIST_EXISTS analysis=$PLIST_ANALYSIS"

# --- C8: LaunchAgent loaded ------------------------------------------------
# `launchctl list` shows registered agents/daemons under the current user
# session. Look for an exact-label match (anchored).
LAUNCH_AGENT_LOADED=0
if /bin/launchctl list 2>/dev/null | /usr/bin/awk -v lbl="$LABEL" '$3 == lbl { found=1 } END { exit (found ? 0 : 1) }'; then
  LAUNCH_AGENT_LOADED=1
fi
echo "launchctl list match: $LAUNCH_AGENT_LOADED"

# --- Stitch the result. One Python call so JSON quoting is right. ----------
/usr/bin/python3 - \
  "$TASK_START" \
  "$BREW_PATH" "$BREW_INSTALLED" \
  "$GOCRYPTFS_PATH" "$GOCRYPTFS_INSTALLED" \
  "$VAULT_ENC_EXISTS" "$VAULT_ENC_CONF_EXISTS" "$VAULT_ENC_DIRIV_EXISTS" \
  "$VAULT_PLAIN_EXISTS" \
  "$MOUNT_EXISTS" "$MOUNT_EXECUTABLE" "$MOUNT_HAS_GOCRYPTFS" \
  "$UMOUNT_EXISTS" "$UMOUNT_EXECUTABLE" "$UMOUNT_HAS_UNMOUNT" \
  "$PLIST_EXISTS" "$PLIST_ANALYSIS" \
  "$LAUNCH_AGENT_LOADED" \
  "$MOUNT_CONTENT" "$UMOUNT_CONTENT" << 'PYEOF'
import json, sys

def b(x):
    return bool(int(x))

try:
    plist_analysis = json.loads(sys.argv[17])
except Exception:
    plist_analysis = {
        "plist_parses": False,
        "label_matches": False,
        "run_at_load_true": False,
        "log_paths_set": False,
        "program_args_invokes_mount": False,
    }

result = {
    "task_start": int(sys.argv[1] or 0),
    "brew_path": sys.argv[2],
    "brew_installed": b(sys.argv[3]),
    "gocryptfs_path": sys.argv[4],
    "gocryptfs_installed": b(sys.argv[5]),
    "vault_enc_exists": b(sys.argv[6]),
    "vault_enc_conf_exists": b(sys.argv[7]),
    "vault_enc_diriv_exists": b(sys.argv[8]),
    "vault_plain_exists": b(sys.argv[9]),
    "mount_script_exists": b(sys.argv[10]),
    "mount_script_executable": b(sys.argv[11]),
    "mount_script_has_gocryptfs": b(sys.argv[12]),
    "umount_script_exists": b(sys.argv[13]),
    "umount_script_executable": b(sys.argv[14]),
    "umount_script_has_unmount": b(sys.argv[15]),
    "plist_exists": b(sys.argv[16]),
    "plist_parses": bool(plist_analysis.get("plist_parses")),
    "plist_label_matches": bool(plist_analysis.get("label_matches")),
    "plist_run_at_load_true": bool(plist_analysis.get("run_at_load_true")),
    "plist_log_paths_set": bool(plist_analysis.get("log_paths_set")),
    "plist_program_args_invokes_mount": bool(plist_analysis.get("program_args_invokes_mount")),
    "launch_agent_loaded": b(sys.argv[18]),
    "mount_script_content": sys.argv[19],
    "umount_script_content": sys.argv[20],
}

with open("/tmp/gocryptfs_personal_vault_result.json", "w") as f:
    json.dump(result, f, indent=2)

# Pretty-print to stdout for log readability.
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="
