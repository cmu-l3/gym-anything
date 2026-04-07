#!/bin/bash
set -e
echo "=== Setting up Upload Student Document task ==="

# 1. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 2. Create dummy PDF transcript on Desktop
cat > /home/ga/Desktop/transcript_source.pdf << 'PDFEOF'
%PDF-1.4
1 0 obj <</Type /Catalog /Pages 2 0 R>> endobj
2 0 obj <</Type /Pages /Kids [3 0 R] /Count 1>> endobj
3 0 obj <</Type /Page /MediaBox [0 0 612 792] /Parent 2 0 R /Resources <<>> /Contents 4 0 R>> endobj
4 0 obj <</Length 55>> stream
BT /F1 24 Tf 100 700 Td (Official Transcript: Robert Transfer) Tj ET
endstream
endobj
xref
0 5
0000000000 65535 f
0000000010 00000 n
0000000060 00000 n
0000000117 00000 n
0000000220 00000 n
trailer <</Size 5 /Root 1 0 R>>
startxref
326
%%EOF
PDFEOF

# Ensure file permissions
chown ga:ga /home/ga/Desktop/transcript_source.pdf
chmod 644 /home/ga/Desktop/transcript_source.pdf

# 3. Ensure database and student exist
DB_USER="opensis_user"
DB_PASS="opensis_password_123"
DB_NAME="opensis"

# Wait for MariaDB
for i in {1..30}; do
    if mysqladmin ping -u "$DB_USER" -p"$DB_PASS" --silent; then
        break
    fi
    sleep 1
done

# Check if Robert Transfer exists
STUDENT_EXISTS=$(mysql -u $DB_USER -p"$DB_PASS" $DB_NAME -N -e "SELECT count(*) FROM students WHERE first_name='Robert' AND last_name='Transfer'" 2>/dev/null || echo "0")

if [ "$STUDENT_EXISTS" -eq "0" ]; then
    echo "Creating student Robert Transfer..."
    # Insert student (minimal required fields)
    mysql -u $DB_USER -p"$DB_PASS" $DB_NAME -e "
    INSERT INTO students (first_name, last_name, username, password, grade_level, is_active, gender) 
    VALUES ('Robert', 'Transfer', 'rtransfer', 'password123', '10', 'Y', 'M');
    " 2>/dev/null || true
fi

# 4. Ensure uploads directory is writable (common issue in LAMP)
# Try multiple potential locations for OpenSIS file storage
mkdir -p /var/www/html/opensis/files
mkdir -p /var/www/html/opensis/assets
mkdir -p /var/www/html/opensis/modules/students/student_files
chown -R www-data:www-data /var/www/html/opensis
chmod -R 775 /var/www/html/opensis/files 2>/dev/null || true
chmod -R 775 /var/www/html/opensis/assets 2>/dev/null || true

# 5. Open Chrome to Dashboard
pkill -f chrome 2>/dev/null || true
sleep 1

if command -v google-chrome-stable &> /dev/null; then
    CHROME_CMD="google-chrome-stable"
elif command -v chromium-browser &> /dev/null; then
    CHROME_CMD="chromium-browser"
else
    CHROME_CMD="chrome-browser"
fi

echo "Starting Chrome..."
su - ga -c "DISPLAY=:1 $CHROME_CMD --start-maximized --no-first-run --no-default-browser-check http://localhost/opensis/ &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Chrome\|Chromium"; then
        break
    fi
    sleep 1
done

# Focus window
DISPLAY=:1 wmctrl -a "Chrome" 2>/dev/null || true
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 6. Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="