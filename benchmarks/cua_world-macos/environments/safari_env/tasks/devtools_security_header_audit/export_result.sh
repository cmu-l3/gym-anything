#!/bin/bash
# post_task hook for devtools_security_header_audit on Safari/macOS.
#
# Produces /tmp/devtools_security_header_audit_result.json with:
#   - task_start (unix epoch)
#   - per-site Safari history visit counts after task start
#   - report_exists / report_fresh / report_valid_json flags
#   - sites_present (list of required sites found as keys in the report)
#   - per_site_header_count (count of non-empty header values per site)
#   - hsts_looks_valid, csp_looks_valid (plausibility flags per site)
#   - total_non_empty_headers (sum across all sites)
#
# Anti-pattern #12: every embedded Python heredoc has try/except around its
# main logic and writes a safe default if anything fails, so the verifier
# always reads valid JSON.

set -u   # NOT set -e — we want to continue even if individual stages fail.

echo "=== Exporting devtools_security_header_audit results ==="

/usr/sbin/screencapture -x /tmp/task_end.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
echo "task_start_unix=$TASK_START"

# Mac absolute time = Unix - 978307200 (seconds between 1970-01-01 and 2001-01-01 UTC)
TASK_START_MAC=$((TASK_START - 978307200))

# Force Safari to flush History.db's WAL by quitting it cleanly.
osascript -e 'tell application "Safari" to quit' 2>/dev/null || true
sleep 3
pkill -x Safari 2>/dev/null || true
sleep 1

HISTORY_DB="$HOME/Library/Safari/History.db"
TEMP_DB="/tmp/safari_history_export_$$.sqlite"
GITHUB_VISITS=0
GITLAB_VISITS=0
BITBUCKET_VISITS=0
NPM_VISITS=0
PYPI_VISITS=0

if [ -f "$HISTORY_DB" ]; then
  # Belt-and-suspenders: try to checkpoint WAL, then copy. If sqlite3 errors,
  # the cp still produces a usable file in most cases.
  /usr/bin/sqlite3 "$HISTORY_DB" "PRAGMA wal_checkpoint(TRUNCATE);" 2>/dev/null || true
  cp "$HISTORY_DB" "$TEMP_DB" 2>/dev/null || true

  if [ -f "$TEMP_DB" ]; then
    # Safari schema: history_items(id, url, ...), history_visits(history_item, visit_time, ...)
    # visit_time is in Mac absolute time (seconds since 2001-01-01 UTC).
    Q() {
      /usr/bin/sqlite3 "$TEMP_DB" \
        "SELECT COUNT(DISTINCT i.id) FROM history_visits v
         JOIN history_items i ON v.history_item = i.id
         WHERE i.url LIKE '%$1%' AND v.visit_time > ${TASK_START_MAC};" 2>/dev/null || echo "0"
    }
    GITHUB_VISITS=$(Q 'github.com')
    GITLAB_VISITS=$(Q 'gitlab.com')
    BITBUCKET_VISITS=$(Q 'bitbucket.org')
    NPM_VISITS=$(Q 'npmjs.com')
    PYPI_VISITS=$(Q 'pypi.org')
    rm -f "$TEMP_DB"
  fi
fi
echo "visits: github=$GITHUB_VISITS gitlab=$GITLAB_VISITS bitbucket=$BITBUCKET_VISITS npm=$NPM_VISITS pypi=$PYPI_VISITS"

REPORT_FILE="$HOME/Documents/security_audit_report.json"
REPORT_EXISTS=0
REPORT_FRESH=0
if [ -f "$REPORT_FILE" ]; then
  REPORT_EXISTS=1
  # macOS `stat -f %m` returns Unix epoch mtime
  REPORT_MTIME=$(/usr/bin/stat -f %m "$REPORT_FILE" 2>/dev/null || echo "0")
  if [ "$REPORT_MTIME" -gt "$TASK_START" ] 2>/dev/null; then
    REPORT_FRESH=1
  fi
fi
echo "report: exists=$REPORT_EXISTS fresh=$REPORT_FRESH"

