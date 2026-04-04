#!/bin/bash
echo "=== Setting up team_restructuring_and_permissions task ==="

source /workspace/scripts/task_utils.sh

# ---- Create 3 base mailboxes ----
GENERAL_MAILBOX_ID=$(ensure_mailbox_exists "General Support" "general@helpdesk.local")
if [ -z "$GENERAL_MAILBOX_ID" ]; then
    GENERAL_MAILBOX_ID=$(fs_query "SELECT id FROM mailboxes WHERE email='general@helpdesk.local' LIMIT 1" 2>/dev/null || echo "")
fi
echo "General Support mailbox ID: $GENERAL_MAILBOX_ID"

TECH_MAILBOX_ID=$(ensure_mailbox_exists "Technical Support" "techsupport@helpdesk.local")
if [ -z "$TECH_MAILBOX_ID" ]; then
    TECH_MAILBOX_ID=$(fs_query "SELECT id FROM mailboxes WHERE email='techsupport@helpdesk.local' LIMIT 1" 2>/dev/null || echo "")
fi
echo "Technical Support mailbox ID: $TECH_MAILBOX_ID"

BILLING_MAILBOX_ID=$(ensure_mailbox_exists "Billing Support" "billing@helpdesk.local")
if [ -z "$BILLING_MAILBOX_ID" ]; then
    BILLING_MAILBOX_ID=$(fs_query "SELECT id FROM mailboxes WHERE email='billing@helpdesk.local' LIMIT 1" 2>/dev/null || echo "")
fi
echo "Billing Support mailbox ID: $BILLING_MAILBOX_ID"

# ---- Create Agent 1: Alex Chen (access to all 3 existing mailboxes) ----
ALEX_EXISTS=$(fs_query "SELECT id FROM users WHERE email='alex.chen@helpdesk.local' LIMIT 1" 2>/dev/null || echo "")
if [ -z "$ALEX_EXISTS" ]; then
    fs_tinker "
\$u = new \\App\\User();
\$u->first_name = 'Alex';
\$u->last_name = 'Chen';
\$u->email = 'alex.chen@helpdesk.local';
\$u->password = bcrypt('Agent123!');
\$u->role = 2;
\$u->status = 1;
\$u->save();
echo 'ALEX_ID:' . \$u->id;
" 2>/dev/null || true
fi
ALEX_ID=$(fs_query "SELECT id FROM users WHERE email='alex.chen@helpdesk.local' LIMIT 1" 2>/dev/null || echo "")
echo "Alex Chen ID: $ALEX_ID"

# Grant Alex access to General, Technical, Billing (all 3)
for MBX_ID in "$GENERAL_MAILBOX_ID" "$TECH_MAILBOX_ID" "$BILLING_MAILBOX_ID"; do
    if [ -n "$ALEX_ID" ] && [ -n "$MBX_ID" ]; then
        CNT=$(fs_query "SELECT COUNT(*) FROM mailbox_user WHERE user_id=$ALEX_ID AND mailbox_id=$MBX_ID" 2>/dev/null || echo "0")
        if [ "$CNT" = "0" ]; then
            fs_query "INSERT IGNORE INTO mailbox_user (mailbox_id, user_id) VALUES ($MBX_ID, $ALEX_ID)" 2>/dev/null || true
        fi
    fi
done

# ---- Create Agent 2: Maria Rodriguez (access to General Support only) ----
MARIA_EXISTS=$(fs_query "SELECT id FROM users WHERE email='maria.rodriguez@helpdesk.local' LIMIT 1" 2>/dev/null || echo "")
if [ -z "$MARIA_EXISTS" ]; then
    fs_tinker "
\$u = new \\App\\User();
\$u->first_name = 'Maria';
\$u->last_name = 'Rodriguez';
\$u->email = 'maria.rodriguez@helpdesk.local';
\$u->password = bcrypt('Agent123!');
\$u->role = 2;
\$u->status = 1;
\$u->save();
echo 'MARIA_ID:' . \$u->id;
" 2>/dev/null || true
fi
MARIA_ID=$(fs_query "SELECT id FROM users WHERE email='maria.rodriguez@helpdesk.local' LIMIT 1" 2>/dev/null || echo "")
echo "Maria Rodriguez ID: $MARIA_ID"

