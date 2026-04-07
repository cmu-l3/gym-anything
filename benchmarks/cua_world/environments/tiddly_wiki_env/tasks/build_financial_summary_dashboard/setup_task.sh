#!/bin/bash
echo "=== Setting up build_financial_summary_dashboard task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create realistic transaction tiddlers in the tiddlers directory
echo "Seeding financial transaction data..."
python3 -c "
import os

tiddlers = [
    ('Sponsorship Acme Corp', 'Contribution', 1500, 'Q1 Sponsorship payment from Acme.'),
    ('Individual Donation Alice', 'Contribution', 200, 'Donation via OpenCollective.'),
    ('Individual Donation Bob', 'Contribution', 350, 'Donation via OpenCollective.'),
    ('Grant Mozilla', 'Contribution', 4000, 'Open Source Support Grant.'),
    ('Individual Donation Charlie', 'Contribution', 100, 'Patreon backing.'),
    ('Server Hosting Jan', 'Expense', 1200, 'AWS Hosting invoice.'),
    ('Domain Renewal', 'Expense', 50, 'Namecheap domain renewal.'),
    ('Software Licenses', 'Expense', 400, 'JetBrains and GitHub Copilot licenses.'),
    ('Marketing Materials', 'Expense', 800, 'Stickers and banners for conference.')
]

os.makedirs('/home/ga/mywiki/tiddlers', exist_ok=True)

for title, tag, amt, text in tiddlers:
    safe_title = title.replace(' ', '_')
    with open(f'/home/ga/mywiki/tiddlers/{safe_title}.tid', 'w') as f:
        f.write(f'title: {title}\ntags: {tag}\namount: {amt}\n\n{text}\n')
"

# Fix permissions
chown -R ga:ga /home/ga/mywiki/tiddlers

# Refresh Firefox to ensure it picks up the newly seeded files
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|tiddly" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    echo "Focusing and refreshing Firefox..."
    DISPLAY=:1 wmctrl -ia "$WID"
    sleep 0.5
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 xdotool key F5
    sleep 3
fi

# Take initial screenshot showing the environment
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="