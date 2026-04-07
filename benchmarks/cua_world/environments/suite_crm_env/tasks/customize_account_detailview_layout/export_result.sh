#!/bin/bash
echo "=== Exporting customize_account_detailview_layout results ==="

source /workspace/scripts/task_utils.sh

# Take final trajectory screenshot
take_screenshot /tmp/customize_layout_final.png

# Check file existence and timestamp for anti-gaming inside the container
FILE_EXISTS=$(docker exec suitecrm-app test -f /var/www/html/custom/modules/Accounts/metadata/detailviewdefs.php && echo "true" || echo "false")
FILE_MTIME=$(docker exec suitecrm-app stat -c %Y /var/www/html/custom/modules/Accounts/metadata/detailviewdefs.php 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# PHP script to parse the exact layout multi-dimensional array from SuiteCRM metadata
cat > /tmp/extract_panels.php << 'EOF'
<?php
$file = '/var/www/html/custom/modules/Accounts/metadata/detailviewdefs.php';
if (file_exists($file)) {
    require $file;
    if (isset($viewdefs['Accounts']['DetailView']['panels'])) {
        echo json_encode($viewdefs['Accounts']['DetailView']['panels']);
    } else {
        echo json_encode(["error" => "No panels found"]);
    }
} else {
    echo json_encode(["error" => "File not found"]);
}
EOF

# Execute PHP structure extraction
docker cp /tmp/extract_panels.php suitecrm-app:/tmp/extract_panels.php
docker exec suitecrm-app php /tmp/extract_panels.php > /tmp/panels_output.json 2>/dev/null

# Check if the "Financial Details" label was created within the custom module's language files
LABEL_FOUND=$(docker exec suitecrm-app grep -ri "Financial Details" /var/www/html/custom/modules/Accounts/ 2>/dev/null | wc -l)
HAS_LABEL="false"
if [ "$LABEL_FOUND" -gt 0 ]; then
    HAS_LABEL="true"
fi

# Build standard JSON envelope using Python
RESULT_JSON=$(python3 - <<EOF
import json

try:
    with open('/tmp/panels_output.json', 'r') as f:
        panels = json.load(f)
except Exception as e:
    panels = {"error": str(e)}

result = {
    "file_exists": True if "$FILE_EXISTS" == "true" else False,
    "file_mtime": int("$FILE_MTIME") if "$FILE_MTIME".isdigit() else 0,
    "task_start_time": int("$TASK_START") if "$TASK_START".isdigit() else 0,
    "has_label": True if "$HAS_LABEL" == "true" else False,
    "panels": panels
}

print(json.dumps(result, indent=2))
EOF
)

# Export utilizing framework util to ensure correct read privileges
safe_write_result "/tmp/customize_layout_result.json" "$RESULT_JSON"

echo "Result JSON structure successfully exported."
echo "=== Export complete ==="