# Grant Maria access to General Support only (remove from Technical/Billing if she has any)
if [ -n "$MARIA_ID" ]; then
    if [ -n "$GENERAL_MAILBOX_ID" ]; then
        CNT=$(fs_query "SELECT COUNT(*) FROM mailbox_user WHERE user_id=$MARIA_ID AND mailbox_id=$GENERAL_MAILBOX_ID" 2>/dev/null || echo "0")
        if [ "$CNT" = "0" ]; then
            fs_query "INSERT IGNORE INTO mailbox_user (mailbox_id, user_id) VALUES ($GENERAL_MAILBOX_ID, $MARIA_ID)" 2>/dev/null || true
        fi
    fi
    # Remove Technical and Billing access for Maria
    for MBX_ID in "$TECH_MAILBOX_ID" "$BILLING_MAILBOX_ID"; do
        if [ -n "$MBX_ID" ]; then
            fs_query "DELETE FROM mailbox_user WHERE user_id=$MARIA_ID AND mailbox_id=$MBX_ID" 2>/dev/null || true
        fi
    done
fi

# ---- Create 'vip' tag ----
VIP_TAG_EXISTS=$(fs_query "SELECT id FROM tags WHERE name='vip' LIMIT 1" 2>/dev/null || echo "")
if [ -z "$VIP_TAG_EXISTS" ]; then
    fs_query "INSERT INTO tags (name, created_at, updated_at) VALUES ('vip', NOW(), NOW())" 2>/dev/null || true
fi
VIP_TAG_ID=$(fs_query "SELECT id FROM tags WHERE name='vip' LIMIT 1" 2>/dev/null || echo "")
echo "VIP tag ID: $VIP_TAG_ID"

# ---- Seed VIP-tagged conversations (4 conversations) ----
seed_vip_conv() {
    local FIRST="$1"
    local LAST="$2"
    local EMAIL="$3"
    local SUBJECT="$4"
    local BODY="$5"
    local MAILBOX_ID="$6"

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
        echo "Created VIP conv '$SUBJECT' ID: $CONV_ID"
    fi

    # Apply 'vip' tag
    if [ -n "$CONV_ID" ] && [ -n "$VIP_TAG_ID" ]; then
        ALREADY_TAGGED=$(fs_query "SELECT COUNT(*) FROM conversation_tag WHERE conversation_id=$CONV_ID AND tag_id=$VIP_TAG_ID" 2>/dev/null || echo "0")
        if [ "$ALREADY_TAGGED" = "0" ]; then
            fs_query "INSERT INTO conversation_tag (conversation_id, tag_id) VALUES ($CONV_ID, $VIP_TAG_ID)" 2>/dev/null || true
        fi
    fi

    # Ensure unassigned
    [ -n "$CONV_ID" ] && fs_query "UPDATE conversations SET user_id=NULL WHERE id=$CONV_ID" 2>/dev/null || true

    echo "$CONV_ID"
}

VIP_CONV_1=$(seed_vip_conv "Marisa" "Obrien" "carrollallison@example.com" "Premium account migration request" "We are migrating from our legacy system to your enterprise platform and need assistance with the data migration process. We are a premium account holder and need dedicated support." "$GENERAL_MAILBOX_ID")
VIP_CONV_2=$(seed_vip_conv "Jessica" "Rios" "clarkeashley@example.com" "Enterprise API integration issue" "Our enterprise development team is experiencing issues with the API integration. The authentication endpoints are returning 403 errors intermittently. This is blocking our production deployment." "$GENERAL_MAILBOX_ID")
VIP_CONV_3=$(seed_vip_conv "Christopher" "Robbins" "gonzalestracy@example.com" "SLA breach complaint" "We have been waiting for 5 business days for a resolution to our critical network issue. This is a clear SLA breach and we require immediate escalation to management." "$TECH_MAILBOX_ID")
VIP_CONV_4=$(seed_vip_conv "Tamara" "Hahn" "jensenwilliam@example.net" "Data export request" "We need to export all our data from the platform in CSV format for compliance audit purposes. This is an urgent request with a regulatory deadline in 48 hours." "$TECH_MAILBOX_ID")

