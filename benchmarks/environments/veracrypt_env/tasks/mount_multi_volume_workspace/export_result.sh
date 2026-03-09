#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Multi-Volume Workspace Result ==="

# 1. Capture final state screenshot
take_screenshot /tmp/task_final.png

# 2. Get Verification Data

# A. Mount State
MOUNT_LIST=$(veracrypt --text --list --non-interactive 2>&1 || echo "")
echo "Mount List:"
echo "$MOUNT_LIST"

# B. File Accessibility Check
check_file() {
    if [ -f "$1" ] && [ -r "$1" ]; then echo "true"; else echo "false"; fi
}

ALPHA_FILE=$(check_file "/home/ga/Workspace/project_alpha/incident_report_2024.txt")
GAMMA_FILE=$(check_file "/home/ga/Workspace/project_gamma/network_topology.txt")

# Beta files (check all 3)
BETA_F1=$(check_file "/home/ga/Workspace/project_beta/SF312_Nondisclosure_Agreement.txt")
BETA_F2=$(check_file "/home/ga/Workspace/project_beta/FY2024_Revenue_Budget.csv")
BETA_F3=$(check_file "/home/ga/Workspace/project_beta/backup_authorized_keys")
BETA_FILES_ACCESSIBLE="false"
if [ "$BETA_F1" = "true" ] && [ "$BETA_F2" = "true" ] && [ "$BETA_F3" = "true" ]; then
    BETA_FILES_ACCESSIBLE="true"
fi

# C. Manifest Check
MANIFEST_PATH="/home/ga/Workspace/mount_manifest.txt"
MANIFEST_EXISTS="false"
MANIFEST_CONTENT=""
MANIFEST_CREATED_DURING_TASK="false"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

if [ -f "$MANIFEST_PATH" ]; then
    MANIFEST_EXISTS="true"
    MANIFEST_CONTENT=$(cat "$MANIFEST_PATH" | base64 -w 0) # Encode to avoid JSON issues
    
    # Check timestamp
    FILE_TIME=$(stat -c %Y "$MANIFEST_PATH")
    if [ "$FILE_TIME" -ge "$TASK_START" ]; then
        MANIFEST_CREATED_DURING_TASK="true"
    fi
fi

# D. Check specific mount points
# We parse the output of 'mount' or 'veracrypt -l'
# veracrypt -l format: "1: /home/ga/Volumes/vol.hc /dev/mapper/veracrypt1 /media/veracrypt1"
# OR if mounted to custom dir: "1: ... ... /home/ga/Workspace/..."
MOUNT_ALPHA_CORRECT="false"
MOUNT_BETA_CORRECT="false"
MOUNT_GAMMA_CORRECT="false"

if echo "$MOUNT_LIST" | grep -q "/home/ga/Volumes/test_volume.hc.*project_alpha"; then MOUNT_ALPHA_CORRECT="true"; fi
if echo "$MOUNT_LIST" | grep -q "/home/ga/Volumes/data_volume.hc.*project_beta"; then MOUNT_BETA_CORRECT="true"; fi
if echo "$MOUNT_LIST" | grep -q "/home/ga/Volumes/mounted_volume.hc.*project_gamma"; then MOUNT_GAMMA_CORRECT="true"; fi

# E. Count mounted volumes
MOUNT_COUNT=$(echo "$MOUNT_LIST" | grep -c "^[0-9]" || echo "0")

# 3. Create JSON
RESULT_JSON=$(cat << EOF
{
    "mount_list_output": "$(echo "$MOUNT_LIST" | base64 -w 0)",
    "mount_count": $MOUNT_COUNT,
    "alpha_mounted_correctly": $MOUNT_ALPHA_CORRECT,
    "beta_mounted_correctly": $MOUNT_BETA_CORRECT,
    "gamma_mounted_correctly": $MOUNT_GAMMA_CORRECT,
    "alpha_file_accessible": $ALPHA_FILE,
    "beta_files_accessible": $BETA_FILES_ACCESSIBLE,
    "gamma_file_accessible": $GAMMA_FILE,
    "manifest_exists": $MANIFEST_EXISTS,
    "manifest_content_b64": "$MANIFEST_CONTENT",
    "manifest_created_during_task": $MANIFEST_CREATED_DURING_TASK,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "/tmp/task_result.json" "$RESULT_JSON"
echo "Result saved."