#!/bin/bash
# Export script for Document Review of Systems Task

echo "=== Exporting Review of Systems Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Target patient
PATIENT_PID=2

# Get timestamps and initial counts
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_START_DATETIME=$(cat /tmp/task_start_datetime.txt 2>/dev/null || echo "2000-01-01 00:00:00")
INITIAL_ROS_COUNT=$(cat /tmp/initial_ros_count.txt 2>/dev/null || echo "0")
INITIAL_ROS_IDS=$(cat /tmp/initial_ros_ids.txt 2>/dev/null || echo "")
ENCOUNTER_ID=$(cat /tmp/encounter_id.txt 2>/dev/null || echo "0")

# Get current ROS count
CURRENT_ROS_COUNT=$(openemr_query "SELECT COUNT(*) FROM form_ros WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")

echo "ROS count: initial=$INITIAL_ROS_COUNT, current=$CURRENT_ROS_COUNT"

# Debug: Show all ROS records for this patient
echo ""
echo "=== DEBUG: All ROS records for patient PID=$PATIENT_PID ==="
openemr_query "SELECT id, pid, date, user FROM form_ros WHERE pid=$PATIENT_PID ORDER BY id DESC LIMIT 5" 2>/dev/null
echo "=== END DEBUG ==="
echo ""

# Find new ROS records (IDs not in initial list)
if [ -n "$INITIAL_ROS_IDS" ]; then
    NEW_ROS_QUERY="SELECT id FROM form_ros WHERE pid=$PATIENT_PID AND id NOT IN ($INITIAL_ROS_IDS) ORDER BY id DESC LIMIT 1"
else
    NEW_ROS_QUERY="SELECT id FROM form_ros WHERE pid=$PATIENT_PID ORDER BY id DESC LIMIT 1"
fi
NEW_ROS_ID=$(openemr_query "$NEW_ROS_QUERY" 2>/dev/null || echo "")

echo "New ROS ID detected: $NEW_ROS_ID"

# Initialize variables
ROS_FOUND="false"
ROS_ID=""
ROS_DATE=""
ROS_CONSTITUTIONAL=""
ROS_CARDIOVASCULAR=""
ROS_RESPIRATORY=""
ROS_MUSCULOSKELETAL=""
ROS_NEUROLOGICAL=""
ROS_EYES=""
ROS_ENT=""
ROS_GI=""
ROS_GU=""
ROS_PSYCHIATRIC=""
SYSTEM_COUNT=0

# Query for the newest ROS record for this patient
if [ "$CURRENT_ROS_COUNT" -gt "$INITIAL_ROS_COUNT" ] || [ -n "$NEW_ROS_ID" ]; then
    echo "Querying ROS record details..."
    
    # Get the most recent ROS record
    ROS_DATA=$(openemr_query "SELECT id, date, constitutional, cardiovascular, respiratory, musculoskeletal, neurological, eyes, ear_nose_throat, gastrointestinal, genitourinary, psychiatric FROM form_ros WHERE pid=$PATIENT_PID ORDER BY id DESC LIMIT 1" 2>/dev/null)
    
    if [ -n "$ROS_DATA" ]; then
        ROS_FOUND="true"
        
        # Parse tab-separated values
        ROS_ID=$(echo "$ROS_DATA" | cut -f1)
        ROS_DATE=$(echo "$ROS_DATA" | cut -f2)
        ROS_CONSTITUTIONAL=$(echo "$ROS_DATA" | cut -f3)
        ROS_CARDIOVASCULAR=$(echo "$ROS_DATA" | cut -f4)
        ROS_RESPIRATORY=$(echo "$ROS_DATA" | cut -f5)
        ROS_MUSCULOSKELETAL=$(echo "$ROS_DATA" | cut -f6)
        ROS_NEUROLOGICAL=$(echo "$ROS_DATA" | cut -f7)
        ROS_EYES=$(echo "$ROS_DATA" | cut -f8)
        ROS_ENT=$(echo "$ROS_DATA" | cut -f9)
        ROS_GI=$(echo "$ROS_DATA" | cut -f10)
        ROS_GU=$(echo "$ROS_DATA" | cut -f11)
        ROS_PSYCHIATRIC=$(echo "$ROS_DATA" | cut -f12)
        
        echo "ROS record found:"
        echo "  ID: $ROS_ID"
        echo "  Date: $ROS_DATE"
        echo "  Constitutional: $ROS_CONSTITUTIONAL"
        echo "  Cardiovascular: $ROS_CARDIOVASCULAR"
        echo "  Respiratory: $ROS_RESPIRATORY"
        echo "  Musculoskeletal: $ROS_MUSCULOSKELETAL"
        
        # Count documented systems
        for field in "$ROS_CONSTITUTIONAL" "$ROS_CARDIOVASCULAR" "$ROS_RESPIRATORY" "$ROS_MUSCULOSKELETAL" "$ROS_NEUROLOGICAL" "$ROS_EYES" "$ROS_ENT" "$ROS_GI" "$ROS_GU" "$ROS_PSYCHIATRIC"; do
            if [ -n "$field" ] && [ "$field" != "NULL" ] && [ "$field" != "N" ]; then
                SYSTEM_COUNT=$((SYSTEM_COUNT + 1))
            fi
        done
        echo "  Systems documented: $SYSTEM_COUNT"
    fi
