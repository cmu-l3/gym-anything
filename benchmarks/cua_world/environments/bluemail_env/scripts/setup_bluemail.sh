#!/bin/bash
set -e

echo "=== Setting up BlueMail ==="

# Wait for desktop to be ready
sleep 5

# ============================================================
# Start Dovecot IMAP and Postfix SMTP servers
# ============================================================
echo "Starting mail servers..."
systemctl restart dovecot || dovecot 2>/dev/null || true
systemctl restart postfix || true

# Wait for mail servers to be ready
for i in $(seq 1 15); do
    if nc -z 127.0.0.1 993 2>/dev/null; then
        echo "Dovecot IMAP ready on port 993 (plain text)"
        break
    fi
    sleep 1
done

for i in $(seq 1 10); do
    if nc -z 127.0.0.1 587 2>/dev/null; then
        echo "Postfix SMTP ready on port 587"
        break
    fi
    sleep 1
done

# ============================================================
# Populate Maildir with real emails from SpamAssassin corpus
# ============================================================
echo "Importing real emails into Maildir..."

MAILDIR="/home/ga/Maildir"
mkdir -p "$MAILDIR/new" "$MAILDIR/cur" "$MAILDIR/tmp"
mkdir -p "$MAILDIR/.Junk/new" "$MAILDIR/.Junk/cur" "$MAILDIR/.Junk/tmp"
mkdir -p "$MAILDIR/.Drafts/new" "$MAILDIR/.Drafts/cur" "$MAILDIR/.Drafts/tmp"
mkdir -p "$MAILDIR/.Sent/new" "$MAILDIR/.Sent/cur" "$MAILDIR/.Sent/tmp"
mkdir -p "$MAILDIR/.Trash/new" "$MAILDIR/.Trash/cur" "$MAILDIR/.Trash/tmp"

cat > "$MAILDIR/subscriptions" << 'EOF'
Junk
Drafts
Sent
Trash
EOF

