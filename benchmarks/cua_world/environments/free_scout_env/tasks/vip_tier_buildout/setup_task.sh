#!/bin/bash
echo "=== Setting up vip_tier_buildout task ==="

source /workspace/scripts/task_utils.sh

# ---- Delete stale outputs BEFORE recording timestamp ----
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/task_start_timestamp 2>/dev/null || true
rm -f /tmp/general_mailbox_id_vtb 2>/dev/null || true
rm -f /tmp/temp_worker_id_vtb 2>/dev/null || true
rm -f /tmp/conv_*_id_vtb 2>/dev/null || true
rm -f /tmp/pinnacle_customer_id_vtb 2>/dev/null || true

# ---- Create General Support mailbox ----
GENERAL_MAILBOX_ID=$(ensure_mailbox_exists "General Support" "general@helpdesk.local")
if [ -z "$GENERAL_MAILBOX_ID" ]; then
    GENERAL_MAILBOX_ID=$(fs_query "SELECT id FROM mailboxes WHERE email='general@helpdesk.local' LIMIT 1" 2>/dev/null || echo "")
fi
echo "General Support mailbox ID: $GENERAL_MAILBOX_ID"

# ---- Ensure NO pre-existing VIP Support mailbox (clean state) ----
EXISTING_VIP=$(fs_query "SELECT id FROM mailboxes WHERE email='vip@helpdesk.local' LIMIT 1" 2>/dev/null || echo "")
if [ -n "$EXISTING_VIP" ]; then
    # Move any conversations out, then remove
    fs_query "UPDATE conversations SET mailbox_id=$GENERAL_MAILBOX_ID WHERE mailbox_id=$EXISTING_VIP" 2>/dev/null || true
    fs_query "DELETE FROM mailbox_user WHERE mailbox_id=$EXISTING_VIP" 2>/dev/null || true
    fs_query "DELETE FROM folders WHERE mailbox_id=$EXISTING_VIP" 2>/dev/null || true
    fs_query "DELETE FROM mailboxes WHERE id=$EXISTING_VIP" 2>/dev/null || true
    echo "Cleaned up pre-existing VIP mailbox"
fi

# ---- Ensure NO pre-existing Jordan Mitchell user (clean state) ----
EXISTING_JORDAN=$(fs_query "SELECT id FROM users WHERE email='jordan.mitchell@helpdesk.local' LIMIT 1" 2>/dev/null || echo "")
if [ -n "$EXISTING_JORDAN" ]; then
    fs_query "DELETE FROM mailbox_user WHERE user_id=$EXISTING_JORDAN" 2>/dev/null || true
    fs_query "UPDATE conversations SET user_id=NULL WHERE user_id=$EXISTING_JORDAN" 2>/dev/null || true
    fs_query "DELETE FROM users WHERE id=$EXISTING_JORDAN" 2>/dev/null || true
    echo "Cleaned up pre-existing Jordan Mitchell"
fi

# ---- Create Temp Worker (active — agent must deactivate) ----
TEMP_EXISTS=$(fs_query "SELECT id FROM users WHERE email='temp.worker@helpdesk.local' LIMIT 1" 2>/dev/null || echo "")
if [ -z "$TEMP_EXISTS" ]; then
    fs_tinker "
\$u = new \\App\\User();
\$u->first_name = 'Temp';
\$u->last_name = 'Worker';
\$u->email = 'temp.worker@helpdesk.local';
\$u->password = bcrypt('TempPass123!');
\$u->role = 2;
\$u->status = 1;
\$u->save();
echo 'TEMP_ID:' . \$u->id;
" 2>/dev/null || true
else
    # Ensure temp worker is ACTIVE (status=1) for clean state
    fs_query "UPDATE users SET status=1 WHERE email='temp.worker@helpdesk.local'" 2>/dev/null || true
fi
TEMP_ID=$(fs_query "SELECT id FROM users WHERE email='temp.worker@helpdesk.local' LIMIT 1" 2>/dev/null || echo "")
echo "Temp Worker ID: $TEMP_ID"

# Grant Temp Worker access to General Support
if [ -n "$TEMP_ID" ] && [ -n "$GENERAL_MAILBOX_ID" ]; then
    CNT=$(fs_query "SELECT COUNT(*) FROM mailbox_user WHERE user_id=$TEMP_ID AND mailbox_id=$GENERAL_MAILBOX_ID" 2>/dev/null || echo "0")
    if [ "$CNT" = "0" ]; then
        fs_query "INSERT IGNORE INTO mailbox_user (mailbox_id, user_id) VALUES ($GENERAL_MAILBOX_ID, $TEMP_ID)" 2>/dev/null || true
    fi
