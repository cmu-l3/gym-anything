#!/bin/bash

echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot for visual evidence
take_screenshot /tmp/task_end.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Extract diary entries for today via Django ORM to reliably capture the logged data
django_shell "
import json
import datetime
from django.contrib.auth.models import User

try:
    from wger.nutrition.models import NutritionDiary as DiaryModel
except ImportError:
    try:
        from wger.nutrition.models import NutritionLog as DiaryModel
    except ImportError:
        DiaryModel = None

out = []
if DiaryModel:
    today = datetime.date.today()
    try:
        admin = User.objects.get(username='admin')
        entries = DiaryModel.objects.filter(user=admin, date=today)
        for e in entries:
            out.append({
                'ingredient_name': e.ingredient.name if hasattr(e, 'ingredient') and e.ingredient else '',
                'amount': float(e.amount) if hasattr(e, 'amount') else 0.0
            })
    except Exception as e:
        out.append({'error': str(e)})

with open('/tmp/diary_dump.json', 'w') as f:
    json.dump(out, f)
"

# Copy the dump from the container to the host-accessible temporary space
docker cp wger-web:/tmp/diary_dump.json /tmp/diary_dump.json 2>/dev/null || echo "[]" > /tmp/diary_dump.json

# Secondary fallback: Extract data using direct DB queries (handles ORM changes or API unavailability)
OATS_AMOUNT=$(db_query "SELECT amount FROM nutrition_nutritiondiary d JOIN nutrition_ingredient i ON d.ingredient_id = i.id WHERE i.name = 'Rolled Oats' AND d.date = CURRENT_DATE LIMIT 1;" 2>/dev/null)
MILK_AMOUNT=$(db_query "SELECT amount FROM nutrition_nutritiondiary d JOIN nutrition_ingredient i ON d.ingredient_id = i.id WHERE i.name = 'Whole Milk' AND d.date = CURRENT_DATE LIMIT 1;" 2>/dev/null)

APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# Assemble the final result payload
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "db_oats_amount": "$OATS_AMOUNT",
    "db_milk_amount": "$MILK_AMOUNT",
    "diary_dump": $(cat /tmp/diary_dump.json)
}
EOF

echo "Result JSON saved to /tmp/task_result.json"
echo "=== Export complete ==="