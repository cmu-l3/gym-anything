#!/bin/bash
# post_task hook for sshfs_home_nas_setup.
#
# Produces /tmp/sshfs_home_nas_setup_result.json with the parsed state of
# every artifact the agent was supposed to produce:
#   - brew installed?
#   - gromgit/fuse tap added?
#   - sshfs binary path?
#   - ~/NAS/ mount point exists?
#   - ~/.ssh/config homeserver block (host present + correct hostname/user/identity)?
#   - ~/Documents/mount_nas.sh (exists + executable + has volname/reconnect/defer_permissions)?
#   - ~/Library/LaunchAgents/com.lume.sshfs.homeserver.plist (label/RunAtLoad/KeepAlive/logging)?
#
# Anti-pattern #12 (export robustness): the embedded Python parser uses
# try/except around every read and always emits valid JSON, so the
# verifier never has to deal with a malformed result file.
set -u   # NOT set -e — we want to continue even if individual probes fail.

echo "=== Exporting sshfs_home_nas_setup results ==="

/usr/sbin/screencapture -x /tmp/sshfs_home_nas_setup_end.png 2>/dev/null || true

TASK_START=$(/bin/cat /tmp/sshfs_home_nas_setup_start_ts 2>/dev/null || echo "0")
echo "task_start_unix=$TASK_START"

HOME_DIR="/Users/lume"
MOUNT_POINT="$HOME_DIR/NAS"
MOUNT_SCRIPT="$HOME_DIR/Documents/mount_nas.sh"
LAUNCHAGENT_PLIST="$HOME_DIR/Library/LaunchAgents/com.lume.sshfs.homeserver.plist"
SSH_CONFIG="$HOME_DIR/.ssh/config"
RESULT_FILE="/tmp/sshfs_home_nas_setup_result.json"

# --- brew binary ---
BREW_BIN=""
for cand in /opt/homebrew/bin/brew /usr/local/bin/brew; do
  if [ -x "$cand" ]; then
    BREW_BIN="$cand"
    break
  fi
done
if [ -z "$BREW_BIN" ] && command -v brew >/dev/null 2>&1; then
  BREW_BIN="$(command -v brew)"
fi
BREW_INSTALLED="false"
[ -n "$BREW_BIN" ] && BREW_INSTALLED="true"
echo "brew_bin=$BREW_BIN installed=$BREW_INSTALLED"

# --- brew tap list ---
GROMGIT_TAP_ADDED="false"
BREW_TAP_LIST=""
if [ "$BREW_INSTALLED" = "true" ]; then
  BREW_TAP_LIST="$("$BREW_BIN" tap 2>/dev/null || true)"
  if echo "$BREW_TAP_LIST" | /usr/bin/grep -qi '^gromgit/fuse$'; then
    GROMGIT_TAP_ADDED="true"
  fi
fi
echo "gromgit_tap=$GROMGIT_TAP_ADDED"

# --- sshfs binary ---
SSHFS_PATH=""
for cand in /opt/homebrew/bin/sshfs /usr/local/bin/sshfs /opt/homebrew/sbin/sshfs /usr/local/sbin/sshfs; do
  if [ -x "$cand" ]; then
    SSHFS_PATH="$cand"
    break
  fi
done
if [ -z "$SSHFS_PATH" ] && command -v sshfs >/dev/null 2>&1; then
  SSHFS_PATH="$(command -v sshfs)"
fi
echo "sshfs_path=$SSHFS_PATH"

# --- mount point ---
MOUNT_POINT_EXISTS="false"
[ -d "$MOUNT_POINT" ] && MOUNT_POINT_EXISTS="true"
echo "mount_point_exists=$MOUNT_POINT_EXISTS"

# --- mount script existence + exec bit (raw flags; option-content checks
# happen in the Python parser below where we have full file content) ---
MOUNT_SCRIPT_EXISTS="false"
MOUNT_SCRIPT_EXECUTABLE="false"
if [ -f "$MOUNT_SCRIPT" ]; then
  MOUNT_SCRIPT_EXISTS="true"
  if [ -x "$MOUNT_SCRIPT" ]; then
    MOUNT_SCRIPT_EXECUTABLE="true"
  fi
