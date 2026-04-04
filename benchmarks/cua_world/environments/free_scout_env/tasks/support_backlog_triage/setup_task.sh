#!/bin/bash
echo "=== Setting up support_backlog_triage task ==="

source /workspace/scripts/task_utils.sh

# ---- Create General Support mailbox ----
MAILBOX_ID=$(ensure_mailbox_exists "General Support" "general@helpdesk.local")
if [ -z "$MAILBOX_ID" ]; then
    MAILBOX_ID=$(fs_query "SELECT id FROM mailboxes WHERE email='general@helpdesk.local' LIMIT 1" 2>/dev/null || echo "")
fi
echo "General Support mailbox ID: $MAILBOX_ID"

# ---- Get Admin User ID ----
ADMIN_ID=$(fs_query "SELECT id FROM users WHERE email='admin@helpdesk.local' LIMIT 1" 2>/dev/null || echo "1")
echo "Admin user ID: $ADMIN_ID"

# ---- Create Derek Thompson agent ----
DEREK_EXISTS=$(fs_query "SELECT id FROM users WHERE email='derek.thompson@helpdesk.local' LIMIT 1" 2>/dev/null || echo "")
if [ -z "$DEREK_EXISTS" ]; then
    fs_tinker "
\$u = new \\App\\User();
\$u->first_name = 'Derek';
\$u->last_name = 'Thompson';
\$u->email = 'derek.thompson@helpdesk.local';
\$u->password = bcrypt('Agent123!');
\$u->role = 2;
\$u->status = 1;
\$u->save();
echo 'DEREK_ID:' . \$u->id;
" 2>/dev/null || true
fi
DEREK_ID=$(fs_query "SELECT id FROM users WHERE email='derek.thompson@helpdesk.local' LIMIT 1" 2>/dev/null || echo "")
echo "Derek Thompson ID: $DEREK_ID"

# Assign Derek to General Support
if [ -n "$DEREK_ID" ] && [ -n "$MAILBOX_ID" ]; then
    CNT=$(fs_query "SELECT COUNT(*) FROM mailbox_user WHERE user_id=$DEREK_ID AND mailbox_id=$MAILBOX_ID" 2>/dev/null || echo "0")
    if [ "$CNT" = "0" ]; then
        fs_query "INSERT IGNORE INTO mailbox_user (mailbox_id, user_id) VALUES ($MAILBOX_ID, $DEREK_ID)" 2>/dev/null || true
    fi
fi

# =====================================================================
# SEED: 4 active conversations with NO agent replies
# Real data from Kaggle Customer Support Ticket Dataset
# =====================================================================

seed_customer_conv() {
    local FIRST="$1"
    local LAST="$2"
    local EMAIL="$3"
    local SUBJECT="$4"
    local BODY="$5"
    local STATUS="$6"   # 1=active, 3=closed

    # Customer
    local CUST_ID
    CUST_ID=$(fs_query "SELECT id FROM customers WHERE first_name='$FIRST' AND last_name='$LAST' LIMIT 1" 2>/dev/null || echo "")
    if [ -z "$CUST_ID" ]; then
        fs_query "INSERT INTO customers (first_name, last_name, created_at, updated_at) VALUES ('$FIRST', '$LAST', NOW(), NOW())" 2>/dev/null || true
        CUST_ID=$(fs_query "SELECT id FROM customers WHERE first_name='$FIRST' AND last_name='$LAST' ORDER BY id DESC LIMIT 1" 2>/dev/null || echo "")
        if [ -n "$CUST_ID" ]; then
            local EMAIL_EXISTS
            EMAIL_EXISTS=$(fs_query "SELECT COUNT(*) FROM emails WHERE customer_id=$CUST_ID AND email='$EMAIL'" 2>/dev/null || echo "0")
            if [ "$EMAIL_EXISTS" = "0" ]; then
                fs_query "INSERT INTO emails (customer_id, email) VALUES ($CUST_ID, '$EMAIL')" 2>/dev/null || true
            fi
        fi
    fi

    # Conversation
    local CONV_ID
    CONV_ID=$(fs_query "SELECT id FROM conversations WHERE subject='$SUBJECT' AND mailbox_id=$MAILBOX_ID LIMIT 1" 2>/dev/null || echo "")
    if [ -z "$CONV_ID" ]; then
        CONV_ID=$(create_conversation_via_orm "$SUBJECT" "$MAILBOX_ID" "$EMAIL" "${CUST_ID:-}" "$BODY")
        echo "Created conv '$SUBJECT' ID: $CONV_ID"
    fi

    # Set status and ensure unassigned
    if [ -n "$CONV_ID" ]; then
        fs_query "UPDATE conversations SET status=$STATUS, user_id=NULL WHERE id=$CONV_ID" 2>/dev/null || true
        # Delete any existing threads so it has no agent replies
        fs_query "DELETE FROM threads WHERE conversation_id=$CONV_ID AND type=2" 2>/dev/null || true
    fi
    echo "$CONV_ID"
}

