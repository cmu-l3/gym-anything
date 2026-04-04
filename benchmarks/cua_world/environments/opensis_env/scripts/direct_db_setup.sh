#!/bin/bash
# Direct OpenSIS Database Setup
# Based on actual table structures from OpenSIS v9.2 schema

set -e

OPENSIS_DIR="/var/www/html/opensis"
DB_NAME="opensis"
DB_USER="opensis_user"
DB_PASS="opensis_password_123"
ADMIN_USER="admin"
ADMIN_PASS="Admin@123"

# Calculate current school year (use current year for end date)
CURRENT_YEAR=$(date +%Y)
CURRENT_MONTH=$(date +%m)
# If we're in Aug-Dec, school year is CURRENT-NEXT, else PREV-CURRENT
if [ "$CURRENT_MONTH" -ge 8 ]; then
    SCHOOL_YEAR_START=$CURRENT_YEAR
    SCHOOL_YEAR_END=$((CURRENT_YEAR + 1))
else
    SCHOOL_YEAR_START=$((CURRENT_YEAR - 1))
    SCHOOL_YEAR_END=$CURRENT_YEAR
fi
SYEAR=$SCHOOL_YEAR_END  # OpenSIS uses the end year as SYEAR

echo "Using school year: ${SCHOOL_YEAR_START}-${SCHOOL_YEAR_END} (SYEAR=${SYEAR})"

# MySQL command wrapper
MYSQL_CMD="mysql"
if ! mysql -u root -e "SELECT 1" &>/dev/null; then
    MYSQL_CMD="sudo mysql"
fi

echo "=== Direct OpenSIS Database Setup ==="

# Create database and user
echo "Step 1: Creating database and user..."
$MYSQL_CMD << DBSETUP
DROP DATABASE IF EXISTS $DB_NAME;
CREATE DATABASE $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
DBSETUP
echo "  Database created: $DB_NAME"

# Import base schema
echo "Step 2: Importing database schema..."
if [ -f "$OPENSIS_DIR/install/OpensisSchemaMysqlInc.sql" ]; then
    $MYSQL_CMD $DB_NAME < "$OPENSIS_DIR/install/OpensisSchemaMysqlInc.sql" 2>/dev/null || true
    echo "  Base schema imported"
else
    echo "ERROR: Schema file not found!"
    exit 1
fi

# Import procedures and triggers
[ -f "$OPENSIS_DIR/install/OpensisProcsMysqlInc.sql" ] && $MYSQL_CMD $DB_NAME < "$OPENSIS_DIR/install/OpensisProcsMysqlInc.sql" 2>/dev/null || true
[ -f "$OPENSIS_DIR/install/OpensisTriggerMysqlInc.sql" ] && $MYSQL_CMD $DB_NAME < "$OPENSIS_DIR/install/OpensisTriggerMysqlInc.sql" 2>/dev/null || true
echo "  Procedures and triggers imported"

# Generate password hash
echo "Step 3: Generating password hash..."
PASS_HASH=$(php -r 'include "/var/www/html/opensis/functions/PasswordHashFnc.php"; echo GenerateNewHash("Admin@123");' 2>/dev/null)
if [ -z "$PASS_HASH" ]; then
    PASS_HASH=$(php -r 'echo password_hash("Admin@123", PASSWORD_BCRYPT);')
fi
echo "  Password hash generated"

# Insert essential data - using correct column names from actual schema
echo "Step 4: Inserting essential data..."
$MYSQL_CMD $DB_NAME << ESSENTIAL_DATA
-- App version
INSERT INTO app (name, value) VALUES
('version', '9.2'),
('date', 'January 2025'),
('build', '20250101001'),
('update', '0'),
('last_updated', 'January 2025')
ON DUPLICATE KEY UPDATE value=VALUES(value);

-- User profiles
INSERT INTO user_profiles (id, profile, title) VALUES
(1, 'admin', 'Administrator'),
(2, 'teacher', 'Teacher'),
(3, 'student', 'Student'),
(4, 'parent', 'Parent')
ON DUPLICATE KEY UPDATE profile=VALUES(profile);

-- School (using dynamic school year)
INSERT INTO schools (id, syear, title, address, city, state, zipcode, phone, reporting_gp_scale) VALUES
(1, $SYEAR, 'Demo School', '123 Main St', 'City', 'ST', '12345', '555-1234', 4.0)
ON DUPLICATE KEY UPDATE title=VALUES(title), syear=$SYEAR;

-- School year (marking period) - using dynamic dates that cover current date
INSERT INTO school_years (marking_period_id, syear, school_id, title, short_name, sort_order, start_date, end_date, does_grades, does_comments) VALUES
(1, $SYEAR, 1, '${SCHOOL_YEAR_START}-${SCHOOL_YEAR_END}', 'FY', 1, '${SCHOOL_YEAR_START}-08-01', '${SCHOOL_YEAR_END}-06-30', 'Y', 'Y')
ON DUPLICATE KEY UPDATE title=VALUES(title), syear=$SYEAR, start_date='${SCHOOL_YEAR_START}-08-01', end_date='${SCHOOL_YEAR_END}-06-30';

