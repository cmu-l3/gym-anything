#!/bin/bash
# post_task hook for macfuse_python_passthrough.
#
# Produces /tmp/macfuse_python_passthrough_result.json with:
#   - task_start (Unix epoch from setup)
#   - mfusepy_importable (bool) — can we `from fuse import FUSE, Operations`?
#   - script_exists / script_fresh / script_size
#   - syntax_ok (bool) — python3 -m py_compile passes?
#   - source_dir_exists / source_file_count
#   - mount_dir_exists
#   - From an embedded Python analysis of the script body:
#       has_fuse_import (bool)
#       subclasses_operations (bool)
#       method_count (int)
#       method_names (list[str])
#       logs_to_access_log (bool)
#       fuse_call_with_flags (bool)
#       mentions_fuse (bool)         — wrong-target gate
#       has_main_block (bool)
#
# Anti-Pattern 12: every embedded Python heredoc is wrapped in try/except
# with safe defaults so the verifier always reads valid JSON.
set -u  # NOT set -e — we want to continue past individual failures.

echo "=== Exporting macfuse_python_passthrough results ==="

# End-state screenshot (best-effort).
/usr/sbin/screencapture -x /tmp/macfuse_python_passthrough_task_end.png 2>/dev/null || true

TASK_START=$(cat /tmp/macfuse_python_passthrough_task_start_timestamp 2>/dev/null || echo "0")
echo "task_start_unix=$TASK_START"

SCRIPT_FILE="$HOME/Documents/passthrough_fuse.py"
SOURCE_DIR="$HOME/Documents/source"
MOUNT_DIR="$HOME/Volumes/watched_source"

# --- 1) mfusepy importability probe -----------------------------------------
# `from fuse import FUSE, Operations` is the canonical mfusepy import. We
# intentionally exit non-zero on any failure so the bash check is unambiguous.
MFUSEPY_OK=0
if /usr/bin/python3 -c "from fuse import FUSE, Operations; print('ok')" >/dev/null 2>&1; then
  MFUSEPY_OK=1
fi
echo "mfusepy_importable=$MFUSEPY_OK"

# --- 2) Script file status --------------------------------------------------
SCRIPT_EXISTS=0
SCRIPT_FRESH=0
SCRIPT_SIZE=0
if [ -f "$SCRIPT_FILE" ]; then
  SCRIPT_EXISTS=1
  SCRIPT_SIZE=$(/usr/bin/stat -f %z "$SCRIPT_FILE" 2>/dev/null || echo "0")
  SCRIPT_MTIME=$(/usr/bin/stat -f %m "$SCRIPT_FILE" 2>/dev/null || echo "0")
  if [ "$SCRIPT_MTIME" -gt "$TASK_START" ] 2>/dev/null; then
    SCRIPT_FRESH=1
  fi
fi
echo "script: exists=$SCRIPT_EXISTS fresh=$SCRIPT_FRESH size=$SCRIPT_SIZE"

# --- 3) Python syntax check -------------------------------------------------
SYNTAX_OK=0
if [ "$SCRIPT_EXISTS" -eq 1 ]; then
  if /usr/bin/python3 -m py_compile "$SCRIPT_FILE" >/dev/null 2>&1; then
    SYNTAX_OK=1
  fi
fi
echo "syntax_ok=$SYNTAX_OK"

# --- 4) Directory states ----------------------------------------------------
SOURCE_DIR_EXISTS=0
SOURCE_FILE_COUNT=0
if [ -d "$SOURCE_DIR" ]; then
  SOURCE_DIR_EXISTS=1
  # -type f only (not subdirs). Use find for portability.
  SOURCE_FILE_COUNT=$(/usr/bin/find "$SOURCE_DIR" -maxdepth 1 -type f 2>/dev/null | /usr/bin/wc -l | /usr/bin/tr -d ' ')
fi
echo "source_dir: exists=$SOURCE_DIR_EXISTS file_count=$SOURCE_FILE_COUNT"

MOUNT_DIR_EXISTS=0
if [ -d "$MOUNT_DIR" ]; then
  MOUNT_DIR_EXISTS=1
fi
echo "mount_dir: exists=$MOUNT_DIR_EXISTS"

