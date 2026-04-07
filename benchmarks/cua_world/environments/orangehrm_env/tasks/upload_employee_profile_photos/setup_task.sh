#!/bin/bash
set -e
echo "=== Setting up upload_employee_profile_photos task ==="

source /workspace/scripts/task_utils.sh

# 1. Record start time
date +%s > /tmp/task_start_time.txt

# 2. Wait for OrangeHRM
wait_for_http "$ORANGEHRM_URL" 60

# 3. Prepare Employee Data (Seed James Carter and Linda Chen)
echo "Seeding employees..."

# Function to ensure employee exists
ensure_employee() {
    local fname="$1"
    local lname="$2"
    local emp_id="$3"
    
    # Check if exists
    local exists
    exists=$(orangehrm_db_query "SELECT count(*) FROM hs_hr_employee WHERE emp_firstname='$fname' AND emp_lastname='$lname' AND purged_at IS NULL;" 2>/dev/null | tr -d '[:space:]')
    
    if [ "$exists" -eq "0" ]; then
        echo "Creating employee: $fname $lname"
        # Insert minimal employee record
        orangehrm_db_query "INSERT INTO hs_hr_employee (emp_firstname, emp_lastname, employee_id, emp_status) VALUES ('$fname', '$lname', '$emp_id', 1);"
    else
        echo "Employee $fname $lname already exists."
    fi

    # Get emp_number
    local emp_num
    emp_num=$(orangehrm_db_query "SELECT emp_number FROM hs_hr_employee WHERE emp_firstname='$fname' AND emp_lastname='$lname' AND purged_at IS NULL LIMIT 1;" 2>/dev/null | tr -d '[:space:]')
    
    # clear any existing photo
    if [ -n "$emp_num" ]; then
        orangehrm_db_query "DELETE FROM hs_hr_emp_picture WHERE emp_number=$emp_num;"
    fi
}

ensure_employee "James" "Carter" "EMP090"
ensure_employee "Linda" "Chen" "EMP091"

# 4. Prepare Photo Data (Download real looking portraits)
PHOTO_DIR="/home/ga/Documents/Photos"
mkdir -p "$PHOTO_DIR"
chown ga:ga "$PHOTO_DIR"

echo "Downloading source photos..."
# Using reliable randomuser.me portraits
wget -O "$PHOTO_DIR/james_carter.jpg" "https://randomuser.me/api/portraits/men/32.jpg"
wget -O "$PHOTO_DIR/linda_chen.jpg" "https://randomuser.me/api/portraits/women/44.jpg"

chown ga:ga "$PHOTO_DIR"/*.jpg

# 5. Record Initial State (Employee list counts)
INITIAL_COUNT=$(get_employee_count)
echo "$INITIAL_COUNT" > /tmp/initial_count.txt

# 6. Launch Application
TARGET_URL="${ORANGEHRM_URL}/web/index.php/pim/viewEmployeeList"
ensure_orangehrm_logged_in "$TARGET_URL"

# 7. Take initial screenshot
sleep 5
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="