fi

# ---- Create Pinnacle Systems customer (with blank Company and Phone) ----
PINNACLE_CUST_EXISTS=$(fs_query "SELECT c.id FROM customers c JOIN emails e ON c.id=e.customer_id WHERE e.email='infra-ops@pinnacle-systems.com' LIMIT 1" 2>/dev/null || echo "")
if [ -z "$PINNACLE_CUST_EXISTS" ]; then
    fs_tinker "
\$c = new \\App\\Customer();
\$c->first_name = 'Infrastructure';
\$c->last_name = 'Operations';
\$c->company = '';
\$c->save();
\$e = new \\App\\Email();
\$e->customer_id = \$c->id;
\$e->email = 'infra-ops@pinnacle-systems.com';
\$e->save();
echo 'PINNACLE_CUST_ID:' . \$c->id;
" 2>/dev/null || true
else
    # Reset Company and Phone to blank for clean state
    fs_query "UPDATE customers SET company='', phones='' WHERE id=$PINNACLE_CUST_EXISTS" 2>/dev/null || true
fi
PINNACLE_CUST_ID=$(fs_query "SELECT c.id FROM customers c JOIN emails e ON c.id=e.customer_id WHERE e.email='infra-ops@pinnacle-systems.com' LIMIT 1" 2>/dev/null || echo "")
echo "Pinnacle customer ID: $PINNACLE_CUST_ID"

# ==============================================================
# Seed 6 conversations in General Support
# ==============================================================

# ---- ENTERPRISE CONV 1: Pinnacle Systems (CLOSED + assigned to Temp Worker) ----
CONV1_SUBJECT="Production Server Cluster Failing Health Checks"
CONV1_EXISTS=$(fs_query "SELECT id FROM conversations WHERE subject='$CONV1_SUBJECT' LIMIT 1" 2>/dev/null || echo "")
if [ -z "$CONV1_EXISTS" ]; then
    CONV1_ID=$(create_conversation_via_orm "$CONV1_SUBJECT" "$GENERAL_MAILBOX_ID" "infra-ops@pinnacle-systems.com" "$PINNACLE_CUST_ID" "Our production server cluster has been failing automated health checks since Monday. The monitoring dashboard shows intermittent 503 errors on nodes prod-web-04 and prod-web-07. Average response time has degraded from 120ms to 2400ms. This is affecting our enterprise SLA commitments and we risk breaching our 99.9% uptime guarantee. The ops team has ruled out network issues on our side. Stack trace from the health check agent shows ConnectionPoolExhausted exceptions originating at db.connection.pool:443. Please prioritize — our CTO is requesting hourly updates.")
else
    CONV1_ID="$CONV1_EXISTS"
fi
# Set status=3 (Closed) and assign to Temp Worker
if [ -n "$CONV1_ID" ]; then
    fs_query "UPDATE conversations SET status=3, user_id=${TEMP_ID:-NULL}, mailbox_id=$GENERAL_MAILBOX_ID WHERE id=$CONV1_ID" 2>/dev/null || true
    # Update folder to Closed folder (type=40 in FreeScout)
    CLOSED_FOLDER=$(fs_query "SELECT id FROM folders WHERE mailbox_id=$GENERAL_MAILBOX_ID AND type=40 LIMIT 1" 2>/dev/null || echo "")
    if [ -n "$CLOSED_FOLDER" ]; then
        fs_query "UPDATE conversations SET folder_id=$CLOSED_FOLDER WHERE id=$CONV1_ID" 2>/dev/null || true
    fi
fi
echo "Conv 1 (Pinnacle, Closed): $CONV1_ID"

# ---- ENTERPRISE CONV 2: Meridian Corp (Active, unassigned) ----
CONV2_SUBJECT="Q4 Invoice Discrepancy — Duplicate Charges on Enterprise License"
# Escape the em dash for SQL
CONV2_SUBJECT_SQL="Q4 Invoice Discrepancy"
CONV2_EXISTS=$(fs_query "SELECT id FROM conversations WHERE subject LIKE '%${CONV2_SUBJECT_SQL}%' LIMIT 1" 2>/dev/null || echo "")
if [ -z "$CONV2_EXISTS" ]; then
    # Create Meridian customer
    MERIDIAN_CUST_EXISTS=$(fs_query "SELECT c.id FROM customers c JOIN emails e ON c.id=e.customer_id WHERE e.email='accounts-payable@meridian-corp.com' LIMIT 1" 2>/dev/null || echo "")
    if [ -z "$MERIDIAN_CUST_EXISTS" ]; then
        fs_tinker "
