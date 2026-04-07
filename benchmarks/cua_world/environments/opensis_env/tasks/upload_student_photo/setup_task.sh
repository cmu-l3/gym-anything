#!/bin/bash
set -e
echo "=== Setting up task: upload_student_photo ==="

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# Ensure Services are running
systemctl start mariadb 2>/dev/null || systemctl start mysql 2>/dev/null || true
systemctl start apache2 2>/dev/null || true
sleep 2

# Wait for MariaDB
for i in {1..30}; do
    if mysqladmin ping -h localhost --silent 2>/dev/null; then
        break
    fi
    sleep 1
done

# Database Credentials
DB_USER="opensis_user"
DB_PASS="opensis_password_123"
DB_NAME="opensis"

# Determine SYEAR
CURRENT_YEAR=$(date +%Y)
CURRENT_MONTH=$(date +%m)
if [ "$CURRENT_MONTH" -ge 8 ]; then
    SYEAR=$((CURRENT_YEAR + 1))
else
    SYEAR=$CURRENT_YEAR
fi

# 1. Create the dummy photo file
mkdir -p /home/ga/Documents
if command -v convert >/dev/null 2>&1; then
    # Create a placeholder face using ImageMagick
    convert -size 300x400 xc:lightblue \
        -fill darkblue -draw "circle 150,150 150,250" \
        -fill darkblue -draw "circle 150,350 150,150" \
        -pointsize 30 -fill white -gravity center -annotate +0+0 "Jason Miller" \
        /home/ga/Documents/jason_miller.jpg
else
    # Fallback: Create a text file but give it a valid JPEG header to pass basic validation
    echo -n -e '\xff\xd8\xff\xe0\x00\x10\x4a\x46\x49\x46\x00\x01' > /home/ga/Documents/jason_miller.jpg
    echo "Placeholder image data" >> /home/ga/Documents/jason_miller.jpg
fi
chown ga:ga /home/ga/Documents/jason_miller.jpg
chmod 644 /home/ga/Documents/jason_miller.jpg

# 2. Reset Student "Jason Miller"
# We delete him and recreate him to ensure a clean state (photo=NULL)
mysql -u $DB_USER -p"$DB_PASS" $DB_NAME -e "DELETE FROM students WHERE first_name='Jason' AND last_name='Miller'" 2>/dev/null || true

# Insert Jason Miller
# Note: school_id=1 is standard for the default install
mysql -u $DB_USER -p"$DB_PASS" $DB_NAME <<EOF
INSERT INTO students (
    first_name, last_name, username, password, 
    grade_level, gender, ethnicity, 
    birthdate, language, 
    address_id, school_id, is_active, photo
) VALUES (
    'Jason', 'Miller', 'jmiller', 'password123',
    '10', 'Male', 'White',
    '2008-05-15', 'English',
    0, 1, 'Y', NULL
);

-- Enroll him to make him visible
SET @student_id = LAST_INSERT_ID();
INSERT INTO student_enrollment (
    student_id, school_id, syear, grade_id, 
    enrollment_code, start_date, end_date
) VALUES (
    @student_id, 1, $SYEAR, 2, 
    1, CURDATE(), NULL
);
EOF

# 3. Record Initial State
INITIAL_PHOTO=$(mysql -u $DB_USER -p"$DB_PASS" $DB_NAME -N -e "SELECT photo FROM students WHERE first_name='Jason' AND last_name='Miller'" 2>/dev/null || echo "NULL")
echo "$INITIAL_PHOTO" > /tmp/initial_photo_state.txt
echo "Initial Photo State recorded: $INITIAL_PHOTO"

# 4. Launch Chrome
if ! pgrep -f "chrome" > /dev/null; then
    su - ga -c "google-chrome-stable --no-sandbox --disable-gpu --start-maximized http://localhost/opensis/ &"
    sleep 5
fi

# Maximize Window
DISPLAY=:1 wmctrl -r "Chrome" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="