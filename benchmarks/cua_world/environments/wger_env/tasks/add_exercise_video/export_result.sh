#!/bin/bash
echo "=== Exporting add_exercise_video result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
echo "Capturing final state..."
take_screenshot /tmp/task_end.png

# -----------------------------------------------------------------------
# Query Django ORM to extract the saved video and its linked exercise
# -----------------------------------------------------------------------
cat > /tmp/check_video.py << 'PYEOF'
import json
from wger.exercises.models import Video

try:
    # Find any video containing the specific YouTube video ID
    videos = Video.objects.filter(url__icontains='wYREQkVtvEc')
    results = []
    
    for v in videos:
        results.append({
            "id": v.id,
            "url": v.url,
            "exercise_name": v.exercise.name if v.exercise else "None"
        })
        
    print(json.dumps({"success": True, "videos": results}))
except Exception as e:
    import traceback
    print(json.dumps({"success": False, "error": str(e), "traceback": traceback.format_exc(), "videos": []}))
PYEOF

docker cp /tmp/check_video.py wger-web:/tmp/check_video.py
DB_RESULT=$(docker exec wger-web python3 /tmp/check_video.py 2>/dev/null || echo '{"success": false, "error": "Query execution failed", "videos": []}')

# -----------------------------------------------------------------------
# Construct the final JSON payload
# -----------------------------------------------------------------------
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "db_result": $DB_RESULT,
    "screenshot_exists": $([ -f "/tmp/task_end.png" ] && echo "true" || echo "false")
}
EOF

# Move to the final location and handle permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="