\$c = new \\App\\Customer();
\$c->first_name = 'Accounts';
\$c->last_name = 'Payable';
\$c->company = '';
\$c->save();
\$e = new \\App\\Email();
\$e->customer_id = \$c->id;
\$e->email = 'accounts-payable@meridian-corp.com';
\$e->save();
echo 'MERIDIAN_CUST_ID:' . \$c->id;
" 2>/dev/null || true
    fi
    MERIDIAN_CUST_ID=$(fs_query "SELECT c.id FROM customers c JOIN emails e ON c.id=e.customer_id WHERE e.email='accounts-payable@meridian-corp.com' LIMIT 1" 2>/dev/null || echo "")
    CONV2_ID=$(create_conversation_via_orm "$CONV2_SUBJECT" "$GENERAL_MAILBOX_ID" "accounts-payable@meridian-corp.com" "$MERIDIAN_CUST_ID" "We have identified duplicate line items on invoice #INV-2024-3847 dated November 15th. The Enterprise Platform License line item appears twice, resulting in a total overcharge of four thousand two hundred dollars. Our finance department cannot close the quarterly books until this discrepancy is resolved. Attached is a highlighted copy of the invoice showing the duplicate entries. Please issue a corrected invoice and confirm the credit to our account at your earliest convenience. Reference: PO #MC-2024-0892. Contact: Maria Torres, Senior Financial Analyst, Meridian Corp.")
else
    CONV2_ID="$CONV2_EXISTS"
fi
if [ -n "$CONV2_ID" ]; then
    fs_query "UPDATE conversations SET status=1, user_id=NULL, mailbox_id=$GENERAL_MAILBOX_ID WHERE id=$CONV2_ID" 2>/dev/null || true
fi
echo "Conv 2 (Meridian, Active): $CONV2_ID"

# ---- ENTERPRISE CONV 3: Summit Engineering (Active, unassigned) ----
CONV3_SUBJECT="Replacement UPS Battery Units for Server Room B — PO #EQ-5521"
CONV3_SUBJECT_SQL="Replacement UPS Battery Units"
CONV3_EXISTS=$(fs_query "SELECT id FROM conversations WHERE subject LIKE '%${CONV3_SUBJECT_SQL}%' LIMIT 1" 2>/dev/null || echo "")
if [ -z "$CONV3_EXISTS" ]; then
    # Create Summit customer
    SUMMIT_CUST_EXISTS=$(fs_query "SELECT c.id FROM customers c JOIN emails e ON c.id=e.customer_id WHERE e.email='procurement@summit-engineering.com' LIMIT 1" 2>/dev/null || echo "")
    if [ -z "$SUMMIT_CUST_EXISTS" ]; then
        fs_tinker "
\$c = new \\App\\Customer();
\$c->first_name = 'Procurement';
\$c->last_name = 'Department';
\$c->company = '';
\$c->save();
\$e = new \\App\\Email();
\$e->customer_id = \$c->id;
\$e->email = 'procurement@summit-engineering.com';
\$e->save();
echo 'SUMMIT_CUST_ID:' . \$c->id;
" 2>/dev/null || true
    fi
    SUMMIT_CUST_ID=$(fs_query "SELECT c.id FROM customers c JOIN emails e ON c.id=e.customer_id WHERE e.email='procurement@summit-engineering.com' LIMIT 1" 2>/dev/null || echo "")
    CONV3_ID=$(create_conversation_via_orm "$CONV3_SUBJECT" "$GENERAL_MAILBOX_ID" "procurement@summit-engineering.com" "$SUMMIT_CUST_ID" "Requesting replacement battery modules for the APC Smart-UPS SRT 5000VA units in Server Room B, Building 3. Current batteries are showing Replace Battery warnings on 3 of 4 units. Part number: APCRBC140. Quantity needed: 4 units. Our server room UPS units are running on degraded batteries and we risk a data center outage if they fail during a power event. Delivery address: Summit Engineering, 1200 Industrial Blvd, Building 3, Server Room B. Purchase order #EQ-5521 is attached. Please confirm lead time and expected delivery date. Contact: James Whitfield, Facilities Director.")
else
    CONV3_ID="$CONV3_EXISTS"
fi
if [ -n "$CONV3_ID" ]; then
    fs_query "UPDATE conversations SET status=1, user_id=NULL, mailbox_id=$GENERAL_MAILBOX_ID WHERE id=$CONV3_ID" 2>/dev/null || true
fi
echo "Conv 3 (Summit, Active): $CONV3_ID"

