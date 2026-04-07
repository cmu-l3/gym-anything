#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up eDiscovery Privilege Log Task ==="

# Record task start timestamp for anti-gaming
echo $(date +%s) > /tmp/task_start_time.txt

cleanup_temp_files
kill_onlyoffice ga
sleep 1

WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
DOCS_DIR="/home/ga/Documents"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

CSV_PATH="$WORKSPACE_DIR/enron_production_vol1.csv"
COUNSEL_PATH="$DOCS_DIR/counsel_list.txt"

# Create the counsel list reference file
cat > "$COUNSEL_PATH" << 'EOF'
CONFIDENTIAL COUNSEL LIST
-------------------------
Any communications involving the following internal/external legal counsel must be withheld under Attorney-Client Privilege:

1. James Derrick (General Counsel)
2. Richard Sanders (VP & Assistant General Counsel)
3. Mark Haedicke (Managing Director, Legal)
4. Carol Essig (Paralegal)
5. Vinson & Elkins (Outside Counsel)
EOF

chown ga:ga "$COUNSEL_PATH"

# Generate a highly realistic eDiscovery CSV extract
cat > /tmp/create_ediscovery_data.py << 'PYEOF'
#!/usr/bin/env python3
import csv
import sys
import random

output_path = sys.argv[1]
random.seed(101)

# Real Enron figures and topics
non_counsel = [
    "Kenneth Lay", "Jeffrey Skilling", "Andrew Fastow", "Vince Kaminski", 
    "Sally Beck", "Greg Whalley", "Sherron Watkins", "Lou Pai", "Cliff Baxter",
    "Amanda Martin", "Rick Buy", "Ben Glisan"
]

counsel = [
    "James Derrick", "Richard Sanders", "Mark Haedicke", 
    "Carol Essig", "Vinson & Elkins"
]

subjects_normal = [
    "Q3 Earnings Call Prep", "Weekly Staff Meeting", "California Energy Market Update",
    "Dabhol Power Plant status", "Broadband business plan", "Expense report approval",
    "Trading floor updates", "New hire requisition", "Congratulations on the quarter",
    "Holiday party RSVP", "Lunch on Tuesday?", "Performance review schedule",
    "Market risk analysis", "Var limits", "Corporate communications draft"
]

subjects_legal = [
    "Project Raptor restructuring", "SEC inquiry response", "Draft litigation hold",
    "Board minutes review", "Off-balance sheet SPE liabilities", "LJM partnership conflict",
    "Subpoena compliance", "Employee whistleblower complaint", "Contract termination clause",
    "Regulatory filing draft", "Outside counsel billing", "Settlement agreement terms"
]

records = []
header = ["Control_Number", "Date", "From", "To", "Cc", "Subject", "File_Name"]
records.append(header)

for i in range(1, 151):
    ctrl_num = f"ENR-{100000 + i}"
    date = f"10/{random.randint(1, 31):02d}/2001"
    
    is_privileged = random.random() < 0.25  # ~25% privileged
    
    if is_privileged:
        # Include at least one counsel
        participants = random.sample(counsel, 1) + random.sample(non_counsel, random.randint(1, 2))
        random.shuffle(participants)
        from_person = participants[0]
        to_person = participants[1]
        cc_person = participants[2] if len(participants) > 2 else ""
        subject = random.choice(subjects_legal) + f" - {random.randint(10,99)}"
    else:
        # No counsel
        participants = random.sample(non_counsel, random.randint(2, 4))
        from_person = participants[0]
        to_person = "; ".join(participants[1:3])
        cc_person = participants[3] if len(participants) > 3 else ""
        subject = random.choice(subjects_normal)
    
    file_name = f"{from_person.split()[-1][:5]}_{ctrl_num[-4:]}.msg"
    
    records.append([ctrl_num, date, from_person, to_person, cc_person, subject, file_name])

with open(output_path, 'w', newline='', encoding='utf-8') as f:
    writer = csv.writer(f)
    writer.writerows(records)

print(f"Generated {len(records)-1} eDiscovery records.")
PYEOF

python3 /tmp/create_ediscovery_data.py "$CSV_PATH"
chown ga:ga "$CSV_PATH"

# Open the CSV file in ONLYOFFICE
echo "Starting ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$CSV_PATH' > /tmp/onlyoffice.log 2>&1 &"

# Wait for ONLYOFFICE window to appear
wait_for_window "ONLYOFFICE\|Desktop Editors" 30

# Maximize and focus the window
WID=$(get_onlyoffice_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="