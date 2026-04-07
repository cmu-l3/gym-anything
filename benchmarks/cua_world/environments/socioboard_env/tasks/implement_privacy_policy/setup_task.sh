#!/bin/bash
echo "=== Setting up implement_privacy_policy task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time

# Wait for Socioboard to be ready
if ! wait_for_http "http://localhost/" 120; then
  echo "WARNING: Socioboard not reachable at http://localhost/"
fi

# Create the privacy policy text file
mkdir -p /home/ga/Documents
cat > /home/ga/Documents/privacy_policy.txt << 'EOF'
# Privacy Policy

**Effective Date:** January 1, 2024

Welcome to Apex Digital Media's Socioboard platform. We value your privacy and are committed to protecting your personal data. This Privacy Policy explains how we collect, use, disclose, and safeguard your information when you use our services.

## 1. Information We Collect
We collect personal data that you voluntarily provide to us when registering for the platform, including your name, email address, and social media authentication tokens.

## 2. GDPR compliance
In accordance with the General Data Protection Regulation (GDPR), we ensure that your personal data is processed lawfully, fairly, and transparently. We only collect data for specified, explicit, and legitimate purposes.

## 3. Your Rights
Under GDPR, you have several rights regarding your personal data:
- **Right to Access:** You can request a copy of the personal data we hold about you.
- **Right to Rectification:** You can request that we correct any inaccurate or incomplete personal data.
- **Right to Erasure:** You have the "right to be forgotten" and can request the deletion of your personal data under certain circumstances.

## 4. Contact Us
If you have any questions about this Privacy Policy or our data practices, please contact our Data Protection Officer at dpo@apexdigitalmedia.com.
EOF

chown ga:ga /home/ga/Documents/privacy_policy.txt

# Clear Laravel caches just in case
sudo -u ga bash -c 'cd /opt/socioboard/socioboard-web-php && php artisan route:clear 2>/dev/null || true'
sudo -u ga bash -c 'cd /opt/socioboard/socioboard-web-php && php artisan view:clear 2>/dev/null || true'

# Navigate Firefox to the home page
navigate_to "http://localhost/"
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_start.png
log "Task start screenshot saved: /tmp/task_start.png"
echo "=== Task setup complete ==="