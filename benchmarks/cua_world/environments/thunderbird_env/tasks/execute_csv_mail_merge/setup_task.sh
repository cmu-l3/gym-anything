#!/bin/bash
set -euo pipefail

echo "=== Setting up Mail Merge task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Create the vendors.csv dataset
mkdir -p /home/ga/Documents
cat > /home/ga/Documents/vendors.csv << 'EOF'
FirstName,LastName,Company,Email
Alice,Smith,Acme Corp,alice.smith@acmecorp.example.com
Bob,Jones,Globex,bob.jones@globex.example.com
Carol,Williams,Soylent,carol.williams@soylent.example.com
David,Brown,Initech,david.brown@initech.example.com
Eve,Davis,Umbrella Corp,eve.davis@umbrella.example.com
Frank,Miller,Massive Dynamic,frank.miller@massive.example.com
Grace,Wilson,Cyberdyne,grace.wilson@cyberdyne.example.com
Henry,Moore,Wayne Ent,henry.moore@wayne.example.com
Ivy,Taylor,Stark Ind,ivy.taylor@stark.example.com
Jack,Anderson,Gekko Co,jack.anderson@gekko.example.com
Karen,Thomas,Wonka Ind,karen.thomas@wonka.example.com
Leo,Jackson,Oscorp,leo.jackson@oscorp.example.com
Mia,White,Pied Piper,mia.white@piedpiper.example.com
Noah,Harris,Hooli,noah.harris@hooli.example.com
Olivia,Martin,Dunder Mifflin,olivia.martin@dunder.example.com
EOF
chown ga:ga /home/ga/Documents/vendors.csv

# Ensure Thunderbird outbox ("Unsent Messages") is completely empty
TB_PROFILE="/home/ga/.thunderbird/default-release"
OUTBOX="${TB_PROFILE}/Mail/Local Folders/Unsent Messages"

# Ensure Local Folders directory exists
mkdir -p "${TB_PROFILE}/Mail/Local Folders"

# Create/Empty the outbox mbox file
> "$OUTBOX"
chown ga:ga "$OUTBOX"

# Start Thunderbird if not running
start_thunderbird

# Wait for Thunderbird window to appear
wait_for_thunderbird_window 30
sleep 3

# Maximize the window for visibility
maximize_thunderbird

# Take initial screenshot
echo "Capturing initial state..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="