# Active conversations with NO agent replies (4 conversations)
UNRESPONDED_1=$(seed_customer_conv "Jacqueline" "Wright" "donaldkeith@example.org" "Software installation failure" "I purchased Microsoft Surface last week and the software installation keeps failing. The setup wizard crashes at step 3 every time. I have tried reinstalling multiple times on different browsers but the same error occurs repeatedly." "1")

UNRESPONDED_2=$(seed_customer_conv "Denise" "Lee" "joelwilliams@example.com" "Refund request not processed" "I submitted a refund request for my Philips Hue Lights three weeks ago and have not received any confirmation or refund. My order number is PHL-2847. The lights stopped working after just two weeks of use." "1")

UNRESPONDED_3=$(seed_customer_conv "Sandra" "Barnes" "gwendolyn51@example.net" "Account login not working" "My Nest Thermostat account is completely inaccessible. After the last app update, I cannot log in at all. I have tried password reset but the reset email never arrives. I have checked spam and junk folders." "1")

UNRESPONDED_4=$(seed_customer_conv "Amy" "Hill" "medinasteven@example.net" "Subscription renewal error" "My Sony PlayStation subscription was supposed to auto-renew but I received a charge without the subscription being activated. I have been charged 59.99 but my account still shows as expired. Please advise." "1")

echo "Unresponded conversations: $UNRESPONDED_1 $UNRESPONDED_2 $UNRESPONDED_3 $UNRESPONDED_4"

# =====================================================================
# SEED: 3 active conversations WITH agent replies (already responded)
# =====================================================================

seed_responded_conv() {
    local FIRST="$1"
    local LAST="$2"
    local EMAIL="$3"
    local SUBJECT="$4"
    local BODY="$5"

    local CUST_ID
    CUST_ID=$(fs_query "SELECT id FROM customers WHERE first_name='$FIRST' AND last_name='$LAST' LIMIT 1" 2>/dev/null || echo "")
    if [ -z "$CUST_ID" ]; then
        fs_query "INSERT INTO customers (first_name, last_name, created_at, updated_at) VALUES ('$FIRST', '$LAST', NOW(), NOW())" 2>/dev/null || true
        CUST_ID=$(fs_query "SELECT id FROM customers WHERE first_name='$FIRST' AND last_name='$LAST' ORDER BY id DESC LIMIT 1" 2>/dev/null || echo "")
        if [ -n "$CUST_ID" ]; then
            local EMAIL_EXISTS
            EMAIL_EXISTS=$(fs_query "SELECT COUNT(*) FROM emails WHERE customer_id=$CUST_ID AND email='$EMAIL'" 2>/dev/null || echo "0")
            if [ "$EMAIL_EXISTS" = "0" ]; then
                fs_query "INSERT INTO emails (customer_id, email) VALUES ($CUST_ID, '$EMAIL')" 2>/dev/null || true
            fi
        fi
    fi

    local CONV_ID
    CONV_ID=$(fs_query "SELECT id FROM conversations WHERE subject='$SUBJECT' AND mailbox_id=$MAILBOX_ID LIMIT 1" 2>/dev/null || echo "")
    if [ -z "$CONV_ID" ]; then
        CONV_ID=$(create_conversation_via_orm "$SUBJECT" "$MAILBOX_ID" "$EMAIL" "${CUST_ID:-}" "$BODY")
    fi

    if [ -n "$CONV_ID" ]; then
        fs_query "UPDATE conversations SET status=1, user_id=$ADMIN_ID WHERE id=$CONV_ID" 2>/dev/null || true
        # Add an agent reply thread
        local AGENT_REPLY_EXISTS
        AGENT_REPLY_EXISTS=$(fs_query "SELECT COUNT(*) FROM threads WHERE conversation_id=$CONV_ID AND type=2" 2>/dev/null || echo "0")
        if [ "$AGENT_REPLY_EXISTS" = "0" ]; then
            fs_query "INSERT INTO threads (conversation_id, type, status, state, body, source_type, source_via, created_by_user_id, created_at, updated_at) VALUES ($CONV_ID, 2, 1, 3, 'We have received your request and are looking into this for you. We will follow up shortly.', 1, 2, $ADMIN_ID, NOW(), NOW())" 2>/dev/null || true
        fi
    fi
    echo "$CONV_ID"
}

RESPONDED_1=$(seed_responded_conv "Joseph" "Moreno" "mbrown@example.org" "Billing overcharge inquiry" "I believe I was overcharged on my last Nintendo Switch purchase. The invoice shows 299.99 but I should have been charged the promotional price of 249.99.")

RESPONDED_2=$(seed_responded_conv "Brandon" "Arnold" "davisjohn@example.net" "Password reset not received" "I requested a password reset for my Microsoft Xbox Controller account three days ago and still have not received the email. My registered email is davisjohn@example.net.")

