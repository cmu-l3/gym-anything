#!/bin/bash
# Setup script for sakila_fraud_detection_forensics task

echo "=== Setting up Sakila Fraud Detection Forensics Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time

# Ensure MySQL is running
if [ "$(is_mysql_running)" = "false" ]; then
    echo "Starting MySQL service..."
    systemctl start mysql
    sleep 5
fi

# Ensure Workbench is running (for agent convenience)
if [ "$(is_workbench_running)" = "false" ]; then
    start_workbench
fi

# Clean up previous state
mysql -u root -p'GymAnything#2024' sakila -e "DROP VIEW IF EXISTS v_fraud_report;" 2>/dev/null || true
rm -f /home/ga/Documents/exports/fraud_report.csv 2>/dev/null || true

echo "Injecting forensic anomalies..."

# 1. Inject TIME TRAVEL (Return date before rental date)
# Insert a new rental with valid keys
echo "Injecting Time Travel case..."
mysql -u root -p'GymAnything#2024' sakila -e "
    INSERT INTO rental (rental_date, inventory_id, customer_id, return_date, staff_id)
    VALUES (NOW(), 1, 1, DATE_SUB(NOW(), INTERVAL 1 DAY), 1);
" 2>/dev/null

TIME_TRAVEL_ID=$(mysql -u root -p'GymAnything#2024' sakila -N -e "SELECT LAST_INSERT_ID();")
echo "Time Travel Rental ID: $TIME_TRAVEL_ID"

# 2. Inject NEPOTISM (Staff processes rental for same last name, 0.00 payment)
# Get staff 1 details (Mike Hillyer)
echo "Injecting Nepotism case..."
STAFF_LAST_NAME=$(mysql -u root -p'GymAnything#2024' sakila -N -e "SELECT last_name FROM staff WHERE staff_id=1;")
echo "Staff Last Name: $STAFF_LAST_NAME"

# Create a customer with same last name
mysql -u root -p'GymAnything#2024' sakila -e "
    INSERT INTO customer (store_id, first_name, last_name, email, address_id, active, create_date)
    VALUES (1, 'Fraudulent', '$STAFF_LAST_NAME', 'fraud@example.com', 1, 1, NOW());
" 2>/dev/null
NEPO_CUSTOMER_ID=$(mysql -u root -p'GymAnything#2024' sakila -N -e "SELECT LAST_INSERT_ID();")

# Create rental processed by Staff 1
mysql -u root -p'GymAnything#2024' sakila -e "
    INSERT INTO rental (rental_date, inventory_id, customer_id, return_date, staff_id)
    VALUES (NOW(), 2, $NEPO_CUSTOMER_ID, NULL, 1);
" 2>/dev/null
NEPO_RENTAL_ID=$(mysql -u root -p'GymAnything#2024' sakila -N -e "SELECT LAST_INSERT_ID();")

# Create 0.00 payment
mysql -u root -p'GymAnything#2024' sakila -e "
    INSERT INTO payment (customer_id, staff_id, rental_id, amount, payment_date)
    VALUES ($NEPO_CUSTOMER_ID, 1, $NEPO_RENTAL_ID, 0.00, NOW());
" 2>/dev/null

echo "Nepotism Rental ID: $NEPO_RENTAL_ID"

# 3. Inject HOARDING (Customer with > 3 overdue rentals)
echo "Injecting Hoarding case..."
# Create a new hoarder customer
mysql -u root -p'GymAnything#2024' sakila -e "
    INSERT INTO customer (store_id, first_name, last_name, email, address_id, active, create_date)
    VALUES (1, 'Hoarder', 'Joe', 'hoarder@example.com', 1, 1, NOW());
" 2>/dev/null
HOARDER_ID=$(mysql -u root -p'GymAnything#2024' sakila -N -e "SELECT LAST_INSERT_ID();")

# Insert 5 overdue rentals (old rental_date, NULL return_date)
for i in {1..5}; do
    mysql -u root -p'GymAnything#2024' sakila -e "
        INSERT INTO rental (rental_date, inventory_id, customer_id, return_date, staff_id)
        VALUES ('2005-01-01 00:00:00', $i, $HOARDER_ID, NULL, 1);
    " 2>/dev/null
done
echo "Hoarder Customer ID: $HOARDER_ID"

# Save IDs for verification
cat > /tmp/injected_anomalies.json << EOF
{
    "time_travel_id": $TIME_TRAVEL_ID,
    "nepotism_id": $NEPO_RENTAL_ID,
    "hoarder_id": $HOARDER_ID
}
EOF

# Ensure directory exists
mkdir -p /home/ga/Documents/exports
chown -R ga:ga /home/ga/Documents/exports

# Focus Workbench
focus_workbench

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="