# --- 5) Script content analysis (embedded Python, safe-defaults) -----------
ANALYSIS_JSON='{"has_fuse_import": false, "subclasses_operations": false, "method_count": 0, "method_names": [], "logs_to_access_log": false, "fuse_call_with_flags": false, "mentions_fuse": false, "has_main_block": false}'
if [ "$SCRIPT_EXISTS" -eq 1 ]; then
  PY_OUT=$(/usr/bin/python3 - "$SCRIPT_FILE" << 'PYEOF'
import json, re, sys

out = {
    "has_fuse_import": False,
    "subclasses_operations": False,
    "method_count": 0,
    "method_names": [],
    "logs_to_access_log": False,
    "fuse_call_with_flags": False,
    "mentions_fuse": False,
    "has_main_block": False,
}
try:
    with open(sys.argv[1], "r", encoding="utf-8", errors="replace") as f:
        src = f.read()

    # C3 — fuse import: tolerate either `from fuse import ...` or
    # `import fuse`. The canonical form for mfusepy is `from fuse import
    # FUSE, Operations` (the package is published as `mfusepy` on PyPI but
    # installs the `fuse` module).
    if re.search(r"^\s*from\s+fuse\s+import\b", src, flags=re.MULTILINE):
        out["has_fuse_import"] = True
    elif re.search(r"^\s*import\s+fuse\b", src, flags=re.MULTILINE):
        out["has_fuse_import"] = True

    # C4 — class declaration referencing Operations as a base.
    # Match e.g. `class PassthroughFS(Operations):` or
    # `class PassthroughFS(fuse.Operations):` or with extra whitespace.
    if re.search(r"class\s+\w+\s*\([^)]*\bOperations\b[^)]*\)\s*:", src):
        out["subclasses_operations"] = True

    # C5 — count distinct FUSE method definitions. We look for `def NAME(`
    # where NAME is one of the canonical FUSE Operations methods.
    candidates = ["access", "getattr", "readdir", "open", "read",
                  "write", "create", "release", "flush"]
    found = set()
    for name in candidates:
        if re.search(rf"^\s*def\s+{name}\s*\(", src, flags=re.MULTILINE):
            found.add(name)
    out["method_names"] = sorted(found)
    out["method_count"] = len(found)

    # C6 — logging to fuse-access.log. Match the bare filename anywhere
    # in the source (covers absolute, ~ , and relative paths).
    if "fuse-access.log" in src:
        out["logs_to_access_log"] = True

    # C7 — FUSE(...) call with nothreads=True or foreground=True.
    # Look for `FUSE(` followed (within ~400 chars, non-greedy) by either
    # keyword. We deliberately use `.` (any char incl. `)`) instead of
    # `[^)]` so that nested calls like `FUSE(PassthroughFS(root), ...,
    # nothreads=True)` still match — we just want to detect the kwarg,
    # not validate paren-balance.
    fuse_call_pat = re.compile(
        r"\bFUSE\s*\(.{0,400}?(?:nothreads\s*=\s*True|foreground\s*=\s*True)",
        flags=re.DOTALL,
    )
    if fuse_call_pat.search(src):
        out["fuse_call_with_flags"] = True

    # Wrong-target gate signal: any mention of fuse/FUSE at all.
    if re.search(r"\bfuse\b", src, flags=re.IGNORECASE):
        out["mentions_fuse"] = True

    # __main__ block (informational; not directly scored but reported).
    if re.search(r"if\s+__name__\s*==\s*['\"]__main__['\"]\s*:", src):
        out["has_main_block"] = True
except Exception as exc:
    out["analysis_error"] = f"{type(exc).__name__}: {exc}"

print(json.dumps(out))
PYEOF
)
  if [ -n "$PY_OUT" ]; then
    ANALYSIS_JSON="$PY_OUT"
  fi
fi

# --- 6) Stitch result JSON --------------------------------------------------
# Single Python invocation so the quoting story is right and the resulting
# file is guaranteed-parseable.
/usr/bin/python3 - "$ANALYSIS_JSON" "$TASK_START" \
  "$MFUSEPY_OK" "$SCRIPT_EXISTS" "$SCRIPT_FRESH" "$SCRIPT_SIZE" "$SYNTAX_OK" \
  "$SOURCE_DIR_EXISTS" "$SOURCE_FILE_COUNT" "$MOUNT_DIR_EXISTS" << 'PYEOF'
import json, sys

analysis = json.loads(sys.argv[1])

def to_int_or_zero(s):
    try: return int(s)
    except Exception: return 0

def to_bool_from_01(s):
    return str(s).strip() == "1"

result = {
    "task_start": to_int_or_zero(sys.argv[2]),
    "mfusepy_importable": to_bool_from_01(sys.argv[3]),
    "script_exists": to_bool_from_01(sys.argv[4]),
    "script_fresh": to_bool_from_01(sys.argv[5]),
    "script_size": to_int_or_zero(sys.argv[6]),
    "syntax_ok": to_bool_from_01(sys.argv[7]),
    "source_dir_exists": to_bool_from_01(sys.argv[8]),
    "source_file_count": to_int_or_zero(sys.argv[9]),
    "mount_dir_exists": to_bool_from_01(sys.argv[10]),
}
result.update(analysis)

with open("/tmp/macfuse_python_passthrough_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="
