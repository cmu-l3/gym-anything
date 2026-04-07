#!/bin/bash
# export_result.sh — Extract the created routine and its deep volume structures
set -e

echo "=== Exporting program_powerlifting_peaking_block task result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Extract database state directly using Django ORM
# We use dynamic hasattr checks to ensure compatibility with different wger DB relational structures
cat > /tmp/wger_export.py << 'EOF'
import json
from wger.manager.models import Routine, Day, Set

output = {
    "routine_found": False,
    "routine_name": "",
    "days_count": 0,
    "configs": []
}

# Find the specific routine created by the user
routines = Routine.objects.filter(name__icontains='Smolov')

if routines.exists():
    r = routines.last()
    output["routine_found"] = True
    output["routine_name"] = r.name
    
    # Retrieve days mapped to this routine
    days = list(Day.objects.filter(routine=r))
    output["days_count"] = len(days)
    day_ids = [d.id for d in days]
    
    # Retrieve associated sets carefully across relations
    for s in Set.objects.all():
        belongs = False
        
        # Check all possible wger ORM variations for linking sets to days
        if hasattr(s, 'exerciseday_id') and s.exerciseday_id in day_ids:
            belongs = True
        elif hasattr(s, 'day_id') and s.day_id in day_ids:
            belongs = True
        elif hasattr(s, 'exerciseday') and hasattr(s.exerciseday, 'day_id') and s.exerciseday.day_id in day_ids:
            belongs = True
            
        if belongs:
            # Extract exercise name or ID
            ex_name = "Unknown"
            if hasattr(s, 'exercise') and s.exercise:
                ex_name = s.exercise.name
                
            output["configs"].append({
                "sets": getattr(s, 'sets', 0),
                "reps": getattr(s, 'reps', ""),
                "exercise": ex_name
            })
            
with open('/tmp/wger_export_result.json', 'w') as f:
    json.dump(output, f)
EOF

echo "Executing Wger Django extraction script..."
docker cp /tmp/wger_export.py wger-web:/tmp/wger_export.py
docker exec wger-web python3 manage.py shell -c "exec(open('/tmp/wger_export.py').read())"

# 3. Pull the result out to the host
docker cp wger-web:/tmp/wger_export_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="
cat /tmp/task_result.json