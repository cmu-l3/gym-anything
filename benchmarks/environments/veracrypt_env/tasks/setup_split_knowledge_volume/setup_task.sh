#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Setting up Split Knowledge Volume Task ==="

# 1. Clean up previous run artifacts
echo "Cleaning up..."
rm -f /home/ga/Volumes/master_keys.hc 2>/dev/null || true
rm -rf /home/ga/Dept_IT /home/ga/Dept_Security /home/ga/Dept_Compliance /home/ga/Sensitive 2>/dev/null || true
veracrypt --text --dismount --non-interactive 2>/dev/null || true

# 2. Create Directory Structure
mkdir -p /home/ga/Dept_IT
mkdir -p /home/ga/Dept_Security
mkdir -p /home/ga/Dept_Compliance
mkdir -p /home/ga/Sensitive

# 3. Generate Keyfiles (Realistic Data)

# IT Token: Binary blob
echo "Generating IT Token..."
dd if=/dev/urandom of=/home/ga/Dept_IT/it_token.bin bs=2048 count=1 2>/dev/null

# Security Cert: Self-signed PEM
echo "Generating Security Cert..."
openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 \
    -subj "/C=US/ST=State/L=City/O=SecurityDept/CN=AuthToken" \
    -keyout /dev/null -out /home/ga/Dept_Security/sec_cert.pem 2>/dev/null

# Compliance Policy: PDF (using ImageMagick)
echo "Generating Compliance Policy PDF..."
convert -size 600x400 xc:white -font DejaVu-Sans -pointsize 24 -fill black \
    -draw "text 50,200 'OFFICIAL AUDIT POLICY - TOP SECRET'" \
    /home/ga/Dept_Compliance/audit_policy.pdf 2>/dev/null || \
    echo "Dummy PDF Content" > /home/ga/Dept_Compliance/audit_policy.pdf

# 4. Generate Sensitive Seed File
echo "Generating Master Seed..."
echo "e6c3109a9f4c330276a8b13d2f26b5278131317663473c241940af45953e5365" > /home/ga/Sensitive/master_seed.txt
chmod 600 /home/ga/Sensitive/master_seed.txt

# Set ownership
chown -R ga:ga /home/ga/Dept_* /home/ga/Sensitive

# Record start time
date +%s > /tmp/task_start_time.txt

# 5. Ensure VeraCrypt is running
if ! is_veracrypt_running; then
    echo "Starting VeraCrypt..."
    su - ga -c "DISPLAY=:1 veracrypt &"
    sleep 3
fi

if ! wait_for_window "VeraCrypt" 15; then
    echo "WARNING: VeraCrypt window may not be visible"
fi

# Focus VeraCrypt window
wid=$(get_veracrypt_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="