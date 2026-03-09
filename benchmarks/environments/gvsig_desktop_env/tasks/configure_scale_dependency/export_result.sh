#!/bin/bash
echo "=== Exporting configure_scale_dependency result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
PROJECT_PATH="/home/ga/gvsig_data/projects/scale_visibility.gvsproj"
EXTRACT_DIR="/tmp/gvsig_project_extract"

# Initialize result variables
PROJECT_EXISTS="false"
PROJECT_CREATED_DURING_TASK="false"
PROJECT_SIZE="0"
XML_CONTENT_FOUND="false"
SCALE_CONFIG_FOUND="false"
TARGET_VALUE_FOUND="false"

# Check if project file exists
if [ -f "$PROJECT_PATH" ]; then
    PROJECT_EXISTS="true"
    PROJECT_SIZE=$(stat -c %s "$PROJECT_PATH" 2>/dev/null || echo "0")
    
    # Check modification time
    PROJECT_MTIME=$(stat -c %Y "$PROJECT_PATH" 2>/dev/null || echo "0")
    if [ "$PROJECT_MTIME" -gt "$TASK_START" ]; then
        PROJECT_CREATED_DURING_TASK="true"
    fi
    
    # Analyze project content (gvSIG projects are ZIP files)
    echo "Analyzing project file content..."
    rm -rf "$EXTRACT_DIR"
    mkdir -p "$EXTRACT_DIR"
    
    # Try to unzip
    if unzip -q "$PROJECT_PATH" -d "$EXTRACT_DIR"; then
        echo "Project unzipped successfully"
        
        # Find the main XML file (usually .gvp or similar XML inside)
        # Search recursively for the layer definition and scale
        # ne_110m_populated_places
        
        # Look for the layer name in all files
        LAYER_MATCH=$(grep -r "ne_110m_populated_places" "$EXTRACT_DIR" | head -1 | cut -d: -f1)
        
        if [ -n "$LAYER_MATCH" ]; then
            echo "Found layer configuration in: $LAYER_MATCH"
            XML_CONTENT_FOUND="true"
            
            # Check for scale tags near the layer
            # We look for 20,000,000 (20000000) or scientific notation 2.0E7
            
            # Extract content around the layer match to search for scale
            # (Note: simpler grep check first)
            
            if grep -q "20000000\|2.0E7" "$LAYER_MATCH"; then
                echo "Found target scale value (20,000,000)"
                TARGET_VALUE_FOUND="true"
            fi
            
            if grep -q "minScale\|maxScale\|scale" "$LAYER_MATCH"; then
                echo "Found scale configuration tags"
                SCALE_CONFIG_FOUND="true"
            fi
        else
            echo "WARNING: Layer 'ne_110m_populated_places' not found in project XML"
        fi
    else
        echo "ERROR: Failed to unzip project file"
    fi
    
    # Cleanup extract
    rm -rf "$EXTRACT_DIR"
fi

# Check if application was running
APP_RUNNING=$(pgrep -f "gvSIG" > /dev/null && echo "true" || echo "false")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "project_exists": $PROJECT_EXISTS,
    "project_created_during_task": $PROJECT_CREATED_DURING_TASK,
    "project_size_bytes": $PROJECT_SIZE,
    "xml_content_valid": $XML_CONTENT_FOUND,
    "scale_config_found": $SCALE_CONFIG_FOUND,
    "target_value_found": $TARGET_VALUE_FOUND,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save result safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="