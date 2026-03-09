#!/bin/bash
# export_result.sh - Post-task hook for apt_threat_intel_profiles

echo "=== Exporting apt_threat_intel_profiles results ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_end.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_end.png 2>/dev/null || true

# Kill Firefox to flush WAL to main database
echo "Flushing Firefox database..."
pkill -u ga -f firefox 2>/dev/null || true
sleep 3

# Read task start
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_START_US=$((TASK_START * 1000000))

# Find Firefox profile
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
if [ -z "$PROFILE_DIR" ]; then
    PROFILE_DIR=$(find /home/ga -name "places.sqlite" 2>/dev/null | head -1 | xargs -I{} dirname {} 2>/dev/null || echo "")
fi
echo "Using profile: $PROFILE_DIR"

PLACES_DB="$PROFILE_DIR/places.sqlite"

# Initialize all result variables
MITRE_VISITS=0
GOV_VISITS=0
APT_FOLDER_ID=""
APT_FOLDER_EXISTS=0
SANDWORM_SUBFOLDER=0
LAZARUS_SUBFOLDER=0
SANDWORM_BOOKMARKS=0
LAZARUS_BOOKMARKS=0
TOTAL_APT_BOOKMARKS=0
MITRE_BOOKMARKS_IN_APT=0
GOV_BOOKMARKS_IN_APT=0
REPORT_EXISTS=0
REPORT_SIZE=0
REPORT_HAS_SANDWORM=0
REPORT_HAS_LAZARUS=0
REPORT_HAS_TCODES=0
REPORT_HAS_ATTRIBUTION=0

