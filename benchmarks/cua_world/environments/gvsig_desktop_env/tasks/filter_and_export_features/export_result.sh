#!/bin/bash
echo "=== Exporting filter_and_export_features result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
EXPORTS_DIR="/home/ga/gvsig_data/exports"
OUTPUT_BASE="$EXPORTS_DIR/populous_countries"

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check file existence
SHP_EXISTS="false"
SHX_EXISTS="false"
DBF_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE_BYTES=0

if [ -f "${OUTPUT_BASE}.shp" ]; then
    SHP_EXISTS="true"
    FILE_SIZE_BYTES=$(stat -c%s "${OUTPUT_BASE}.shp" 2>/dev/null || echo 0)
    
    # Check creation time
    FILE_TIME=$(stat -c%Y "${OUTPUT_BASE}.shp" 2>/dev/null || echo 0)
    if [ "$FILE_TIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

[ -f "${OUTPUT_BASE}.shx" ] && SHX_EXISTS="true"
[ -f "${OUTPUT_BASE}.dbf" ] && DBF_EXISTS="true"

# 3. Analyze DBF content (Feature count & Attribute validation)
# We run this inside the container to avoid dependency issues on host
# Output format: JSON-like dict printed to stdout
ANALYSIS_JSON="{}"

if [ "$DBF_EXISTS" = "true" ]; then
    echo "Analyzing DBF file..."
    ANALYSIS_JSON=$(python3 - "${OUTPUT_BASE}.dbf" << 'PYEOF'
import sys
import json
import struct

dbf_path = sys.argv[1]
result = {
    "feature_count": 0,
    "valid_pop_count": 0,
    "max_pop": 0,
    "min_pop": 0,
    "pop_field_found": False
}

try:
    # Try using dbfread if available
    try:
        from dbfread import DBF
        table = DBF(dbf_path, load=True)
        records = list(table)
        result["feature_count"] = len(records)
        
        pop_field = None
        if records:
            # Find field case-insensitively
            for key in records[0].keys():
                if 'POP_EST' in key.upper():
                    pop_field = key
                    break
        
        if pop_field:
            result["pop_field_found"] = True
            pops = []
            for r in records:
                try:
                    val = float(r[pop_field])
                    pops.append(val)
                except:
                    pass
            
            result["valid_pop_count"] = sum(1 for p in pops if p > 100000000)
            if pops:
                result["max_pop"] = max(pops)
                result["min_pop"] = min(pops)
    
    except ImportError:
        # Fallback to manual binary parsing if pip install failed
        with open(dbf_path, 'rb') as f:
            # Header
            f.read(4)
            num_records = struct.unpack('<I', f.read(4))[0]
            header_size = struct.unpack('<H', f.read(2))[0]
            record_size = struct.unpack('<H', f.read(2))[0]
            
            result["feature_count"] = num_records
            # Deep parsing is hard without library, assume partially successful if header parsed
            # We'll rely on feature count mostly in fallback mode
except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF
)
fi

# 4. Check if app is running
APP_RUNNING=$(pgrep -f "gvSIG" > /dev/null && echo "true" || echo "false")

# 5. Compile full result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "shp_exists": $SHP_EXISTS,
    "shx_exists": $SHX_EXISTS,
    "dbf_exists": $DBF_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size_bytes": $FILE_SIZE_BYTES,
    "app_was_running": $APP_RUNNING,
    "dbf_analysis": $ANALYSIS_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="