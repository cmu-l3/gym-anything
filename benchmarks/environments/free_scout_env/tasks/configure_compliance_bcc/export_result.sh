#!/bin/bash
set -e

echo "=== Exporting Configure Compliance BCC Result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Get Task Start Time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Inspect Database State via Tinker
# We extract all relevant fields to verify:
# - Billing BCC was set correctly
# - Billing SMTP settings were NOT wiped
# - Support BCC was NOT touched
# - Timestamps indicate recent modification

# We output JSON directly from PHP for reliability
JSON_RESULT=$(fs_tinker "
\$billing = \App\Mailbox::where('email', 'billing@acme-finance.com')->first();
\$support = \App\Mailbox::where('email', 'support@acme-finance.com')->first();

echo json_encode([
    'billing_exists' => (bool)\$billing,
    'billing_bcc' => \$billing ? \$billing->bcc : null,
    'billing_smtp_host' => \$billing ? \$billing->out_server : null,
    'billing_smtp_user' => \$billing ? \$billing->out_username : null,
    'billing_smtp_pass_set' => \$billing ? !empty(\$billing->out_password) : false,
    'billing_updated_at_ts' => \$billing ? \$billing->updated_at->timestamp : 0,
    'support_bcc' => \$support ? \$support->bcc : null,
    'support_updated_at_ts' => \$support ? \$support->updated_at->timestamp : 0
]);
")

# 4. Clean up the output (Tinker might output preamble/postamble text)
# We grep for the JSON structure
CLEAN_JSON=$(echo "$JSON_RESULT" | grep -o '{.*}')

# 5. Construct Final Result JSON
# We combine the PHP result with shell-level metadata
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "db_state": $CLEAN_JSON,
    "screenshot_path": "/tmp/task_final.png",
    "export_timestamp": $(date +%s)
}
EOF

# 6. Save to final location with permissions
safe_write_result "$TEMP_JSON" /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="