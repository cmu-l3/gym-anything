#!/bin/bash
echo "=== Setting up customer_profile_enrichment task ==="

source /workspace/scripts/task_utils.sh

# ---- Create mailboxes ----
TECH_MAILBOX_ID=$(ensure_mailbox_exists "Technical Support" "techsupport@helpdesk.local")
if [ -z "$TECH_MAILBOX_ID" ]; then
    TECH_MAILBOX_ID=$(fs_query "SELECT id FROM mailboxes WHERE email='techsupport@helpdesk.local' LIMIT 1" 2>/dev/null || echo "")
fi
echo "Technical Support mailbox ID: $TECH_MAILBOX_ID"

GENERAL_MAILBOX_ID=$(ensure_mailbox_exists "General Support" "general@helpdesk.local")
if [ -z "$GENERAL_MAILBOX_ID" ]; then
    GENERAL_MAILBOX_ID=$(fs_query "SELECT id FROM mailboxes WHERE email='general@helpdesk.local' LIMIT 1" 2>/dev/null || echo "")
fi
echo "General Support mailbox ID: $GENERAL_MAILBOX_ID"

# ---- Helper: create customer with empty profile fields ----
create_empty_customer() {
    local FIRST="$1"
    local LAST="$2"
    local EMAIL="$3"

    local CUST_ID
    CUST_ID=$(fs_query "SELECT id FROM customers WHERE first_name='$FIRST' AND last_name='$LAST' LIMIT 1" 2>/dev/null || echo "")
    if [ -z "$CUST_ID" ]; then
        # Insert with empty company, job_title, phones
        fs_query "INSERT INTO customers (first_name, last_name, company, job_title, created_at, updated_at) VALUES ('$FIRST', '$LAST', '', '', NOW(), NOW())" 2>/dev/null || true
        CUST_ID=$(fs_query "SELECT id FROM customers WHERE first_name='$FIRST' AND last_name='$LAST' ORDER BY id DESC LIMIT 1" 2>/dev/null || echo "")
        if [ -n "$CUST_ID" ]; then
            local EMAIL_EXISTS
            EMAIL_EXISTS=$(fs_query "SELECT COUNT(*) FROM emails WHERE customer_id=$CUST_ID AND email='$EMAIL'" 2>/dev/null || echo "0")
            if [ "$EMAIL_EXISTS" = "0" ]; then
                fs_query "INSERT INTO emails (customer_id, email) VALUES ($CUST_ID, '$EMAIL')" 2>/dev/null || true
            fi
        fi
    else
        # Reset existing customer's company and job title to empty
        fs_query "UPDATE customers SET company='', job_title='' WHERE id=$CUST_ID" 2>/dev/null || true
        # Remove phones if any
        fs_query "DELETE FROM phones WHERE customer_id=$CUST_ID" 2>/dev/null || true
    fi
    echo "$CUST_ID"
}

# ---- Create Customer 1: Marisa Obrien (3 conversations in Technical Support) ----
MARISA_ID=$(create_empty_customer "Marisa" "Obrien" "carrollallison@example.com")
echo "Marisa Obrien ID: $MARISA_ID"

# 3 conversations for Marisa in Technical Support
MARISA_SUBJECTS=(
    "Product setup"
    "Firmware update problem"
    "Device connectivity issue"
)
MARISA_BODIES=(
    "I am having an issue with my GoPro Hero. The device setup process fails at the last step. I have tried following the manual but the camera does not connect to the app. Please help me resolve this setup issue."
    "After updating the firmware on my GoPro Hero, the camera no longer connects to the GoPro app on my iPhone. The update was applied automatically last night and now the Bluetooth pairing fails every time I try."
    "My GoPro Hero is not connecting to any WiFi network or Bluetooth device since yesterday. I have tried factory resetting the device but the connectivity issue persists. I need urgent assistance as I have a shoot scheduled tomorrow."
)

