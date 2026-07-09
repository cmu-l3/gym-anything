#!/bin/bash
# post_task hook for macfuse_sysinfo_fuse_c.
#
# Produces /tmp/macfuse_sysinfo_fuse_c_result.json with structured boolean
# / integer flags for every scoring criterion. The verifier reads this
# file via copy_from_env and does not need to re-parse the C source.
#
# Anti-Pattern 12 safety: every Python heredoc has try/except around its
# main logic and ALWAYS emits valid JSON to stdout. The outer bash script
# uses `set -u` only (NOT `set -e`) so a single command failure does not
# abort the whole export.
set -u

echo "=== Exporting macfuse_sysinfo_fuse_c results ==="

/usr/sbin/screencapture -x /tmp/macfuse_sysinfo_fuse_c_task_end.png 2>/dev/null || true

TASK_START=$(cat /tmp/macfuse_sysinfo_fuse_c_task_start_timestamp 2>/dev/null || echo "0")
echo "task_start_unix=$TASK_START"

PROJECT_DIR="$HOME/Documents/sysinfo_fuse"
SOURCE_FILE="$PROJECT_DIR/sysinfo.c"
MAKEFILE="$PROJECT_DIR/Makefile"
BINARY="$PROJECT_DIR/sysinfo_fuse"

# ---- Filesystem-level facts ----
PROJECT_DIR_EXISTS=0
SOURCE_EXISTS=0
SOURCE_BYTES=0
SOURCE_FRESH=0
MAKEFILE_EXISTS=0
MAKEFILE_BYTES=0
BINARY_EXISTS=0
BINARY_EXECUTABLE=0
BINARY_IS_MACHO=0

if [ -d "$PROJECT_DIR" ]; then
  PROJECT_DIR_EXISTS=1
fi

if [ -f "$SOURCE_FILE" ]; then
  SOURCE_EXISTS=1
  SOURCE_BYTES=$(/usr/bin/stat -f %z "$SOURCE_FILE" 2>/dev/null || echo "0")
  SOURCE_MTIME=$(/usr/bin/stat -f %m "$SOURCE_FILE" 2>/dev/null || echo "0")
  if [ "$SOURCE_MTIME" -gt "$TASK_START" ] 2>/dev/null; then
    SOURCE_FRESH=1
  fi
fi

if [ -f "$MAKEFILE" ]; then
  MAKEFILE_EXISTS=1
  MAKEFILE_BYTES=$(/usr/bin/stat -f %z "$MAKEFILE" 2>/dev/null || echo "0")
fi

if [ -f "$BINARY" ]; then
  BINARY_EXISTS=1
  if [ -x "$BINARY" ]; then
    BINARY_EXECUTABLE=1
  fi
  # `file` returns "Mach-O ..." for native macOS executables.
  FILE_OUT=$(/usr/bin/file -b "$BINARY" 2>/dev/null || echo "")
  case "$FILE_OUT" in
    *Mach-O*) BINARY_IS_MACHO=1 ;;
    *) BINARY_IS_MACHO=0 ;;
  esac
fi

echo "project_dir_exists=$PROJECT_DIR_EXISTS source_exists=$SOURCE_EXISTS source_bytes=$SOURCE_BYTES"
echo "makefile_exists=$MAKEFILE_EXISTS makefile_bytes=$MAKEFILE_BYTES"
echo "binary_exists=$BINARY_EXISTS executable=$BINARY_EXECUTABLE macho=$BINARY_IS_MACHO"

# ---- Source-file content analysis (defaults for the no-source case) ----
SOURCE_ANALYSIS='{"has_fuse_use_version_define": false, "has_fuse_h_include": false, "fuse_use_version_before_include": false, "fuse_use_version_value": null, "callbacks_defined": {"getattr": false, "readdir": false, "open": false, "read": false}, "sysctl_call_count": 0, "filenames_present": {"cpu.txt": false, "memory.txt": false, "uptime.txt": false, "hostname.txt": false}, "mentions_fuse_main_or_operations": false, "source_first_bytes_preview": null, "analysis_error": null}'

