#!/bin/bash
set -e
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Define paths
PROJECT_FILE="/home/ga/Documents/projects/airfoil_comparison.wpa"
REPORT_FILE="/home/ga/Documents/projects/airfoil_selection_report.txt"
START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
take_screenshot /tmp/task_final.png

# --- Analyze Project File ---
PROJECT_EXISTS="false"
PROJECT_SIZE=0
ROTORS_FOUND=0
POLARS_FOUND=0
AIRFOILS_IMPORTED=0
PROJECT_CREATED_DURING_TASK="false"

if [ -f "$PROJECT_FILE" ]; then
    PROJECT_EXISTS="true"
    PROJECT_SIZE=$(stat -c%s "$PROJECT_FILE")
    FILE_MTIME=$(stat -c%Y "$PROJECT_FILE")
    
    if [ "$FILE_MTIME" -gt "$START_TIME" ]; then
        PROJECT_CREATED_DURING_TASK="true"
    fi

    # Grep XML content for key elements (QBlade .wpa is XML)
    # Check for Airfoils
    if grep -q "Clark Y" "$PROJECT_FILE" && grep -q "NACA 4412" "$PROJECT_FILE"; then
        AIRFOILS_IMPORTED=2
    elif grep -q "Clark Y" "$PROJECT_FILE" || grep -q "NACA 4412" "$PROJECT_FILE"; then
        AIRFOILS_IMPORTED=1
    fi
    
    # Check for Rotors/Blades (look for <Blade> or specific QBlade XML tags)
    # Counting occurrences of "Blade" definition blocks roughly
    ROTORS_FOUND=$(grep -c "<Blade>" "$PROJECT_FILE" || echo "0")
    
    # Check for Polars (look for Re=300000)
    POLARS_FOUND=$(grep -c "Re=300000" "$PROJECT_FILE" || echo "0")
fi

# --- Analyze Report File ---
REPORT_EXISTS="false"
CLARKY_CP="0"
NACA_CP="0"
WINNER=""
REPORT_CREATED_DURING_TASK="false"

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    FILE_MTIME=$(stat -c%Y "$REPORT_FILE")
    if [ "$FILE_MTIME" -gt "$START_TIME" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
    
    # Read file content safely
    REPORT_CONTENT=$(cat "$REPORT_FILE" | tr '[:upper:]' '[:lower:]')
    
    # Extract values using basic regex
    # Looking for pattern "ClarkY...: 0.45"
    CLARKY_CP=$(grep -i "Clark" "$REPORT_FILE" | grep -oE "[0-9]+\.[0-9]+" | head -1 || echo "0")
    NACA_CP=$(grep -i "NACA" "$REPORT_FILE" | grep -oE "[0-9]+\.[0-9]+" | head -1 || echo "0")
    
    # Check winner
    if echo "$REPORT_CONTENT" | grep -q "naca"; then
        WINNER="NACA 4412"
    elif echo "$REPORT_CONTENT" | grep -q "clark"; then
        WINNER="Clark-Y"
    fi
fi

# Check if QBlade is running
APP_RUNNING=$(pgrep -f "QBlade" > /dev/null && echo "true" || echo "false")

# Create result JSON
cat > /tmp/task_result.json << EOF
{
    "project_exists": $PROJECT_EXISTS,
    "project_size": $PROJECT_SIZE,
    "project_created_during_task": $PROJECT_CREATED_DURING_TASK,
    "rotors_found_count": $ROTORS_FOUND,
    "polars_found_count": $POLARS_FOUND,
    "airfoils_imported_status": $AIRFOILS_IMPORTED,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "reported_clarky_cp": "$CLARKY_CP",
    "reported_naca_cp": "$NACA_CP",
    "reported_winner": "$WINNER",
    "app_running": $APP_RUNNING
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json