#!/bin/bash
set -e
echo "=== Setting up add_supplement task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Wait for NOSH database to be ready
echo "Checking database readiness..."
for i in {1..30}; do
    if docker exec nosh-db mysqladmin ping -h localhost -uroot -prootpassword --silent 2>/dev/null; then
        echo "Database is ready."
        break
    fi
    echo "Waiting for database... ($i/30)"
    sleep 2
done

# Ensure sup_list table exists (create if missing to avoid errors)
docker exec nosh-db mysql -uroot -prootpassword nosh -e \
    "CREATE TABLE IF NOT EXISTS sup_list (
        sup_id INT AUTO_INCREMENT PRIMARY KEY,
        sup_supplement VARCHAR(255),
        sup_dosage VARCHAR(255),
        sup_dosage_unit VARCHAR(50),
        sup_sig VARCHAR(255),
        sup_route VARCHAR(100),
        sup_frequency VARCHAR(100),
        sup_instructions TEXT,
        sup_reason VARCHAR(255),
        sup_date_active DATE,
        sup_date_inactive DATE DEFAULT NULL,
        sup_prescribe VARCHAR(10) DEFAULT 'n',
        sup_provider VARCHAR(255),
        pid BIGINT,
        id BIGINT,
        practice_id BIGINT DEFAULT 1,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8;" 2>/dev/null

# Select a target patient (prefer one with no existing Vitamin D supplements)
# If no suitable patient exists, create one
TARGET_PID=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
    "SELECT pid FROM demographics WHERE active = 1 ORDER BY RAND() LIMIT 1;" 2>/dev/null)

if [ -z "$TARGET_PID" ]; then
    echo "Inserting test patient..."
    docker exec nosh-db mysql -uroot -prootpassword nosh -e \
        "INSERT INTO demographics (firstname, lastname, DOB, sex, active) VALUES ('Margaret', 'Sullivan', '1958-06-12', 'Female', 1);" 2>/dev/null
    TARGET_PID=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
        "SELECT pid FROM demographics WHERE lastname='Sullivan' AND firstname='Margaret' LIMIT 1;" 2>/dev/null)
    # Ensure demographics_relate entry exists
    echo "INSERT IGNORE INTO demographics_relate (pid, id, practice_id) VALUES ($TARGET_PID, 2, 1);" | \
        docker exec -i nosh-db mysql -uroot -prootpassword nosh 2>/dev/null || true
fi

# Get patient name details
TARGET_FIRSTNAME=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
    "SELECT firstname FROM demographics WHERE pid = $TARGET_PID;" 2>/dev/null | tr -d '[:space:]')
TARGET_LASTNAME=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
    "SELECT lastname FROM demographics WHERE pid = $TARGET_PID;" 2>/dev/null | tr -d '[:space:]')

echo "Target Patient: $TARGET_FIRSTNAME $TARGET_LASTNAME (PID: $TARGET_PID)"

# Save target PID for verification
echo "$TARGET_PID" > /tmp/target_pid.txt

# Create instructions file for the agent
cat > /tmp/target_patient.txt << EOF
Patient Name: $TARGET_FIRSTNAME $TARGET_LASTNAME
Patient ID: $TARGET_PID
EOF
chmod 644 /tmp/target_patient.txt

# Record initial supplement count for this patient
INITIAL_SUP_COUNT=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
    "SELECT COUNT(*) FROM sup_list WHERE pid = $TARGET_PID;" 2>/dev/null || echo "0")
echo "$INITIAL_SUP_COUNT" > /tmp/initial_sup_count.txt

# Setup Firefox
echo "Starting Firefox..."
pkill -f firefox 2>/dev/null || true
sleep 2

# Start Firefox and navigate to NOSH login
su - ga -c "DISPLAY=:1 firefox http://localhost/login &"
sleep 5

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i -E "(firefox|mozilla|nosh)"; then
        echo "Firefox window detected."
        break
    fi
    sleep 1
done

# Maximize window
DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Mozilla Firefox" 2>/dev/null || true

# Capture initial state screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="