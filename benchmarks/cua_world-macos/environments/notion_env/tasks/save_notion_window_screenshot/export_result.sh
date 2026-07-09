#!/bin/bash
# post_task hook for save_notion_window_screenshot on notion_env/macOS.
#
# Walks the agent's expected output locations (~/Desktop, ~/Documents),
# finds the most recently modified .png file with mtime > task_start, and
# extracts metadata the verifier uses to grade the capture:
#   - existence + path
#   - mtime (fresh check)
#   - file size
#   - PNG magic-byte validity
#   - macOS screencap xattrs (is_screencapture flag and capture type)
#   - whether Notion is still running at export time
#
# Anti-pattern #12: the embedded Python block is try/except wrapped and
# falls back to a safe-default result JSON if any stage errors.

set -u   # NOT set -e — partial-failure resilience matters more than fail-fast.

echo "=== Exporting save_notion_window_screenshot results ==="

TASK_START=$(cat /tmp/save_notion_window_screenshot_task_start 2>/dev/null || echo "0")
echo "task_start_unix=$TASK_START"

# Capture an end-state screenshot for the trajectory archive. The verifier
# does NOT read this — it's evidence only. The agent's own output file is
# what gets verified.
/usr/sbin/screencapture -x /tmp/save_notion_window_screenshot_end.png 2>/dev/null || true

# Is Notion still running? (C6 in the verifier.)
NOTION_RUNNING=0
if pgrep -x "Notion" >/dev/null 2>&1; then
  NOTION_RUNNING=1
fi
echo "notion_running=$NOTION_RUNNING"

# Find candidate output files. Search ~/Desktop and ~/Documents (the two
# legitimate save locations the task description mentions) for .png files
# modified after task_start. Pick the most recently modified one to grade.
#
# `stat -f %m` returns Unix epoch mtime on macOS. We avoid `find -newer`
# (it compares against another file's mtime, not an arbitrary time) and
# do the comparison in Python instead — cleaner and timezone-independent.

PY_OUT=$(/usr/bin/python3 - "$TASK_START" << 'PYEOF'
import json, os, plistlib, struct, subprocess, sys, time


def safe_xattr(key, path):
    """Read a single extended attribute as bytes. Returns None on any error."""
    try:
        r = subprocess.run(
            ["xattr", "-px", key, path],
            capture_output=True, text=True, timeout=5,
        )
        if r.returncode != 0:
            return None
        hex_str = r.stdout.strip().replace(" ", "").replace("\n", "")
        if not hex_str:
            return None
        return bytes.fromhex(hex_str)
    except Exception:
        return None


def safe_plist_load(b):
    """Decode a binary-plist bytes blob, returning None on any error."""
    if not b:
        return None
    try:
        return plistlib.loads(b)
    except Exception:
        return None


def has_png_magic(path):
    """True if `path` starts with the PNG signature 89 50 4E 47 0D 0A 1A 0A."""
    try:
        with open(path, "rb") as f:
            head = f.read(8)
        return head == b"\x89PNG\r\n\x1a\n"
    except Exception:
        return False


def png_dimensions(path):
    """(width, height) for a PNG by parsing the IHDR chunk. None on error."""
    try:
        with open(path, "rb") as f:
            sig = f.read(8)
            if sig != b"\x89PNG\r\n\x1a\n":
                return None
            f.read(4)            # IHDR length
            kind = f.read(4)
            if kind != b"IHDR":
                return None
            w, h = struct.unpack(">II", f.read(8))
            return (int(w), int(h))
    except Exception:
        return None


task_start = int(sys.argv[1])
search_dirs = ["/Users/lume/Desktop", "/Users/lume/Documents"]

candidates = []
for d in search_dirs:
    if not os.path.isdir(d):
        continue
    try:
        for name in os.listdir(d):
            if not name.lower().endswith(".png"):
                continue
            p = os.path.join(d, name)
            try:
                mtime = os.path.getmtime(p)
                size = os.path.getsize(p)
            except Exception:
                continue
            candidates.append({"path": p, "mtime": mtime, "size": size})
    except Exception:
        continue

# Most recent first
candidates.sort(key=lambda c: c["mtime"], reverse=True)

# Inspect at most the top 5 candidates for the report; the verifier grades
# the BEST one (most recent that also has the screencap xattr if any).
inspected = []
chosen = None
for c in candidates[:10]:
    is_sc_blob = safe_xattr("com.apple.metadata:kMDItemIsScreenCapture", c["path"])
    is_sc_value = safe_plist_load(is_sc_blob)
    sc_type_blob = safe_xattr("com.apple.metadata:kMDItemScreenCaptureType", c["path"])
    sc_type_value = safe_plist_load(sc_type_blob)
    entry = {
        "path": c["path"],
        "mtime": int(c["mtime"]),
        "fresh": c["mtime"] > task_start,
        "size": int(c["size"]),
        "is_png_magic": has_png_magic(c["path"]),
        "dimensions": png_dimensions(c["path"]),
        "is_screencapture": bool(is_sc_value) if is_sc_value is not None else False,
        "screencapture_type": sc_type_value if isinstance(sc_type_value, str) else None,
    }
    inspected.append(entry)

# The verifier looks at the most recent FRESH candidate first; otherwise
# the most recent non-fresh.
fresh_candidates = [c for c in inspected if c["fresh"]]
if fresh_candidates:
    # Prefer the one with screencap-type "window" if any are fresh, otherwise
    # the most recent fresh. This lets a verifier feedback message describe
    # the best-attempted capture.
    window_capture = [c for c in fresh_candidates if c["screencapture_type"] == "window"]
    if window_capture:
        chosen = window_capture[0]
    else:
        chosen = fresh_candidates[0]
elif inspected:
    chosen = inspected[0]

result = {
    "task_start": task_start,
    "exported_at": int(time.time()),
    "search_dirs": search_dirs,
    "candidate_count_total": len(candidates),
    "candidates_inspected": inspected,
    "chosen": chosen,
}
print(json.dumps(result))
PYEOF
)

if [ -z "$PY_OUT" ]; then
  PY_OUT='{"task_start": 0, "candidate_count_total": 0, "candidates_inspected": [], "chosen": null, "error": "python_block_failed"}'
fi

# Stitch the final result with the Notion-running flag added.
/usr/bin/python3 - "$PY_OUT" "$NOTION_RUNNING" "$TASK_START" << 'PYEOF'
import json, sys
inner = json.loads(sys.argv[1])
inner["notion_running"] = bool(int(sys.argv[2]))
inner["task_start"] = int(sys.argv[3])
with open("/tmp/save_notion_window_screenshot_result.json", "w") as f:
    json.dump(inner, f, indent=2)
print(json.dumps(inner, indent=2))
PYEOF

echo "=== Export complete ==="
