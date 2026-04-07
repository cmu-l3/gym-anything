#!/bin/bash
# Export script for Create Resource Folder task

echo "=== Exporting Create Resource Folder Result ==="

# Source shared utilities
. /workspace/scripts/task_utils.sh

# Fallback definitions
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
    take_screenshot() {
        local output_file="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 import -window root "$output_file" 2>/dev/null || echo "Could not take screenshot"
    }
    safe_write_json() {
        local temp_file="$1"; local dest_path="$2"
        rm -f "$dest_path" 2>/dev/null || true
        cp "$temp_file" "$dest_path"; chmod 666 "$dest_path" 2>/dev/null || true
        rm -f "$temp_file"; echo "Result saved to $dest_path"
    }
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Load stored course ID
COURSE_ID=$(cat /tmp/target_course_id 2>/dev/null || echo "0")
INITIAL_FOLDER_COUNT=$(cat /tmp/initial_folder_count 2>/dev/null || echo "0")
TASK_START_TIME=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# 1. Check if folder exists
# Look for folder with roughly correct name
FOLDER_DATA=$(moodle_query "SELECT id, name, display, showdownloadfolder, timemodified FROM mdl_folder WHERE course=$COURSE_ID AND LOWER(name) LIKE '%week 1 documents%' ORDER BY id DESC LIMIT 1")

FOLDER_FOUND="false"
FOLDER_ID=""
FOLDER_NAME=""
DISPLAY_MODE=""
SHOW_DOWNLOAD=""
FOLDER_TIMEMODIFIED="0"

if [ -n "$FOLDER_DATA" ]; then
    FOLDER_FOUND="true"
    # Parse tab-separated output
    FOLDER_ID=$(echo "$FOLDER_DATA" | cut -f1 | tr -d '[:space:]')
    FOLDER_NAME=$(echo "$FOLDER_DATA" | cut -f2)
    DISPLAY_MODE=$(echo "$FOLDER_DATA" | cut -f3 | tr -d '[:space:]')
    SHOW_DOWNLOAD=$(echo "$FOLDER_DATA" | cut -f4 | tr -d '[:space:]')
    FOLDER_TIMEMODIFIED=$(echo "$FOLDER_DATA" | cut -f5 | tr -d '[:space:]')
    
    echo "Folder found: ID=$FOLDER_ID, Name='$FOLDER_NAME', Display=$DISPLAY_MODE, Download=$SHOW_DOWNLOAD"
else
    echo "Folder 'Week 1 Documents' NOT found in BIO101"
fi

# 2. Check files inside the folder
# Chain: mdl_folder.id -> mdl_course_modules.instance (module=folder) -> mdl_context.instanceid (contextlevel=70) -> mdl_files.contextid
FILE_SYLLABUS_EXISTS="false"
FILE_LAB_EXISTS="false"
FILE_COUNT="0"

if [ "$FOLDER_FOUND" = "true" ]; then
    # Get Module ID for 'folder' type
    MODULE_ID=$(moodle_query "SELECT id FROM mdl_modules WHERE name='folder'" | tr -d '[:space:]')
    
    # Get Course Module ID
    CM_ID=$(moodle_query "SELECT id FROM mdl_course_modules WHERE instance=$FOLDER_ID AND module=$MODULE_ID" | tr -d '[:space:]')
    
    if [ -n "$CM_ID" ]; then
        # Get Context ID (contextlevel 70 = MODULE)
        CONTEXT_ID=$(moodle_query "SELECT id FROM mdl_context WHERE instanceid=$CM_ID AND contextlevel=70" | tr -d '[:space:]')
        
        if [ -n "$CONTEXT_ID" ]; then
            # Get Files
            FILES_LIST=$(moodle_query "SELECT filename FROM mdl_files WHERE contextid=$CONTEXT_ID AND component='mod_folder' AND filearea='content' AND filename != '.'")
            
            echo "Files found in folder:"
            echo "$FILES_LIST"
            
            # Check for specific files (case insensitive partial match)
            if echo "$FILES_LIST" | grep -qi "syllabus_supplement"; then
                FILE_SYLLABUS_EXISTS="true"
            fi
            if echo "$FILES_LIST" | grep -qi "lab_safety_checklist"; then
                FILE_LAB_EXISTS="true"
            fi
            
            # Count non-directory files
            FILE_COUNT=$(echo "$FILES_LIST" | wc -l)
        fi
    fi
fi

# 3. Check local file creation (Anti-gaming: did agent create them locally first?)
LOCAL_SYLLABUS_CREATED="false"
if [ -f "/home/ga/Documents/Syllabus_Supplement.txt" ]; then
    MTIME=$(stat -c %Y "/home/ga/Documents/Syllabus_Supplement.txt")
    if [ "$MTIME" -ge "$TASK_START_TIME" ]; then
        LOCAL_SYLLABUS_CREATED="true"
    fi
fi

LOCAL_LAB_CREATED="false"
if [ -f "/home/ga/Documents/Lab_Safety_Checklist.txt" ]; then
    MTIME=$(stat -c %Y "/home/ga/Documents/Lab_Safety_Checklist.txt")
    if [ "$MTIME" -ge "$TASK_START_TIME" ]; then
        LOCAL_LAB_CREATED="true"
    fi
fi

# Escape JSON strings
FOLDER_NAME_ESC=$(echo "$FOLDER_NAME" | sed 's/"/\\"/g')

# Create JSON result
TEMP_JSON=$(mktemp /tmp/folder_task_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "course_id": ${COURSE_ID:-0},
    "initial_folder_count": ${INITIAL_FOLDER_COUNT:-0},
    "folder_found": $FOLDER_FOUND,
    "folder_id": "$FOLDER_ID",
    "folder_name": "$FOLDER_NAME_ESC",
    "display_mode": ${DISPLAY_MODE:-0},
    "show_download": ${SHOW_DOWNLOAD:-0},
    "timemodified": ${FOLDER_TIMEMODIFIED:-0},
    "task_start_time": ${TASK_START_TIME:-0},
    "file_syllabus_exists": $FILE_SYLLABUS_EXISTS,
    "file_lab_exists": $FILE_LAB_EXISTS,
    "local_syllabus_created": $LOCAL_SYLLABUS_CREATED,
    "local_lab_created": $LOCAL_LAB_CREATED,
    "total_files_uploaded": ${FILE_COUNT:-0},
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/create_resource_folder_result.json

echo ""
cat /tmp/create_resource_folder_result.json
echo ""
echo "=== Export Complete ==="