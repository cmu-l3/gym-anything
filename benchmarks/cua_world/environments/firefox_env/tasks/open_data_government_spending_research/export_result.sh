#!/bin/bash
# export_result.sh - Post-task hook for open_data_government_spending_research

echo "=== Exporting open_data_government_spending_research results ==="

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

# Check USASpending.gov visit history
USASPENDING_VISITS=0
USASPENDING_SEARCH_VISITS=0
GOV_DATA_VISITS=0

if [ -f "$PLACES_DB" ]; then
    sqlite3 "$PLACES_DB" "PRAGMA wal_checkpoint(TRUNCATE);" 2>/dev/null || true
    TEMP_DB="/tmp/places_spending_export_$$.sqlite"
    cp "$PLACES_DB" "$TEMP_DB" 2>/dev/null
    if [ -f "$TEMP_DB" ]; then
        USASPENDING_VISITS=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(DISTINCT p.id) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id
             WHERE p.url LIKE '%usaspending.gov%' AND h.visit_date > ${TASK_START_US};" 2>/dev/null || echo "0")
        USASPENDING_SEARCH_VISITS=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(DISTINCT p.id) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id
             WHERE (p.url LIKE '%usaspending.gov/search%' OR p.url LIKE '%usaspending.gov/agency%'
                    OR p.url LIKE '%usaspending.gov/recipient%' OR p.url LIKE '%usaspending.gov/award%')
             AND h.visit_date > ${TASK_START_US};" 2>/dev/null || echo "0")
        GOV_DATA_VISITS=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(DISTINCT p.id) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id
             WHERE (p.url LIKE '%fpds.gov%' OR p.url LIKE '%data.gov%' OR p.url LIKE '%usaspending.gov%'
                    OR p.url LIKE '%sam.gov%' OR p.url LIKE '%grants.gov%')
             AND h.visit_date > ${TASK_START_US};" 2>/dev/null || echo "0")
        rm -f "$TEMP_DB"
    fi
fi

# Check for CSV downloads
INITIAL_CSV_COUNT=$(cat /tmp/initial_csv_count 2>/dev/null || echo "0")
NEW_CSVS=$(find /home/ga/Downloads -maxdepth 3 -name "*.csv" -newer /proc/1 \
    2>/dev/null | head -20)
# Count CSVs modified after task start
CSV_COUNT_NOW=0
CSV_NAMES=""
for f in /home/ga/Downloads/*.csv /home/ga/Downloads/**/*.csv; do
    [ -f "$f" ] || continue
    MTIME=$(stat -c %Y "$f" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ] 2>/dev/null; then
        SIZE=$(stat -c %s "$f" 2>/dev/null || echo "0")
        if [ "$SIZE" -gt "1000" ]; then
            CSV_COUNT_NOW=$((CSV_COUNT_NOW + 1))
            CSV_NAMES="$CSV_NAMES $f"
        fi
    fi
done

# Check research notes file
NOTES_FILE="/home/ga/Documents/dod_spending_research.txt"
NOTES_MTIME=$(stat -c %Y "$NOTES_FILE" 2>/dev/null || echo "0")
NOTES_EXISTS=0
NOTES_FRESH=0
NOTES_SIZE=0
if [ -f "$NOTES_FILE" ]; then
    NOTES_EXISTS=1
    NOTES_SIZE=$(stat -c %s "$NOTES_FILE" 2>/dev/null || echo "0")
    if [ "$NOTES_MTIME" -gt "$TASK_START" ] 2>/dev/null; then
        NOTES_FRESH=1
    fi
fi

# Check for bookmark folder
SPENDING_FOLDER_EXISTS=0
SPENDING_FOLDER_BOOKMARK_COUNT=0
SPENDING_FOLDER_HAS_USASPENDING=0

