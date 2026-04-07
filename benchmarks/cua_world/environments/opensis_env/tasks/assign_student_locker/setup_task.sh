#!/bin/bash
set -e

echo "=== Setting up assign_student_locker task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Database credentials
DB_USER="opensis_user"
DB_PASS="opensis_password_123"
DB_NAME="opensis"

# Ensure services are running
sudo systemctl start mariadb || sudo systemctl start mysql
sudo systemctl start apache2

# Wait for database
until mysql -u"$DB_USER" -p"$DB_PASS" -e "SELECT 1" &>/dev/null; do
    echo "Waiting for database..."
    sleep 2
done

# 1. Ensure the 'students' table has a 'locker_number' column.
# In some OpenSIS versions this is standard, in others custom. We force it for this task.
mysql -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "
    ALTER TABLE students ADD COLUMN IF NOT EXISTS locker_number VARCHAR(50) DEFAULT NULL;
" 2>/dev/null || true

# 2. Create target student 'Kenny McCormick' if not exists
# We use INSERT IGNORE or checking existence to avoid duplicates
echo "Creating/Resetting student Kenny McCormick..."
mysql -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "
    INSERT INTO students (first_name, last_name, gender, grade_level, is_active)
    SELECT 'Kenny', 'McCormick', 'Male', '10', 'Y'
    WHERE NOT EXISTS (
        SELECT 1 FROM students WHERE first_name='Kenny' AND last_name='McCormick'
    );
"

# 3. CRITICAL: Clear any existing locker assignment for this student
# This ensures the agent must perform the action to pass (anti-gaming)
mysql -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "
    UPDATE students 
    SET locker_number = NULL 
    WHERE first_name='Kenny' AND last_name='McCormick';
"

# 4. Record initial state (should be NULL/empty)
INITIAL_LOCKER=$(mysql -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" -N -e "
    SELECT locker_number FROM students WHERE first_name='Kenny' AND last_name='McCormick';
")
echo "Initial locker state: '$INITIAL_LOCKER'"

# 5. Launch Chrome
if ! pgrep -f "chrome" > /dev/null; then
    echo "Starting Chrome..."
    su - ga -c "DISPLAY=:1 google-chrome-stable --start-maximized --no-sandbox --disable-gpu http://localhost/opensis/ &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "Chrome"; then
            echo "Chrome window detected."
            break
        fi
        sleep 1
    done
    
    # Maximize and focus
    DISPLAY=:1 wmctrl -r "Chrome" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -a "Chrome" 2>/dev/null || true
fi

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="