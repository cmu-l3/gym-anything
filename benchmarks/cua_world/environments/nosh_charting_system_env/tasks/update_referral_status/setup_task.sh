#!/bin/bash
echo "=== Setting up update_referral_status task ==="

# 1. Record Task Start Time (Anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Ensure NOSH Database is Ready
echo "Waiting for database connection..."
for i in {1..30}; do
    if docker exec nosh-db mysqladmin ping -h localhost -uroot -prootpassword --silent; then
        break
    fi
    sleep 1
done

# 3. Data Preparation: Ensure Patient Alice Vance Exists
echo "Preparing patient data..."
PATIENT_SQL="SELECT pid FROM demographics WHERE firstname='Alice' AND lastname='Vance' LIMIT 1;"
PID=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e "$PATIENT_SQL" 2>/dev/null)

if [ -z "$PID" ]; then
    echo "Creating patient Alice Vance..."
    # Insert patient and get new PID
    docker exec nosh-db mysql -uroot -prootpassword nosh -e \
        "INSERT INTO demographics (firstname, lastname, DOB, sex, street_address1, city, state, zip, phone_home, email) \
         VALUES ('Alice', 'Vance', '1980-05-15', 'Female', '123 Oak Ln', 'Springfield', 'MA', '01105', '413-555-0199', 'alice.vance@example.com');"
    
    PID=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e "$PATIENT_SQL" 2>/dev/null)
    
    # Link patient to practice (required for visibility)
    if [ -n "$PID" ]; then
        docker exec nosh-db mysql -uroot -prootpassword nosh -e \
            "INSERT INTO demographics_relate (pid, id, practice_id) VALUES ($PID, 1, 1);"
    fi
fi
echo "Target Patient PID: $PID"

# 4. Data Preparation: Create Pending Referral Order
# First, clear any existing cardiology orders for this patient to ensure clean state
docker exec nosh-db mysql -uroot -prootpassword nosh -e \
    "DELETE FROM orders WHERE pid=$PID AND orders_description LIKE '%Cardiology%';"

# Insert new pending order (backdated 2 weeks)
ORDER_DATE=$(date -d "2 weeks ago" +%Y-%m-%d)
echo "Creating pending referral order..."
docker exec nosh-db mysql -uroot -prootpassword nosh -e \
    "INSERT INTO orders (pid, t_messages_id, encounter_id, orders_type, orders_description, date_ordered, order_status, practice_id) \
     VALUES ($PID, 0, 0, 'referral', 'Cardiology Consult', '$ORDER_DATE', 'pending', 1);"

# Get the Order ID we just created
ORDER_ID=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
    "SELECT order_id FROM orders WHERE pid=$PID AND orders_description='Cardiology Consult' AND order_status='pending' ORDER BY order_id DESC LIMIT 1;")

echo "Created Order ID: $ORDER_ID"
echo "$ORDER_ID" > /tmp/target_order_id.txt
echo "$PID" > /tmp/target_pid.txt

# 5. Application Setup (Firefox)
echo "Setting up Firefox..."
pkill -f firefox 2>/dev/null || true
sleep 2

# Start Firefox at Login Page
su - ga -c "DISPLAY=:1 firefox 'http://localhost/login' &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "firefox"; then
        echo "Firefox window detected"
        break
    fi
    sleep 1
done

# Maximize Window
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true

# 6. Capture Initial State
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

# Verify setup
if [ -z "$ORDER_ID" ]; then
    echo "CRITICAL ERROR: Failed to create target order."
    exit 1
fi

echo "=== Setup complete ==="