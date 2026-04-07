#!/bin/bash
# Post-task export for reassign_workflow_task
# Queries the final state of the task to see if jdoe was added.

echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Load initial state
DOC_ID=$(python3 -c "import json; print(json.load(open('/tmp/initial_state.json')).get('doc_id',''))" 2>/dev/null)
INITIAL_TASK_ID=$(python3 -c "import json; print(json.load(open('/tmp/initial_state.json')).get('task_id',''))" 2>/dev/null)

echo "Checking task state for Document: $DOC_ID"

# Query current tasks on the document
# We check ALL tasks on the document because the ID might change if the workflow advances (though reassignment usually keeps ID or creates sibling)
# However, we expect the workflow to still be active.

TASKS_JSON=$(nuxeo_api GET "/id/$DOC_ID/@task")

# Parse the JSON to find relevant info
# We are looking for ANY open task on this doc where jdoe is an actor
RESULT_JSON=$(echo "$TASKS_JSON" | python3 -c "
import sys, json

try:
    data = json.load(sys.stdin)
    entries = data.get('entries', [])
    
    found_jdoe = False
    workflow_active = False
    task_actors = []
    task_state = 'unknown'
    task_id = ''
    
    if len(entries) > 0:
        workflow_active = True
        # Check all active tasks
        for task in entries:
            task_id = task.get('id')
            state = task.get('state')
            actors = task.get('actors', [])
            delegated = task.get('delegatedActors', [])
            
            # Combine actors and delegated actors
            all_actors = set(actors + delegated)
            
            # Extract usernames (sometimes they are prefixed with 'user:')
            clean_actors = [a.replace('user:', '') for a in all_actors]
            
            task_actors.append(clean_actors)
            task_state = state
            
            if 'jdoe' in clean_actors:
                found_jdoe = True

    result = {
        'workflow_active': workflow_active,
        'jdoe_found': found_jdoe,
        'final_actors': task_actors,
        'task_state': task_state,
        'doc_id': '$DOC_ID'
    }
    print(json.dumps(result))

except Exception as e:
    print(json.dumps({'error': str(e), 'workflow_active': False}))
")

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Final JSON Construction
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "api_result": $RESULT_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported:"
cat /tmp/task_result.json
echo "=== Export complete ==="