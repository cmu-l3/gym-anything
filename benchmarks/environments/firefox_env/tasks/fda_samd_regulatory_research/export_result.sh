#!/bin/bash
# export_result.sh - Post-task hook for fda_samd_regulatory_research

echo "=== Exporting fda_samd_regulatory_research results ==="

DISPLAY=:1 scrot /tmp/task_end.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_end.png 2>/dev/null || true

# Kill Firefox to flush WAL
pkill -u ga -f firefox 2>/dev/null || true
sleep 3

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_START_US=$((TASK_START * 1000000))

# Find profile
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

# Initialize
FDA_VISITS=0
FEDREG_VISITS=0
IMDRF_VISITS=0
FDA_BOOKMARK_FOLDER_EXISTS=0
FDA_FOLDER_BOOKMARK_COUNT=0
FDA_BOOKMARKS_COUNT=0
FEDREG_BOOKMARKS_COUNT=0
IMDRF_BOOKMARKS_COUNT=0
MATRIX_EXISTS=0
MATRIX_FRESH=0
MATRIX_SIZE=0
MATRIX_HAS_SAMD=0
MATRIX_HAS_FDA=0
MATRIX_HAS_IMDRF=0
MATRIX_HAS_REGULATORY=0

if [ -f "$PLACES_DB" ]; then
    sqlite3 "$PLACES_DB" "PRAGMA wal_checkpoint(TRUNCATE);" 2>/dev/null || true
    TEMP_DB="/tmp/places_fda_export_$$.sqlite"
    cp "$PLACES_DB" "$TEMP_DB" 2>/dev/null
    if [ -f "$TEMP_DB" ]; then
        # History: FDA.gov
        FDA_VISITS=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(DISTINCT p.id) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id
             WHERE p.url LIKE '%fda.gov%' AND h.visit_date > ${TASK_START_US};" 2>/dev/null || echo "0")

        # History: Federal Register
        FEDREG_VISITS=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(DISTINCT p.id) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id
             WHERE p.url LIKE '%federalregister.gov%' AND h.visit_date > ${TASK_START_US};" 2>/dev/null || echo "0")

        # History: IMDRF
        IMDRF_VISITS=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(DISTINCT p.id) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id
             WHERE p.url LIKE '%imdrf.org%' AND h.visit_date > ${TASK_START_US};" 2>/dev/null || echo "0")

        # Bookmark folder "FDA Regulatory Research"
        FDA_FOLDER_ID=$(sqlite3 "$TEMP_DB" \
            "SELECT id FROM moz_bookmarks WHERE type=2 AND lower(title) LIKE '%fda regulatory%' LIMIT 1;" 2>/dev/null || echo "")

        if [ -n "$FDA_FOLDER_ID" ]; then
            FDA_BOOKMARK_FOLDER_EXISTS=1

            # Total bookmarks in folder (including sub-folders)
            FDA_FOLDER_BOOKMARK_COUNT=$(sqlite3 "$TEMP_DB" \
                "SELECT COUNT(*) FROM moz_bookmarks b JOIN moz_places p ON b.fk=p.id
                 WHERE b.type=1
                 AND (b.parent=$FDA_FOLDER_ID
                   OR b.parent IN (SELECT id FROM moz_bookmarks WHERE type=2 AND parent=$FDA_FOLDER_ID));" 2>/dev/null || echo "0")

            # FDA bookmarks in folder
            FDA_BOOKMARKS_COUNT=$(sqlite3 "$TEMP_DB" \
                "SELECT COUNT(*) FROM moz_bookmarks b JOIN moz_places p ON b.fk=p.id
                 WHERE b.type=1 AND p.url LIKE '%fda.gov%'
                 AND (b.parent=$FDA_FOLDER_ID
                   OR b.parent IN (SELECT id FROM moz_bookmarks WHERE type=2 AND parent=$FDA_FOLDER_ID));" 2>/dev/null || echo "0")

            # Federal Register bookmarks
            FEDREG_BOOKMARKS_COUNT=$(sqlite3 "$TEMP_DB" \
                "SELECT COUNT(*) FROM moz_bookmarks b JOIN moz_places p ON b.fk=p.id
                 WHERE b.type=1 AND p.url LIKE '%federalregister.gov%'
                 AND (b.parent=$FDA_FOLDER_ID
                   OR b.parent IN (SELECT id FROM moz_bookmarks WHERE type=2 AND parent=$FDA_FOLDER_ID));" 2>/dev/null || echo "0")

            # IMDRF bookmarks
            IMDRF_BOOKMARKS_COUNT=$(sqlite3 "$TEMP_DB" \
                "SELECT COUNT(*) FROM moz_bookmarks b JOIN moz_places p ON b.fk=p.id
                 WHERE b.type=1 AND p.url LIKE '%imdrf.org%'
                 AND (b.parent=$FDA_FOLDER_ID
                   OR b.parent IN (SELECT id FROM moz_bookmarks WHERE type=2 AND parent=$FDA_FOLDER_ID));" 2>/dev/null || echo "0")
        fi

        rm -f "$TEMP_DB"
    fi
fi

# Downloads: PDFs from .gov or regulatory domains, newer than task_start, size > 10KB
PDF_COUNT=0
LARGEST_PDF_SIZE=0
while IFS= read -r -d '' f; do
    SIZE=$(stat -c %s "$f" 2>/dev/null || echo "0")
    if [ "$SIZE" -gt 10240 ]; then
        PDF_COUNT=$((PDF_COUNT + 1))
        if [ "$SIZE" -gt "$LARGEST_PDF_SIZE" ]; then
            LARGEST_PDF_SIZE="$SIZE"
        fi
    fi
done < <(find /home/ga/Downloads -newer /tmp/task_start_timestamp \( -name "*.pdf" -o -name "*.PDF" \) -print0 2>/dev/null)

# Also check for any significant file downloads (not just PDF)
NEW_LARGE_FILES=$(find /home/ga/Downloads -newer /tmp/task_start_timestamp -size +10k 2>/dev/null | wc -l)

# Matrix file checks
MATRIX_FILE="/home/ga/Documents/samd_regulatory_matrix.txt"
MATRIX_MTIME=0
if [ -f "$MATRIX_FILE" ]; then
    MATRIX_EXISTS=1
    MATRIX_SIZE=$(wc -c < "$MATRIX_FILE" 2>/dev/null || echo "0")
    MATRIX_MTIME=$(stat -c %Y "$MATRIX_FILE" 2>/dev/null || echo "0")
    if [ "$MATRIX_MTIME" -gt "$TASK_START" ] 2>/dev/null; then
        MATRIX_FRESH=1
    fi

    CONTENT_LOWER=$(cat "$MATRIX_FILE" 2>/dev/null | tr '[:upper:]' '[:lower:]')
    if echo "$CONTENT_LOWER" | grep -qi "samd"; then MATRIX_HAS_SAMD=1; fi
    if echo "$CONTENT_LOWER" | grep -qi "fda"; then MATRIX_HAS_FDA=1; fi
    if echo "$CONTENT_LOWER" | grep -qi "imdrf"; then MATRIX_HAS_IMDRF=1; fi
    if echo "$CONTENT_LOWER" | grep -qiE "requirement|guidance|premarket|clearance|approval|510.k|de novo|pma|regulation|compliance"; then
        MATRIX_HAS_REGULATORY=1
    fi
fi

python3 << PYEOF
import json

result = {
    "task_start": $TASK_START,
    "fda_visits": $FDA_VISITS,
    "fedreg_visits": $FEDREG_VISITS,
    "imdrf_visits": $IMDRF_VISITS,
    "fda_bookmark_folder_exists": bool($FDA_BOOKMARK_FOLDER_EXISTS),
    "fda_folder_bookmark_count": $FDA_FOLDER_BOOKMARK_COUNT,
    "fda_bookmarks_count": $FDA_BOOKMARKS_COUNT,
    "fedreg_bookmarks_count": $FEDREG_BOOKMARKS_COUNT,
    "imdrf_bookmarks_count": $IMDRF_BOOKMARKS_COUNT,
    "pdf_downloads": $PDF_COUNT,
    "largest_pdf_size": $LARGEST_PDF_SIZE,
    "new_large_files": $NEW_LARGE_FILES,
    "matrix_exists": bool($MATRIX_EXISTS),
    "matrix_fresh": bool($MATRIX_FRESH),
    "matrix_size": $MATRIX_SIZE,
    "matrix_has_samd": bool($MATRIX_HAS_SAMD),
    "matrix_has_fda": bool($MATRIX_HAS_FDA),
    "matrix_has_imdrf": bool($MATRIX_HAS_IMDRF),
    "matrix_has_regulatory": bool($MATRIX_HAS_REGULATORY)
}

with open("/tmp/fda_samd_regulatory_research_result.json", "w") as f:
    json.dump(result, f, indent=2)
print("Result written")
PYEOF

echo "=== Export complete ==="
cat /tmp/fda_samd_regulatory_research_result.json
