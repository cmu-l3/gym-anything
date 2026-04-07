#!/bin/bash
# setup_task.sh — Set up the clean_up_empty_workout_sessions task
echo "=== Setting up clean_up_empty_workout_sessions task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for wger to be fully available
wait_for_wger_page

# 1. Clean slate: Delete all existing workout sessions to ensure a predictable environment
echo "Cleaning existing workout sessions..."
docker exec wger-db psql -U wger -d wger -c "DELETE FROM manager_workoutsession;" >/dev/null

# 2. Ensure an exercise exists to assign to valid sessions
echo "Ensuring an exercise exists in the database..."
docker exec wger-web python3 manage.py shell -c "
from wger.exercises.models import Exercise, ExerciseCategory, Language
lang, _ = Language.objects.get_or_create(short_name='en', defaults={'full_name': 'English'})
cat, _ = ExerciseCategory.objects.get_or_create(name='Custom')
ex, _ = Exercise.objects.get_or_create(name='Barbell Squat', category=cat, language=lang)
print(f'EXERCISE_ID:{ex.id}')
" > /tmp/ex_setup.log 2>/dev/null

EXERCISE_ID=$(grep "EXERCISE_ID:" /tmp/ex_setup.log | cut -d':' -f2)
if [ -z "$EXERCISE_ID" ]; then
    echo "ERROR: Failed to establish base exercise."
    # Fallback to 1 just in case
    EXERCISE_ID=1
fi

# 3. Generate 15 workout sessions (5 empty, 10 valid)
echo "Generating 15 workout sessions (5 empty, 10 valid)..."

EMPTY_IDS=""
VALID_IDS=""

for i in {1..15}; do
    # Generate dates moving backwards over the past 30 days
    DATE=$(date -d "-$((i * 2)) days" +%Y-%m-%d 2>/dev/null || date -v-$((i * 2))d +%Y-%m-%d 2>/dev/null)
    
    if [ "$i" -le 5 ]; then
        NOTES="Ghost session $i - aborted due to bad connection"
    else
        NOTES="Routine workout $i - felt good today"
    fi

    # Create session via API
    RES=$(wger_api POST /api/v2/workoutsession/ "{\"date\": \"$DATE\", \"notes\": \"$NOTES\"}")
    SID=$(echo "$RES" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('id', ''))" 2>/dev/null)

    if [ -n "$SID" ]; then
        if [ "$i" -le 5 ]; then
            EMPTY_IDS="${EMPTY_IDS}${SID},"
        else
            # For valid sessions, log an exercise to it
            wger_api POST /api/v2/workoutlog/ "{\"workout_session\": $SID, \"exercise\": $EXERCISE_ID, \"reps\": 10, \"weight\": 100}" > /dev/null
            VALID_IDS="${VALID_IDS}${SID},"
        fi
    else
        echo "Warning: failed to create session $i"
    fi
done

# Save IDs for export_result.sh to evaluate
echo "${EMPTY_IDS%,}" > /tmp/empty_session_ids.txt
echo "${VALID_IDS%,}" > /tmp/valid_session_ids.txt

echo "Setup complete. Empty Session IDs: ${EMPTY_IDS%,}"
echo "Setup complete. Valid Session IDs: ${VALID_IDS%,}"

# 4. Launch Firefox to the workout sessions overview page
launch_firefox_to "http://localhost/en/user/login" 3
navigate_to "http://localhost/en/dashboard" 5

# Take initial screenshot showing the initial logbook state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="