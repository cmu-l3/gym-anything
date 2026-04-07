#!/bin/bash
echo "=== Exporting regression_pipeline_world_happiness results ==="

# 1. Capture task timing
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 2. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 3. Check JASP project file (.jasp)
JASP_FILE="/home/ga/Documents/JASP/happiness_regression_pipeline.jasp"
JASP_EXISTS="false"
JASP_VALID_TIME="false"
JASP_SIZE="0"

if [ -f "$JASP_FILE" ]; then
    JASP_EXISTS="true"
    JASP_SIZE=$(stat -c %s "$JASP_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$JASP_FILE" 2>/dev/null || echo "0")

    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        JASP_VALID_TIME="true"
    fi
fi

# 4. Check report file (.txt)
REPORT_FILE="/home/ga/Documents/JASP/regression_report.txt"
REPORT_EXISTS="false"
REPORT_VALID_TIME="false"
REPORT_CONTENT=""

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")

    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        REPORT_VALID_TIME="true"
    fi

    # Read content safely (limit size to prevent massive JSON)
    REPORT_CONTENT=$(head -c 4000 "$REPORT_FILE" | base64 -w 0)
fi

# 5. Check if JASP is running
APP_RUNNING="false"
if pgrep -f "org.jaspstats.JASP" > /dev/null; then
    APP_RUNNING="true"
fi

# 6. Extract and parse the .jasp file (ZIP archive) for analysis metadata
ANALYSES_COUNT="0"
ANALYSES_TYPES="[]"
HAS_COMPUTED_COLUMN="false"

if [ "$JASP_EXISTS" = "true" ]; then
    EXTRACT_DIR="/tmp/jasp_extract_pipeline"
    rm -rf "$EXTRACT_DIR"
    mkdir -p "$EXTRACT_DIR"

    if unzip -q -o "$JASP_FILE" -d "$EXTRACT_DIR" 2>/dev/null; then
        # Use Python to parse analyses.json
        python3 << 'PYEOF'
import json
import os
import sys

extract_dir = "/tmp/jasp_extract_pipeline"
analyses_path = os.path.join(extract_dir, "analyses.json")

result = {"count": 0, "types": [], "has_computed": False}

if os.path.exists(analyses_path):
    try:
        with open(analyses_path, 'r') as f:
            data = json.load(f)
        analyses = data.get("analyses", []) if isinstance(data, dict) else data if isinstance(data, list) else []
        result["count"] = len(analyses)
        for a in analyses:
            atype = a.get("analysisName", a.get("name", "unknown"))
            result["types"].append(atype)
            # Check for computed column reference
            opts_str = json.dumps(a.get("options", {}))
            if "GDP_squared" in opts_str or "gdp_squared" in opts_str.lower():
                result["has_computed"] = True
    except Exception as e:
        print(f"Parse error: {e}", file=sys.stderr)

# Check for computed columns in data metadata
for fname in ["dataSet.json", "metadata.json"]:
    fpath = os.path.join(extract_dir, fname)
    if os.path.exists(fpath):
        try:
            with open(fpath, 'r') as f:
                content = f.read()
            if "GDP_squared" in content or "computed" in content.lower():
                result["has_computed"] = True
        except:
            pass

with open("/tmp/jasp_pipeline_analyses.json", "w") as f:
    json.dump(result, f)
PYEOF

        if [ -f "/tmp/jasp_pipeline_analyses.json" ]; then
            ANALYSES_COUNT=$(python3 -c "import json; d=json.load(open('/tmp/jasp_pipeline_analyses.json')); print(d['count'])" 2>/dev/null || echo "0")
            ANALYSES_TYPES=$(python3 -c "import json; d=json.load(open('/tmp/jasp_pipeline_analyses.json')); print(json.dumps(d['types']))" 2>/dev/null || echo "[]")
            HAS_COMPUTED_COLUMN=$(python3 -c "import json; d=json.load(open('/tmp/jasp_pipeline_analyses.json')); print(str(d['has_computed']).lower())" 2>/dev/null || echo "false")
        fi
    fi
fi

# 7. Generate result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "jasp_file_exists": $JASP_EXISTS,
    "jasp_file_created_during_task": $JASP_VALID_TIME,
    "jasp_file_size": $JASP_SIZE,
    "report_file_exists": $REPORT_EXISTS,
    "report_file_created_during_task": $REPORT_VALID_TIME,
    "report_content_base64": "$REPORT_CONTENT",
    "analyses_count": $ANALYSES_COUNT,
    "analysis_types": $ANALYSES_TYPES,
    "has_computed_column": $HAS_COMPUTED_COLUMN,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "jasp_file_path": "$JASP_FILE",
    "report_file_path": "$REPORT_FILE"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
