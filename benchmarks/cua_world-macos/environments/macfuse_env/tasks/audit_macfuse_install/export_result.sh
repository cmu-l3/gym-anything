#!/bin/bash
# post_task hook for audit_macfuse_install.
#
# Produces /tmp/audit_macfuse_install_result.json with:
#   - task_start (Unix epoch)
#   - report_exists / report_fresh / report_valid_json
#   - Ground-truth values gathered directly from the system at export time
#   - The agent's reported values (extracted from the report JSON)
#
# Anti-pattern #12: every embedded Python heredoc has try/except around its
# main logic and writes a safe default if anything fails, so the verifier
# always reads valid JSON.
set -u   # NOT set -e — we want to continue even if individual stages fail.

echo "=== Exporting audit_macfuse_install results ==="

/usr/sbin/screencapture -x /tmp/macfuse_audit_task_end.png 2>/dev/null || true

TASK_START=$(cat /tmp/macfuse_audit_task_start_timestamp 2>/dev/null || echo "0")
echo "task_start_unix=$TASK_START"

REPORT_FILE="$HOME/Documents/macfuse_audit_report.json"

# Report file status.
REPORT_EXISTS=0
REPORT_FRESH=0
if [ -f "$REPORT_FILE" ]; then
  REPORT_EXISTS=1
  REPORT_MTIME=$(/usr/bin/stat -f %m "$REPORT_FILE" 2>/dev/null || echo "0")
  if [ "$REPORT_MTIME" -gt "$TASK_START" ] 2>/dev/null; then
    REPORT_FRESH=1
  fi
fi
echo "report: exists=$REPORT_EXISTS fresh=$REPORT_FRESH"

# Ground-truth values gathered from the system NOW (export time). These are
# the authoritative answers the agent should have produced.
GT_BUNDLE_VERSION=$(/usr/bin/defaults read /Library/Filesystems/macfuse.fs/Contents/Info CFBundleShortVersionString 2>/dev/null || echo "")
GT_BUNDLE_IDENTIFIER=$(/usr/bin/defaults read /Library/Filesystems/macfuse.fs/Contents/Info CFBundleIdentifier 2>/dev/null || echo "")
GT_PKG_CORE_VERSION=$(/usr/sbin/pkgutil --pkg-info io.macfuse.installer.components.core 2>/dev/null | /usr/bin/awk '/^version:/{print $2}')
GT_CORE_INSTALL_TIME=$(/usr/sbin/pkgutil --pkg-info io.macfuse.installer.components.core 2>/dev/null | /usr/bin/awk '/^install-time:/{print $2}')
GT_PREFPANE_INSTALL_TIME=$(/usr/sbin/pkgutil --pkg-info io.macfuse.installer.components.preferencepane 2>/dev/null | /usr/bin/awk '/^install-time:/{print $2}')
GT_KEXT_LOADED=$(/usr/sbin/kextstat 2>/dev/null | /usr/bin/grep -ciq fuse && echo true || echo false)
GT_MOUNT_HELPER="/Library/Filesystems/macfuse.fs/Contents/Resources/mount_macfuse"
GT_EXT_COUNT=$(/bin/ls /Library/Filesystems/macfuse.fs/Contents/Extensions/ 2>/dev/null | /usr/bin/wc -l | /usr/bin/tr -d ' ')
GT_LIBFUSE_COUNT=$(/bin/ls /usr/local/lib/ 2>/dev/null | /usr/bin/grep -c '^libfuse.*\.dylib$' | /usr/bin/tr -d ' ')
GT_PREFPANE_EXISTS=$([ -d /Library/PreferencePanes/macFUSE.prefPane ] && echo true || echo false)

echo "GT bundle_version=$GT_BUNDLE_VERSION identifier=$GT_BUNDLE_IDENTIFIER pkg_core=$GT_PKG_CORE_VERSION"
echo "GT core_install=$GT_CORE_INSTALL_TIME prefpane_install=$GT_PREFPANE_INSTALL_TIME"
echo "GT kext_loaded=$GT_KEXT_LOADED ext_count=$GT_EXT_COUNT libfuse_count=$GT_LIBFUSE_COUNT prefpane=$GT_PREFPANE_EXISTS"

