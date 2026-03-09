#!/bin/bash
set -e
echo "=== Setting up create_hidden_volume task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# 1. Clean up previous artifacts
rm -f /home/ga/Volumes/plausible_deniability.hc
# Record hash of existing volumes to ensure agent doesn't just rename one
sha256sum /home/ga/Volumes/*.hc 2>/dev/null > /tmp/pre_existing_volume_hashes.txt || true

# 2. Prepare Decoy Data
# Using real-world looking data as per requirements
mkdir -p /home/ga/Documents/decoy_data
# Copy from assets if available, otherwise create realistic dummies
if [ -f /workspace/assets/sample_data/SF312_Nondisclosure_Agreement.txt ]; then
    cp /workspace/assets/sample_data/SF312_Nondisclosure_Agreement.txt /home/ga/Documents/decoy_data/
else
    # Fallback to creating a realistic looking text file
    cat > /home/ga/Documents/decoy_data/SF312_Nondisclosure_Agreement.txt << EOF
CLASSIFIED INFORMATION NONDISCLOSURE AGREEMENT
STANDARD FORM 312 (REV. 7-2013)
PRESCRIBED BY GSA/ISOO 32 CFR 2003

1. Intending to be legally bound, I hereby accept the obligations contained in this Agreement in consideration of my being granted access to classified information.
2. I hereby acknowledge that I have received a security indoctrination concerning the nature and protection of classified information.
EOF
fi

if [ -f /workspace/assets/sample_data/FY2024_Revenue_Budget.csv ]; then
    cp /workspace/assets/sample_data/FY2024_Revenue_Budget.csv /home/ga/Documents/decoy_data/
else
    # Fallback CSV
    cat > /home/ga/Documents/decoy_data/FY2024_Revenue_Budget.csv << EOF
Department,Q1_Allocation,Q2_Allocation,Q3_Allocation,Q4_Allocation,Total_FY2024
Operations,1200000,1250000,1100000,1400000,4950000
Marketing,450000,500000,650000,800000,2400000
R&D,2100000,2100000,2100000,2100000,8400000
Legal,300000,300000,350000,400000,1350000
EOF
fi

chown -R ga:ga /home/ga/Documents/decoy_data

# 3. Ensure VeraCrypt is running and window is prepared
if ! is_veracrypt_running; then
    echo "Starting VeraCrypt..."
    su - ga -c "DISPLAY=:1 veracrypt &"
fi

wait_for_window "VeraCrypt" 20

# Get Window ID and maximize
WID=$(get_veracrypt_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="