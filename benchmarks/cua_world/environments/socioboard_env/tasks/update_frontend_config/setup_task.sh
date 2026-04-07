#!/bin/bash
echo "=== Setting up update_frontend_config task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

ENV_FILE="/opt/socioboard/socioboard-web-php/.env"
TEMPLATE_FILE="/opt/socioboard/socioboard-web-php/environmentfile.env"

# 1. Ensure the .env file exists
if [ ! -f "$ENV_FILE" ]; then
    if [ -f "$TEMPLATE_FILE" ]; then
        cp "$TEMPLATE_FILE" "$ENV_FILE"
    else
        echo "ERROR: Original env template not found!"
        exit 1
    fi
fi

# Ensure the agent has permission to edit the file
chmod 666 "$ENV_FILE"

# 2. Extract critical keys to save for verification (Hidden from agent)
APP_KEY=$(grep "^APP_KEY=" "$ENV_FILE" | cut -d'=' -f2-)
DB_PASSWORD=$(grep "^DB_PASSWORD=" "$ENV_FILE" | cut -d'=' -f2-)
APP_URL=$(grep "^APP_URL=" "$ENV_FILE" | cut -d'=' -f2-)

cat > /tmp/original_env_values.json << EOF
{
  "APP_KEY": "$APP_KEY",
  "DB_PASSWORD": "$DB_PASSWORD",
  "APP_URL": "$APP_URL"
}
EOF
chmod 444 /tmp/original_env_values.json

# 3. Ensure target fields exist and set them to known defaults
# (This forces the agent to actively make the changes rather than finding them pre-done)
for KEY in APP_NAME MAIL_DRIVER MAIL_HOST MAIL_PORT MAIL_USERNAME MAIL_PASSWORD MAIL_ENCRYPTION SESSION_LIFETIME; do
    if ! grep -q "^${KEY}=" "$ENV_FILE"; then
        echo "${KEY}=" >> "$ENV_FILE"
    fi
done

sed -i 's/^APP_NAME=.*/APP_NAME=Socioboard/' "$ENV_FILE"
sed -i 's/^MAIL_DRIVER=.*/MAIL_DRIVER=log/' "$ENV_FILE"
sed -i 's/^MAIL_HOST=.*/MAIL_HOST=smtp.mailtrap.io/' "$ENV_FILE"
sed -i 's/^MAIL_PORT=.*/MAIL_PORT=2525/' "$ENV_FILE"
sed -i 's/^MAIL_USERNAME=.*/MAIL_USERNAME=null/' "$ENV_FILE"
sed -i 's/^MAIL_PASSWORD=.*/MAIL_PASSWORD=null/' "$ENV_FILE"
sed -i 's/^MAIL_ENCRYPTION=.*/MAIL_ENCRYPTION=null/' "$ENV_FILE"
sed -i 's/^SESSION_LIFETIME=.*/SESSION_LIFETIME=120/' "$ENV_FILE"

# 4. Record baseline line count (for structural integrity check)
wc -l < "$ENV_FILE" > /tmp/baseline_line_count.txt

# 5. Launch applications
# Start Firefox pointed to Socioboard
if ! pgrep -f "firefox" > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox http://localhost/ &"
    sleep 5
fi

# Start a terminal emulator for the agent
if ! pgrep -f "gnome-terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga &"
    sleep 3
fi

# Maximize windows
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -r "Terminal" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="