if [ -f "$SOURCE_FILE" ]; then
  PY_OUT=$(/usr/bin/python3 - "$SOURCE_FILE" << 'PYEOF'
import json, re, sys

OUT = {
    "has_fuse_use_version_define": False,
    "has_fuse_h_include": False,
    "fuse_use_version_before_include": False,
    "fuse_use_version_value": None,
    "callbacks_defined": {"getattr": False, "readdir": False, "open": False, "read": False},
    "sysctl_call_count": 0,
    "filenames_present": {"cpu.txt": False, "memory.txt": False, "uptime.txt": False, "hostname.txt": False},
    "mentions_fuse_main_or_operations": False,
    "source_first_bytes_preview": None,
    "analysis_error": None,
}

try:
    with open(sys.argv[1], "r", encoding="utf-8", errors="replace") as f:
        src = f.read()
    OUT["source_first_bytes_preview"] = src[:200]

    # ---- C3: FUSE_USE_VERSION define, and ordering relative to fuse.h include ----
    # A `#define FUSE_USE_VERSION 26` somewhere in the file. We don't insist
    # on a particular value for the boolean — the value is reported
    # separately. But the macro MUST appear before any fuse.h include for
    # the API selection to take effect.
    define_match = re.search(
        r"#\s*define\s+FUSE_USE_VERSION\s+(\d+)",
        src,
    )
    if define_match:
        OUT["has_fuse_use_version_define"] = True
        try:
            OUT["fuse_use_version_value"] = int(define_match.group(1))
        except Exception:
            OUT["fuse_use_version_value"] = None
        define_pos = define_match.start()
    else:
        define_pos = None

    # ---- C4: fuse.h include ----
    # Accept #include <fuse.h>, "fuse.h", <fuse/fuse.h>, "fuse/fuse.h".
    include_match = re.search(
        r'#\s*include\s+[<"]\s*(?:fuse/)?fuse\.h\s*[>"]',
        src,
    )
    if include_match:
        OUT["has_fuse_h_include"] = True
        include_pos = include_match.start()
    else:
        include_pos = None

    if define_pos is not None and include_pos is not None:
        OUT["fuse_use_version_before_include"] = define_pos < include_pos
    else:
        OUT["fuse_use_version_before_include"] = False

    # ---- C5: each of the 4 mandatory callbacks defined as a function ----
    # FUSE callbacks are wired into a `struct fuse_operations` initializer
    # via `.getattr = my_getattr`, `.readdir = my_readdir`, etc. The
    # function the agent points at is typically prefixed (e.g.
    # `sysinfo_getattr`), so a literal `getattr(` regex misses the real
    # definition. We use two complementary signals; either one counts:
    #
    #   (a) struct-initializer wiring: `\.getattr\s*=\s*<ident>` — the
    #       agent has assigned a function pointer for this callback in
    #       a fuse_operations struct. This is necessary for the
    #       filesystem to function, so it's a strong signal the callback
    #       is present.
    #   (b) function definition where the identifier ends in `_<cb>` or
    #       *is* `<cb>` and is followed by `(...)` and a `{` body. The
    #       identifier-suffix form accommodates the common naming
    #       convention `sysinfo_getattr`, `my_readdir`, etc.
    def has_callback(name: str) -> bool:
        # (a) struct initializer
        if re.search(r"\.\s*" + re.escape(name) + r"\s*=\s*[A-Za-z_]\w*", src):
            return True
        # (b) function definition: optional storage-class / type tokens,
        #     then an identifier matching `*_<name>` or exactly `<name>`,
        #     followed by `(` and eventually `{`. We allow the identifier
        #     to be embedded mid-line because most agents write `static int
        #     prefix_<name>(...) {`.
        ident = r"(?:[A-Za-z_]\w*_)?" + re.escape(name)
        # Use a global pass: any line containing the identifier followed by
        # `(`, where between `{` and that identifier there's a type-ish
        # token (covers `static int`, `int`, `void *`, `static ssize_t`,
        # etc.). Then a `{` must appear after the parameter list within
        # ~400 chars (function body, not declaration).
        candidate_pat = re.compile(
            r"(?:^|\n)[^\n;]*?"
            r"(?:int|void|ssize_t|size_t|off_t|long|unsigned|signed|char|short)"
            r"[\w\s\*]*\b" + ident + r"\s*\([^;]*?\)\s*\{",
            re.DOTALL,
        )
        if candidate_pat.search(src):
            return True
        return False
    for cb in ("getattr", "readdir", "open", "read"):
        OUT["callbacks_defined"][cb] = has_callback(cb)

    # ---- C6: sysctl / sysctlbyname call count ----
    # Count occurrences of `sysctl(` or `sysctlbyname(` (function calls, not
    # mere mentions in comments — but a comment match is unlikely to harm
    # the threshold since we require >= 2).
    sysctl_calls = re.findall(r"\bsysctl(?:byname)?\s*\(", src)
    OUT["sysctl_call_count"] = len(sysctl_calls)

    # ---- C7: required filename string literals ----
    for vname in ("cpu.txt", "memory.txt", "uptime.txt", "hostname.txt"):
        # Either `"cpu.txt"`, `"/cpu.txt"`, or substring inside a longer
        # literal — accept any string occurrence; defensive against the
        # agent prefixing a slash or storing in a const.
        if re.search(r'"[^"\n]*' + re.escape(vname) + r'[^"\n]*"', src):
            OUT["filenames_present"][vname] = True

    # ---- Bonus: agent wires up fuse_main / fuse_operations ----
    OUT["mentions_fuse_main_or_operations"] = bool(
        re.search(r"\bfuse_main\s*\(", src)
        or re.search(r"\bfuse_operations\b", src)
    )

except Exception as exc:
    OUT["analysis_error"] = f"{type(exc).__name__}: {exc}"

print(json.dumps(OUT))
PYEOF
  )
  if [ -n "$PY_OUT" ]; then
    SOURCE_ANALYSIS="$PY_OUT"
  fi
