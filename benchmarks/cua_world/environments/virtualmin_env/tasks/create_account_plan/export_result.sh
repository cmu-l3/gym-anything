#!/bin/bash
echo "=== Exporting create_account_plan results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Capture Plan Details
# We need the full multiline output to parse the limits
echo "Exporting plan details..."
virtualmin list-plans --multiline > /tmp/final_plans_detailed.txt 2>/dev/null || echo "Error listing plans" > /tmp/final_plans_detailed.txt

# 2. Capture Domain Status
echo "Exporting domain details..."
virtualmin list-domains --domain acmecorp.test --multiline > /tmp/final_domain_details.txt 2>/dev/null || echo "Error listing domain" > /tmp/final_domain_details.txt

# 3. Check for Anti-Gaming (Plan creation time)
# We can't easily get creation time from CLI, but we rely on the fact it didn't exist at start (checked in setup)
# and now exists.
PLAN_EXISTS_NOW="false"
if grep -q "^Business Pro$" /tmp/final_plans_detailed.txt 2>/dev/null || grep -q "^Business Pro$" <(virtualmin list-plans --name-only); then
    PLAN_EXISTS_NOW="true"
fi

PLAN_EXISTED_BEFORE="false"
if grep -q "^Business Pro$" /tmp/initial_plans_list.txt 2>/dev/null; then
    PLAN_EXISTED_BEFORE="true"
fi

# 4. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 5. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "plan_exists_now": $PLAN_EXISTS_NOW,
    "plan_existed_before": $PLAN_EXISTED_BEFORE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move files to temp accessible location
# We need to expose the text files for the verifier to parse
cp /tmp/final_plans_detailed.txt /tmp/task_plans.txt
cp /tmp/final_domain_details.txt /tmp/task_domain.txt
chmod 644 /tmp/task_plans.txt /tmp/task_domain.txt

# Save main result JSON
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="