#!/bin/bash
# export_result.sh - Post-task hook for sec_edgar_annual_report_analysis

echo "=== Exporting sec_edgar_annual_report_analysis results ==="

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

# Check history for SEC EDGAR domains
SEC_VISITS=0
EDGAR_VISITS=0

if [ -f "$PLACES_DB" ]; then
    sqlite3 "$PLACES_DB" "PRAGMA wal_checkpoint(TRUNCATE);" 2>/dev/null || true
    TEMP_DB="/tmp/places_edgar_export_$$.sqlite"
    cp "$PLACES_DB" "$TEMP_DB" 2>/dev/null
    if [ -f "$TEMP_DB" ]; then
        SEC_VISITS=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(DISTINCT p.id) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id
             WHERE p.url LIKE '%sec.gov%' AND h.visit_date > ${TASK_START_US};" 2>/dev/null || echo "0")
        EDGAR_VISITS=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(DISTINCT p.id) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id
             WHERE (p.url LIKE '%sec.gov/cgi-bin%' OR p.url LIKE '%efts.sec.gov%' OR p.url LIKE '%sec.gov/Archives%')
             AND h.visit_date > ${TASK_START_US};" 2>/dev/null || echo "0")
        rm -f "$TEMP_DB"
    fi
fi

# Check for output JSON file
REPORT_FILE="/home/ga/Documents/edgar_analysis.json"
REPORT_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
REPORT_EXISTS=0
REPORT_FRESH=0
if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS=1
    if [ "$REPORT_MTIME" -gt "$TASK_START" ] 2>/dev/null; then
        REPORT_FRESH=1
    fi
fi

# Check for SEC EDGAR Research bookmark folder and bookmarks
EDGAR_FOLDER_EXISTS=0
EDGAR_FOLDER_BOOKMARK_COUNT=0
EDGAR_FOLDER_HAS_SEC_URLS=0

if [ -f "$PLACES_DB" ]; then
    TEMP_DB2="/tmp/places_edgar_bm_$$.sqlite"
    cp "$PLACES_DB" "$TEMP_DB2" 2>/dev/null
    if [ -f "$TEMP_DB2" ]; then
        EDGAR_FOLDER_ID=$(sqlite3 "$TEMP_DB2" \
            "SELECT id FROM moz_bookmarks WHERE title='SEC EDGAR Research' AND type=2 LIMIT 1;" 2>/dev/null || echo "")
        if [ -n "$EDGAR_FOLDER_ID" ]; then
            EDGAR_FOLDER_EXISTS=1
            EDGAR_FOLDER_BOOKMARK_COUNT=$(sqlite3 "$TEMP_DB2" \
                "SELECT COUNT(*) FROM moz_bookmarks WHERE parent=${EDGAR_FOLDER_ID} AND type=1;" 2>/dev/null || echo "0")
            EDGAR_FOLDER_HAS_SEC_URLS=$(sqlite3 "$TEMP_DB2" \
                "SELECT COUNT(*) FROM moz_bookmarks bm JOIN moz_places p ON bm.fk=p.id
                 WHERE bm.parent=${EDGAR_FOLDER_ID} AND bm.type=1 AND p.url LIKE '%sec.gov%';" 2>/dev/null || echo "0")
        fi
        rm -f "$TEMP_DB2"
    fi
fi

# Parse the JSON analysis report using Python
python3 << PYEOF
import json, os, sys, re

TASK_START = $TASK_START
REPORT_FILE = "/home/ga/Documents/edgar_analysis.json"
COMPANIES = ["microsoft", "apple", "alphabet"]

# Known revenue ranges in billions (generous ±35% tolerance for any recent year)
REVENUE_RANGES = {
    "microsoft": (120, 350),   # FY2021: $168B ... FY2024: $245B
    "apple":     (250, 500),   # FY2021: $365B ... FY2024: $391B
    "alphabet":  (180, 420),   # FY2021: $258B ... FY2024: $350B
}

result = {
    "task_start": TASK_START,
    "sec_visits": $SEC_VISITS,
    "edgar_visits": $EDGAR_VISITS,
    "report_exists": bool($REPORT_EXISTS),
    "report_fresh": bool($REPORT_FRESH),
    "report_valid_json": False,
    "companies_present": [],
    "per_company": {},
    "filing_dates_valid": 0,
    "risk_counts_plausible": 0,
    "revenues_plausible": 0,
}

for company in COMPANIES:
    result["per_company"][company] = {
        "present": False,
        "has_filing_date": False,
        "has_risk_count": False,
        "has_revenue": False,
        "filing_date_valid": False,
        "risk_count_plausible": False,
        "revenue_plausible": False,
    }

if os.path.exists(REPORT_FILE):
    try:
        with open(REPORT_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
        result["report_valid_json"] = True

        data_lower = {k.lower(): v for k, v in data.items()}

        for company in COMPANIES:
            # Find company key (case insensitive)
            matched_key = None
            for k in data_lower:
                if company in k:
                    matched_key = k
                    break

            cp = result["per_company"][company]

            if matched_key is None:
                continue

            entry = data_lower[matched_key]
            if not isinstance(entry, dict):
                continue

            cp["present"] = True
            result["companies_present"].append(company)
            entry_lower = {str(k).lower(): v for k, v in entry.items()}

            # Check filing_date
            filing_date = None
            for k in ["filing_date", "filingdate", "date", "filed"]:
                if k in entry_lower and entry_lower[k]:
                    filing_date = str(entry_lower[k])
                    break
            if filing_date:
                cp["has_filing_date"] = True
                # Validate date range 2022-01-01 to 2025-12-31 (ISO-ish format)
                date_match = re.search(r"(202[2-5])[- /](0[1-9]|1[0-2])[- /](\d{2})", filing_date)
                if date_match:
                    cp["filing_date_valid"] = True
                    result["filing_dates_valid"] += 1

            # Check risk_factor_count
            risk_count = None
            for k in ["risk_factor_count", "risk_factors", "riskfactorcount", "risk_count", "num_risk_factors"]:
                if k in entry_lower and entry_lower[k] is not None:
                    try:
                        risk_count = int(entry_lower[k])
                    except (ValueError, TypeError):
                        pass
                    break
            if risk_count is not None:
                cp["has_risk_count"] = True
                if 5 <= risk_count <= 250:
                    cp["risk_count_plausible"] = True
                    result["risk_counts_plausible"] += 1

            # Check revenue_billions
            revenue = None
            for k in ["revenue_billions", "revenue", "total_revenue", "revenues_billions"]:
                if k in entry_lower and entry_lower[k] is not None:
                    try:
                        revenue = float(entry_lower[k])
                    except (ValueError, TypeError):
                        pass
                    break
            if revenue is not None:
                cp["has_revenue"] = True
                lo, hi = REVENUE_RANGES.get(company, (0, 10000))
                if lo <= revenue <= hi:
                    cp["revenue_plausible"] = True
                    result["revenues_plausible"] += 1

    except (json.JSONDecodeError, Exception) as e:
        result["report_valid_json"] = False
        result["json_error"] = str(e)

with open("/tmp/sec_edgar_annual_report_analysis_result.json", "w") as f:
    json.dump(result, f, indent=2)
print("Result written")
PYEOF

echo "=== Export complete ==="
cat /tmp/sec_edgar_annual_report_analysis_result.json
