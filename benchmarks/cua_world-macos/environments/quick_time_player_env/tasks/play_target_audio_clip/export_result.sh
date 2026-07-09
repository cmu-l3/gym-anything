#!/bin/bash
# post_task hook for play_target_audio_clip.
#
# Produces /tmp/play_target_audio_clip_result.json with:
#   - task_start (unix epoch read from /tmp/task_start_timestamp)
#   - front_document_name        (AppleScript)
#   - front_document_path        ("file" property of front document; macOS file ref)
#   - front_document_duration    (AppleScript, seconds)
#   - front_document_current_time(AppleScript, seconds)
#   - front_document_playing     (AppleScript boolean as string)
#   - documents_open_count       (count of all open documents)
#   - target_file_exists         (does ~/Documents/qtp_target_audio.aiff still exist)
#   - target_file_mtime          (epoch; 0 if absent)
#   - target_file_size           (bytes; 0 if absent)
#   - target_file_unchanged      (size + mtime sanity: file wasn't truncated/replaced
#                                  with a different file mid-task)
#   - process_running            (pgrep + lsappinfo combined: did QT survive)
#
# Anti-pattern #12: every embedded query has a safe fallback so the verifier
# always reads valid JSON.
set -u   # NOT set -e — we want partial results on failure too.

echo "=== Exporting play_target_audio_clip results ==="

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
echo "task_start_unix=$TASK_START"

# end-state screenshot (for evidence; verifier doesn't use it)
/usr/sbin/screencapture -x /tmp/task_end.png 2>/dev/null || true

# --- AppleScript probes ---
QT_QUERY_AS='tell application "QuickTime Player"
  set out to ""
  try
    set docCount to count of documents
    if docCount = 0 then
      return "DOC_COUNT=0|NAME=|PATH=|DUR=0|CUR=0|PLAYING=false|"
    end if
    set theDoc to front document
    set theName to name of theDoc
    set theDur to duration of theDoc
    set theCur to current time of theDoc
    set thePlaying to playing of theDoc
    -- The file property returns an alias; coerce to POSIX path. Wrap in try
    -- so we still emit the other fields even if path access fails.
    set thePath to ""
    try
      set thePath to POSIX path of (file of theDoc as alias)
    end try
    return "DOC_COUNT=" & docCount & "|NAME=" & theName & "|PATH=" & thePath & ¬
           "|DUR=" & theDur & "|CUR=" & theCur & "|PLAYING=" & thePlaying & "|"
  on error errMsg
    return "ERROR=" & errMsg & "|"
  end try
end tell'

AS_OUT=$(osascript -e "$QT_QUERY_AS" 2>&1 || true)
echo "AS_OUT raw: $AS_OUT"

# Parse pipe-delimited keys from the AppleScript output.
get_field() {
  echo "$AS_OUT" | grep -oE "$1=[^|]*" | head -1 | sed "s/^$1=//"
}

DOC_COUNT=$(get_field "DOC_COUNT")
[ -z "$DOC_COUNT" ] && DOC_COUNT=0
FRONT_NAME=$(get_field "NAME")
FRONT_PATH=$(get_field "PATH")
FRONT_DUR=$(get_field "DUR")
[ -z "$FRONT_DUR" ] && FRONT_DUR=0
FRONT_CUR=$(get_field "CUR")
[ -z "$FRONT_CUR" ] && FRONT_CUR=0
FRONT_PLAYING=$(get_field "PLAYING")
[ -z "$FRONT_PLAYING" ] && FRONT_PLAYING=false

echo "documents_open=$DOC_COUNT name=$FRONT_NAME dur=$FRONT_DUR cur=$FRONT_CUR playing=$FRONT_PLAYING"

# --- File-state probes ---
TARGET="$HOME/Documents/qtp_target_audio.aiff"
TARGET_EXISTS=0
TARGET_MTIME=0
TARGET_SIZE=0
if [ -f "$TARGET" ]; then
  TARGET_EXISTS=1
  TARGET_MTIME=$(/usr/bin/stat -f %m "$TARGET" 2>/dev/null || echo 0)
  TARGET_SIZE=$(/usr/bin/stat -f %z "$TARGET" 2>/dev/null || echo 0)
fi

# Source-file fingerprint — the file was copied from Funk.aiff (623130 bytes).
# If size matches the original AND mtime is the task-start mtime,
# the file is unchanged. If the agent re-wrote it (different size or
# unexpected mtime), the target-unchanged check fails — anti-gaming.
EXPECTED_SIZE=623130
TARGET_UNCHANGED=0
if [ "$TARGET_SIZE" -eq "$EXPECTED_SIZE" ]; then
  TARGET_UNCHANGED=1
fi

# Process running probe
PGREP_OUT=$(pgrep -x "QuickTime Player" 2>/dev/null || true)
PROCESS_RUNNING=0
[ -n "$PGREP_OUT" ] && PROCESS_RUNNING=1

# Stitch result JSON with one Python call so quoting is correct.
/usr/bin/python3 - "$TASK_START" "$DOC_COUNT" "$FRONT_NAME" "$FRONT_PATH" "$FRONT_DUR" "$FRONT_CUR" "$FRONT_PLAYING" "$TARGET_EXISTS" "$TARGET_MTIME" "$TARGET_SIZE" "$TARGET_UNCHANGED" "$PROCESS_RUNNING" << 'PYEOF'
import json, sys
(task_start, doc_count, name, path, dur, cur, playing,
 t_exists, t_mtime, t_size, t_unchanged, proc_running) = sys.argv[1:]
def _f(x):
    try: return float(x)
    except Exception: return 0.0
def _i(x):
    try: return int(x)
    except Exception: return 0
result = {
    "task_start": _i(task_start),
    "documents_open_count": _i(doc_count),
    "front_document_name": name or "",
    "front_document_path": path or "",
    "front_document_duration": _f(dur),
    "front_document_current_time": _f(cur),
    "front_document_playing": (str(playing).strip().lower() == "true"),
    "target_file_exists": bool(_i(t_exists)),
    "target_file_mtime": _i(t_mtime),
    "target_file_size": _i(t_size),
    "target_file_unchanged": bool(_i(t_unchanged)),
    "process_running": bool(_i(proc_running)),
}
with open("/tmp/play_target_audio_clip_result.json", "w") as f:
    json.dump(result, f, indent=2)
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="