# Parse the agent's report (safe defaults if anything goes wrong).
ANALYSIS_JSON='{"report_valid_json": false, "agent_bundle_version": null, "agent_bundle_identifier": null, "agent_pkg_core_version": null, "agent_core_pkg_install_time": null, "agent_prefpane_pkg_install_time": null, "agent_kext_currently_loaded": null, "agent_mount_helper_path": null, "agent_supported_macos_versions_count": null, "agent_libfuse_dylib_count": null, "agent_prefpane_installed": null, "extra_keys": [], "mentions_macfuse": false}'
if [ -f "$REPORT_FILE" ]; then
  PY_OUT=$(/usr/bin/python3 - "$REPORT_FILE" << 'PYEOF'
import json, sys

EXPECTED = {
    "bundle_version": "agent_bundle_version",
    "bundle_identifier": "agent_bundle_identifier",
    "pkg_core_version": "agent_pkg_core_version",
    "core_pkg_install_time": "agent_core_pkg_install_time",
    "prefpane_pkg_install_time": "agent_prefpane_pkg_install_time",
    "kext_currently_loaded": "agent_kext_currently_loaded",
    "mount_helper_path": "agent_mount_helper_path",
    "supported_macos_versions_count": "agent_supported_macos_versions_count",
    "libfuse_dylib_count": "agent_libfuse_dylib_count",
    "prefpane_installed": "agent_prefpane_installed",
}

out = {
    "report_valid_json": False,
    "extra_keys": [],
    "mentions_macfuse": False,
}
for v in EXPECTED.values():
    out[v] = None

try:
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        data = json.load(f)
    out["report_valid_json"] = True
    if isinstance(data, dict):
        for src_key, dst_key in EXPECTED.items():
            out[dst_key] = data.get(src_key)
        out["extra_keys"] = sorted([k for k in data.keys() if k not in EXPECTED])
        # Detect "report at all about macFUSE" — used for wrong-target gate.
        # Cast value to lowercase string and check for the substring "macfuse"
        # or "fuse" anywhere. This is intentionally permissive so an honest
        # agent isn't punished for typing the identifier in a slightly
        # different form; the strict gate only fires if NOTHING mentions
        # macfuse at all.
        blob = json.dumps(data, default=str).lower()
        out["mentions_macfuse"] = ("macfuse" in blob) or ("/library/filesystems" in blob)
except Exception as exc:
    out["json_error"] = f"{type(exc).__name__}: {exc}"
print(json.dumps(out))
PYEOF
)
  if [ -n "$PY_OUT" ]; then
    ANALYSIS_JSON="$PY_OUT"
  fi
fi

# Stitch the result. One Python call so JSON quoting is right.
/usr/bin/python3 - "$ANALYSIS_JSON" "$TASK_START" \
  "$GT_BUNDLE_VERSION" "$GT_BUNDLE_IDENTIFIER" "$GT_PKG_CORE_VERSION" \
  "$GT_CORE_INSTALL_TIME" "$GT_PREFPANE_INSTALL_TIME" \
  "$GT_KEXT_LOADED" "$GT_MOUNT_HELPER" \
  "$GT_EXT_COUNT" "$GT_LIBFUSE_COUNT" "$GT_PREFPANE_EXISTS" \
  "$REPORT_EXISTS" "$REPORT_FRESH" << 'PYEOF'
import json, sys
analysis = json.loads(sys.argv[1])

def to_int_or_zero(s):
    try: return int(s)
    except Exception: return 0

def to_bool(s):
    return str(s).strip().lower() == "true"

result = {
    "task_start": to_int_or_zero(sys.argv[2]),
    "gt_bundle_version": sys.argv[3],
    "gt_bundle_identifier": sys.argv[4],
    "gt_pkg_core_version": sys.argv[5],
    "gt_core_pkg_install_time": to_int_or_zero(sys.argv[6]),
    "gt_prefpane_pkg_install_time": to_int_or_zero(sys.argv[7]),
    "gt_kext_currently_loaded": to_bool(sys.argv[8]),
    "gt_mount_helper_path": sys.argv[9],
    "gt_supported_macos_versions_count": to_int_or_zero(sys.argv[10]),
    "gt_libfuse_dylib_count": to_int_or_zero(sys.argv[11]),
    "gt_prefpane_installed": to_bool(sys.argv[12]),
    "report_exists": bool(int(sys.argv[13])),
    "report_fresh": bool(int(sys.argv[14])),
}
result.update(analysis)
with open("/tmp/audit_macfuse_install_result.json", "w") as f:
    json.dump(result, f, indent=2)
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="