else
    echo "No new ROS records found"
fi

# Check if ROS is linked to encounter via forms table
FORM_LINKED="false"
if [ -n "$ROS_ID" ]; then
    LINK_CHECK=$(openemr_query "SELECT id, encounter FROM forms WHERE form_id=$ROS_ID AND formdir='ros' AND pid=$PATIENT_PID LIMIT 1" 2>/dev/null)
    if [ -n "$LINK_CHECK" ]; then
        FORM_LINKED="true"
        echo "ROS form is linked to encounter"
    fi
fi

# Determine if this is a new record (created after task start)
IS_NEW_RECORD="false"
if [ "$CURRENT_ROS_COUNT" -gt "$INITIAL_ROS_COUNT" ]; then
    IS_NEW_RECORD="true"
fi

# Check if ID is not in initial list
if [ -n "$ROS_ID" ] && [ -n "$INITIAL_ROS_IDS" ]; then
    if ! echo ",$INITIAL_ROS_IDS," | grep -q ",$ROS_ID,"; then
        IS_NEW_RECORD="true"
    fi
fi

# Escape special characters for JSON
escape_json() {
    echo "$1" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed 's/\t/ /g' | tr '\n' ' ' | head -c 500
}

ROS_CONSTITUTIONAL_ESC=$(escape_json "$ROS_CONSTITUTIONAL")
ROS_CARDIOVASCULAR_ESC=$(escape_json "$ROS_CARDIOVASCULAR")
ROS_RESPIRATORY_ESC=$(escape_json "$ROS_RESPIRATORY")
ROS_MUSCULOSKELETAL_ESC=$(escape_json "$ROS_MUSCULOSKELETAL")
ROS_NEUROLOGICAL_ESC=$(escape_json "$ROS_NEUROLOGICAL")
ROS_EYES_ESC=$(escape_json "$ROS_EYES")
ROS_ENT_ESC=$(escape_json "$ROS_ENT")
ROS_GI_ESC=$(escape_json "$ROS_GI")
ROS_PSYCHIATRIC_ESC=$(escape_json "$ROS_PSYCHIATRIC")

# Create result JSON
TEMP_JSON=$(mktemp /tmp/ros_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "patient_pid": $PATIENT_PID,
    "encounter_id": "$ENCOUNTER_ID",
    "task_start_timestamp": $TASK_START,
    "task_start_datetime": "$TASK_START_DATETIME",
    "initial_ros_count": ${INITIAL_ROS_COUNT:-0},
    "current_ros_count": ${CURRENT_ROS_COUNT:-0},
    "initial_ros_ids": "$INITIAL_ROS_IDS",
    "ros_record_found": $ROS_FOUND,
    "is_new_record": $IS_NEW_RECORD,
    "form_linked_to_encounter": $FORM_LINKED,
    "ros_record": {
        "id": "$ROS_ID",
        "date": "$ROS_DATE",
        "constitutional": "$ROS_CONSTITUTIONAL_ESC",
        "cardiovascular": "$ROS_CARDIOVASCULAR_ESC",
        "respiratory": "$ROS_RESPIRATORY_ESC",
        "musculoskeletal": "$ROS_MUSCULOSKELETAL_ESC",
        "neurological": "$ROS_NEUROLOGICAL_ESC",
        "eyes": "$ROS_EYES_ESC",
        "ear_nose_throat": "$ROS_ENT_ESC",
        "gastrointestinal": "$ROS_GI_ESC",
        "psychiatric": "$ROS_PSYCHIATRIC_ESC"
    },
    "systems_documented_count": $SYSTEM_COUNT,
    "screenshot_final_exists": $([ -f "/tmp/task_final_state.png" ] && echo "true" || echo "false"),
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/ros_task_result.json 2>/dev/null || sudo rm -f /tmp/ros_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/ros_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/ros_task_result.json
chmod 666 /tmp/ros_task_result.json 2>/dev/null || sudo chmod 666 /tmp/ros_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/ros_task_result.json"
cat /tmp/ros_task_result.json
echo ""
echo "=== Export Complete ==="