fi
echo "mount_script_exists=$MOUNT_SCRIPT_EXISTS executable=$MOUNT_SCRIPT_EXECUTABLE"

# --- plist existence (content parsing in Python below) ---
LAUNCHAGENT_EXISTS="false"
[ -f "$LAUNCHAGENT_PLIST" ] && LAUNCHAGENT_EXISTS="true"
echo "launchagent_exists=$LAUNCHAGENT_EXISTS"

# --- plist -> JSON via plutil (handles both XML and binary plists) ---
PLIST_JSON=""
if [ "$LAUNCHAGENT_EXISTS" = "true" ]; then
  PLIST_JSON="$(/usr/bin/plutil -convert json -o - "$LAUNCHAGENT_PLIST" 2>/dev/null || echo "")"
fi

# --- Parse everything into a single JSON result via Python ---
/usr/bin/python3 - \
  "$TASK_START" "$BREW_INSTALLED" "$BREW_BIN" "$GROMGIT_TAP_ADDED" \
  "$SSHFS_PATH" "$MOUNT_POINT_EXISTS" "$MOUNT_SCRIPT_EXISTS" \
  "$MOUNT_SCRIPT_EXECUTABLE" "$LAUNCHAGENT_EXISTS" \
  "$SSH_CONFIG" "$MOUNT_SCRIPT" "$LAUNCHAGENT_PLIST" "$PLIST_JSON" \
  "$RESULT_FILE" << 'PYEOF'
import json, os, re, sys

def to_bool(s):
    return str(s).strip().lower() == "true"

(_, task_start, brew_installed, brew_bin, gromgit_tap, sshfs_path,
 mount_point_exists, mount_script_exists, mount_script_executable,
 launchagent_exists, ssh_config_path, mount_script_path,
 launchagent_path, plist_json_str, result_file) = sys.argv

result = {
    "task_start": int(task_start) if task_start.isdigit() else 0,
    "brew_installed": to_bool(brew_installed),
    "brew_binary_path": brew_bin or None,
    "gromgit_tap_added": to_bool(gromgit_tap),
    "sshfs_binary_path": sshfs_path or None,
    "mount_point_exists": to_bool(mount_point_exists),
    # SSH config probes
    "ssh_host_configured": False,
    "ssh_hostname_correct": False,
    "ssh_user_correct": False,
    "ssh_identity_file_set": False,
    # Mount script probes
    "mount_script_exists": to_bool(mount_script_exists),
    "mount_script_executable": to_bool(mount_script_executable),
    "mount_script_has_volname": False,
    "mount_script_has_reconnect": False,
    "mount_script_has_defer_permissions": False,
    # LaunchAgent plist probes
    "launchagent_plist_exists": to_bool(launchagent_exists),
    "launchagent_label_correct": False,
    "launchagent_has_runatload": False,
    "launchagent_has_keepalive": False,
    "launchagent_has_logging": False,
    "launchagent_program_arguments_points_at_mount_script": False,
}

