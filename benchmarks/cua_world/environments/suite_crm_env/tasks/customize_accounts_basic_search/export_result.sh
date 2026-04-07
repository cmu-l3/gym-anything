#!/bin/bash
echo "=== Exporting customize_accounts_basic_search results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

take_screenshot /tmp/task_final.png

FILE_PATH="/var/www/html/custom/modules/Accounts/metadata/searchdefs.php"
FILE_EXISTS=$(docker exec suitecrm-app test -f "$FILE_PATH" && echo "true" || echo "false")
FILE_MTIME=0

if [ "$FILE_EXISTS" = "true" ]; then
    FILE_MTIME=$(docker exec suitecrm-app stat -c %Y "$FILE_PATH" 2>/dev/null || echo "0")
fi

# Extract JSON of searchdefs directly from PHP
cat > /tmp/extract_searchdefs.php << 'EOF'
<?php
$file = '/var/www/html/custom/modules/Accounts/metadata/searchdefs.php';
if(file_exists($file)) {
    require($file);
    if(isset($searchdefs)) {
        echo json_encode($searchdefs);
    } else {
        echo json_encode(["error" => "searchdefs variable not found"]);
    }
} else {
    echo json_encode(null);
}
?>
EOF

docker cp /tmp/extract_searchdefs.php suitecrm-app:/tmp/extract_searchdefs.php
SEARCHDEFS_JSON=$(docker exec suitecrm-app php /tmp/extract_searchdefs.php 2>/dev/null)

if [ -z "$SEARCHDEFS_JSON" ]; then
    SEARCHDEFS_JSON="null"
fi

cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_mtime": $FILE_MTIME,
    "searchdefs": $SEARCHDEFS_JSON
}
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. Result saved to /tmp/task_result.json"