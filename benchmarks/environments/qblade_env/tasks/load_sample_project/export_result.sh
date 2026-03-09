#!/bin/bash
echo "=== Exporting load_sample_project result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Check for the specific expected output file
PROJECT_FILE="/home/ga/Documents/projects/my_turbine.wpa"
PROJECT_EXISTS="false"
PROJECT_SIZE=0
FILE_IS_UNIQUE="false"

if [ -f "$PROJECT_FILE" ]; then
    PROJECT_EXISTS="true"
    PROJECT_SIZE=$(stat -c%s "$PROJECT_FILE" 2>/dev/null || echo "0")

    # Anti-copy check: compare hash against pre-existing sample project hashes
    FILE_HASH=$(md5sum "$PROJECT_FILE" 2>/dev/null | awk '{print $1}')
    IS_COPY="false"
    for sample in /home/ga/Documents/sample_projects/*.wpa; do
        if [ -f "$sample" ]; then
            SAMPLE_HASH=$(md5sum "$sample" 2>/dev/null | awk '{print $1}')
            if [ "$FILE_HASH" = "$SAMPLE_HASH" ]; then
                IS_COPY="true"
                break
            fi
        fi
    done
    # Also check the original install location
    SAMPLE_DIR=$(find /opt/qblade -name "sample projects" -type d 2>/dev/null | head -1)
    if [ -n "$SAMPLE_DIR" ] && [ "$IS_COPY" = "false" ]; then
        for sample in "$SAMPLE_DIR"/*.wpa; do
            if [ -f "$sample" ]; then
                SAMPLE_HASH=$(md5sum "$sample" 2>/dev/null | awk '{print $1}')
                if [ "$FILE_HASH" = "$SAMPLE_HASH" ]; then
                    IS_COPY="true"
                    break
                fi
            fi
        done
    fi
    if [ "$IS_COPY" = "false" ]; then
        FILE_IS_UNIQUE="true"
    fi
fi

# Check alternate locations for my_turbine.wpa only
ALT_FILES=""
for alt in /home/ga/Desktop/my_turbine.wpa /home/ga/my_turbine.wpa /tmp/my_turbine.wpa /home/ga/Documents/my_turbine.wpa; do
    if [ -f "$alt" ]; then
        ALT_FILES="$ALT_FILES $alt"
        if [ "$PROJECT_EXISTS" = "false" ]; then
            PROJECT_EXISTS="true"
            PROJECT_FILE="$alt"
            PROJECT_SIZE=$(stat -c%s "$alt" 2>/dev/null || echo "0")
        fi
    fi
done

QBLADE_RUNNING=$(is_qblade_running)

RESULT_JSON=$(cat << EOF
{
    "project_file_exists": $PROJECT_EXISTS,
    "project_file_path": "$PROJECT_FILE",
    "project_file_size": $PROJECT_SIZE,
    "file_is_unique": $FILE_IS_UNIQUE,
    "qblade_running": $([ "$QBLADE_RUNNING" -gt 0 ] && echo "true" || echo "false"),
    "alternative_files": "$(echo $ALT_FILES | xargs)",
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "$RESULT_JSON"

echo "=== Export complete ==="
