#!/bin/bash
set -e

echo "=== Exporting Marking Guide Result ==="

# Source shared utilities
. /workspace/scripts/task_utils.sh

# Fallback definitions if needed
if ! type moodle_query &>/dev/null; then
    _get_mariadb_method() { cat /tmp/mariadb_method 2>/dev/null || echo "native"; }
    moodle_query() {
        local query="$1"
        local method=$(_get_mariadb_method)
        if [ "$method" = "docker" ]; then
            docker exec moodle-mariadb mysql -u moodleuser -pmoodlepass moodle -N -B -e "$query" 2>/dev/null
        else
            mysql -u moodleuser -pmoodlepass moodle -N -B -e "$query" 2>/dev/null
        fi
    }
    safe_write_json() {
        local temp_file="$1"; local dest_path="$2"
        cp "$temp_file" "$dest_path"; chmod 666 "$dest_path" 2>/dev/null || true
        rm -f "$temp_file"
    }
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 1. Get Course ID
COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='HIST201'" | tr -d '[:space:]')

# 2. Get Assignment ID and current Grading Method
ASSIGN_DATA=$(moodle_query "SELECT id, gradingmethod FROM mdl_assign WHERE course='$COURSE_ID' AND name='Industrial Revolution Research Paper'")
ASSIGN_ID=$(echo "$ASSIGN_DATA" | cut -f1 | tr -d '[:space:]')
GRADING_METHOD=$(echo "$ASSIGN_DATA" | cut -f2 | tr -d '[:space:]')

echo "Assignment ID: $ASSIGN_ID"
echo "Grading Method: $GRADING_METHOD"

# 3. Get Context ID for the Assignment Module
# We need to join mdl_course_modules to get the ID, then check mdl_context
CM_ID=$(moodle_query "SELECT id FROM mdl_course_modules WHERE course='$COURSE_ID' AND instance='$ASSIGN_ID' AND module=(SELECT id FROM mdl_modules WHERE name='assign')")
CONTEXT_ID=$(moodle_query "SELECT id FROM mdl_context WHERE instanceid='$CM_ID' AND contextlevel=70") # 70 = MODULE

echo "Context ID: $CONTEXT_ID"

# 4. Get Grading Definition (The Guide)
# Check if a definition exists for this context and area 'submission'
# Area 'submission' usually has component 'mod_assign'
DEF_DATA=$(moodle_query "SELECT d.id, d.name, d.status 
                        FROM mdl_grading_definitions d 
                        JOIN mdl_grading_areas a ON d.areaid = a.id 
                        WHERE a.contextid='$CONTEXT_ID' 
                        AND a.component='mod_assign' 
                        AND a.areaname='submissions'
                        AND d.method='guide'
                        ORDER BY d.timemodified DESC LIMIT 1")

DEF_ID=$(echo "$DEF_DATA" | cut -f1 | tr -d '[:space:]')
DEF_NAME=$(echo "$DEF_DATA" | cut -f2)
DEF_STATUS=$(echo "$DEF_DATA" | cut -f3 | tr -d '[:space:]') # 20 = Ready

echo "Definition ID: $DEF_ID"
echo "Definition Name: $DEF_NAME"
echo "Definition Status: $DEF_STATUS"

# 5. Export Criteria
CRITERIA_JSON="[]"
if [ -n "$DEF_ID" ]; then
    # Use python to construct JSON from SQL query to handle text properly
    CRITERIA_JSON=$(python3 -c "
import subprocess
import json

def get_query_output(query):
    # This assumes moodle_query function behavior is replicated or called
    # Simplified for this context: calling the bash function is hard from python
    # So we call mysql directly
    cmd = [\"mysql\", \"-u\", \"moodleuser\", \"-pmoodlepass\", \"moodle\", \"-N\", \"-B\", \"-e\", query]
    # Check if we need docker
    try:
        with open('/tmp/mariadb_method', 'r') as f:
            if f.read().strip() == 'docker':
                cmd = [\"docker\", \"exec\", \"moodle-mariadb\"] + cmd
    except:
        pass
    
    try:
        res = subprocess.check_output(cmd, stderr=subprocess.DEVNULL)
        return res.decode('utf-8', errors='ignore')
    except:
        return ''

query = \"SELECT shortname, maxscore, descriptionmarkers FROM mdl_gradingform_guide_criteria WHERE definitionid=$DEF_ID ORDER BY id ASC\"
output = get_query_output(query)

criteria = []
for line in output.strip().split('\n'):
    if not line: continue
    parts = line.split('\t')
    if len(parts) >= 3:
        criteria.append({
            'shortname': parts[0],
            'maxscore': float(parts[1]),
            'descriptionmarkers': parts[2]
        })

print(json.dumps(criteria))
")
fi

# 6. Export Comments
COMMENTS_JSON="[]"
if [ -n "$DEF_ID" ]; then
    COMMENTS_JSON=$(python3 -c "
import subprocess
import json

def get_query_output(query):
    cmd = [\"mysql\", \"-u\", \"moodleuser\", \"-pmoodlepass\", \"moodle\", \"-N\", \"-B\", \"-e\", query]
    try:
        with open('/tmp/mariadb_method', 'r') as f:
            if f.read().strip() == 'docker':
                cmd = [\"docker\", \"exec\", \"moodle-mariadb\"] + cmd
    except:
        pass
    try:
        res = subprocess.check_output(cmd, stderr=subprocess.DEVNULL)
        return res.decode('utf-8', errors='ignore')
    except:
        return ''

query = \"SELECT description FROM mdl_gradingform_guide_comments WHERE definitionid=$DEF_ID\"
output = get_query_output(query)

comments = []
for line in output.strip().split('\n'):
    if line:
        comments.append(line)

print(json.dumps(comments))
")
fi

# Construct Final JSON
TEMP_JSON=$(mktemp /tmp/marking_guide_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "assignment_id": "${ASSIGN_ID:-0}",
    "grading_method": "${GRADING_METHOD}",
    "guide_definition_id": "${DEF_ID:-0}",
    "guide_name": "$(echo $DEF_NAME | sed 's/"/\\"/g')",
    "guide_status": ${DEF_STATUS:-0},
    "criteria": ${CRITERIA_JSON:-[]},
    "comments": ${COMMENTS_JSON:-[]},
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/marking_guide_result.json

echo "Result saved to /tmp/marking_guide_result.json"
cat /tmp/marking_guide_result.json
echo ""
echo "=== Export Complete ==="