MARISA_CONV_IDS=()
for i in 0 1 2; do
    SUBJ="${MARISA_SUBJECTS[$i]}"
    BODY="${MARISA_BODIES[$i]}"
    CONV_EXISTS=$(fs_query "SELECT id FROM conversations WHERE subject='$SUBJ' AND mailbox_id=$TECH_MAILBOX_ID LIMIT 1" 2>/dev/null || echo "")
    if [ -z "$CONV_EXISTS" ]; then
        CONV_ID=$(create_conversation_via_orm "$SUBJ" "$TECH_MAILBOX_ID" "carrollallison@example.com" "${MARISA_ID:-}" "$BODY")
        echo "Created Marisa conv '$SUBJ' ID: $CONV_ID"
    else
        CONV_ID="$CONV_EXISTS"
    fi
    # Ensure untagged
    if [ -n "$CONV_ID" ]; then
        TAG_ID=$(fs_query "SELECT id FROM tags WHERE name='vip-client' LIMIT 1" 2>/dev/null || echo "")
        if [ -n "$TAG_ID" ]; then
            fs_query "DELETE FROM conversation_tag WHERE conversation_id=$CONV_ID AND tag_id=$TAG_ID" 2>/dev/null || true
        fi
    fi
    MARISA_CONV_IDS+=("$CONV_ID")
done

# ---- Create Customer 2: Nicolas Wilson (2 conversations in General Support) ----
NICOLAS_ID=$(create_empty_customer "Nicolas" "Wilson" "joshua24@example.com")
echo "Nicolas Wilson ID: $NICOLAS_ID"

NICOLAS_SUBJECTS=(
    "Installation support"
    "App sync issue"
)
NICOLAS_BODIES=(
    "I purchased the Fitbit Versa Smartwatch last month and I am having trouble with the installation of the companion app on my Android phone. The setup wizard keeps crashing at the account sync step. I have tried reinstalling multiple times."
    "My Fitbit Versa Smartwatch is not syncing properly with the Fitbit app on my phone. The app shows the last sync was 5 days ago even though the watch is charged and Bluetooth is enabled. I have tried unpairing and re-pairing the device."
)

NICOLAS_CONV_IDS=()
for i in 0 1; do
    SUBJ="${NICOLAS_SUBJECTS[$i]}"
    BODY="${NICOLAS_BODIES[$i]}"
    CONV_EXISTS=$(fs_query "SELECT id FROM conversations WHERE subject='$SUBJ' AND mailbox_id=$GENERAL_MAILBOX_ID LIMIT 1" 2>/dev/null || echo "")
    if [ -z "$CONV_EXISTS" ]; then
        CONV_ID=$(create_conversation_via_orm "$SUBJ" "$GENERAL_MAILBOX_ID" "joshua24@example.com" "${NICOLAS_ID:-}" "$BODY")
        echo "Created Nicolas conv '$SUBJ' ID: $CONV_ID"
    else
        CONV_ID="$CONV_EXISTS"
    fi
    NICOLAS_CONV_IDS+=("$CONV_ID")
done

# Clear cache
docker exec freescout-app php /www/html/artisan cache:clear 2>/dev/null || true

# ---- Record baseline state ----
INITIAL_CUSTOMER_COUNT=$(fs_query "SELECT COUNT(*) FROM customers" 2>/dev/null || echo "0")
INITIAL_CONV_COUNT=$(fs_query "SELECT COUNT(*) FROM conversations" 2>/dev/null || echo "0")

echo "$INITIAL_CUSTOMER_COUNT" > /tmp/initial_customer_count
echo "$INITIAL_CONV_COUNT" > /tmp/initial_conv_count
echo "$TECH_MAILBOX_ID" > /tmp/tech_mailbox_id_cpe
echo "$GENERAL_MAILBOX_ID" > /tmp/general_mailbox_id_cpe
echo "$MARISA_ID" > /tmp/marisa_customer_id
echo "$NICOLAS_ID" > /tmp/nicolas_customer_id

CONV_ID_STR=$(IFS=','; echo "${MARISA_CONV_IDS[*]}")
echo "$CONV_ID_STR" > /tmp/marisa_conv_ids

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Navigate Firefox to customers list
if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox "http://localhost:8080" > /tmp/firefox.log 2>&1 &
    sleep 5
fi
wait_for_window "firefox|mozilla|freescout" 30
focus_firefox
navigate_to_url "http://localhost:8080/customers"
sleep 3

take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="
echo "Marisa Obrien ID: $MARISA_ID (${MARISA_CONV_IDS[*]})"
echo "Nicolas Wilson ID: $NICOLAS_ID (${NICOLAS_CONV_IDS[*]})"
echo "Initial customer count: $INITIAL_CUSTOMER_COUNT"
