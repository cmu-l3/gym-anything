#!/bin/bash
echo "=== Setting up Record Procedure/Charge Entry task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure MySQL and Apache are running
systemctl start mysql 2>/dev/null || service mysql start 2>/dev/null || true
systemctl start apache2 2>/dev/null || service apache2 start 2>/dev/null || true
sleep 2

# Ensure patient Margaret Thompson exists
PATIENT_EXISTS=$(mysql -u freemed -pfreemed freemed -N -e \
    "SELECT COUNT(*) FROM patient WHERE ptfname='Margaret' AND ptlname='Thompson';" 2>/dev/null || echo "0")

if [ "${PATIENT_EXISTS}" -eq 0 ]; then
    echo "Creating patient Margaret Thompson..."
    mysql -u freemed -pfreemed freemed -e "
        INSERT INTO patient (ptfname, ptmname, ptlname, ptdob, ptsex, ptaddr1, ptcity, ptstate, ptzip, ptcountry, ptprefcontact)
        VALUES ('Margaret', 'A', 'Thompson', '1958-06-22', 'f', '456 Oak Avenue', 'Springfield', 'IL', '62704', 'US', 'phone');
    " 2>/dev/null || echo "Warning: Could not insert patient"
fi

# Get patient ID
PATIENT_ID=$(mysql -u freemed -pfreemed freemed -N -e \
    "SELECT id FROM patient WHERE ptfname='Margaret' AND ptlname='Thompson' LIMIT 1;" 2>/dev/null || echo "0")
echo "Patient Margaret Thompson ID: $PATIENT_ID"
echo "$PATIENT_ID" > /tmp/task_patient_id.txt

# Record initial procedure record max ID for diffing
MAX_PROCREC_ID=$(mysql -u freemed -pfreemed freemed -N -e \
    "SELECT MAX(id) FROM procrec;" 2>/dev/null || echo "0")
if [ -z "$MAX_PROCREC_ID" ] || [ "$MAX_PROCREC_ID" == "NULL" ]; then
    MAX_PROCREC_ID="0"
fi
echo "Initial max procrec ID: $MAX_PROCREC_ID"
echo "$MAX_PROCREC_ID" > /tmp/initial_max_procrec_id.txt

# Ensure CPT code 99213 exists in the system
CPT_EXISTS=$(mysql -u freemed -pfreemed freemed -N -e \
    "SELECT COUNT(*) FROM cpt WHERE cptcode='99213';" 2>/dev/null || echo "0")
if [ "${CPT_EXISTS}" -eq 0 ]; then
    echo "Inserting CPT code 99213..."
    mysql -u freemed -pfreemed freemed -e "
        INSERT IGNORE INTO cpt (cptcode, cptnameint, cptnameext)
        VALUES ('99213', 'Office/outpatient visit est patient level 3', 'Office Visit Level 3 (Est)');
    " 2>/dev/null || echo "Warning: Could not insert CPT code"
fi

# Ensure ICD code I10 exists
ICD_EXISTS=$(mysql -u freemed -pfreemed freemed -N -e \
    "SELECT COUNT(*) FROM icd9 WHERE icd9code='I10';" 2>/dev/null || echo "0")
if [ "${ICD_EXISTS}" -eq 0 ]; then
    echo "Inserting ICD code I10..."
    mysql -u freemed -pfreemed freemed -e "
        INSERT IGNORE INTO icd9 (icd9code, icd9descrip)
        VALUES ('I10', 'Essential (primary) hypertension');
    " 2>/dev/null || echo "Warning: Could not insert ICD code"
fi

# Launch Firefox with FreeMED
echo "Starting Firefox with FreeMED..."

# Kill any existing Firefox instances cleanly
pkill -f firefox 2>/dev/null || true
sleep 2

FREEMED_URL="http://localhost/freemed/"

if [ -x /snap/bin/firefox ]; then
    PROFILE_DIR="/home/ga/snap/firefox/common/.mozilla/firefox/freemed.profile"
    mkdir -p "$PROFILE_DIR" 2>/dev/null || true
    rm -f "$PROFILE_DIR/.parentlock" "$PROFILE_DIR/lock" 2>/dev/null || true
    su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        setsid /snap/bin/firefox --new-instance \
        -profile '$PROFILE_DIR' \
        '${FREEMED_URL}' > /tmp/firefox_task.log 2>&1 &"
else
    su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        setsid firefox '${FREEMED_URL}' > /tmp/firefox_task.log 2>&1 &"
fi

echo "Waiting for Firefox to start..."
sleep 8

# Wait for Firefox window
for i in {1..30}; do
    if DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|FreeMED"; then
        echo "Firefox window detected after ${i}s"
        break
    fi
    sleep 1
done

# Maximize Firefox window
sleep 2
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
sleep 3
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot /tmp/task_initial_state.png 2>/dev/null || \
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority import -window root /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="