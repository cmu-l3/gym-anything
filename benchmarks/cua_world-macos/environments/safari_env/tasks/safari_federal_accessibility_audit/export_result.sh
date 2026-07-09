#!/usr/bin/env bash
set -euo pipefail

RESULT_FILE="/tmp/federal_accessibility_audit_result.json"
REPORT_FILE="/Users/lume/Documents/federal_accessibility_audit.json"
HISTORY_DB="/Users/lume/Library/Safari/History.db"

TASK_START=$(cat /tmp/a11y_task_start_timestamp 2>/dev/null || echo "0")
MAC_START=$((TASK_START - 978307200))

osascript -e 'tell application "Safari" to quit' 2>/dev/null || true
pkill -x Safari 2>/dev/null || true
sleep 2
sqlite3 "$HISTORY_DB" "PRAGMA wal_checkpoint(TRUNCATE);" 2>/dev/null || true
sleep 1

query_visits() {
    local domain="$1"
    sqlite3 "$HISTORY_DB" \
        "SELECT COUNT(*) FROM history_items hi
         JOIN history_visits hv ON hi.id = hv.history_item
         WHERE hi.domain_expansion LIKE '%${domain}%'
           AND hv.visit_time > ${MAC_START};" 2>/dev/null || echo "0"
}

SSA_VISITS=$(query_visits "ssa.gov")
MEDICARE_VISITS=$(query_visits "medicare.gov")
VA_VISITS=$(query_visits "va.gov")
BENEFITS_VISITS=$(query_visits "benefits.gov")

REPORT_EXISTS=false
REPORT_MTIME=0
REPORT_SIZE=0
if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS=true
    REPORT_MTIME=$(stat -f %m "$REPORT_FILE" 2>/dev/null || echo "0")
    REPORT_SIZE=$(stat -f %z "$REPORT_FILE" 2>/dev/null || echo "0")
fi

python3 << 'PYEOF'
import json, os

REPORT_PATH  = "/Users/lume/Documents/federal_accessibility_audit.json"
TASK_START   = int(open("/tmp/a11y_task_start_timestamp").read().strip()) if os.path.exists("/tmp/a11y_task_start_timestamp") else 0
REPORT_MTIME = int(os.stat(REPORT_PATH).st_mtime) if os.path.exists(REPORT_PATH) else 0

REQUIRED_SITES = {
    "ssa.gov":      ["ssa.gov", "ssa"],
    "medicare.gov": ["medicare.gov", "medicare"],
    "va.gov":       ["va.gov", ".va."],
    "benefits.gov": ["benefits.gov", "benefits"],
}
ISSUE_TYPE_KEYS = ["errors", "warnings", "comments", "error", "warning", "comment"]

analysis = {
    "report_exists":              False,
    "report_written_after_start": False,
    "sites_found":                [],
    "sites_complete":             [],
    "site_details":               {},
    "parse_error":                None,
}

try:
    if not os.path.exists(REPORT_PATH):
        raise FileNotFoundError("output file missing")

    analysis["report_exists"] = True
    analysis["report_written_after_start"] = REPORT_MTIME > TASK_START

    with open(REPORT_PATH) as f:
        data = json.load(f)

    if isinstance(data, list):
        # Convert list to dict keyed by domain hint
        keyed = {}
        for item in data:
            if isinstance(item, dict):
                domain = item.get("domain") or item.get("site") or item.get("url") or ""
                keyed[str(domain).lower()] = item
        data = keyed

    if not isinstance(data, dict):
        raise ValueError("top-level JSON must be a dict or list of site objects")

    for canonical, keywords in REQUIRED_SITES.items():
        # Find the entry for this site
        entry = None
        for key, val in data.items():
            if any(kw in key.lower() for kw in keywords):
                entry = val
                break
        # Also search inside values if key didn't match
        if entry is None:
            for val in data.values():
                if not isinstance(val, dict):
                    continue
                val_str = json.dumps(val).lower()
                if any(kw in val_str for kw in keywords):
                    entry = val
                    break

        if entry is None:
            continue

        if canonical in analysis["sites_found"]:
            continue
        analysis["sites_found"].append(canonical)

        entry_str = json.dumps(entry).lower()
        total_issues = entry.get("total_issues") or entry.get("total") or entry.get("issue_count") or 0
        has_total = isinstance(total_issues, (int, float)) and total_issues >= 0

        # Check for issue type breakdown
        has_breakdown = any(k in entry for k in ISSUE_TYPE_KEYS)

        # Check for at least 3 specific issue descriptions
        descriptions = (
            entry.get("issues") or
            entry.get("issue_descriptions") or
            entry.get("details") or
            entry.get("findings") or
            []
        )
        if isinstance(descriptions, dict):
            descriptions = list(descriptions.values())
        desc_count = len([d for d in descriptions if isinstance(d, str) and len(d.strip()) > 5])

        detail = {
            "has_total":        has_total,
            "total_issues":     int(total_issues) if has_total else None,
            "has_breakdown":    has_breakdown,
            "desc_count":       desc_count,
            "has_3_descs":      desc_count >= 3,
        }
        analysis["site_details"][canonical] = detail

        if has_total and has_breakdown and desc_count >= 3:
            analysis["sites_complete"].append(canonical)

except Exception as e:
    analysis["parse_error"] = str(e)

with open("/tmp/_a11y_analysis.json", "w") as f:
    json.dump(analysis, f)
PYEOF

ANALYSIS=$(cat /tmp/_a11y_analysis.json 2>/dev/null || echo '{}')
rm -f /tmp/_a11y_analysis.json

python3 << PYEOF
import json

analysis       = json.loads("""${ANALYSIS}""")
ssa_visits     = int("${SSA_VISITS}"      or 0)
medicare_visits= int("${MEDICARE_VISITS}" or 0)
va_visits      = int("${VA_VISITS}"       or 0)
benefits_visits= int("${BENEFITS_VISITS}" or 0)
report_size    = int("${REPORT_SIZE}"     or 0)
task_start     = int("${TASK_START}"      or 0)

result = {
    "history": {
        "ssa_visits":      ssa_visits,
        "medicare_visits": medicare_visits,
        "va_visits":       va_visits,
        "benefits_visits": benefits_visits,
    },
    "report_exists":              analysis.get("report_exists", False),
    "report_written_after_start": analysis.get("report_written_after_start", False),
    "sites_found":                analysis.get("sites_found", []),
    "sites_complete":             analysis.get("sites_complete", []),
    "site_details":               analysis.get("site_details", {}),
    "parse_error":                analysis.get("parse_error"),
    "report_size_bytes":          report_size,
}

with open("${RESULT_FILE}", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "export complete → ${RESULT_FILE}"
