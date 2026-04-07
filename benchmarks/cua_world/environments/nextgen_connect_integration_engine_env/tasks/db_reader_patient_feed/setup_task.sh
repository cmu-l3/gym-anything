#!/bin/bash
# Setup for db_reader_patient_feed task
# Creates patient_registrations table and populates with realistic data

echo "=== Setting up DB Patient Registration Feed task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Wait for API
wait_for_api 120 || echo "WARNING: API may not be ready"

# Record initial channel count
INITIAL_CHANNEL_COUNT=$(get_channel_count)
echo "$INITIAL_CHANNEL_COUNT" > /tmp/initial_channel_count.txt
echo "Initial channel count: $INITIAL_CHANNEL_COUNT"

# Create the patient_registrations table and populate with realistic data
echo "Creating patient_registrations table..."
docker exec nextgen-postgres psql -U postgres -d mirthdb << 'EOSQL'
-- Drop if exists (clean state)
DROP TABLE IF EXISTS patient_registrations;

-- Create registration table
CREATE TABLE patient_registrations (
    id SERIAL PRIMARY KEY,
    mrn VARCHAR(20) NOT NULL,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    dob DATE NOT NULL,
    gender CHAR(1) NOT NULL,
    ssn VARCHAR(11),
    address VARCHAR(100),
    city VARCHAR(50),
    state VARCHAR(2),
    zip VARCHAR(10),
    phone VARCHAR(15),
    registration_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    processed BOOLEAN DEFAULT FALSE
);

