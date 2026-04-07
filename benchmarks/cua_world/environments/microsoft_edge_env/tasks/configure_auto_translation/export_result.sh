#!/bin/bash
# export_result.sh - Post-task hook for configure_auto_translation
# Checks if PDF exists and if Preferences reflect the auto-translation setting

echo "=== Exporting Task Results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/Desktop/spain_transport_report.pdf"
PREFS_FILE="/home/ga/.config/microsoft-edge/Default/Preferences"
HISTORY_DB="/home/ga/.config/microsoft-edge/Default/History"

# 1. Take final screenshot (before killing app)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Kill Edge to flush preferences to disk
# CRITICAL: Edge writes preferences on exit. If we read while running, we might get stale data.
echo "Stopping Edge to flush preferences..."
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 3

# 3. Check PDF Output
PDF_EXISTS="false"
PDF_SIZE=0
PDF_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_PATH" ]; then
    PDF_EXISTS="true"
    PDF_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    PDF_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    if [ "$PDF_MTIME" -gt "$TASK_START" ]; then
        PDF_CREATED_DURING_TASK="true"
    fi
fi

# 4. Check Preferences for Auto-Translation
# We look for "es" in "translate_whitelists" (maps 'es' -> 'en') or "always_translate_languages"
AUTO_TRANSLATE_CONFIGURED="false"

if [ -f "$PREFS_FILE" ]; then
    AUTO_TRANSLATE_CONFIGURED=$(python3 -c "
import json, sys
try:
    with open('$PREFS_FILE', 'r') as f:
        data = json.load(f)
    
    translate = data.get('translate', {})
    whitelists = translate.get('translate_whitelists', {})
    always_list = translate.get('always_translate_languages', [])
    
    # Check if 'es' is whitelisted for translation to 'en'
    es_whitelisted = 'es' in whitelists and whitelists['es'] == 'en'
    
    # Check legacy list
    es_always = 'es' in always_list
    
    if es_whitelisted or es_always:
        print('true')
    else:
        print('false')
except Exception:
    print('false')
")
fi

# 5. Check History for Visit
HISTORY_VISITED="false"
if [ -f "$HISTORY_DB" ]; then
    # Copy DB to avoid locks
    cp "$HISTORY_DB" /tmp/history_check.db
    VISIT_COUNT=$(sqlite3 /tmp/history_check.db "SELECT COUNT(*) FROM urls WHERE url LIKE '%es.wikipedia.org/wiki/Transporte_en_Espa%';" 2>/dev/null || echo "0")
    if [ "$VISIT_COUNT" -gt "0" ]; then
        HISTORY_VISITED="true"
    fi
    rm -f /tmp/history_check.db
fi

# 6. Generate Result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "pdf_exists": $PDF_EXISTS,
    "pdf_size_bytes": $PDF_SIZE,
    "pdf_created_during_task": $PDF_CREATED_DURING_TASK,
    "auto_translate_configured": $AUTO_TRANSLATE_CONFIGURED,
    "source_visited": $HISTORY_VISITED,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="