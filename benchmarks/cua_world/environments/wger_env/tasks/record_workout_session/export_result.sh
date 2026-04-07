#!/bin/bash
echo "=== Exporting record_workout_session task results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Write the Python data extraction script
cat > /tmp/extract_data.py << 'EOF'
import json
import sys
from datetime import date
from wger.manager.models import WorkoutSession, WorkoutLog, Routine

try:
    today = date.today()

    # Find the target routine
    routine = Routine.objects.filter(name__icontains='5x5 Beginner').first()
    routine_id = routine.id if routine else None

    # Fetch today's sessions
    sessions = WorkoutSession.objects.filter(date=today)
    target_session = sessions.filter(routine=routine).last() if routine else sessions.last()

    session_data = {
        'exists': bool(target_session),
        'routine_match': getattr(target_session, 'routine_id', None) == routine_id if target_session and routine_id else False,
        'notes': getattr(target_session, 'notes', ''),
        'impression': getattr(target_session, 'impression', '')
    }

    # Fetch logs for 'Squats' today
    logs_data = []
    for log in WorkoutLog.objects.filter(date=today):
        ex_name = ''
        if getattr(log, 'exercise', None):
            ex_name = getattr(log.exercise, 'name', '')
            if not ex_name and hasattr(log.exercise, 'exercisetranslation_set'):
                tr = log.exercise.exercisetranslation_set.first()
                if tr:
                    ex_name = tr.name
        
        if 'squat' in str(ex_name).lower():
            logs_data.append({
                'weight': float(getattr(log, 'weight', 0)),
                'reps': int(getattr(log, 'reps', 0))
            })

    # Get current row counts
    counts = {
        'sessions': WorkoutSession.objects.count(),
        'logs': WorkoutLog.objects.count()
    }

    # Load initial counts
    try:
        with open('/tmp/initial_counts.json', 'r') as f:
            initial_counts = json.load(f)
    except:
        initial_counts = {'sessions': 0, 'logs': 0}

    # Output JSON payload
    out = {
        'initial_counts': initial_counts,
        'current_counts': counts,
        'session': session_data,
        'squat_logs': logs_data
    }
    print(json.dumps(out))

except Exception as e:
    print(json.dumps({'error': str(e)}))
EOF

# Execute the extraction inside the docker container
docker cp /tmp/initial_counts.json wger-web:/tmp/initial_counts.json
docker cp /tmp/extract_data.py wger-web:/tmp/extract_data.py
docker exec wger-web python3 manage.py shell -c "exec(open('/tmp/extract_data.py').read())" > /tmp/task_result.json

# Adjust permissions so the verifier running on host can read it securely
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json:"
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="