echo "VIP conversations: $VIP_CONV_1 $VIP_CONV_2 $VIP_CONV_3 $VIP_CONV_4"

# ---- Seed 3 non-VIP conversations ----
NON_VIP_1_EXISTS=$(fs_query "SELECT id FROM conversations WHERE subject='Standard billing inquiry' AND mailbox_id=$BILLING_MAILBOX_ID LIMIT 1" 2>/dev/null || echo "")
if [ -z "$NON_VIP_1_EXISTS" ]; then
    create_conversation_via_orm "Standard billing inquiry" "$BILLING_MAILBOX_ID" "bradleyolson@example.org" "" "I have a question about my recent invoice. The line items do not seem to add up to the total amount charged." > /dev/null
fi

NON_VIP_2_EXISTS=$(fs_query "SELECT id FROM conversations WHERE subject='General product question' AND mailbox_id=$GENERAL_MAILBOX_ID LIMIT 1" 2>/dev/null || echo "")
if [ -z "$NON_VIP_2_EXISTS" ]; then
    create_conversation_via_orm "General product question" "$GENERAL_MAILBOX_ID" "clopez@example.com" "" "I would like to understand the difference between the Professional and Enterprise subscription tiers." > /dev/null
fi

NON_VIP_3_EXISTS=$(fs_query "SELECT id FROM conversations WHERE subject='Password reset issue' AND mailbox_id=$TECH_MAILBOX_ID LIMIT 1" 2>/dev/null || echo "")
if [ -z "$NON_VIP_3_EXISTS" ]; then
    create_conversation_via_orm "Password reset issue" "$TECH_MAILBOX_ID" "davisjohn@example.net" "" "I requested a password reset 2 hours ago and have not received the email. Please help me regain access to my account." > /dev/null
fi

# Clear cache
docker exec freescout-app php /www/html/artisan cache:clear 2>/dev/null || true

# ---- Record baseline state ----
INITIAL_MAILBOX_COUNT=$(fs_query "SELECT COUNT(*) FROM mailboxes" 2>/dev/null || echo "0")
INITIAL_SAVED_REPLY_COUNT=$(fs_query "SELECT COUNT(*) FROM saved_replies" 2>/dev/null || echo "0")

echo "$INITIAL_MAILBOX_COUNT" > /tmp/initial_mailbox_count_trp
echo "$INITIAL_SAVED_REPLY_COUNT" > /tmp/initial_saved_reply_count_trp
echo "$ALEX_ID" > /tmp/alex_user_id
echo "$MARIA_ID" > /tmp/maria_user_id
echo "$GENERAL_MAILBOX_ID" > /tmp/general_mailbox_id_trp
echo "$TECH_MAILBOX_ID" > /tmp/tech_mailbox_id_trp
echo "$BILLING_MAILBOX_ID" > /tmp/billing_mailbox_id_trp
echo "$VIP_TAG_ID" > /tmp/vip_tag_id
echo "$VIP_CONV_1,$VIP_CONV_2,$VIP_CONV_3,$VIP_CONV_4" > /tmp/vip_conv_ids

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Navigate to admin section
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
echo "General Mailbox: $GENERAL_MAILBOX_ID, Tech: $TECH_MAILBOX_ID, Billing: $BILLING_MAILBOX_ID"
echo "Alex ID: $ALEX_ID (access: General, Tech, Billing)"
echo "Maria ID: $MARIA_ID (access: General only)"
echo "VIP tag ID: $VIP_TAG_ID"
echo "VIP conversations: $VIP_CONV_1 $VIP_CONV_2 $VIP_CONV_3 $VIP_CONV_4"