# ---- NON-ENTERPRISE CONV 4: Personal user (Active, assigned to Admin) ----
CONV4_SUBJECT="Cannot Reset Password After Email Migration"
CONV4_EXISTS=$(fs_query "SELECT id FROM conversations WHERE subject='$CONV4_SUBJECT' LIMIT 1" 2>/dev/null || echo "")
if [ -z "$CONV4_EXISTS" ]; then
    CONV4_CUST_EXISTS=$(fs_query "SELECT c.id FROM customers c JOIN emails e ON c.id=e.customer_id WHERE e.email='sarah.watts@gmail.com' LIMIT 1" 2>/dev/null || echo "")
    if [ -z "$CONV4_CUST_EXISTS" ]; then
        fs_tinker "
\$c = new \\App\\Customer();
\$c->first_name = 'Sarah';
\$c->last_name = 'Watts';
\$c->save();
\$e = new \\App\\Email();
\$e->customer_id = \$c->id;
\$e->email = 'sarah.watts@gmail.com';
\$e->save();
echo 'CONV4_CUST_ID:' . \$c->id;
" 2>/dev/null || true
    fi
    CONV4_CUST_ID=$(fs_query "SELECT c.id FROM customers c JOIN emails e ON c.id=e.customer_id WHERE e.email='sarah.watts@gmail.com' LIMIT 1" 2>/dev/null || echo "")
    CONV4_ID=$(create_conversation_via_orm "$CONV4_SUBJECT" "$GENERAL_MAILBOX_ID" "sarah.watts@gmail.com" "$CONV4_CUST_ID" "Hi, I recently switched my email from Yahoo to Gmail and now I cannot reset my password on your platform. When I enter my new Gmail address on the password reset page, it says email not found. My account was originally registered with sarah.watts@yahoo.com but that mailbox no longer exists. Can you update my email on file so I can regain access to my account? My username is swatts2019. Thanks, Sarah")
else
    CONV4_ID="$CONV4_EXISTS"
fi
ADMIN_ID=$(fs_query "SELECT id FROM users WHERE email='admin@helpdesk.local' LIMIT 1" 2>/dev/null || echo "")
if [ -n "$CONV4_ID" ]; then
    fs_query "UPDATE conversations SET status=1, user_id=${ADMIN_ID:-NULL}, mailbox_id=$GENERAL_MAILBOX_ID WHERE id=$CONV4_ID" 2>/dev/null || true
fi
echo "Conv 4 (Gmail, Active, assigned Admin): $CONV4_ID"

# ---- NON-ENTERPRISE CONV 5: Startup user (Active, unassigned) ----
CONV5_SUBJECT="Feature Request — Dark Mode for Dashboard"
CONV5_SUBJECT_SQL="Feature Request"
CONV5_EXISTS=$(fs_query "SELECT id FROM conversations WHERE subject LIKE '%${CONV5_SUBJECT_SQL}%Dark Mode%' LIMIT 1" 2>/dev/null || echo "")
if [ -z "$CONV5_EXISTS" ]; then
    CONV5_CUST_EXISTS=$(fs_query "SELECT c.id FROM customers c JOIN emails e ON c.id=e.customer_id WHERE e.email='dev.feedback@techstartup.io' LIMIT 1" 2>/dev/null || echo "")
    if [ -z "$CONV5_CUST_EXISTS" ]; then
        fs_tinker "
\$c = new \\App\\Customer();
\$c->first_name = 'DevOps';
\$c->last_name = 'Team';
\$c->save();
\$e = new \\App\\Email();
\$e->customer_id = \$c->id;
\$e->email = 'dev.feedback@techstartup.io';
\$e->save();
echo 'CONV5_CUST_ID:' . \$c->id;
" 2>/dev/null || true
    fi
    CONV5_CUST_ID=$(fs_query "SELECT c.id FROM customers c JOIN emails e ON c.id=e.customer_id WHERE e.email='dev.feedback@techstartup.io' LIMIT 1" 2>/dev/null || echo "")
    CONV5_ID=$(create_conversation_via_orm "$CONV5_SUBJECT" "$GENERAL_MAILBOX_ID" "dev.feedback@techstartup.io" "$CONV5_CUST_ID" "Hello! Our team has been using your platform for about 3 months now and we love it. One thing that would really improve our experience is a dark mode option for the dashboard. Several of our engineers work night shifts and the bright white interface causes significant eye strain during extended monitoring sessions. We noticed your competitors offer this feature. Would you consider adding it to the roadmap? Happy to provide more detailed feedback or participate in beta testing. Thanks! — The DevOps team at TechStartup.io")
else
    CONV5_ID="$CONV5_EXISTS"
