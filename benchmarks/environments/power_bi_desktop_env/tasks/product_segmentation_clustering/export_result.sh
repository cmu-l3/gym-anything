#!/bin/bash
echo "=== Exporting product_segmentation_clustering results ==="

# Paths
TARGET_FILE="C:/Users/Docker/Desktop/Product_Segmentation.pbix"
TEMP_DIR="/tmp/pbi_analysis"
RESULT_JSON="/tmp/task_result.json"

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check File Existence & Timestamp
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"

if [ -f "$TARGET_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$TARGET_FILE" 2>/dev/null || echo "0")
    
    # Check modification time
    FILE_MTIME=$(stat -c %Y "$TARGET_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 2. Analyze PBIX Structure (it's a ZIP file)
VISUALS_FOUND="[]"
HAS_CLUSTERS="false"
HAS_SCATTER="false"
HAS_TABLE="false"
CLUSTER_FIELD_FOUND="false"

if [ "$FILE_EXISTS" = "true" ]; then
    echo "Analyzing PBIX structure..."
    rm -rf "$TEMP_DIR"
    mkdir -p "$TEMP_DIR"
    
    # Unzip PBIX (quietly)
    unzip -q "$TARGET_FILE" -d "$TEMP_DIR" || echo "Unzip failed or not a zip"
    
    # Parse Layout for visuals
    LAYOUT_FILE="$TEMP_DIR/Report/Layout"
    if [ -f "$LAYOUT_FILE" ]; then
        # Check for visual types. Note: Layout is JSON but complex. 
        # We grep for visual types.
        if grep -q "scatterChart" "$LAYOUT_FILE"; then HAS_SCATTER="true"; fi
        if grep -qE "pivotTable|tableEx" "$LAYOUT_FILE"; then HAS_TABLE="true"; fi
        
        # Extract all visual types for reporting
        VISUALS_FOUND=$(grep -oE '"visualType":"[^"]+"' "$LAYOUT_FILE" | cut -d'"' -f4 | sort | uniq | tr '\n' ',' | sed 's/,$//')
        VISUALS_FOUND="[\"$(echo $VISUALS_FOUND | sed 's/,/","/g')\"]"
    fi
    
    # Check DataModel for Cluster field
    # The DataModel is binary, but field names appear as strings.
    # We look for "Product_Segment" (user renamed) or internal "Cluster" references
    MODEL_FILE="$TEMP_DIR/DataModel"
    if [ -f "$MODEL_FILE" ]; then
        if strings "$MODEL_FILE" | grep -qi "Product_Segment"; then
            CLUSTER_FIELD_FOUND="true"
        fi
        
        # "Method": "Clustering" often appears in the linguistic schema or metadata within the model
        if strings "$MODEL_FILE" | grep -qi "Clustering"; then
            HAS_CLUSTERS="true"
        fi
    fi
    
    # Clean up
    rm -rf "$TEMP_DIR"
fi

# 3. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 4. Generate Result JSON
cat > "$RESULT_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size_bytes": $FILE_SIZE,
    "has_scatter": $HAS_SCATTER,
    "has_table": $HAS_TABLE,
    "cluster_field_found": $CLUSTER_FIELD_FOUND,
    "visuals_found": $VISUALS_FOUND,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Set permissions
chmod 666 "$RESULT_JSON"

echo "Result generated at $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export complete ==="