#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Import USLCI Database Result ==="

# Take final screenshot BEFORE closing (for VLM verification)
FINAL_SCREENSHOT="/tmp/openlca_final_screenshot.png"
take_screenshot "$FINAL_SCREENSHOT"
echo "Final screenshot saved to $FINAL_SCREENSHOT"

# ============================================================
# METHOD 1: Check OpenLCA workspace for new databases
# ============================================================

DB_DIR="/home/ga/openLCA-data-1.4/databases"
INITIAL_DB_COUNT=$(cat /tmp/initial_db_count 2>/dev/null || echo "0")
CURRENT_DB_COUNT=$(ls -1d "$DB_DIR"/*/ 2>/dev/null | wc -l || echo "0")

EXPECTED_DB="USLCI_Analysis"
DB_FOUND="false"
DB_PATH=""
ACTUAL_DB_NAME=""

# Search case-insensitively for USLCI-related database
for db_path in "$DB_DIR"/*/; do
    db_name=$(basename "$db_path")
    if echo "$db_name" | grep -qi "uslci\|lci\|analysis"; then
        DB_FOUND="true"
        DB_PATH="$db_path"
        ACTUAL_DB_NAME="$db_name"
        break
    fi
done

# If not found by name, check if any new database was created
if [ "$DB_FOUND" = "false" ] && [ "$CURRENT_DB_COUNT" -gt "$INITIAL_DB_COUNT" ]; then
    NEWEST_DB=$(ls -td "$DB_DIR"/*/ 2>/dev/null | head -1)
    if [ -n "$NEWEST_DB" ]; then
        DB_FOUND="true"
        DB_PATH="$NEWEST_DB"
        ACTUAL_DB_NAME=$(basename "$NEWEST_DB")
    fi
fi

# ============================================================
# METHOD 2: Query Derby database directly for content counts
# This is much stronger than size heuristics
# ============================================================

DB_HAS_PROCESSES="false"
DB_HAS_FLOWS="false"
DB_HAS_CATEGORIES="false"
PROCESS_COUNT=0
FLOW_COUNT=0
DB_SIZE=0

if [ "$DB_FOUND" = "true" ] && [ -d "$DB_PATH" ]; then
    echo "Examining database at: $DB_PATH"
    DB_SIZE=$(du -sm "$DB_PATH" 2>/dev/null | cut -f1 || echo "0")
    echo "  Database size: ${DB_SIZE}MB"

    # Try Derby ij query for exact counts
    echo "  Querying Derby database for content..."

    # Close OpenLCA first so Derby isn't locked
    close_openlca
    sleep 3

    PROCESS_COUNT=$(derby_count "$DB_PATH" "PROCESSES")
    echo "  Process count: $PROCESS_COUNT"
    if [ "$PROCESS_COUNT" -gt 0 ] 2>/dev/null; then
        DB_HAS_PROCESSES="true"
    fi

    FLOW_COUNT=$(derby_count "$DB_PATH" "FLOWS")
    echo "  Flow count: $FLOW_COUNT"
    if [ "$FLOW_COUNT" -gt 0 ] 2>/dev/null; then
        DB_HAS_FLOWS="true"
    fi

    CATEGORY_COUNT=$(derby_count "$DB_PATH" "CATEGORIES")
    echo "  Category count: $CATEGORY_COUNT"
    if [ "$CATEGORY_COUNT" -gt 0 ] 2>/dev/null; then
        DB_HAS_CATEGORIES="true"
    fi

    # Fallback: if Derby query failed, use size heuristics
    if [ "$PROCESS_COUNT" = "0" ] && [ "$FLOW_COUNT" = "0" ]; then
        echo "  Derby query may have failed, using size heuristic..."
        if [ "$DB_SIZE" -gt 20 ]; then
            DB_HAS_PROCESSES="true"
            DB_HAS_FLOWS="true"
        elif [ "$DB_SIZE" -gt 5 ]; then
            DB_HAS_CATEGORIES="true"
        fi
    fi
else
    # Close OpenLCA anyway
    close_openlca
fi

# ============================================================
# METHOD 3: Check window titles and import evidence
# ============================================================

WINDOWS_LIST=$(DISPLAY=:1 wmctrl -l 2>/dev/null || echo "")
OPENLCA_WINDOW_FOUND="false"
DB_WINDOW_TITLE=""

if echo "$WINDOWS_LIST" | grep -qi "openLCA\|openlca"; then
    OPENLCA_WINDOW_FOUND="true"
    DB_WINDOW_TITLE=$(echo "$WINDOWS_LIST" | grep -i "openLCA\|openlca" | head -1 | sed 's/^[^ ]* *[^ ]* *[^ ]* *//')
fi

IMPORT_EVIDENCE="false"
if echo "$WINDOWS_LIST" | grep -qi "import\|progress\|uslci"; then
    IMPORT_EVIDENCE="true"
fi

# ============================================================
# METHOD 4: Check for USLCI-specific markers
# Use process counts from Derby as primary evidence (not file access time
# which gives false positives from setup script's cp)
# ============================================================

USLCI_MARKERS_FOUND="false"

# Strong evidence: real process counts from Derby
if [ "$PROCESS_COUNT" -gt 5 ] 2>/dev/null; then
    USLCI_MARKERS_FOUND="true"
fi

# Fallback: check if import file was accessed AFTER task setup
# (compare against task_start_screenshot timestamp, not absolute time)
if [ "$USLCI_MARKERS_FOUND" = "false" ]; then
    IMPORT_FILE="/home/ga/LCA_Imports/uslci_database.zip"
    if [ -f "$IMPORT_FILE" ] && [ -f "/tmp/task_start_screenshot.png" ]; then
        if [ "$IMPORT_FILE" -nt "/tmp/task_start_screenshot.png" ]; then
            USLCI_MARKERS_FOUND="true"
        fi
    fi
fi

# ============================================================
# Create result JSON
# ============================================================

DB_SIZE=$(du -sm "$DB_PATH" 2>/dev/null | cut -f1)
DB_SIZE=${DB_SIZE:-0}
ALL_DBS=$(ls -1d "$DB_DIR"/*/ 2>/dev/null | while read d; do basename "$d"; done | tr '\n' ',' | sed 's/,$//')

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "database_found": $DB_FOUND,
    "database_name": "$ACTUAL_DB_NAME",
    "database_path": "$DB_PATH",
    "database_size_mb": $DB_SIZE,
    "has_processes": $DB_HAS_PROCESSES,
    "has_flows": $DB_HAS_FLOWS,
    "has_categories": $DB_HAS_CATEGORIES,
    "process_count": $PROCESS_COUNT,
    "flow_count": $FLOW_COUNT,
    "initial_db_count": $INITIAL_DB_COUNT,
    "current_db_count": $CURRENT_DB_COUNT,
    "all_databases": "$ALL_DBS",
    "openlca_window_found": $OPENLCA_WINDOW_FOUND,
    "window_title": "$DB_WINDOW_TITLE",
    "import_evidence": $IMPORT_EVIDENCE,
    "uslci_markers_found": $USLCI_MARKERS_FOUND,
    "screenshot_path": "$FINAL_SCREENSHOT",
    "windows_list": "$(echo "$WINDOWS_LIST" | tr '\n' '|')",
    "timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Result ==="
cat /tmp/task_result.json
echo ""
echo "=== Export Complete ==="