-- Insert 25 realistic patient registration records
-- Using common US names, real US cities/states/ZIPs
INSERT INTO patient_registrations (mrn, first_name, last_name, dob, gender, ssn, address, city, state, zip, phone) VALUES
('MRN-2024-00101', 'Maria', 'Garcia', '1978-04-12', 'F', '412-55-7831', '2847 Elm Street', 'Houston', 'TX', '77001', '713-555-0142'),
('MRN-2024-00102', 'James', 'Wilson', '1965-11-23', 'M', '528-43-6912', '159 Oak Avenue', 'Chicago', 'IL', '60601', '312-555-0287'),
('MRN-2024-00103', 'Aisha', 'Patel', '1992-07-08', 'F', '631-22-8845', '4420 Birch Lane', 'Phoenix', 'AZ', '85001', '602-555-0361'),
('MRN-2024-00104', 'Robert', 'Johnson', '1951-03-30', 'M', '245-67-3398', '78 Pine Road', 'Philadelphia', 'PA', '19101', '215-555-0493'),
('MRN-2024-00105', 'Wei', 'Chen', '1988-09-15', 'M', '718-33-4456', '3301 Maple Drive', 'San Francisco', 'CA', '94102', '415-555-0528'),
('MRN-2024-00106', 'Sarah', 'Thompson', '1973-12-01', 'F', '334-78-9921', '612 Cedar Court', 'Boston', 'MA', '02101', '617-555-0674'),
('MRN-2024-00107', 'David', 'Martinez', '1995-05-19', 'M', '567-11-2234', '8945 Walnut Blvd', 'San Antonio', 'TX', '78201', '210-555-0715'),
('MRN-2024-00108', 'Jennifer', 'Brown', '1960-08-07', 'F', '423-89-5567', '221B Baker Street', 'Seattle', 'WA', '98101', '206-555-0839'),
('MRN-2024-00109', 'Mohammed', 'Ali', '1983-01-25', 'M', '789-44-1128', '5567 Spruce Way', 'Denver', 'CO', '80201', '303-555-0942'),
('MRN-2024-00110', 'Emily', 'Davis', '1998-06-14', 'F', '156-92-3345', '1200 Ash Terrace', 'Atlanta', 'GA', '30301', '404-555-1087'),
('MRN-2024-00111', 'Carlos', 'Rodriguez', '1970-02-28', 'M', '892-15-6673', '345 Poplar Place', 'Miami', 'FL', '33101', '305-555-1123'),
('MRN-2024-00112', 'Linda', 'Anderson', '1955-10-09', 'F', '234-56-7890', '7890 Hickory Hill', 'Minneapolis', 'MN', '55401', '612-555-1256'),
('MRN-2024-00113', 'Hiroshi', 'Tanaka', '1991-04-03', 'M', '678-23-4512', '2100 Redwood Circle', 'Portland', 'OR', '97201', '503-555-1378'),
('MRN-2024-00114', 'Patricia', 'Moore', '1967-07-22', 'F', '345-78-9012', '456 Chestnut Lane', 'Nashville', 'TN', '37201', '615-555-1492'),
('MRN-2024-00115', 'Michael', 'Taylor', '1980-12-18', 'M', '901-34-5678', '3678 Sycamore Ave', 'Columbus', 'OH', '43201', '614-555-1537'),
('MRN-2024-00116', 'Fatima', 'Hassan', '1986-03-11', 'F', '567-89-0123', '890 Dogwood Drive', 'Charlotte', 'NC', '28201', '704-555-1683'),
('MRN-2024-00117', 'William', 'Jackson', '1948-09-05', 'M', '123-45-6789', '1456 Magnolia Blvd', 'Detroit', 'MI', '48201', '313-555-1794'),
('MRN-2024-00118', 'Priya', 'Sharma', '1993-11-29', 'F', '456-12-3456', '2789 Willow Way', 'Austin', 'TX', '73301', '512-555-1825'),
('MRN-2024-00119', 'Thomas', 'White', '1975-06-16', 'M', '789-01-2345', '5123 Juniper Road', 'Baltimore', 'MD', '21201', '410-555-1967'),
('MRN-2024-00120', 'Susan', 'Harris', '1962-01-08', 'F', '012-34-5678', '678 Cypress Lane', 'San Diego', 'CA', '92101', '619-555-2041'),
('MRN-2024-00121', 'Andrei', 'Volkov', '1989-08-21', 'M', '345-67-8901', '9012 Beech Street', 'Las Vegas', 'NV', '89101', '702-555-2158'),
('MRN-2024-00122', 'Grace', 'Lee', '1997-02-14', 'F', '678-90-1234', '1345 Palm Avenue', 'Honolulu', 'HI', '96801', '808-555-2273'),
('MRN-2024-00123', 'Richard', 'Clark', '1958-05-27', 'M', '901-23-4567', '4678 Pecan Court', 'Oklahoma City', 'OK', '73101', '405-555-2389'),
('MRN-2024-00124', 'Ana', 'Morales', '1984-10-03', 'F', '234-56-7891', '7901 Hawthorn Blvd', 'Tucson', 'AZ', '85701', '520-555-2492'),
('MRN-2024-00125', 'Daniel', 'Kim', '1971-07-19', 'M', '567-89-0124', '2234 Laurel Drive', 'Pittsburgh', 'PA', '15201', '412-555-2567');
EOSQL

echo "Verifying table creation..."
RECORD_COUNT=$(docker exec nextgen-postgres psql -U postgres -d mirthdb -t -A -c "SELECT COUNT(*) FROM patient_registrations;" 2>/dev/null)
echo "Patient registration records: $RECORD_COUNT"

UNPROCESSED_COUNT=$(docker exec nextgen-postgres psql -U postgres -d mirthdb -t -A -c "SELECT COUNT(*) FROM patient_registrations WHERE processed = false;" 2>/dev/null)
echo "Unprocessed records: $UNPROCESSED_COUNT"
echo "$UNPROCESSED_COUNT" > /tmp/initial_unprocessed_count.txt

# Create output directory inside the NextGen Connect container
echo "Creating output directory in container..."
docker exec nextgen-connect mkdir -p /opt/connect/outbound_hl7
docker exec nextgen-connect chmod 777 /opt/connect/outbound_hl7
# Clean any pre-existing files just in case
docker exec nextgen-connect rm -f /opt/connect/outbound_hl7/*.hl7

# Ensure Firefox is showing the landing page
echo "Ensuring Firefox is focused..."
sleep 2

# Maximize Firefox
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true

# Take initial state screenshot
sleep 2
DISPLAY=:1 import -window root /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="
echo "Patient registrations table created with $RECORD_COUNT records"
echo "All records are unprocessed (processed = false)"
echo "Output directory: /opt/connect/outbound_hl7 (inside nextgen-connect container)"