fi
if [ -n "$CONV5_ID" ]; then
    fs_query "UPDATE conversations SET status=1, user_id=NULL, mailbox_id=$GENERAL_MAILBOX_ID WHERE id=$CONV5_ID" 2>/dev/null || true
fi
echo "Conv 5 (techstartup.io, Active): $CONV5_ID"

# ---- NON-ENTERPRISE CONV 6: Freelancer (Active, unassigned) ----
CONV6_SUBJECT="Subscription Billing Date Change Request"
CONV6_EXISTS=$(fs_query "SELECT id FROM conversations WHERE subject='$CONV6_SUBJECT' LIMIT 1" 2>/dev/null || echo "")
if [ -z "$CONV6_EXISTS" ]; then
    CONV6_CUST_EXISTS=$(fs_query "SELECT c.id FROM customers c JOIN emails e ON c.id=e.customer_id WHERE e.email='jamie.lee@freelance-design.com' LIMIT 1" 2>/dev/null || echo "")
    if [ -z "$CONV6_CUST_EXISTS" ]; then
        fs_tinker "
\$c = new \\App\\Customer();
\$c->first_name = 'Jamie';
\$c->last_name = 'Lee';
\$c->save();
\$e = new \\App\\Email();
\$e->customer_id = \$c->id;
\$e->email = 'jamie.lee@freelance-design.com';
\$e->save();
echo 'CONV6_CUST_ID:' . \$c->id;
" 2>/dev/null || true
    fi
    CONV6_CUST_ID=$(fs_query "SELECT c.id FROM customers c JOIN emails e ON c.id=e.customer_id WHERE e.email='jamie.lee@freelance-design.com' LIMIT 1" 2>/dev/null || echo "")
    CONV6_ID=$(create_conversation_via_orm "$CONV6_SUBJECT" "$GENERAL_MAILBOX_ID" "jamie.lee@freelance-design.com" "$CONV6_CUST_ID" "Hi there, I am a freelance graphic designer on your Personal plan. My current billing date is the 1st of each month, but most of my clients pay me around the 10th to 15th. Could you change my billing date to the 15th so it aligns better with my cash flow? I have been a subscriber for 14 months and would like to continue, but the timing mismatch is causing issues with my budget. Account email: jamie.lee@freelance-design.com. Thanks, Jamie Lee")
else
    CONV6_ID="$CONV6_EXISTS"
fi
if [ -n "$CONV6_ID" ]; then
    fs_query "UPDATE conversations SET status=1, user_id=NULL, mailbox_id=$GENERAL_MAILBOX_ID WHERE id=$CONV6_ID" 2>/dev/null || true
fi
echo "Conv 6 (freelance, Active): $CONV6_ID"

# ---- Clear any stale auto-reply on a potential pre-existing VIP mailbox ----
# (Already deleted above, but belt-and-suspenders)

# ---- Clear caches ----
docker exec freescout-app php /www/html/artisan cache:clear 2>/dev/null || true

# ---- Record task start timestamp ----
date +%s > /tmp/task_start_timestamp

# ---- Store IDs for export_result.sh ----
echo "$GENERAL_MAILBOX_ID" > /tmp/general_mailbox_id_vtb
echo "$TEMP_ID" > /tmp/temp_worker_id_vtb
echo "$CONV1_ID" > /tmp/conv_1_id_vtb
echo "$CONV2_ID" > /tmp/conv_2_id_vtb
echo "$CONV3_ID" > /tmp/conv_3_id_vtb
echo "$CONV4_ID" > /tmp/conv_4_id_vtb
echo "$CONV5_ID" > /tmp/conv_5_id_vtb
echo "$CONV6_ID" > /tmp/conv_6_id_vtb
echo "$PINNACLE_CUST_ID" > /tmp/pinnacle_customer_id_vtb

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
echo "General Support mailbox: $GENERAL_MAILBOX_ID"
echo "Temp Worker ID: $TEMP_ID (status=Active, agent must deactivate)"
echo "Conv 1 (Pinnacle, CLOSED, assigned TempWorker): $CONV1_ID"
echo "Conv 2 (Meridian, Active, unassigned): $CONV2_ID"
echo "Conv 3 (Summit, Active, unassigned): $CONV3_ID"
echo "Conv 4 (Gmail, Active, assigned Admin): $CONV4_ID"
echo "Conv 5 (techstartup.io, Active, unassigned): $CONV5_ID"
echo "Conv 6 (freelance, Active, unassigned): $CONV6_ID"
echo "Pinnacle customer: $PINNACLE_CUST_ID (Company/Phone blank)"