fi

# ---- Makefile content analysis ----
MAKEFILE_ANALYSIS='{"has_fuse_use_version_26": false, "has_pkg_config_fuse": false, "has_clang_or_cc": false, "has_sysinfo_fuse_target": false, "preview": null, "analysis_error": null}'

if [ -f "$MAKEFILE" ]; then
  PY_OUT=$(/usr/bin/python3 - "$MAKEFILE" << 'PYEOF'
import json, re, sys

OUT = {
    "has_fuse_use_version_26": False,
    "has_pkg_config_fuse": False,
    "has_clang_or_cc": False,
    "has_sysinfo_fuse_target": False,
    "preview": None,
    "analysis_error": None,
}

try:
    with open(sys.argv[1], "r", encoding="utf-8", errors="replace") as f:
        mk = f.read()
    OUT["preview"] = mk[:400]

    # FUSE_USE_VERSION=26 anywhere in the Makefile, with or without `-D`.
    # Accepts `-DFUSE_USE_VERSION=26`, `FUSE_USE_VERSION=26`, etc.
    if re.search(r"FUSE_USE_VERSION\s*=\s*26", mk):
        OUT["has_fuse_use_version_26"] = True

    # `pkg-config` invocation referencing fuse — `pkg-config --cflags fuse`
    # or `pkg-config --libs fuse` or `pkg-config fuse ...`.
    if re.search(r"pkg-config[^\n]*\bfuse\b", mk):
        OUT["has_pkg_config_fuse"] = True

    # Compiler reference (clang, or `CC = ...`).
    if re.search(r"\bclang\b", mk) or re.search(r"\bCC\s*=", mk) or re.search(r"\$\(CC\)", mk):
        OUT["has_clang_or_cc"] = True

    # `sysinfo_fuse` appears as a Make target — start of a line followed by
    # `:` (and optionally prerequisites).
    if re.search(r"(?:^|\n)\s*sysinfo_fuse\s*:", mk):
        OUT["has_sysinfo_fuse_target"] = True

except Exception as exc:
    OUT["analysis_error"] = f"{type(exc).__name__}: {exc}"

print(json.dumps(OUT))
PYEOF
  )
  if [ -n "$PY_OUT" ]; then
    MAKEFILE_ANALYSIS="$PY_OUT"
  fi
fi

# ---- Stitch result JSON ----
/usr/bin/python3 - \
  "$TASK_START" \
  "$PROJECT_DIR_EXISTS" "$SOURCE_EXISTS" "$SOURCE_BYTES" "$SOURCE_FRESH" \
  "$MAKEFILE_EXISTS" "$MAKEFILE_BYTES" \
  "$BINARY_EXISTS" "$BINARY_EXECUTABLE" "$BINARY_IS_MACHO" \
  "$SOURCE_ANALYSIS" "$MAKEFILE_ANALYSIS" << 'PYEOF'
import json, sys

def to_int(s, default=0):
    try: return int(s)
    except Exception: return default

def to_bool_from_01(s):
    return s == "1"

task_start = to_int(sys.argv[1])
project_dir_exists = to_bool_from_01(sys.argv[2])
source_exists = to_bool_from_01(sys.argv[3])
source_bytes = to_int(sys.argv[4])
source_fresh = to_bool_from_01(sys.argv[5])
makefile_exists = to_bool_from_01(sys.argv[6])
makefile_bytes = to_int(sys.argv[7])
binary_exists = to_bool_from_01(sys.argv[8])
binary_executable = to_bool_from_01(sys.argv[9])
binary_is_macho = to_bool_from_01(sys.argv[10])

try:
    source_analysis = json.loads(sys.argv[11])
except Exception:
    source_analysis = {"analysis_error": "failed to parse source analysis JSON"}

try:
    makefile_analysis = json.loads(sys.argv[12])
except Exception:
    makefile_analysis = {"analysis_error": "failed to parse makefile analysis JSON"}

result = {
    "task_start": task_start,
    "project_dir_exists": project_dir_exists,
    "source_exists": source_exists,
    "source_bytes": source_bytes,
    "source_fresh": source_fresh,
    "makefile_exists": makefile_exists,
    "makefile_bytes": makefile_bytes,
    "binary_exists": binary_exists,
    "binary_executable": binary_executable,
    "binary_is_macho": binary_is_macho,
    "source_analysis": source_analysis,
    "makefile_analysis": makefile_analysis,
}

with open("/tmp/macfuse_sysinfo_fuse_c_result.json", "w") as f:
    json.dump(result, f, indent=2)
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="