if [ -f "$PLACES_DB" ]; then
    # Checkpoint WAL before copying
    sqlite3 "$PLACES_DB" "PRAGMA wal_checkpoint(TRUNCATE);" 2>/dev/null || true
    TEMP_DB="/tmp/places_apt_export_$$.sqlite"
    cp "$PLACES_DB" "$TEMP_DB" 2>/dev/null
    if [ -f "$TEMP_DB" ]; then
        # --- HISTORY CHECKS ---
        # Visits to attack.mitre.org after task start
        MITRE_VISITS=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(*) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id
             WHERE p.url LIKE '%attack.mitre.org%' AND h.visit_date > ${TASK_START_US};" 2>/dev/null || echo "0")

        # Visits to any government/authoritative security advisory source
        GOV_VISITS=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(*) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id
             WHERE (p.url LIKE '%cisa.gov%' OR p.url LIKE '%fbi.gov%' OR p.url LIKE '%ic3.gov%'
                    OR p.url LIKE '%us-cert%' OR p.url LIKE '%nsa.gov%' OR p.url LIKE '%ncsc.gov%')
             AND h.visit_date > ${TASK_START_US};" 2>/dev/null || echo "0")

        # --- BOOKMARK CHECKS ---
        # Find "APT Research" folder (case-insensitive name match)
        APT_FOLDER_ID=$(sqlite3 "$TEMP_DB" \
            "SELECT id FROM moz_bookmarks WHERE type=2 AND lower(title) LIKE '%apt research%' LIMIT 1;" 2>/dev/null || echo "")

        if [ -n "$APT_FOLDER_ID" ] && [ "$APT_FOLDER_ID" != "" ]; then
            APT_FOLDER_EXISTS=1

            # Check for Sandworm sub-folder under APT Research
            SANDWORM_ID=$(sqlite3 "$TEMP_DB" \
                "SELECT id FROM moz_bookmarks WHERE type=2 AND parent=$APT_FOLDER_ID
                 AND lower(title) LIKE '%sandworm%' LIMIT 1;" 2>/dev/null || echo "")
            if [ -n "$SANDWORM_ID" ]; then
                SANDWORM_SUBFOLDER=1
                SANDWORM_BOOKMARKS=$(sqlite3 "$TEMP_DB" \
                    "SELECT COUNT(*) FROM moz_bookmarks WHERE type=1 AND parent=$SANDWORM_ID;" 2>/dev/null || echo "0")
            fi

            # Check for Lazarus sub-folder under APT Research
            LAZARUS_ID=$(sqlite3 "$TEMP_DB" \
                "SELECT id FROM moz_bookmarks WHERE type=2 AND parent=$APT_FOLDER_ID
                 AND (lower(title) LIKE '%lazarus%' OR lower(title) LIKE '%apt38%' OR lower(title) LIKE '%hidden cobra%')
                 LIMIT 1;" 2>/dev/null || echo "")
            if [ -n "$LAZARUS_ID" ]; then
                LAZARUS_SUBFOLDER=1
                LAZARUS_BOOKMARKS=$(sqlite3 "$TEMP_DB" \
                    "SELECT COUNT(*) FROM moz_bookmarks WHERE type=1 AND parent=$LAZARUS_ID;" 2>/dev/null || echo "0")
            fi

            # Count all bookmarks anywhere under APT Research folder (including sub-folders)
            TOTAL_APT_BOOKMARKS=$(sqlite3 "$TEMP_DB" \
                "SELECT COUNT(*) FROM moz_bookmarks b JOIN moz_places p ON b.fk=p.id
                 WHERE b.type=1 AND (b.parent=$APT_FOLDER_ID
                   OR b.parent IN (SELECT id FROM moz_bookmarks WHERE type=2 AND parent=$APT_FOLDER_ID));" 2>/dev/null || echo "0")

            # Count bookmarks to MITRE ATT&CK in APT folder tree
            MITRE_BOOKMARKS_IN_APT=$(sqlite3 "$TEMP_DB" \
                "SELECT COUNT(*) FROM moz_bookmarks b JOIN moz_places p ON b.fk=p.id
                 WHERE b.type=1 AND p.url LIKE '%attack.mitre.org%'
                 AND (b.parent=$APT_FOLDER_ID
                   OR b.parent IN (SELECT id FROM moz_bookmarks WHERE type=2 AND parent=$APT_FOLDER_ID));" 2>/dev/null || echo "0")

            # Count bookmarks to gov advisory sources in APT folder tree
            GOV_BOOKMARKS_IN_APT=$(sqlite3 "$TEMP_DB" \
                "SELECT COUNT(*) FROM moz_bookmarks b JOIN moz_places p ON b.fk=p.id
                 WHERE b.type=1
                 AND (p.url LIKE '%cisa.gov%' OR p.url LIKE '%fbi.gov%' OR p.url LIKE '%ic3.gov%'
                      OR p.url LIKE '%crowdstrike%' OR p.url LIKE '%mandiant%' OR p.url LIKE '%ncsc.gov%'
                      OR p.url LIKE '%nsa.gov%' OR p.url LIKE '%recordedfuture%' OR p.url LIKE '%secureworks%'
                      OR p.url LIKE '%us-cert%' OR p.url LIKE '%bleepingcomputer%' OR p.url LIKE '%therecord%')
                 AND (b.parent=$APT_FOLDER_ID
                   OR b.parent IN (SELECT id FROM moz_bookmarks WHERE type=2 AND parent=$APT_FOLDER_ID));" 2>/dev/null || echo "0")
        fi

        rm -f "$TEMP_DB"
    fi
fi

# --- REPORT FILE CHECKS ---
REPORT_FILE="/home/ga/Desktop/threat_intel_report.txt"
if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS=1
    REPORT_SIZE=$(wc -c < "$REPORT_FILE" 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ] 2>/dev/null; then
        REPORT_FRESH=1
    else
        REPORT_FRESH=0
    fi

    # Content checks (case-insensitive)
    CONTENT_LOWER=$(cat "$REPORT_FILE" 2>/dev/null | tr '[:upper:]' '[:lower:]')

    if echo "$CONTENT_LOWER" | grep -q "sandworm"; then REPORT_HAS_SANDWORM=1; fi
    if echo "$CONTENT_LOWER" | grep -q "lazarus"; then REPORT_HAS_LAZARUS=1; fi

    # Check for MITRE ATT&CK T-codes (e.g. T1059, T1566, T1071, etc.)
    if echo "$CONTENT_LOWER" | grep -qE "t1[0-9]{3}"; then REPORT_HAS_TCODES=1; fi

    # Check for attribution keywords
    if echo "$CONTENT_LOWER" | grep -qE "russia|gru|north korea|dprk|lazarus|attribution|sponsored|nation.?state"; then
        REPORT_HAS_ATTRIBUTION=1
    fi
else
    REPORT_FRESH=0
fi

# --- DOWNLOADED FILES CHECK ---
NEW_FILES=$(find /home/ga/Downloads -newer /tmp/task_start_timestamp 2>/dev/null | wc -l)

# Build result JSON using Python for reliability
python3 << PYEOF
import json, os

result = {
    "task_start": $TASK_START,
    "mitre_visits": $MITRE_VISITS,
    "gov_visits": $GOV_VISITS,
    "apt_folder_exists": bool($APT_FOLDER_EXISTS),
    "sandworm_subfolder": bool($SANDWORM_SUBFOLDER),
    "lazarus_subfolder": bool($LAZARUS_SUBFOLDER),
    "sandworm_bookmarks": $SANDWORM_BOOKMARKS,
    "lazarus_bookmarks": $LAZARUS_BOOKMARKS,
    "total_apt_bookmarks": $TOTAL_APT_BOOKMARKS,
    "mitre_bookmarks_in_apt": $MITRE_BOOKMARKS_IN_APT,
    "gov_bookmarks_in_apt": $GOV_BOOKMARKS_IN_APT,
    "report_exists": bool($REPORT_EXISTS),
    "report_fresh": bool($REPORT_FRESH),
    "report_size": $REPORT_SIZE,
    "report_has_sandworm": bool($REPORT_HAS_SANDWORM),
    "report_has_lazarus": bool($REPORT_HAS_LAZARUS),
    "report_has_tcodes": bool($REPORT_HAS_TCODES),
    "report_has_attribution": bool($REPORT_HAS_ATTRIBUTION),
    "new_downloads": $NEW_FILES
}

with open("/tmp/apt_threat_intel_profiles_result.json", "w") as f:
    json.dump(result, f, indent=2)
print("Result JSON written")
PYEOF

echo "=== Export complete ==="
cat /tmp/apt_threat_intel_profiles_result.json