RESPONDED_3=$(seed_responded_conv "Nicolas" "Wilson" "joshua24@example.com" "Shipping delay concern" "My Fitbit Versa Smartwatch order from three weeks ago has not arrived yet. The tracking number shows it left the warehouse but no further updates. Can you please investigate?")

echo "Responded conversations: $RESPONDED_1 $RESPONDED_2 $RESPONDED_3"

# =====================================================================
# SEED: 3 CLOSED conversations (mistakenly closed)
# =====================================================================

seed_closed_conv() {
    local FIRST="$1"
    local LAST="$2"
    local EMAIL="$3"
    local SUBJECT="$4"
    local BODY="$5"

    local CUST_ID
    CUST_ID=$(fs_query "SELECT id FROM customers WHERE first_name='$FIRST' AND last_name='$LAST' LIMIT 1" 2>/dev/null || echo "")
    if [ -z "$CUST_ID" ]; then
        fs_query "INSERT INTO customers (first_name, last_name, created_at, updated_at) VALUES ('$FIRST', '$LAST', NOW(), NOW())" 2>/dev/null || true
        CUST_ID=$(fs_query "SELECT id FROM customers WHERE first_name='$FIRST' AND last_name='$LAST' ORDER BY id DESC LIMIT 1" 2>/dev/null || echo "")
        if [ -n "$CUST_ID" ]; then
            local EMAIL_EXISTS
            EMAIL_EXISTS=$(fs_query "SELECT COUNT(*) FROM emails WHERE customer_id=$CUST_ID AND email='$EMAIL'" 2>/dev/null || echo "0")
            if [ "$EMAIL_EXISTS" = "0" ]; then
                fs_query "INSERT INTO emails (customer_id, email) VALUES ($CUST_ID, '$EMAIL')" 2>/dev/null || true
            fi
        fi
    fi

    local CONV_ID
    CONV_ID=$(fs_query "SELECT id FROM conversations WHERE subject='$SUBJECT' AND mailbox_id=$MAILBOX_ID LIMIT 1" 2>/dev/null || echo "")
    if [ -z "$CONV_ID" ]; then
        CONV_ID=$(create_conversation_via_orm "$SUBJECT" "$MAILBOX_ID" "$EMAIL" "${CUST_ID:-}" "$BODY")
    fi

    if [ -n "$CONV_ID" ]; then
        # Set to closed status (3)
        fs_query "UPDATE conversations SET status=3, user_id=NULL WHERE id=$CONV_ID" 2>/dev/null || true
    fi
    echo "$CONV_ID"
}

CLOSED_1=$(seed_closed_conv "William" "Dawson" "clopez@example.com" "Product defect report" "My Dyson Vacuum Cleaner stopped working after just two months. The motor makes a grinding noise and the suction has completely stopped. I need a replacement or repair under warranty.")

CLOSED_2=$(seed_closed_conv "Christina" "Dillon" "bradleyolson@example.org" "Invoice discrepancy" "The invoice I received for Microsoft Office does not match what was quoted to me. I was quoted 99.99 annually but billed 149.99. Please issue a corrected invoice.")

CLOSED_3=$(seed_closed_conv "Alexander" "Carroll" "bradleymark@example.com" "Warranty claim pending" "I submitted a warranty claim for my Autodesk AutoCAD license six weeks ago and have not heard back. The claim reference number is WC-48291. Please provide an update.")

echo "Closed conversations: $CLOSED_1 $CLOSED_2 $CLOSED_3"

# Clear cache
docker exec freescout-app php /www/html/artisan cache:clear 2>/dev/null || true

# ---- Record baseline state ----
INITIAL_TAGGED_COUNT=0
echo "$INITIAL_TAGGED_COUNT" > /tmp/initial_tagged_count
echo "$MAILBOX_ID" > /tmp/general_mailbox_id
echo "$ADMIN_ID" > /tmp/admin_user_id
echo "$DEREK_ID" > /tmp/derek_user_id

# Store unresponded conv IDs
echo "$UNRESPONDED_1,$UNRESPONDED_2,$UNRESPONDED_3,$UNRESPONDED_4" > /tmp/unresponded_conv_ids
echo "$CLOSED_1,$CLOSED_2,$CLOSED_3" > /tmp/closed_conv_ids

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# ---- Navigate Firefox to General Support mailbox ----
if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox "http://localhost:8080" > /tmp/firefox.log 2>&1 &
    sleep 5
fi
wait_for_window "firefox|mozilla|freescout" 30
focus_firefox
navigate_to_url "http://localhost:8080/mailbox/${MAILBOX_ID}"
sleep 3

take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="
echo "General Support mailbox ID: $MAILBOX_ID"
echo "Admin ID: $ADMIN_ID, Derek ID: $DEREK_ID"
echo "Unresponded convs: $UNRESPONDED_1 $UNRESPONDED_2 $UNRESPONDED_3 $UNRESPONDED_4"
echo "Closed convs: $CLOSED_1 $CLOSED_2 $CLOSED_3"