EMAIL_COUNT=0
if [ -d "/workspace/assets/emails/ham" ]; then
    for eml_file in /workspace/assets/emails/ham/*; do
        if [ -f "$eml_file" ] && [ $EMAIL_COUNT -lt 50 ]; then
            TIMESTAMP=$(date +%s)
            UNIQUE="${TIMESTAMP}.${EMAIL_COUNT}.$(hostname)"
            cp "$eml_file" "$MAILDIR/cur/${UNIQUE}:2,S"
            EMAIL_COUNT=$((EMAIL_COUNT + 1))
        fi
    done
    echo "Imported $EMAIL_COUNT ham emails into Inbox"
fi

SPAM_COUNT=0
if [ -d "/workspace/assets/emails/spam" ]; then
    for eml_file in /workspace/assets/emails/spam/*; do
        if [ -f "$eml_file" ] && [ $SPAM_COUNT -lt 20 ]; then
            TIMESTAMP=$(date +%s)
            UNIQUE="${TIMESTAMP}.spam${SPAM_COUNT}.$(hostname)"
            cp "$eml_file" "$MAILDIR/.Junk/cur/${UNIQUE}:2,S"
            SPAM_COUNT=$((SPAM_COUNT + 1))
        fi
    done
    echo "Imported $SPAM_COUNT spam emails into Junk"
fi

chown -R ga:ga "$MAILDIR"

# ============================================================
# Create desktop launcher and launch script
# ============================================================
mkdir -p /home/ga/Documents

cat > /home/ga/Desktop/bluemail.desktop << 'DESKTOP'
[Desktop Entry]
Name=BlueMail
Comment=Email Client
Exec=/opt/BlueMail/bluemail --no-sandbox
Icon=bluemail
StartupNotify=true
Terminal=false
Type=Application
Categories=Network;Email;
DESKTOP
chown ga:ga /home/ga/Desktop/bluemail.desktop
chmod +x /home/ga/Desktop/bluemail.desktop

cat > /home/ga/launch_bluemail.sh << 'LAUNCH'
#!/bin/bash
export DISPLAY=${DISPLAY:-:1}
xhost +local: 2>/dev/null || true
/opt/BlueMail/bluemail --no-sandbox > /tmp/bluemail_ga.log 2>&1 &
echo "BlueMail started"
LAUNCH
chown ga:ga /home/ga/launch_bluemail.sh
chmod +x /home/ga/launch_bluemail.sh

# ============================================================
# Launch BlueMail and automate first-run wizard
#
# All xdotool events must run as user ga in a single shell
# session so they are delivered correctly to the Electron app.
#
# Working configuration (verified interactively):
#   Email: ga@example.com
#   IMAP: localhost, Security=None, Port=993 (plain text via Dovecot ssl=no)
#   SMTP: localhost, Security=None, Port=587 (plain text)
#
# Coordinate system: 720p (1280x720) scaled to actual 1920x1080
#
# IMAP Settings page (720p coords):
#   Email Address:    (661, 290)
#   Username:         (661, 335)
#   Password:         (661, 380)
#   IMAP Server:      (661, 425)
#   Security:         (661, 470)  - dropdown
#   Authentication:   (590, 519)  - dropdown (left)
#   Port:             (728, 519)  - dropdown (right) - leave at 993
#   Next:             (663, 559)  - button
#
# SMTP (Outgoing) Settings page (720p coords):
#   Username:         (663, 276)  - pre-filled
#   Password:         (663, 321)  - pre-filled
#   SMTP server:      (663, 367)  - FILL with localhost
#   Security:         (663, 413)  - change to None
#   Authentication:   (591, 461)  - leave at AUTOMATIC
#   Port:             (732, 461)  - leave at 587
#   Require sign-in:  (539, 488)  - UNCHECK
#   Next:             (663, 559)  - button
#
# Almost Done page:
#   Name:             (663, 278)  - pre-filled with "ga"
#   Description:      (663, 364)  - pre-filled with "Example"
#   Next:             (663, 545)
#
# Customize BlueMail page:
#   Done:             (658, 544)
#
# Welcome to BlueMail overlay:
#   No thanks:        (547, 501)
# ============================================================
echo "Launching BlueMail for first-run setup..."

rm -rf /home/ga/.config/BlueMail 2>/dev/null || true
rm -rf /home/ga/.bluemail 2>/dev/null || true

# Write wizard automation script (runs entirely as user ga)
cat > /tmp/bluemail_wizard.sh << 'WIZEOF'
#!/bin/bash
export DISPLAY=:1

# Helper: click at 720p coordinates (scaled to actual 1920x1080)
click_720() {
    local x720=$1 y720=$2
    local x=$((x720 * 1920 / 1280))
    local y=$((y720 * 1080 / 720))
    xdotool mousemove $x $y
    sleep 0.3
    xdotool click 1
    sleep 0.5
}

# Helper: clear field and type text
clear_and_type() {
    xdotool key ctrl+a
    sleep 0.1
    xdotool key Delete
    sleep 0.1
    xdotool type --delay 30 "$1"
    sleep 0.3
}

# Launch BlueMail
/opt/BlueMail/bluemail --no-sandbox > /tmp/bluemail_ga.log 2>&1 &
BMPID=$!

# Wait for window
echo "Waiting for BlueMail window..."
ELAPSED=0
while [ $ELAPSED -lt 45 ]; do
    if xdotool search --name 'BlueMail' 2>/dev/null | head -1 | grep -q .; then
        echo "BlueMail window found after ${ELAPSED}s"
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done
sleep 5

# ---------------------------------------------------------------
# Step 1: Welcome screen -> Click "Continue"
# ---------------------------------------------------------------
echo "Step 1: Click Continue on Welcome screen"
click_720 663 399
sleep 4

# ---------------------------------------------------------------
# Step 2: Add Account -> Type email and click "Manual Setup"
# ---------------------------------------------------------------
echo "Step 2: Type email address"
click_720 663 259
sleep 0.5
xdotool type --delay 30 "ga@example.com"
sleep 1

echo "Step 2b: Click Manual Setup"
click_720 663 400
sleep 4

# ---------------------------------------------------------------
# Step 3: Choose Provider -> Click "Manual Setup" (bottom option)
# ---------------------------------------------------------------
echo "Step 3: Click Manual Setup on Choose Provider"
click_720 663 516
sleep 4

# ---------------------------------------------------------------
# Step 4: Manual Setup type -> Click "IMAP"
# ---------------------------------------------------------------
echo "Step 4: Click IMAP"
click_720 663 291
sleep 4

# ---------------------------------------------------------------
# Step 5: Fill IMAP (Incoming) Settings
# Port 993 is the default and Dovecot accepts plain text on it
# ---------------------------------------------------------------
echo "Step 5: Fill IMAP settings"

# Email Address (661, 290)
click_720 661 290
sleep 0.3
clear_and_type "ga@example.com"

# Username (661, 335)
click_720 661 335
sleep 0.3
clear_and_type "ga"

# Password (661, 380)
click_720 661 380
sleep 0.3
clear_and_type "password123"

# IMAP Server (661, 425)
click_720 661 425
sleep 0.3
clear_and_type "localhost"

# Security dropdown -> None (661, 470)
echo "Step 5b: Change Security to None"
click_720 661 470
sleep 1
xdotool key Home
sleep 0.3
xdotool key Return
sleep 1

# Leave Port at 993 (default) - Dovecot accepts plain text on 993
echo "Step 5c: Leaving Port=993 (plain text via Dovecot ssl=no)"

# Click Next (663, 559)
echo "Step 5d: Click Next for IMAP"
click_720 663 559
sleep 3

# Wait for IMAP connection attempt
echo "Waiting for IMAP connection (30s)..."
sleep 30

# ---------------------------------------------------------------
# Step 6: SMTP (Outgoing) Settings
# ---------------------------------------------------------------
echo "Step 6: Filling SMTP settings"

# SMTP Server (663, 367)
click_720 663 367
sleep 0.3
clear_and_type "localhost"

# Security dropdown -> None (663, 413)
echo "Step 6b: Change SMTP Security to None"
click_720 663 413
sleep 1
xdotool key Home
sleep 0.3
xdotool key Return
sleep 1

# Uncheck "Require sign-in" (539, 488)
echo "Step 6c: Uncheck Require sign-in"
click_720 539 488
sleep 0.5

# Leave Port at 587 (default) - Postfix listens on 587

# Click Next (663, 559)
echo "Step 6d: Click Next for SMTP"
click_720 663 559
sleep 3

# Wait for SMTP connection
echo "Waiting for SMTP connection (20s)..."
sleep 20

# ---------------------------------------------------------------
# Step 7: "You're almost done!" page -> Click Next
# ---------------------------------------------------------------
echo "Step 7: Almost done page - click Next"
click_720 663 545
sleep 5

# ---------------------------------------------------------------
# Step 8: "Customize BlueMail" dialog -> Click Done
# ---------------------------------------------------------------
echo "Step 8: Customize page - click Done"
click_720 658 544
sleep 5

# ---------------------------------------------------------------
# Step 9: "Welcome to BlueMail" overlay -> Click "No thanks"
# ---------------------------------------------------------------
echo "Step 9: Welcome overlay - click No thanks"
click_720 547 501
sleep 3

echo "Wizard automation complete"
WIZEOF
chmod +x /tmp/bluemail_wizard.sh

# Run wizard as user ga in a single session
su - ga -c "bash /tmp/bluemail_wizard.sh"

echo "=== BlueMail setup complete ==="
echo "Inbox emails: $EMAIL_COUNT"
echo "Junk emails: $SPAM_COUNT"
echo "IMAP: localhost:993 (plain text), SMTP: localhost:587 (plain text)"
