#!/bin/bash
set -e

echo "=== Setting up Configure Compliance BCC Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Start FreeScout if not running
if ! pgrep -f "supervisord" > /dev/null; then
    echo "Starting FreeScout..."
    /workspace/scripts/setup_freescout.sh
fi

# 2. Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Prepare Database State using Tinker
# We need to ensure a clean state: 
# - Billing mailbox exists with specific SMTP settings and NO BCC
# - Support mailbox exists (decoy)

echo "Configuring mailboxes..."
fs_tinker "
// Setup Billing Mailbox
\$billing = \App\Mailbox::firstOrNew(['email' => 'billing@acme-finance.com']);
\$billing->name = 'Billing Department';
\$billing->email = 'billing@acme-finance.com';
\$billing->out_method = 2; // SMTP
\$billing->out_server = 'mail.acme-finance.com';
\$billing->out_port = 587;
\$billing->out_encryption = 'tls';
\$billing->out_username = 'billing@acme-finance.com';
// Encrypt a fake password so it looks real
\$billing->out_password = encrypt('SecretBillingPassword');
\$billing->bcc = null;
\$billing->save();

// Setup Support Mailbox (Decoy)
\$support = \App\Mailbox::firstOrNew(['email' => 'support@acme-finance.com']);
\$support->name = 'IT Support';
\$support->email = 'support@acme-finance.com';
\$support->bcc = null;
\$support->save();
"

# 4. Clear Cache to ensure DB changes are reflected
docker exec freescout-app php /www/html/artisan cache:clear 2>/dev/null || true

# 5. Launch Firefox and Login
echo "Launching Firefox..."
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080/login' > /tmp/firefox.log 2>&1 &"
    sleep 5
fi

# Wait for window
wait_for_window "firefox\|mozilla\|freescout" 60

# Maximize
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Perform Login
ensure_logged_in

# Navigate to Mailboxes page to save the agent a click (optional, but good for context)
navigate_to_url "http://localhost:8080/mailboxes"

# 6. Capture Initial State Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="