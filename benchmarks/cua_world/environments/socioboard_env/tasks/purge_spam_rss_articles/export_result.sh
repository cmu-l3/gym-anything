#!/bin/bash
echo "=== Exporting purge_spam_rss_articles result ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

SECRET_TOKEN=$(cat /tmp/secret_token.txt 2>/dev/null)

# Create an evaluation script
cat > /tmp/evaluate_db.js << EOF
use socioboard;

try {
    let total = db.rss_articles.countDocuments({});
    
    // Count spam documents remaining (case-insensitive)
    let spam = db.rss_articles.countDocuments({
        \$or: [
            { title: { \$regex: "crypto-giveaway", \$options: "i" } },
            { description: { \$regex: "crypto-giveaway", \$options: "i" } }
        ]
    });
    
    let legit = total - spam;
    
    // Verify our anti-gaming token exists
    let token_exists = db.rss_articles.countDocuments({ secret_token: "$SECRET_TOKEN" }) > 0;
    
    let result = {
        total_count: total,
        spam_count: spam,
        legit_count: legit,
        token_intact: token_exists
    };
    
    print("RESULT_JSON=" + JSON.stringify(result));
} catch (e) {
    print("RESULT_JSON=" + JSON.stringify({ error: e.toString() }));
}
EOF

# Execute evaluation script
mongosh --quiet --norc /tmp/evaluate_db.js > /tmp/eval_output.txt 2>&1

# Extract the JSON payload reliably
EVAL_JSON=$(grep "RESULT_JSON=" /tmp/eval_output.txt | cut -d'=' -f2- || echo '{"error": "Failed to parse"}')

# Compile final result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "screenshot_exists": $([ -f "/tmp/task_final.png" ] && echo "true" || echo "false"),
    "db_eval": $EVAL_JSON
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Evaluation result exported:"
cat /tmp/task_result.json

echo "=== Export Complete ==="