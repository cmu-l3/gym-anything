#!/bin/bash
set -e

echo "=== Setting up link_sibling_to_parent task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Database Credentials
DB_USER="opensis_user"
DB_PASS="opensis_password_123"
DB_NAME="opensis"
MYSQL_CMD="mysql -u $DB_USER -p$DB_PASS $DB_NAME -N -e"

# Ensure services are running
sudo systemctl start mariadb
sudo systemctl start apache2

# Wait for DB
for i in {1..30}; do
    if mysqladmin ping -u $DB_USER -p$DB_PASS --silent; then
        break
    fi
    sleep 1
done

echo "Setting up data..."

# 1. Clean up any previous run data
$MYSQL_CMD "DELETE FROM students WHERE last_name='Parr';" 2>/dev/null || true
$MYSQL_CMD "DELETE FROM student_parent WHERE parent_id IN (SELECT student_id FROM students WHERE last_name='Parr');" 2>/dev/null || true 
# Note: In some OpenSIS versions parents are in students table with a parent profile, or separate users table. 
# We will insert them into 'students' table if that's where people are, or 'users'.
# Standard OpenSIS often treats parents as people records linked via student_parent.

# 2. Insert Students (Violet and Dash)
# We assume grade_level_id 1 exists (from defaults)
echo "Creating students..."
$MYSQL_CMD "INSERT INTO students (first_name, last_name, date_of_birth, gender, grade_level, username, password) VALUES 
('Violet', 'Parr', '2008-05-15', 'Female', '10', 'violet.parr', 'password'),
('Dash', 'Parr', '2014-03-10', 'Male', '4', 'dash.parr', 'password');"

# Get IDs
VIOLET_ID=$($MYSQL_CMD "SELECT student_id FROM students WHERE first_name='Violet' AND last_name='Parr' LIMIT 1;")
DASH_ID=$($MYSQL_CMD "SELECT student_id FROM students WHERE first_name='Dash' AND last_name='Parr' LIMIT 1;")

echo "Violet ID: $VIOLET_ID"
echo "Dash ID: $DASH_ID"

# 3. Insert Parent (Robert Parr)
# In many OpenSIS installs, parents are in the 'students' table (people table) with a specific profile, 
# or in a dedicated 'users' table linked. We'll insert into students table as a 'Parent' type if that's the schema,
# or create a user record. 
# For OpenSIS Community, we typically create a record in `student_parent` table directly if it holds the data, 
# or create a person record.
# Let's assume standard behavior: Insert a person record for Robert.

$MYSQL_CMD "INSERT INTO students (first_name, last_name, gender, email) VALUES 
('Robert', 'Parr', 'Male', 'bob.parr@hero.net');"
ROBERT_ID=$($MYSQL_CMD "SELECT student_id FROM students WHERE first_name='Robert' AND last_name='Parr' LIMIT 1;")

echo "Robert ID: $ROBERT_ID"

# 4. Link Robert to Violet (Existing link)
# Check table structure for student_parent
# Columns typically: student_id, parent_id, relation...
$MYSQL_CMD "CREATE TABLE IF NOT EXISTS student_parent (
    student_id INT, 
    parent_id INT, 
    relation VARCHAR(50), 
    PRIMARY KEY(student_id, parent_id)
);"

$MYSQL_CMD "INSERT INTO student_parent (student_id, parent_id, relation) VALUES ($VIOLET_ID, $ROBERT_ID, 'Father');"

# 5. Record Initial State
# Count how many parents named "Robert Parr" exist (should be 1)
INITIAL_PARENT_COUNT=$($MYSQL_CMD "SELECT COUNT(*) FROM students WHERE first_name='Robert' AND last_name='Parr';")
echo "$INITIAL_PARENT_COUNT" > /tmp/initial_parent_count.txt
echo "Initial parent count: $INITIAL_PARENT_COUNT"

# 6. Setup Browser
echo "Launching browser..."
pkill -f chrome 2>/dev/null || true

if command -v google-chrome-stable &> /dev/null; then
    CHROME_CMD="google-chrome-stable"
else
    CHROME_CMD="chromium-browser"
fi

nohup sudo -u ga $CHROME_CMD \
    --no-first-run \
    --no-default-browser-check \
    --start-maximized \
    --password-store=basic \
    "http://localhost/opensis/" > /dev/null 2>&1 &

# Wait for window
for i in {1..30}; do
    if wmctrl -l | grep -qi "chrome\|chromium\|opensis"; then
        break
    fi
    sleep 1
done

# Focus and maximize
wmctrl -a "Chrome" 2>/dev/null || wmctrl -a "Chromium" 2>/dev/null || true
wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="