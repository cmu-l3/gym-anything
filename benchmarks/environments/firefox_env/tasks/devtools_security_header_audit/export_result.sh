#!/bin/bash
# export_result.sh - Post-task hook for devtools_security_header_audit

echo "=== Exporting devtools_security_header_audit results ==="

DISPLAY=:1 scrot /tmp/task_end.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_end.png 2>/dev/null || true

# Kill Firefox to flush WAL
pkill -u ga -f firefox 2>/dev/null || true
sleep 3

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_START_US=$((TASK_START * 1000000))

PROFILE_DIR=$(cat /tmp/firefox_profile_path 2>/dev/null || echo "")
if [ -z "$PROFILE_DIR" ] || [ ! -f "$PROFILE_DIR/places.sqlite" ]; then
    for candidate in \
        "/home/ga/snap/firefox/common/.mozilla/firefox/default.profile" \
        "/home/ga/.mozilla/firefox/default.profile"; do
        if [ -f "$candidate/places.sqlite" ]; then
            PROFILE_DIR="$candidate"
            break
        fi
    done
fi
PLACES_DB="$PROFILE_DIR/places.sqlite"

# Check history for all 5 required domains
GITHUB_VISITS=0
GITLAB_VISITS=0
BITBUCKET_VISITS=0
NPM_VISITS=0
PYPI_VISITS=0

if [ -f "$PLACES_DB" ]; then
    sqlite3 "$PLACES_DB" "PRAGMA wal_checkpoint(TRUNCATE);" 2>/dev/null || true
    TEMP_DB="/tmp/places_devtools_export_$$.sqlite"
    cp "$PLACES_DB" "$TEMP_DB" 2>/dev/null
    if [ -f "$TEMP_DB" ]; then
        GITHUB_VISITS=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(DISTINCT p.id) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id
             WHERE p.url LIKE '%github.com%' AND h.visit_date > ${TASK_START_US};" 2>/dev/null || echo "0")
        GITLAB_VISITS=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(DISTINCT p.id) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id
             WHERE p.url LIKE '%gitlab.com%' AND h.visit_date > ${TASK_START_US};" 2>/dev/null || echo "0")
        BITBUCKET_VISITS=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(DISTINCT p.id) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id
             WHERE p.url LIKE '%bitbucket.org%' AND h.visit_date > ${TASK_START_US};" 2>/dev/null || echo "0")
        NPM_VISITS=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(DISTINCT p.id) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id
             WHERE p.url LIKE '%npmjs.com%' AND h.visit_date > ${TASK_START_US};" 2>/dev/null || echo "0")
        PYPI_VISITS=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(DISTINCT p.id) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id
             WHERE p.url LIKE '%pypi.org%' AND h.visit_date > ${TASK_START_US};" 2>/dev/null || echo "0")
        rm -f "$TEMP_DB"
    fi
fi

# Analyze the JSON audit report using Python for robustness
REPORT_FILE="/home/ga/Documents/security_audit_report.json"
REPORT_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
REPORT_EXISTS=0
REPORT_FRESH=0
if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS=1
    if [ "$REPORT_MTIME" -gt "$TASK_START" ] 2>/dev/null; then
        REPORT_FRESH=1
    fi
fi

python3 << PYEOF
import json, os, sys

TASK_START = $TASK_START
REPORT_FILE = "/home/ga/Documents/security_audit_report.json"
REQUIRED_SITES = ["github.com", "gitlab.com", "bitbucket.org", "npmjs.com", "pypi.org"]
SECURITY_HEADER_KEYS = [
    "strict-transport-security", "hsts",
    "content-security-policy", "csp", "content-security-policy-report-only",
    "x-content-type-options",
    "x-frame-options"
]

result = {
    "task_start": TASK_START,
    "github_visits": $GITHUB_VISITS,
    "gitlab_visits": $GITLAB_VISITS,
    "bitbucket_visits": $BITBUCKET_VISITS,
    "npm_visits": $NPM_VISITS,
    "pypi_visits": $PYPI_VISITS,
    "report_exists": bool($REPORT_EXISTS),
    "report_fresh": bool($REPORT_FRESH),
    "report_valid_json": False,
    "sites_present": [],
    "per_site_header_count": {},
    "total_non_empty_headers": 0,
    "hsts_looks_valid": 0,
    "csp_looks_valid": 0
}

if os.path.exists(REPORT_FILE):
    try:
        with open(REPORT_FILE, 'r', encoding='utf-8') as f:
            data = json.load(f)
        result["report_valid_json"] = True

        # Find which required sites appear in the JSON (case-insensitive key matching)
        data_lower = {k.lower(): v for k, v in data.items()}
        total_non_empty = 0
        hsts_valid = 0
        csp_valid = 0

        for site in REQUIRED_SITES:
            # Match by site key - look for any key containing the domain
            matched_key = None
            for k in data_lower:
                if site in k or site.replace('.', '') in k.replace('.', ''):
                    matched_key = k
                    break

            if matched_key:
                result["sites_present"].append(site)
                entry = data_lower[matched_key]
                if not isinstance(entry, dict):
                    result["per_site_header_count"][site] = 0
                    continue

                # Count non-empty header values for this site
                entry_lower = {str(k).lower(): v for k, v in entry.items()}
                non_empty_count = 0
                for h_key, h_val in entry_lower.items():
                    if isinstance(h_val, str) and len(h_val.strip()) > 3:
                        non_empty_count += 1
                        total_non_empty += 1

                        # Validate HSTS value
                        if "strict-transport-security" in h_key or "hsts" in h_key:
                            if "max-age" in h_val.lower():
                                hsts_valid += 1

                        # Validate CSP value
                        if "content-security-policy" in h_key or "csp" == h_key:
                            if any(x in h_val.lower() for x in ["src", "default-src", "script-src", "none", "self"]):
                                csp_valid += 1

                result["per_site_header_count"][site] = non_empty_count
            else:
                result["per_site_header_count"][site] = 0

        result["total_non_empty_headers"] = total_non_empty
        result["hsts_looks_valid"] = hsts_valid
        result["csp_looks_valid"] = csp_valid

    except (json.JSONDecodeError, Exception) as e:
        result["report_valid_json"] = False
        result["json_error"] = str(e)

with open("/tmp/devtools_security_header_audit_result.json", "w") as f:
    json.dump(result, f, indent=2)
print("Result written")
PYEOF

echo "=== Export complete ==="
cat /tmp/devtools_security_header_audit_result.json
