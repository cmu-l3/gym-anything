#!/bin/bash
echo "=== Setting up enterprise_support_onboarding task ==="

source /workspace/scripts/task_utils.sh

# ---- Real customer data from Kaggle Customer Support Ticket Dataset ----
# (chiapudding/kaggle-customer-service on HuggingFace/Kaggle)

# Technical Support mailbox customers (5 conversations)
TECH_CUSTOMERS=(
    "Marisa Obrien|carrollallison@example.com|Product setup|I'm having an issue with my GoPro Hero. The device won't connect to the app after the latest firmware update. I've tried reinstalling the app and restarting the device but the problem persists."
    "Jessica Rios|clarkeashley@example.com|Peripheral compatibility|I'm having trouble getting my LG Smart TV to recognize external peripherals. The USB ports are not detecting connected devices. I've tried different cables and devices with no success."
    "Christopher Robbins|gonzalestracy@example.com|Network problem|My Dell XPS laptop is experiencing intermittent network drops. It randomly loses WiFi connection even when other devices on the network work fine. The issue started after a recent Windows update."
    "Nicolas Wilson|joshua24@example.com|Installation support|I purchased the Fitbit Versa Smartwatch last month and I'm having trouble with the installation of the companion app on my Android phone. The setup wizard keeps crashing at the sync step."
    "Tamara Hahn|jensenwilliam@example.net|Hardware issue|My Nintendo Switch Pro Controller is not being recognized by the console. The controller was working fine until last week. I've tried different USB cables and ports with no resolution."
)

# Billing Support mailbox customers (3 conversations)
BILLING_CUSTOMERS=(
    "Christina Dillon|bradleyolson@example.org|Account access|I'm having trouble accessing my Microsoft Office account. I was charged for a renewal but my account shows as expired. Please investigate the billing discrepancy."
    "Alexander Carroll|bradleymark@example.com|Data loss|I purchased Autodesk AutoCAD last month and noticed I was charged twice. I need a refund for the duplicate charge as soon as possible."
    "William Dawson|clopez@example.com|Payment issue|I was charged an incorrect amount for my Dyson Vacuum Cleaner warranty extension. The charge was 50 dollars more than the quoted price. Please process a correction."
)

# ---- Create Technical Support mailbox ----
TECH_MAILBOX_ID=$(ensure_mailbox_exists "Technical Support" "techsupport@helpdesk.local")
if [ -z "$TECH_MAILBOX_ID" ]; then
    TECH_MAILBOX_ID=$(fs_query "SELECT id FROM mailboxes WHERE email='techsupport@helpdesk.local' LIMIT 1" 2>/dev/null || echo "")
fi
echo "Technical Support mailbox ID: $TECH_MAILBOX_ID"

# ---- Create Billing Support mailbox ----
BILLING_MAILBOX_ID=$(ensure_mailbox_exists "Billing Support" "billing@helpdesk.local")
if [ -z "$BILLING_MAILBOX_ID" ]; then
    BILLING_MAILBOX_ID=$(fs_query "SELECT id FROM mailboxes WHERE email='billing@helpdesk.local' LIMIT 1" 2>/dev/null || echo "")
fi
echo "Billing Support mailbox ID: $BILLING_MAILBOX_ID"

# ---- Create pre-existing agent Sarah Mitchell ----
SARAH_EXISTS=$(fs_query "SELECT id FROM users WHERE email='sarah.mitchell@helpdesk.local' LIMIT 1" 2>/dev/null || echo "")
if [ -z "$SARAH_EXISTS" ]; then
    fs_tinker "
\$u = new \\App\\User();
\$u->first_name = 'Sarah';
\$u->last_name = 'Mitchell';
\$u->email = 'sarah.mitchell@helpdesk.local';
\$u->password = bcrypt('Agent123!');
\$u->role = 2;
\$u->status = 1;
\$u->save();
echo 'SARAH_ID:' . \$u->id;
" 2>/dev/null || true
fi
SARAH_ID=$(fs_query "SELECT id FROM users WHERE email='sarah.mitchell@helpdesk.local' LIMIT 1" 2>/dev/null || echo "")
echo "Sarah Mitchell ID: $SARAH_ID"

# Assign Sarah to Billing Support only (not Technical Support)
if [ -n "$SARAH_ID" ] && [ -n "$BILLING_MAILBOX_ID" ]; then
    SARAH_IN_BILLING=$(fs_query "SELECT COUNT(*) FROM mailbox_user WHERE user_id=$SARAH_ID AND mailbox_id=$BILLING_MAILBOX_ID" 2>/dev/null || echo "0")
    if [ "$SARAH_IN_BILLING" = "0" ]; then
        fs_query "INSERT IGNORE INTO mailbox_user (mailbox_id, user_id) VALUES ($BILLING_MAILBOX_ID, $SARAH_ID)" 2>/dev/null || true
    fi
fi

