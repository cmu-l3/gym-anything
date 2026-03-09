#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up generate_clinical_cohort_report ==="
date +%s > /tmp/task_start_time.txt

# Ensure LibreHealth is ready
wait_for_librehealth 120

# Create output directory
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Clean up previous runs
rm -f /home/ga/Documents/cohort_report.csv

# --- Data Injection ---
echo "Injecting clinical diagnoses for cohort generation..."

# Select 5 random valid patients (with names) to be our test set
# We use their PIDs. 
# Targets (P1-P3): Will get the diagnosis
# Controls (C1-C2): Will NOT get the diagnosis
PIDS=$(librehealth_query "SELECT pid FROM patient_data WHERE fname!='' AND lname!='' ORDER BY RAND() LIMIT 5" | tr '\n' ' ')
read -r P1 P2 P3 C1 C2 <<< "$PIDS"

if [ -z "$P3" ]; then
    echo "ERROR: Not enough patients found in database."
    exit 1
fi

echo "Targets: $P1, $P2, $P3 | Controls: $C1, $C2"

# Diagnosis Details (ICD-10 for Chronic Fatigue Syndrome)
DIAG_TITLE="Chronic Fatigue Syndrome"
DIAG_CODE="R53.82"
DATE_STR=$(date +%Y-%m-%d)

# Function to inject diagnosis into 'lists' table (OpenEMR/LibreHealth standard for problems)
inject_diagnosis() {
    local pid=$1
    echo "Injecting diagnosis for PID $pid..."
    # Check if already exists to avoid dupes
    local exists=$(librehealth_query "SELECT count(*) FROM lists WHERE pid=$pid AND type='medical_problem' AND diagnosis='$DIAG_CODE'")
    if [ "$exists" -eq "0" ]; then
        librehealth_query "INSERT INTO lists (pid, type, date, title, diagnosis, activity, user) VALUES ($pid, 'medical_problem', '$DATE_STR 00:00:00', '$DIAG_TITLE', '$DIAG_CODE', 1, 'admin')"
    fi
}

# Inject into Targets
inject_diagnosis "$P1"
inject_diagnosis "$P2"
inject_diagnosis "$P3"

# Ensure controls DO NOT have the diagnosis (cleanup if they happened to have it)
librehealth_query "DELETE FROM lists WHERE type='medical_problem' AND diagnosis='$DIAG_CODE' AND pid IN ($C1, $C2)"

# Get Names for Verification (Ground Truth)
get_full_name() {
    librehealth_query "SELECT CONCAT(fname, ' ', lname) FROM patient_data WHERE pid=$1"
}

N1=$(get_full_name "$P1")
N2=$(get_full_name "$P2")
N3=$(get_full_name "$P3")
NC1=$(get_full_name "$C1")
NC2=$(get_full_name "$C2")

# Save ground truth to a hidden location for the verifier
# This directory is generally protected/hidden from the ga user view
mkdir -p /var/lib/app/ground_truth
chmod 755 /var/lib/app/ground_truth

cat > /var/lib/app/ground_truth/expected_targets.txt << EOF
$N1
$N2
$N3
EOF

cat > /var/lib/app/ground_truth/expected_controls.txt << EOF
$NC1
$NC2
EOF

# Also save PIDs just in case
echo "$P1 $P2 $P3" > /var/lib/app/ground_truth/target_pids.txt

chmod 644 /var/lib/app/ground_truth/*
echo "Ground truth saved."

# Restart Firefox to clean state
restart_firefox "http://localhost:8000/interface/login/login.php?site=default"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="