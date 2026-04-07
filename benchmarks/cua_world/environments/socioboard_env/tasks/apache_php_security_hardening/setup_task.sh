#!/bin/bash
echo "=== Setting up Apache & PHP Security Hardening Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for background installation if still running (Socioboard env specific)
if [ ! -f /tmp/socioboard_install_complete.marker ]; then
    echo "Waiting for Socioboard installation to finish..."
    for i in {1..60}; do
        if [ -f /tmp/socioboard_install_complete.marker ]; then break; fi
        sleep 5
    done
fi

# Ensure services are running
systemctl start apache2 2>/dev/null || true

echo "Configuring vulnerable state for the task..."

# 1. Ensure Apache leaks version info
if [ -f /etc/apache2/conf-available/security.conf ]; then
    sudo sed -i 's/^ServerTokens .*/ServerTokens OS/' /etc/apache2/conf-available/security.conf
    sudo sed -i 's/^ServerSignature .*/ServerSignature On/' /etc/apache2/conf-available/security.conf
fi

# 2. Ensure PHP leaks version info
if [ -f /etc/php/7.4/apache2/php.ini ]; then
    sudo sed -i 's/^expose_php = .*/expose_php = On/' /etc/php/7.4/apache2/php.ini
fi

# 3. Create a test directory to evaluate directory browsing
# We create it in /var/www/html which is universally served by default Apache
sudo mkdir -p /var/www/html/test_indexes
sudo bash -c 'echo "CRITICAL_SECRET_DATA_DO_NOT_EXPOSE" > /var/www/html/test_indexes/secret_file.txt'
sudo chmod 755 /var/www/html/test_indexes
sudo chmod 644 /var/www/html/test_indexes/secret_file.txt

# Ensure default Apache config allows directory indexes for /var/www/
sudo bash -c 'cat > /etc/apache2/conf-available/vulnerable_indexes.conf << EOF
<Directory /var/www/html/test_indexes>
    Options +Indexes
    Require all granted
</Directory>
EOF'
sudo a2enconf vulnerable_indexes 2>/dev/null || true

# Restart Apache to apply vulnerable settings
sudo systemctl restart apache2
sleep 2

# Verify vulnerable state internally before task begins
TEST_HEADERS=$(curl -s -I http://localhost/)
echo "Initial Headers:"
echo "$TEST_HEADERS" | grep -iE 'Server:|X-Powered-By:'

# Open a terminal for the user
echo "Opening terminal for agent..."
su - ga -c "DISPLAY=:1 gnome-terminal --maximize &"
sleep 2

# Focus the terminal
WID=$(DISPLAY=:1 wmctrl -l | grep -i "Terminal" | awk '{print $1}' | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

# Take initial screenshot
echo "Capturing initial screenshot..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="