# ---- Seed Technical Support conversations (5 conversations) ----
TECH_CONV_IDS=()
for ENTRY in "${TECH_CUSTOMERS[@]}"; do
    IFS='|' read -r CUST_NAME CUST_EMAIL SUBJECT BODY <<< "$ENTRY"
    FIRST=$(echo "$CUST_NAME" | cut -d' ' -f1)
    LAST=$(echo "$CUST_NAME" | cut -d' ' -f2-)

    # Create customer if not exists
    CUST_EXISTS=$(fs_query "SELECT id FROM customers WHERE first_name='$FIRST' AND last_name='$LAST' LIMIT 1" 2>/dev/null || echo "")
    if [ -z "$CUST_EXISTS" ]; then
        fs_query "INSERT INTO customers (first_name, last_name, created_at, updated_at) VALUES ('$FIRST', '$LAST', NOW(), NOW())" 2>/dev/null || true
        CUST_ID=$(fs_query "SELECT id FROM customers WHERE first_name='$FIRST' AND last_name='$LAST' ORDER BY id DESC LIMIT 1" 2>/dev/null || echo "")
        if [ -n "$CUST_ID" ]; then
            EMAIL_EXISTS=$(fs_query "SELECT COUNT(*) FROM emails WHERE customer_id=$CUST_ID AND email='$CUST_EMAIL'" 2>/dev/null || echo "0")
            if [ "$EMAIL_EXISTS" = "0" ]; then
                fs_query "INSERT INTO emails (customer_id, email) VALUES ($CUST_ID, '$CUST_EMAIL')" 2>/dev/null || true
            fi
        fi
    else
        CUST_ID="$CUST_EXISTS"
    fi

    # Create conversation if not exists
    CONV_EXISTS=$(fs_query "SELECT id FROM conversations WHERE subject='$SUBJECT' AND mailbox_id=$TECH_MAILBOX_ID LIMIT 1" 2>/dev/null || echo "")
    if [ -z "$CONV_EXISTS" ]; then
        CONV_ID=$(create_conversation_via_orm "$SUBJECT" "$TECH_MAILBOX_ID" "$CUST_EMAIL" "$CUST_ID" "$BODY")
        echo "Created Technical conv '$SUBJECT' ID: $CONV_ID"
    else
        CONV_ID="$CONV_EXISTS"
        echo "Using existing Technical conv '$SUBJECT' ID: $CONV_ID"
    fi
    TECH_CONV_IDS+=("$CONV_ID")
done

# ---- Seed Billing Support conversations (3 conversations) ----
BILLING_CONV_IDS=()
for ENTRY in "${BILLING_CUSTOMERS[@]}"; do
    IFS='|' read -r CUST_NAME CUST_EMAIL SUBJECT BODY <<< "$ENTRY"
    FIRST=$(echo "$CUST_NAME" | cut -d' ' -f1)
    LAST=$(echo "$CUST_NAME" | cut -d' ' -f2-)

    # Create customer if not exists
    CUST_EXISTS=$(fs_query "SELECT id FROM customers WHERE first_name='$FIRST' AND last_name='$LAST' LIMIT 1" 2>/dev/null || echo "")
    if [ -z "$CUST_EXISTS" ]; then
        fs_query "INSERT INTO customers (first_name, last_name, created_at, updated_at) VALUES ('$FIRST', '$LAST', NOW(), NOW())" 2>/dev/null || true
        CUST_ID=$(fs_query "SELECT id FROM customers WHERE first_name='$FIRST' AND last_name='$LAST' ORDER BY id DESC LIMIT 1" 2>/dev/null || echo "")
        if [ -n "$CUST_ID" ]; then
            EMAIL_EXISTS=$(fs_query "SELECT COUNT(*) FROM emails WHERE customer_id=$CUST_ID AND email='$CUST_EMAIL'" 2>/dev/null || echo "0")
            if [ "$EMAIL_EXISTS" = "0" ]; then
                fs_query "INSERT INTO emails (customer_id, email) VALUES ($CUST_ID, '$CUST_EMAIL')" 2>/dev/null || true
            fi
        fi
    else
        CUST_ID="$CUST_EXISTS"
    fi

    CONV_EXISTS=$(fs_query "SELECT id FROM conversations WHERE subject='$SUBJECT' AND mailbox_id=$BILLING_MAILBOX_ID LIMIT 1" 2>/dev/null || echo "")
    if [ -z "$CONV_EXISTS" ]; then
        CONV_ID=$(create_conversation_via_orm "$SUBJECT" "$BILLING_MAILBOX_ID" "$CUST_EMAIL" "$CUST_ID" "$BODY")
        echo "Created Billing conv '$SUBJECT' ID: $CONV_ID"
    else
        CONV_ID="$CONV_EXISTS"
        echo "Using existing Billing conv '$SUBJECT' ID: $CONV_ID"
    fi
    BILLING_CONV_IDS+=("$CONV_ID")
done

# Clear caches
docker exec freescout-app php /www/html/artisan cache:clear 2>/dev/null || true

# ---- Record baseline state ----
INITIAL_MAILBOX_COUNT=$(fs_query "SELECT COUNT(*) FROM mailboxes" 2>/dev/null || echo "0")
INITIAL_USER_COUNT=$(fs_query "SELECT COUNT(*) FROM users" 2>/dev/null || echo "0")
INITIAL_SAVED_REPLY_COUNT=$(fs_query "SELECT COUNT(*) FROM saved_replies" 2>/dev/null || echo "0")

echo "$INITIAL_MAILBOX_COUNT" > /tmp/initial_mailbox_count
echo "$INITIAL_USER_COUNT" > /tmp/initial_user_count
echo "$INITIAL_SAVED_REPLY_COUNT" > /tmp/initial_saved_reply_count
echo "$TECH_MAILBOX_ID" > /tmp/tech_mailbox_id
echo "$BILLING_MAILBOX_ID" > /tmp/billing_mailbox_id

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# ---- Launch Firefox to FreeScout ----
if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox "http://localhost:8080" > /tmp/firefox.log 2>&1 &
    sleep 5
fi
wait_for_window "firefox|mozilla|freescout" 30
focus_firefox
navigate_to_url "http://localhost:8080"
sleep 3

take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="
echo "Technical Support mailbox ID: $TECH_MAILBOX_ID"
echo "Billing Support mailbox ID: $BILLING_MAILBOX_ID"
echo "Sarah Mitchell ID: $SARAH_ID"
echo "Initial mailbox count: $INITIAL_MAILBOX_COUNT"
echo "Initial user count: $INITIAL_USER_COUNT"
