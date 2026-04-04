#!/bin/bash
# Export script for chinook_encoding_repair task
# Verifies database content and output files

echo "=== Exporting Encoding Repair Result ==="

source /workspace/scripts/task_utils.sh

# Files
CORRUPT_DB="/home/ga/Documents/databases/chinook_corrupt.db"
REPORT_CSV="/home/ga/Documents/exports/repair_summary.csv"
SCRIPT_SQL="/home/ga/Documents/scripts/fix_encoding.sql"

# Timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Verify Database Content (The most important part)
echo "Checking database content..."

DB_EXISTS="false"
ARTIFACTS_REMAINING=0
CORRECT_CHARS_FOUND=0

if [ -f "$CORRUPT_DB" ]; then
    DB_EXISTS="true"
    
    # Check for remaining artifacts (Should be 0 for full pass)
    # Using specific artifacts defined in task
    # Artifacts: Ã©, Ã¡, Ã£, Ã³, Ã¶, Ã§, Ã¼
    ARTIFACTS_REMAINING=$(sqlite3 "$CORRUPT_DB" "SELECT
        (SELECT COUNT(*) FROM artists WHERE Name LIKE '%Ã©%' OR Name LIKE '%Ã¡%' OR Name LIKE '%Ã£%' OR Name LIKE '%Ã³%' OR Name LIKE '%Ã¶%' OR Name LIKE '%Ã§%' OR Name LIKE '%Ã¼%') +
        (SELECT COUNT(*) FROM tracks WHERE (Name LIKE '%Ã©%' OR Name LIKE '%Ã¡%' OR Name LIKE '%Ã£%' OR Name LIKE '%Ã³%' OR Name LIKE '%Ã¶%' OR Name LIKE '%Ã§%' OR Name LIKE '%Ã¼%') OR (Composer LIKE '%Ã©%' OR Composer LIKE '%Ã¡%' OR Composer LIKE '%Ã£%' OR Composer LIKE '%Ã³%' OR Composer LIKE '%Ã¶%' OR Composer LIKE '%Ã§%' OR Composer LIKE '%Ã¼%')) +
        (SELECT COUNT(*) FROM customers WHERE (FirstName LIKE '%Ã©%' OR FirstName LIKE '%Ã¡%' OR FirstName LIKE '%Ã£%' OR FirstName LIKE '%Ã³%' OR FirstName LIKE '%Ã¶%' OR FirstName LIKE '%Ã§%' OR FirstName LIKE '%Ã¼%') OR (LastName LIKE '%Ã©%' OR LastName LIKE '%Ã¡%' OR LastName LIKE '%Ã£%' OR LastName LIKE '%Ã³%' OR LastName LIKE '%Ã¶%' OR LastName LIKE '%Ã§%' OR LastName LIKE '%Ã¼%')) +
        (SELECT COUNT(*) FROM employees WHERE (FirstName LIKE '%Ã©%' OR FirstName LIKE '%Ã¡%' OR FirstName LIKE '%Ã£%' OR FirstName LIKE '%Ã³%' OR FirstName LIKE '%Ã¶%' OR FirstName LIKE '%Ã§%' OR FirstName LIKE '%Ã¼%') OR (LastName LIKE '%Ã©%' OR LastName LIKE '%Ã¡%' OR LastName LIKE '%Ã£%' OR LastName LIKE '%Ã³%' OR LastName LIKE '%Ã¶%' OR LastName LIKE '%Ã§%' OR LastName LIKE '%Ã¼%'));" 2>/dev/null || echo "-1")
    
    # Check for presence of CORRECT characters (Sanity check against deletion)
    # Characters: é, á, ã, ó, ö, ç, ü
    # We expect > 0 if the agent actually fixed them instead of deleting rows or replacing with empty strings
    CORRECT_CHARS_FOUND=$(sqlite3 "$CORRUPT_DB" "SELECT
        (SELECT COUNT(*) FROM artists WHERE Name LIKE '%é%' OR Name LIKE '%á%' OR Name LIKE '%ã%' OR Name LIKE '%ó%' OR Name LIKE '%ö%' OR Name LIKE '%ç%' OR Name LIKE '%ü%') +
        (SELECT COUNT(*) FROM tracks WHERE (Name LIKE '%é%' OR Name LIKE '%á%' OR Name LIKE '%ã%' OR Name LIKE '%ó%' OR Name LIKE '%ö%' OR Name LIKE '%ç%' OR Name LIKE '%ü%') OR (Composer LIKE '%é%' OR Composer LIKE '%á%' OR Composer LIKE '%ã%' OR Composer LIKE '%ó%' OR Composer LIKE '%ö%' OR Composer LIKE '%ç%' OR Composer LIKE '%ü%'));" 2>/dev/null || echo "-1")

fi

# 2. Verify Report CSV
REPORT_EXISTS="false"
REPORT_CREATED_DURING_TASK="false"
REPORT_CONTENT=""

if [ -f "$REPORT_CSV" ]; then
    REPORT_EXISTS="true"
    if [ "$(stat -c%Y "$REPORT_CSV")" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
    # Read first few lines for feedback
    REPORT_CONTENT=$(head -n 5 "$REPORT_CSV" | tr '\n' '|')
fi

# 3. Verify SQL Script
SCRIPT_EXISTS="false"
SCRIPT_CREATED_DURING_TASK="false"
SCRIPT_CONTENT_SNIPPET=""

if [ -f "$SCRIPT_SQL" ]; then
    SCRIPT_EXISTS="true"
    if [ "$(stat -c%Y "$SCRIPT_SQL")" -gt "$TASK_START" ]; then
        SCRIPT_CREATED_DURING_TASK="true"
    fi
    SCRIPT_CONTENT_SNIPPET=$(head -n 3 "$SCRIPT_SQL" | tr '\n' '|')
fi

# 4. App state
APP_RUNNING=$(is_dbeaver_running)

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "db_exists": $DB_EXISTS,
    "artifacts_remaining": $ARTIFACTS_REMAINING,
    "correct_chars_found": $CORRECT_CHARS_FOUND,
    "initial_artifacts": $(cat /tmp/initial_artifact_count 2>/dev/null || echo "0"),
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "report_content_snippet": "$REPORT_CONTENT",
    "script_exists": $SCRIPT_EXISTS,
    "script_created_during_task": $SCRIPT_CREATED_DURING_TASK,
    "script_content_snippet": "$SCRIPT_CONTENT_SNIPPET",
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Safe move
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="