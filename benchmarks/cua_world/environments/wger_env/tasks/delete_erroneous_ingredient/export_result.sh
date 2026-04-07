#!/bin/bash
echo "=== Exporting delete_erroneous_ingredient result ==="
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Query DB for counts
echo "Querying database for ingredient counts..."
COUNTS_JSON=$(django_shell "
import json
from wger.nutrition.models import Ingredient
try:
    items = Ingredient.objects.filter(name='Gold Standard 100% Whey')
    total = items.count()
    correct = items.filter(protein__gt=70).count()
    typo = items.filter(protein__lt=10).count()
    print('JSON_START' + json.dumps({'total': total, 'correct': correct, 'typo': typo}) + 'JSON_END')
except Exception as e:
    print('JSON_START' + json.dumps({'error': str(e)}) + 'JSON_END')
" | grep -o 'JSON_START.*JSON_END' | sed 's/JSON_START//;s/JSON_END//')

if [ -z "$COUNTS_JSON" ]; then
    COUNTS_JSON='{"total": 0, "correct": 0, "typo": 0}'
fi

# Write results to temporary JSON securely
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "db_counts": $COUNTS_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move JSON out with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="