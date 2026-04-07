#!/bin/bash
echo "=== Exporting enable_field_auditing results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png
sleep 1

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 2. Extract actual bean definitions using a PHP script inside the container
cat > /tmp/check_audits.php << 'PHPEOF'
<?php
define('sugarEntry', true);
require_once('include/entryPoint.php');

$bean = BeanFactory::newBean('Accounts');

$industry_audited = !empty($bean->field_defs['industry']['audited']) ? true : false;
$revenue_audited = !empty($bean->field_defs['annual_revenue']['audited']) ? true : false;

echo json_encode([
    "industry_audited" => $industry_audited,
    "revenue_audited" => $revenue_audited
]);
PHPEOF

docker cp /tmp/check_audits.php suitecrm-app:/tmp/check_audits.php
PHP_RESULT=$(docker exec suitecrm-app sudo -u www-data php /tmp/check_audits.php 2>/dev/null)

# Fallback if PHP fails
if [ -z "$PHP_RESULT" ]; then
    PHP_RESULT='{"industry_audited": false, "revenue_audited": false}'
fi

# 3. Check filesystem timestamps for anti-gaming (Studio creates/modifies these files)
IND_FILE="/var/www/html/custom/Extension/modules/Accounts/Ext/Vardefs/sugarfield_industry.php"
REV_FILE="/var/www/html/custom/Extension/modules/Accounts/Ext/Vardefs/sugarfield_annual_revenue.php"

IND_EXISTS=$(docker exec suitecrm-app test -f "$IND_FILE" && echo "true" || echo "false")
REV_EXISTS=$(docker exec suitecrm-app test -f "$REV_FILE" && echo "true" || echo "false")

IND_MTIME=$(docker exec suitecrm-app stat -c %Y "$IND_FILE" 2>/dev/null || echo "0")
REV_MTIME=$(docker exec suitecrm-app stat -c %Y "$REV_FILE" 2>/dev/null || echo "0")

# 4. Compile into a single JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
  "task_start_time": $TASK_START,
  "bean_defs": $PHP_RESULT,
  "files": {
    "industry": {
      "exists": $IND_EXISTS,
      "mtime": $IND_MTIME
    },
    "revenue": {
      "exists": $REV_EXISTS,
      "mtime": $REV_MTIME
    }
  }
}
EOF

# Safely copy to /tmp/task_result.json
safe_write_result "/tmp/task_result.json" "$(cat "$TEMP_JSON")"
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== enable_field_auditing export complete ==="