# --- SSH config: find the Host homeserver block and read its keys ---
try:
    if os.path.exists(ssh_config_path):
        with open(ssh_config_path, "r", encoding="utf-8", errors="replace") as f:
            text = f.read()
        # Walk line-by-line, tracking the current Host stanza.
        in_homeserver = False
        host_re = re.compile(r"^\s*Host\s+(.+?)\s*$", re.IGNORECASE)
        kv_re = re.compile(r"^\s*([A-Za-z][A-Za-z0-9]*)\s+(.+?)\s*$")
        kv = {}
        for line in text.splitlines():
            m = host_re.match(line)
            if m:
                names = m.group(1).split()
                in_homeserver = ("homeserver" in names)
                continue
            if not in_homeserver:
                continue
            # Skip comments / blank lines.
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                continue
            km = kv_re.match(line)
            if km:
                key = km.group(1).lower()
                val = km.group(2).strip()
                # Keep first occurrence (OpenSSH "first wins" semantics).
                kv.setdefault(key, val)
        if kv:
            result["ssh_host_configured"] = True
            hostname = kv.get("hostname", "")
            user = kv.get("user", "")
            idfile = kv.get("identityfile", "")
            result["ssh_hostname_correct"] = (hostname.strip() == "192.168.1.100")
            result["ssh_user_correct"] = (user.strip() == "pi")
            result["ssh_identity_file_set"] = bool(idfile.strip())
            result["ssh_config_block"] = {
                "hostname": hostname,
                "user": user,
                "identityfile": idfile,
                "port": kv.get("port", ""),
                "serveraliveinterval": kv.get("serveraliveinterval", ""),
                "serveralivecountmax": kv.get("serveralivecountmax", ""),
            }
except Exception as exc:
    result["ssh_config_error"] = f"{type(exc).__name__}: {exc}"

# --- mount script content ---
try:
    if result["mount_script_exists"] and os.path.exists(mount_script_path):
        with open(mount_script_path, "r", encoding="utf-8", errors="replace") as f:
            script_text = f.read()
        low = script_text.lower()
        # macFUSE option detection. The script can pass options as
        # `-o volname=HomeNAS,reconnect,defer_permissions` or split across
        # multiple `-o` flags, or with spaces. We just look for the option
        # token anywhere in the script body, which is what `sshfs` itself
        # cares about at invocation time.
        if "volname=" in low:
            result["mount_script_has_volname"] = True
        if "reconnect" in low:
            result["mount_script_has_reconnect"] = True
        if "defer_permissions" in low:
            result["mount_script_has_defer_permissions"] = True
        result["mount_script_invokes_sshfs"] = ("sshfs" in low)
        result["mount_script_byte_size"] = len(script_text)
except Exception as exc:
    result["mount_script_error"] = f"{type(exc).__name__}: {exc}"

# --- LaunchAgent plist (JSON-converted by plutil in the bash wrapper) ---
try:
    if plist_json_str.strip():
        plist = json.loads(plist_json_str)
        if isinstance(plist, dict):
            label = plist.get("Label", "")
            result["launchagent_label_correct"] = (label == "com.lume.sshfs.homeserver")
            # launchd accepts the legacy synonym OnDemand for KeepAlive=NO,
            # but for our purposes we just want explicit True.
            run_at_load = plist.get("RunAtLoad", None)
            keep_alive = plist.get("KeepAlive", None)
            # RunAtLoad / KeepAlive may be booleans or dicts (for KeepAlive
            # conditional). Either way we accept "truthy".
            result["launchagent_has_runatload"] = bool(run_at_load) is True or run_at_load is True
            result["launchagent_has_keepalive"] = (keep_alive is True or
                                                   isinstance(keep_alive, dict))
            stdout_path = plist.get("StandardOutPath", "")
            stderr_path = plist.get("StandardErrorPath", "")
            result["launchagent_has_logging"] = bool(stdout_path) or bool(stderr_path)
            result["launchagent_program_arguments"] = plist.get("ProgramArguments", [])
            # Point-at-mount-script: the ProgramArguments list should
            # include the path to mount_nas.sh (or bash/sh + that path).
            pa = plist.get("ProgramArguments", [])
            if isinstance(pa, list):
                joined = " ".join(str(x) for x in pa)
                if "mount_nas.sh" in joined:
                    result["launchagent_program_arguments_points_at_mount_script"] = True
            result["launchagent_label"] = label
            result["launchagent_stdout_path"] = stdout_path
            result["launchagent_stderr_path"] = stderr_path
except Exception as exc:
    result["launchagent_parse_error"] = f"{type(exc).__name__}: {exc}"

with open(result_file, "w", encoding="utf-8") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "Result written to: $RESULT_FILE"
echo "=== Export complete ==="