-- System preferences (correct columns: fail_count, activity_days, system_maintenance_switch)
INSERT INTO system_preference_misc (fail_count, activity_days, system_maintenance_switch) VALUES
(5, 90, 'N')
ON DUPLICATE KEY UPDATE fail_count=5;

-- Admin staff member (no syear column in staff table)
INSERT INTO staff (staff_id, current_school_id, title, first_name, last_name, email, profile, profile_id) VALUES
(1, 1, 'Mr.', 'Admin', 'User', 'admin@school.edu', 'admin', 1)
ON DUPLICATE KEY UPDATE first_name=VALUES(first_name);

-- Add USER_ID column if not exists
ALTER TABLE staff ADD COLUMN IF NOT EXISTS USER_ID int(11) DEFAULT NULL;
UPDATE staff SET USER_ID = 1, profile_id = 1 WHERE staff_id = 1;

-- Staff school info
INSERT INTO staff_school_info (staff_id, category, home_school, opensis_access, opensis_profile, school_access) VALUES
(1, 'Administrator', 1, 'Y', 'admin', 'Y')
ON DUPLICATE KEY UPDATE opensis_access='Y', opensis_profile='admin';

-- Staff school relationship (CRITICAL: links staff to school for queries)
INSERT INTO staff_school_relationship (staff_id, school_id, syear) VALUES
(1, 1, $SYEAR)
ON DUPLICATE KEY UPDATE syear=$SYEAR;

-- Login authentication (correct columns: user_id, profile_id, username, password, failed_login)
INSERT INTO login_authentication (user_id, profile_id, username, password, last_login, failed_login) VALUES
(1, 1, '$ADMIN_USER', '$PASS_HASH', NOW(), 0)
ON DUPLICATE KEY UPDATE password='$PASS_HASH', profile_id=1, failed_login=0;

-- Profile exceptions (module permissions)
INSERT INTO profile_exceptions (profile_id, modname, can_use, can_edit) VALUES
(1, 'miscellaneous/Portal.php', 'Y', 'Y'),
(1, 'students/Student.php', 'Y', 'Y'),
(1, 'students/Student.php&include=GeneralInfoInc&student_id=new', 'Y', 'Y'),
(1, 'students/Search.php', 'Y', 'Y'),
(1, 'attendance/TakeAttendance.php', 'Y', 'Y'),
(1, 'grades/Grades.php', 'Y', 'Y'),
(1, 'scheduling/Courses.php', 'Y', 'Y'),
(1, 'schoolsetup/Schools.php', 'Y', 'Y'),
(1, 'users/User.php', 'Y', 'Y')
ON DUPLICATE KEY UPDATE can_use='Y', can_edit='Y';

-- Grade levels
INSERT INTO school_gradelevels (id, school_id, short_name, title, sort_order) VALUES
(1, 1, '9', 'Grade 9', 1),
(2, 1, '10', 'Grade 10', 2),
(3, 1, '11', 'Grade 11', 3),
(4, 1, '12', 'Grade 12', 4)
ON DUPLICATE KEY UPDATE title=VALUES(title);

ESSENTIAL_DATA
echo "  Essential data inserted"

# Create Data.php
echo "Step 5: Creating Data.php..."
cat > "$OPENSIS_DIR/Data.php" << 'DATAPHP'
<?php
$DatabaseType = 'mysqli';
$DatabaseServer = 'localhost';
$DatabaseUsername = 'opensis_user';
$DatabasePassword = 'opensis_password_123';
$DatabaseName = 'opensis';
$DatabasePort = '3306';
?>
DATAPHP
chown www-data:www-data "$OPENSIS_DIR/Data.php"
chmod 644 "$OPENSIS_DIR/Data.php"
echo "  Data.php created"

# Verify
echo ""
echo "=== Verification ==="
TABLE_COUNT=$($MYSQL_CMD $DB_NAME -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$DB_NAME'" 2>/dev/null || echo "0")
echo "Tables: $TABLE_COUNT"

ADMIN_EXISTS=$($MYSQL_CMD $DB_NAME -N -e "SELECT COUNT(*) FROM login_authentication WHERE username='$ADMIN_USER' AND profile_id=1" 2>/dev/null || echo "0")
echo "Admin user: $ADMIN_EXISTS"

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/opensis/ 2>/dev/null || echo "000")
echo "HTTP status: $HTTP_CODE"

echo ""
echo "=== Setup Complete ==="
echo "URL: http://localhost/opensis"
echo "Username: $ADMIN_USER"
echo "Password: $ADMIN_PASS"