if [ -f "$PLACES_DB" ]; then
    TEMP_DB3="/tmp/places_spending_bm_$$.sqlite"
    cp "$PLACES_DB" "$TEMP_DB3" 2>/dev/null
    if [ -f "$TEMP_DB3" ]; then
        SPENDING_FOLDER_ID=$(sqlite3 "$TEMP_DB3" \
            "SELECT id FROM moz_bookmarks WHERE title='Government Spending Research' AND type=2 LIMIT 1;" 2>/dev/null || echo "")
        if [ -n "$SPENDING_FOLDER_ID" ]; then
            SPENDING_FOLDER_EXISTS=1
            SPENDING_FOLDER_BOOKMARK_COUNT=$(sqlite3 "$TEMP_DB3" \
                "SELECT COUNT(*) FROM moz_bookmarks WHERE parent=${SPENDING_FOLDER_ID} AND type=1;" 2>/dev/null || echo "0")
            SPENDING_FOLDER_HAS_USASPENDING=$(sqlite3 "$TEMP_DB3" \
                "SELECT COUNT(*) FROM moz_bookmarks bm JOIN moz_places p ON bm.fk=p.id
                 WHERE bm.parent=${SPENDING_FOLDER_ID} AND bm.type=1
                 AND (p.url LIKE '%usaspending.gov%' OR p.url LIKE '%fpds.gov%' OR p.url LIKE '%data.gov%');" 2>/dev/null || echo "0")
        fi
        rm -f "$TEMP_DB3"
    fi
fi

# Analyze notes content with Python
python3 << PYEOF
import json, os, re

TASK_START = $TASK_START
NOTES_FILE = "/home/ga/Documents/dod_spending_research.txt"

result = {
    "task_start": TASK_START,
    "usaspending_visits": $USASPENDING_VISITS,
    "usaspending_search_visits": $USASPENDING_SEARCH_VISITS,
    "gov_data_visits": $GOV_DATA_VISITS,
    "csv_downloaded": $CSV_COUNT_NOW > 0,
    "csv_count": $CSV_COUNT_NOW,
    "notes_exists": bool($NOTES_EXISTS),
    "notes_fresh": bool($NOTES_FRESH),
    "notes_size": $NOTES_SIZE,
    "spending_folder_exists": bool($SPENDING_FOLDER_EXISTS),
    "spending_folder_bookmark_count": $SPENDING_FOLDER_BOOKMARK_COUNT,
    "spending_folder_has_usaspending_urls": $SPENDING_FOLDER_HAS_USASPENDING,
    # Content analysis (filled below)
    "has_dollar_amount": False,
    "has_contractor_names": False,
    "has_urls": False,
    "has_substantial_content": False,
    "url_count": 0,
    "contractor_names_found": [],
}

if os.path.exists(NOTES_FILE):
    try:
        with open(NOTES_FILE, "r", encoding="utf-8") as f:
            content = f.read()

        result["has_substantial_content"] = len(content.strip()) >= 200

        # Check for dollar amounts (billions/trillions)
        dollar_pattern = re.compile(
            r'\$[\d,\.]+\s*[BTMbтm](?:illion|ILLION)?|'
            r'[\d,\.]+\s*[Bb]illion|'
            r'[\d,\.]+\s*[Tt]rillion|'
            r'\$[\d,\.]+[BTMbtm]',
            re.IGNORECASE
        )
        if dollar_pattern.search(content):
            result["has_dollar_amount"] = True

        # Check for contractor company names
        contractor_keywords = [
            "lockheed", "raytheon", "boeing", "general dynamics",
            "northrop", "l3", "leidos", "bae systems", "saic",
            "huntington ingalls", "booz allen", "kbr", "aecom",
            "dxc technology", "mantech", "caci", "perspecta",
            "inc.", "llc", "corp", "corporation", "company", "ltd"
        ]
        found = []
        content_lower = content.lower()
        for kw in contractor_keywords[:11]:  # Check top 11 specific names
            if kw in content_lower:
                found.append(kw)
        result["has_contractor_names"] = len(found) >= 1
        result["contractor_names_found"] = found[:5]

        # Check for URLs
        url_pattern = re.compile(r'https?://[^\s\)]+', re.IGNORECASE)
        urls = url_pattern.findall(content)
        result["url_count"] = len(urls)
        result["has_urls"] = len(urls) >= 2

        # Check for DOD/Defense-specific content (validates correct agency was researched)
        dod_pattern = re.compile(
            r'\bdod\b|department\s+of\s+defense|defense\s+(contract|spend|budget|procurement)|'
            r'pentagon|defense\.gov|dau\.edu|afrl|darpa|army|navy|air\s+force|marines|'
            r'military\s+(spend|contract|budget)',
            re.IGNORECASE
        )
        result["has_dod_content"] = bool(dod_pattern.search(content))

    except Exception as e:
        result["notes_parse_error"] = str(e)

with open("/tmp/open_data_government_spending_research_result.json", "w") as f:
    json.dump(result, f, indent=2)
print("Result written")
PYEOF

echo "=== Export complete ==="
cat /tmp/open_data_government_spending_research_result.json
