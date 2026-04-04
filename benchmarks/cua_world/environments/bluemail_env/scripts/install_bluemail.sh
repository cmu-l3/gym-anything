#!/bin/bash
set -e

echo "=== Installing BlueMail and Mail Servers ==="

# Non-interactive apt
export DEBIAN_FRONTEND=noninteractive

# Update package lists
apt-get update

# Pre-configure postfix to avoid interactive prompts
debconf-set-selections <<< "postfix postfix/mailname string localhost"
debconf-set-selections <<< "postfix postfix/main_mailer_type string 'Local only'"

# Install BlueMail dependencies, GUI automation tools, Dovecot IMAP, and Postfix SMTP
apt-get install -y \
    wget \
    xdotool \
    wmctrl \
    scrot \
    python3-pip \
    python3-venv \
    jq \
    x11-utils \
    netcat-openbsd \
    libglib2.0-0 \
    libnotify4 \
    libnss3 \
    libxss1 \
    libxtst6 \
    libatk-bridge2.0-0 \
    libgtk-3-0 \
    libgbm1 \
    libasound2 \
    dovecot-imapd \
    dovecot-core \
    libnss3-tools \
    postfix \
    ffmpeg

# Download BlueMail .deb package
echo "Downloading BlueMail..."
cd /tmp
wget -q https://download.bluemail.me/BlueMail/deb/BlueMail.deb -O BlueMail.deb || {
    echo "Failed to download BlueMail from primary URL"
    exit 1
}

# Install BlueMail
echo "Installing BlueMail .deb package..."
apt-get install -y ./BlueMail.deb || {
    # Fix any broken dependencies
    apt-get install -f -y
    dpkg -i /tmp/BlueMail.deb
}

# Verify BlueMail installation
if [ -f /opt/BlueMail/bluemail ]; then
    echo "BlueMail binary found at /opt/BlueMail/bluemail"
else
    echo "ERROR: BlueMail binary not found at expected location"
    which bluemail 2>/dev/null && echo "BlueMail found at: $(which bluemail)"
    find / -name "bluemail" -type f 2>/dev/null | head -5
fi

# ============================================================
# Configure Dovecot IMAP server for local email
# ============================================================
echo "Configuring Dovecot IMAP server..."

# Configure Dovecot for plain-text auth on localhost (safe for local-only use)
cat > /etc/dovecot/conf.d/10-auth.conf << 'EOF'
disable_plaintext_auth = no
auth_mechanisms = plain login
!include auth-system.conf.ext
EOF

# Configure mail location to use Maildir format
cat > /etc/dovecot/conf.d/10-mail.conf << 'EOF'
mail_location = maildir:~/Maildir
namespace inbox {
  inbox = yes
}
EOF

# Disable SSL entirely - BlueMail connects to localhost, no encryption needed
# BlueMail defaults to port 993; with ssl=no, Dovecot accepts plain text on 993
cat > /etc/dovecot/conf.d/10-ssl.conf << 'EOF'
ssl = no
EOF

# Configure IMAP to listen on both 143 and 993 as plain text
# BlueMail's port dropdown defaults to 993 and is difficult to change,
# so we accept plain text on 993 (the traditional IMAPS port)
cat > /etc/dovecot/conf.d/10-master.conf << 'EOF'
service imap-login {
  inet_listener imap {
    address = 127.0.0.1
    port = 143
  }
  inet_listener imaps {
    address = 127.0.0.1
    port = 993
    ssl = no
  }
}
service auth {
  unix_listener auth-userdb {
    mode = 0600
    user = dovecot
  }
}
EOF

# Enable and start Dovecot
systemctl enable dovecot
systemctl restart dovecot || echo "Dovecot will start after full boot"

# Verify Dovecot is configured
dovecot --version && echo "Dovecot installed successfully"

# ============================================================
# Configure Postfix SMTP for local delivery only
# ============================================================
echo "Configuring Postfix SMTP server..."

# Configure postfix for local-only delivery
postconf -e "inet_interfaces = loopback-only"
postconf -e "mydestination = localhost, localhost.localdomain"
postconf -e "mynetworks = 127.0.0.0/8"
postconf -e "relayhost ="
postconf -e "home_mailbox = Maildir/"
postconf -e "smtpd_tls_security_level = none"
postconf -e "smtpd_use_tls = no"

# Enable submission (587) and smtps (465) ports in master.cf
# BlueMail defaults to port 587; we need these ports available
# Read the current master.cf and add submission/smtps lines after the smtp line
python3 << 'PYEOF'
import re

with open('/etc/postfix/master.cf', 'r') as f:
    content = f.read()

# Add submission and smtps entries if not already present
submission_block = """submission inet n       -       y       -       -       smtpd
  -o syslog_name=postfix/submission
  -o smtpd_tls_security_level=none
  -o smtpd_sasl_auth_enable=no
  -o smtpd_relay_restrictions=permit_mynetworks,reject
465       inet  n       -       y       -       -       smtpd
  -o syslog_name=postfix/smtps
  -o smtpd_tls_security_level=none
  -o smtpd_sasl_auth_enable=no
  -o smtpd_relay_restrictions=permit_mynetworks,reject"""

if 'submission inet' not in content:
    # Insert after the first "smtp      inet" line
    content = content.replace(
        'smtp      inet  n       -       y       -       -       smtpd\n',
        'smtp      inet  n       -       y       -       -       smtpd\n' + submission_block + '\n',
        1
    )

with open('/etc/postfix/master.cf', 'w') as f:
    f.write(content)

print("master.cf updated with submission (587) and smtps (465)")
PYEOF

systemctl enable postfix
systemctl restart postfix || echo "Postfix will start after full boot"

# Clean up
rm -f /tmp/BlueMail.deb
apt-get clean

echo "=== BlueMail and mail server installation complete ==="
