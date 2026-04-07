#!/bin/bash
echo "=== Exporting create_financial_math_dashboard result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot BEFORE injecting test data
take_screenshot /tmp/task_final.png

# Check if transaction tiddlers exist
INC1_EXISTS=$(tiddler_exists "Invoice - Website Redesign Acme")
INC2_EXISTS=$(tiddler_exists "Invoice - Logo Design TechStart")
EXP1_EXISTS=$(tiddler_exists "Adobe CC Subscription")
EXP2_EXISTS=$(tiddler_exists "AWS Hosting")
EXP3_EXISTS=$(tiddler_exists "New Ergonomic Chair")

# Check if dashboard exists
DASH_EXISTS=$(tiddler_exists "Financial Dashboard")

# Read dashboard content for syntax verification
DASH_TEXT=""
HAS_SUM="false"
HAS_SUBTRACT="false"

if [ "$DASH_EXISTS" = "true" ]; then
    DASH_TEXT=$(get_tiddler_text "Financial Dashboard")
    # Check for math operators in the text
    echo "$DASH_TEXT" | grep -qi "sum\[\]" && HAS_SUM="true"
    echo "$DASH_TEXT" | grep -qi "subtract" && HAS_SUBTRACT="true"
fi

# ==============================================================================
# ANTI-GAMING INJECTION:
# We inject two new tiddlers behind the scenes and render the dashboard to HTML
# to prove the agent wrote dynamic math logic, not hardcoded text.
# ==============================================================================

echo "Injecting test data for dynamic calculation verification..."
cat > "/home/ga/mywiki/tiddlers/VerifierTestIncome.tid" << 'EOF'
title: VerifierTestIncome
tags: Income
amount: 10000
EOF

cat > "/home/ga/mywiki/tiddlers/VerifierTestExpense.tid" << 'EOF'
title: VerifierTestExpense
tags: Expense
amount: 5000
EOF

# Render the dashboard using the TiddlyWiki Node.js CLI
echo "Rendering dashboard to verify dynamic math..."
su - ga -c "cd /home/ga && tiddlywiki mywiki --render 'Financial Dashboard' 'dashboard_test.html' 'text/html'" > /dev/null 2>&1

# Parse the rendered HTML for the updated totals
# Expected after injection: Income=13300, Expense=5625, Profit=7675
HTML_CONTENT=""
DYNAMIC_INCOME_CORRECT="false"
DYNAMIC_EXPENSE_CORRECT="false"
DYNAMIC_PROFIT_CORRECT="false"

if [ -f "/home/ga/mywiki/output/dashboard_test.html" ]; then
    HTML_CONTENT=$(cat "/home/ga/mywiki/output/dashboard_test.html" 2>/dev/null)
    
    # Check if the exact new totals appear anywhere in the rendered HTML output
    echo "$HTML_CONTENT" | grep -q "13300" && DYNAMIC_INCOME_CORRECT="true"
    echo "$HTML_CONTENT" | grep -q "5625" && DYNAMIC_EXPENSE_CORRECT="true"
    echo "$HTML_CONTENT" | grep -q "7675" && DYNAMIC_PROFIT_CORRECT="true"
fi

# Clean up injected files so they don't persist if agent re-checks
rm -f "/home/ga/mywiki/tiddlers/VerifierTestIncome.tid"
rm -f "/home/ga/mywiki/tiddlers/VerifierTestExpense.tid"
rm -f "/home/ga/mywiki/output/dashboard_test.html"

# Escape text for JSON output
ESCAPED_TEXT=$(json_escape "$DASH_TEXT")

# Build JSON result
JSON_RESULT=$(cat << EOF
{
    "inc1_exists": $INC1_EXISTS,
    "inc2_exists": $INC2_EXISTS,
    "exp1_exists": $EXP1_EXISTS,
    "exp2_exists": $EXP2_EXISTS,
    "exp3_exists": $EXP3_EXISTS,
    "dash_exists": $DASH_EXISTS,
    "has_sum_operator": $HAS_SUM,
    "has_subtract_operator": $HAS_SUBTRACT,
    "dynamic_income_correct": $DYNAMIC_INCOME_CORRECT,
    "dynamic_expense_correct": $DYNAMIC_EXPENSE_CORRECT,
    "dynamic_profit_correct": $DYNAMIC_PROFIT_CORRECT,
    "dashboard_source": "$ESCAPED_TEXT",
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "$JSON_RESULT" "/tmp/task_result.json"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="