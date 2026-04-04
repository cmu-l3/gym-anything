#!/bin/bash
set -e
echo "=== Exporting setup_billable_time result ==="

source /workspace/scripts/task_utils.sh

# Get timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# Get Business Key
BIZ_KEY=$(cat /tmp/biz_key.txt 2>/dev/null || echo "")

if [ -z "$BIZ_KEY" ]; then
    # Try to recover key if missing
    COOKIE_FILE="/tmp/mgr_export_cookies.txt"
    curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" -X POST "$MANAGER_URL/login" -d "Username=administrator" -L -o /dev/null
    BIZ_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/businesses" -L)
    BIZ_KEY=$(echo "$BIZ_PAGE" | python3 -c "import sys, re; html=sys.stdin.read(); m=re.search(r'start\?([^\"&\s]+)[^<]{0,300}Northwind Traders', html); print(m.group(1) if m else '')")
fi

echo "Using Business Key: $BIZ_KEY"

# Prepare cookies
COOKIE_FILE="/tmp/mgr_export_cookies.txt"
curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" -X POST "$MANAGER_URL/login" -d "Username=administrator" -L -o /dev/null

# 1. Check if "Billable Time" is enabled in the sidebar
# We fetch the Summary page (or any page) and look for the link in the sidebar
SUMMARY_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/summary?$BIZ_KEY" -L)
# Sidebar links usually look like <a href="billable-time?FileID=...">Billable Time</a>
MODULE_ENABLED="false"
if echo "$SUMMARY_PAGE" | grep -q "billable-time?"; then
    MODULE_ENABLED="true"
fi

# 2. Extract Billable Time entries
# We fetch the index page and parse the table
BILLABLE_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/billable-time?$BIZ_KEY" -L)

# Use python to parse the HTML table entries more reliably
python3 -c "
import sys, re, json
from html.parser import HTMLParser

html = sys.stdin.read()

entries = []

# Simple regex fallback if HTML parsing is too complex for stdlib
# Look for table rows.
# Valid rows usually contain date, customer, description, amount
# We'll scrape strictly what we need.

# Pattern to find data rows (assuming standard Manager.io table layout)
# This is fragile but usually effective for Manager's simple HTML
# We look for text content.

# Let's extract all text content from table cells
class TableParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.in_table = False
        self.in_row = False
        self.in_cell = False
        self.rows = []
        self.current_row = []
        self.cell_data = ''

    def handle_starttag(self, tag, attrs):
        if tag == 'table':
            self.in_table = True
        elif tag == 'tr' and self.in_table:
            self.in_row = True
            self.current_row = []
        elif tag == 'td' and self.in_row:
            self.in_cell = True
            self.cell_data = ''

    def handle_endtag(self, tag):
        if tag == 'table':
            self.in_table = False
        elif tag == 'tr' and self.in_row:
            self.in_row = False
            if self.current_row:
                self.rows.append(self.current_row)
        elif tag == 'td' and self.in_cell:
            self.in_cell = False
            self.current_row.append(self.cell_data.strip())

    def handle_data(self, data):
        if self.in_cell:
            self.cell_data += data + ' '

parser = TableParser()
parser.feed(html)

# Process rows to find relevant data
# Expected columns often: Date, Customer, Description, ..., Amount, Status
parsed_entries = []
for row in parser.rows:
    # Filter out empty or header rows (header rows are usually th not td, so ignored by logic above)
    # Just grab anything that looks like our data
    if len(row) >= 4:
        entry = {
            'raw': row,
            'date': next((x for x in row if re.match(r'\d{4}-\d{2}-\d{2}', x)), ''),
            'amount': next((x for x in row if re.search(r'\d+\.\d{2}', x)), '0'),
            'description': ' '.join(row) # easier to just search the whole row string
        }
        parsed_entries.append(entry)

print(json.dumps(parsed_entries))
" <<< "$BILLABLE_PAGE" > /tmp/billable_entries.json

# Construct final result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "module_enabled": $MODULE_ENABLED,
    "entries": $(cat /tmp/billable_entries.json),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="