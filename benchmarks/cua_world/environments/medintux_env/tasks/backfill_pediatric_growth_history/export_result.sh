#!/bin/bash
echo "=== Exporting Backfill Task Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if application is running
APP_RUNNING="false"
if pgrep -f "Manager.exe" > /dev/null; then
    APP_RUNNING="true"
fi

# Extract data from MySQL using Python for robust JSON formatting
# We extract all notes for Lucas GRANDJEAN created/modified
# Note: DrTuxTest.Rubriques contains the notes.
# Rub_Date is the clinical date (YYYY-MM-DD).
# Rub_Texte is the content (blob).

echo "Querying database for patient notes..."

python3 -c "
import pymysql
import json
import sys

try:
    conn = pymysql.connect(host='localhost', user='root', password='', db='DrTuxTest', charset='utf8mb4')
    cursor = conn.cursor(pymysql.cursors.DictCursor)
    
    # Query for notes linked to GRANDJEAN Lucas
    # We look for records in Rubriques
    query = \"\"\"
        SELECT Rub_Date, Rub_Texte, Rub_Type, Rub_NomDos, Rub_Prenom
        FROM Rubriques 
        WHERE Rub_NomDos = 'GRANDJEAN' AND Rub_Prenom = 'Lucas'
        ORDER BY Rub_Date ASC
    \"\"\"
    
    cursor.execute(query)
    rows = cursor.fetchall()
    
    # Process rows (handle bytes/blobs)
    results = []
    for row in rows:
        # Rub_Texte is likely bytes, decode if possible
        text_content = ''
        if isinstance(row['Rub_Texte'], bytes):
            try:
                text_content = row['Rub_Texte'].decode('utf-8', errors='ignore')
            except:
                text_content = str(row['Rub_Texte'])
        else:
            text_content = str(row['Rub_Texte'])
            
        # Format date
        date_str = str(row['Rub_Date']) if row['Rub_Date'] else ''
            
        results.append({
            'date': date_str,
            'text': text_content,
            'type': row.get('Rub_Type', '')
        })
        
    output = {
        'notes': results,
        'count': len(results),
        'success': True
    }
    
    with open('/tmp/db_notes.json', 'w') as f:
        json.dump(output, f)
        
except Exception as e:
    error_out = {'success': False, 'error': str(e), 'notes': []}
    with open('/tmp/db_notes.json', 'w') as f:
        json.dump(error_out, f)
"

# Create final result JSON
# Merge the python output with shell metadata
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "db_data": $(cat /tmp/db_notes.json 2>/dev/null || echo "{\"success\": false, \"notes\": []}")
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="