# Analyze the agent's report file with Python. Safe default of "[]" / "{}"
# preserved in shell vars if Python fails (Anti-pattern #12).
ANALYSIS_JSON='{"report_valid_json": false, "sites_present": [], "per_site_header_count": {}, "total_non_empty_headers": 0, "hsts_looks_valid": 0, "csp_looks_valid": 0}'
if [ -f "$REPORT_FILE" ]; then
  PY_OUT=$(/usr/bin/python3 - "$REPORT_FILE" << 'PYEOF'
import json, sys
REQUIRED = ["github.com", "gitlab.com", "bitbucket.org", "npmjs.com", "pypi.org"]
out = {
    "report_valid_json": False, "sites_present": [], "non_required_sites": [],
    "per_site_header_count": {},
    "total_non_empty_headers": 0, "hsts_looks_valid": 0, "csp_looks_valid": 0,
}
try:
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        data = json.load(f)
    out["report_valid_json"] = True
    data_lower = {str(k).lower(): v for k, v in (data.items() if isinstance(data, dict) else [])}
    total = 0; hsts_ok = 0; csp_ok = 0
    # Capture any report keys that don't match a required site, so the verifier
    # can detect "audited wrong sites" cases.
    matched_keys = set()
    for site in REQUIRED:
        for k in data_lower:
            if site in k or site.replace(".", "") in k.replace(".", ""):
                matched_keys.add(k)
    for k in data_lower:
        if k not in matched_keys:
            out["non_required_sites"].append(k)
    for site in REQUIRED:
        matched = None
        for k in data_lower:
            if site in k or site.replace(".", "") in k.replace(".", ""):
                matched = k; break
        if matched is None:
            out["per_site_header_count"][site] = 0
            continue
        out["sites_present"].append(site)
        entry = data_lower[matched]
        if not isinstance(entry, dict):
            out["per_site_header_count"][site] = 0
            continue
        entry_l = {str(k).lower(): v for k, v in entry.items()}
        count = 0
        for hk, hv in entry_l.items():
            if isinstance(hv, str) and len(hv.strip()) > 3:
                count += 1; total += 1
                if "strict-transport-security" in hk or hk == "hsts":
                    if "max-age" in hv.lower():
                        hsts_ok += 1
                if "content-security-policy" in hk or hk == "csp":
                    if any(tok in hv.lower() for tok in ("src", "default-src", "script-src", "none", "self")):
                        csp_ok += 1
        out["per_site_header_count"][site] = count
    out["total_non_empty_headers"] = total
    out["hsts_looks_valid"] = hsts_ok
    out["csp_looks_valid"] = csp_ok
except Exception as e:
    # Leave defaults; record the error class for debugging.
    out["json_error"] = f"{type(e).__name__}: {e}"
print(json.dumps(out))
PYEOF
  )
  if [ -n "$PY_OUT" ]; then
    ANALYSIS_JSON="$PY_OUT"
  fi
fi

# Stitch the result. One Python call so JSON quoting is right.
/usr/bin/python3 - "$ANALYSIS_JSON" "$TASK_START" "$GITHUB_VISITS" "$GITLAB_VISITS" "$BITBUCKET_VISITS" "$NPM_VISITS" "$PYPI_VISITS" "$REPORT_EXISTS" "$REPORT_FRESH" << 'PYEOF'
import json, sys
analysis = json.loads(sys.argv[1])
result = {
    "task_start": int(sys.argv[2]),
    "github_visits": int(sys.argv[3]),
    "gitlab_visits": int(sys.argv[4]),
    "bitbucket_visits": int(sys.argv[5]),
    "npm_visits": int(sys.argv[6]),
    "pypi_visits": int(sys.argv[7]),
    "report_exists": bool(int(sys.argv[8])),
    "report_fresh": bool(int(sys.argv[9])),
}
result.update(analysis)
with open("/tmp/devtools_security_header_audit_result.json", "w") as f:
    json.dump(result, f, indent=2)
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="
