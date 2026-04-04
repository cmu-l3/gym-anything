#!/bin/bash
# OpenSIS HTTP-based Installer
# Uses curl to POST form data to each installer step

set -e

BASE_URL="http://localhost/opensis"
INSTALL_URL="$BASE_URL/install"
COOKIE_FILE="/tmp/opensis_install_cookies.txt"

# Configuration
DB_SERVER="localhost"
DB_PORT="3306"
DB_USERNAME="root"
DB_PASSWORD=""  # Empty for default MariaDB root
DB_NAME="opensis"
SCHOOL_NAME="Demo School"
SCHOOL_START="08/01/2024"
SCHOOL_END="06/30/2025"
ADMIN_FIRST="Admin"
ADMIN_LAST="User"
ADMIN_MIDDLE=""
ADMIN_EMAIL="admin@school.edu"
ADMIN_USERNAME="admin"
ADMIN_PASSWORD="Admin@123"

echo "=== OpenSIS HTTP Installer ==="
rm -f "$COOKIE_FILE"

# Step 0: System Check - just get the page to start session
echo "Step 0: Initializing session..."
curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$INSTALL_URL/Step0.php" > /dev/null
curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$INSTALL_URL/SystemCheck.php" > /dev/null
curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$INSTALL_URL/Step1.php" > /dev/null
sleep 1

# Step 1: Database Credentials -> Ins1.php
# Form fields: server, port, addusername, addpassword, DB_Conn
echo "Step 1: Submitting database credentials..."
RESPONSE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
    -X POST "$INSTALL_URL/Ins1.php" \
    -d "server=$DB_SERVER" \
    -d "port=$DB_PORT" \
    -d "addusername=$DB_USERNAME" \
    -d "addpassword=$DB_PASSWORD" \
    -d "DB_Conn=Save+%26+Next" \
    -L)

# Check if redirected to Step2
if echo "$RESPONSE" | grep -qi "Database Selection\|Step2\|step2"; then
    echo "  Step 1 complete (moved to database selection)"
else
    echo "DEBUG Step 1 response:"
    echo "$RESPONSE" | head -20
fi
sleep 1

# Step 2: Create Database -> Ins2.php
# Form fields: db, data_choice (newdb or purgedb), Add_DB
echo "Step 2: Creating database '$DB_NAME'..."
RESPONSE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
    -X POST "$INSTALL_URL/Ins2.php" \
    -d "db=$DB_NAME" \
    -d "data_choice=newdb" \
    -d "Add_DB=Save+%26+Next" \
    -L)

# Wait for database creation
echo "  Waiting for database creation..."
sleep 10

# Check if moved to Step3
if echo "$RESPONSE" | grep -qi "School Information\|Step3\|step3"; then
    echo "  Step 2 complete (database created)"
else
    echo "DEBUG Step 2 response:"
    echo "$RESPONSE" | head -50
fi
sleep 1

# Step 3: School Information -> Ins3.php
# Form fields: school_name, start_school, end_school, sample_data (checkbox)
echo "Step 3: Submitting school information..."
RESPONSE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
    -X POST "$INSTALL_URL/Ins3.php" \
    -d "school_name=$SCHOOL_NAME" \
    -d "start_school=$SCHOOL_START" \
    -d "end_school=$SCHOOL_END" \
    -d "sample_data=Y" \
    -d "Add_School=Save+%26+Next" \
    -L)

# Wait for school setup
sleep 5

# Check if moved to Step4
if echo "$RESPONSE" | grep -qi "Admin Account\|Step4\|step4"; then
    echo "  Step 3 complete (school configured)"
else
    echo "DEBUG Step 3 response:"
    echo "$RESPONSE" | head -50
fi
sleep 1

# Step 4: Admin Account -> Ins4.php
# Form fields: first_name, last_name, middle_name, email, username, password, c_password
echo "Step 4: Creating admin account..."
RESPONSE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
    -X POST "$INSTALL_URL/Ins4.php" \
    -d "first_name=$ADMIN_FIRST" \
    -d "last_name=$ADMIN_LAST" \
    -d "middle_name=$ADMIN_MIDDLE" \
    -d "email=$ADMIN_EMAIL" \
    -d "username=$ADMIN_USERNAME" \
    -d "password=$ADMIN_PASSWORD" \
    -d "c_password=$ADMIN_PASSWORD" \
    -d "Add_Admin=Save+%26+Next" \
    -L)

sleep 2

# Check if moved to Step5
if echo "$RESPONSE" | grep -qi "Ready to Go\|Congratulations\|Step5\|step5"; then
    echo "  Step 4 complete (admin account created)"
else
    echo "DEBUG Step 4 response:"
    echo "$RESPONSE" | head -50
fi
sleep 1

# Step 5: Complete Installation
echo "Step 5: Completing installation..."
RESPONSE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$INSTALL_URL/Step5.php" 2>&1)

if echo "$RESPONSE" | grep -qi "Congratulations"; then
    echo "  Installation completed successfully!"
fi

# Verify Data.php was created
sleep 2
if [ -f "/var/www/html/opensis/Data.php" ]; then
    echo "  Data.php created successfully"
else
    echo "WARNING: Data.php not created, creating manually..."
    cat > /var/www/html/opensis/Data.php << EOF
<?php
\$DatabaseType = 'mysqli';
\$DatabaseServer = '$DB_SERVER';
\$DatabaseUsername = '$DB_USERNAME';
\$DatabasePassword = '$DB_PASSWORD';
\$DatabaseName = '$DB_NAME';
\$DatabasePort = '$DB_PORT';
?>
EOF
    chown www-data:www-data /var/www/html/opensis/Data.php
fi

# Verify login works
echo ""
echo "=== Verifying Installation ==="
echo "Testing login page..."
LOGIN_PAGE=$(curl -s "$BASE_URL/")
if echo "$LOGIN_PAGE" | grep -qi "username.*password\|login"; then
    echo "  Login page accessible!"
else
    echo "  WARNING: Login page may not be accessible"
fi

# Test database connection
echo "Testing database..."
if mysql -u root "$DB_NAME" -e "SELECT COUNT(*) FROM login_authentication WHERE username='$ADMIN_USERNAME'" 2>/dev/null | grep -q "1"; then
    echo "  Admin user found in database!"
else
    echo "  WARNING: Admin user not found in database"
    # Check if database exists
    if mysql -u root -e "SHOW DATABASES" 2>/dev/null | grep -q "$DB_NAME"; then
        echo "  Database exists, checking tables..."
        TABLE_COUNT=$(mysql -u root "$DB_NAME" -e "SHOW TABLES" 2>/dev/null | wc -l)
        echo "  Tables in database: $TABLE_COUNT"
    else
        echo "  Database does not exist!"
    fi
fi

echo ""
echo "=== Installation Complete ==="
echo "URL: $BASE_URL"
echo "Username: $ADMIN_USERNAME"
echo "Password: $ADMIN_PASSWORD"

rm -f "$COOKIE_FILE"
