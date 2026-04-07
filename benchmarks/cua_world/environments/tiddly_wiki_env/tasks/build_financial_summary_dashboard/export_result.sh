#!/bin/bash
echo "=== Exporting build_financial_summary_dashboard result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

EXPECTED_TITLE="Financial Summary Report"
TIDDLER_FOUND=$(tiddler_exists "$EXPECTED_TITLE")

RAW_TEXT=""
RENDER1=""
RENDER2=""

if [ "$TIDDLER_FOUND" = "true" ]; then
    echo "Tiddler found, extracting raw text and testing rendering..."
    RAW_TEXT=$(get_tiddler_text "$EXPECTED_TITLE")

    # Clean up any existing output directory
    rm -rf /home/ga/mywiki/output 2>/dev/null || true

    # RENDER 1: Evaluate the tiddler with the initial seeded data
    su - ga -c "cd /home/ga && tiddlywiki mywiki --render '[[Financial Summary Report]]' 'report1.html' 'text/html'"
    if [ -f /home/ga/mywiki/output/report1.html ]; then
        # Strip HTML tags and normalize whitespace to make parsing robust
        RENDER1=$(cat /home/ga/mywiki/output/report1.html | sed -e 's/<[^>]*>//g' -e 's/&nbsp;/ /g' | tr '\n' ' ' | tr -s ' ')
        echo "Render 1 extraction successful."
    fi

    # ADD DUMMY DATA: Inject a new $10,000 contribution to test dynamic calculation
    echo "Injecting dummy test data to verify dynamic evaluation..."
    cat > /home/ga/mywiki/tiddlers/DummyContrib.tid << 'EOF'
title: Dummy Test Contribution
tags: Contribution
amount: 10000

Dummy test data for export verification.
EOF
    chown ga:ga /home/ga/mywiki/tiddlers/DummyContrib.tid

    # RENDER 2: Evaluate the tiddler AGAIN with the new dummy data
    su - ga -c "cd /home/ga && tiddlywiki mywiki --render '[[Financial Summary Report]]' 'report2.html' 'text/html'"
    if [ -f /home/ga/mywiki/output/report2.html ]; then
        RENDER2=$(cat /home/ga/mywiki/output/report2.html | sed -e 's/<[^>]*>//g' -e 's/&nbsp;/ /g' | tr '\n' ' ' | tr -s ' ')
        echo "Render 2 extraction successful."
    fi

    # Clean up dummy data so it doesn't linger
    rm /home/ga/mywiki/tiddlers/DummyContrib.tid
else
    echo "Expected tiddler '$EXPECTED_TITLE' not found."
fi

# Escape text for valid JSON
ESCAPED_RAW=$(json_escape "$RAW_TEXT")
ESCAPED_R1=$(json_escape "$RENDER1")
ESCAPED_R2=$(json_escape "$RENDER2")

# Construct JSON Export
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "tiddler_found": $TIDDLER_FOUND,
    "raw_text": "$ESCAPED_RAW",
    "rendered_initial": "$ESCAPED_R1",
    "rendered_dynamic": "$ESCAPED_R2",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved."
cat /tmp/task_result.json
echo "=== Export complete ==="