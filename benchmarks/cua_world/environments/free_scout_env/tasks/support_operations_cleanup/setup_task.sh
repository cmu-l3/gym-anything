#!/bin/bash
echo "=== Setting up support_operations_cleanup task ==="

source /workspace/scripts/task_utils.sh

# ---- Create 3 mailboxes ----
CS_MAILBOX_ID=$(ensure_mailbox_exists "Customer Success" "cs@helpdesk.local")
if [ -z "$CS_MAILBOX_ID" ]; then
    CS_MAILBOX_ID=$(fs_query "SELECT id FROM mailboxes WHERE email='cs@helpdesk.local' LIMIT 1" 2>/dev/null || echo "")
fi
echo "Customer Success mailbox ID: $CS_MAILBOX_ID"

TECH_MAILBOX_ID=$(ensure_mailbox_exists "Technical Support" "techsupport@helpdesk.local")
if [ -z "$TECH_MAILBOX_ID" ]; then
    TECH_MAILBOX_ID=$(fs_query "SELECT id FROM mailboxes WHERE email='techsupport@helpdesk.local' LIMIT 1" 2>/dev/null || echo "")
fi
echo "Technical Support mailbox ID: $TECH_MAILBOX_ID"

SALES_MAILBOX_ID=$(ensure_mailbox_exists "Sales Inquiries" "sales@helpdesk.local")
if [ -z "$SALES_MAILBOX_ID" ]; then
    SALES_MAILBOX_ID=$(fs_query "SELECT id FROM mailboxes WHERE email='sales@helpdesk.local' LIMIT 1" 2>/dev/null || echo "")
fi
echo "Sales Inquiries mailbox ID: $SALES_MAILBOX_ID"

# ---- Create Agent 1: Raj Patel (access to Technical Support + Sales Inquiries — Sales is intentionally wrong) ----
RAJ_EXISTS=$(fs_query "SELECT id FROM users WHERE email='raj.patel@helpdesk.local' LIMIT 1" 2>/dev/null || echo "")
if [ -z "$RAJ_EXISTS" ]; then
    fs_tinker "
\$u = new \App\User();
\$u->first_name = 'Raj';
\$u->last_name = 'Patel';
\$u->email = 'raj.patel@helpdesk.local';
\$u->password = bcrypt('Agent123!');
\$u->role = 2;
\$u->status = 1;
\$u->save();
echo 'RAJ_ID:' . \$u->id;
" 2>/dev/null || true
fi
RAJ_ID=$(fs_query "SELECT id FROM users WHERE email='raj.patel@helpdesk.local' LIMIT 1" 2>/dev/null || echo "")
echo "Raj Patel ID: $RAJ_ID"

# Grant Raj access to Technical Support + Sales Inquiries (Sales is wrong, agent must fix)
for MBX_ID in "$TECH_MAILBOX_ID" "$SALES_MAILBOX_ID"; do
    if [ -n "$RAJ_ID" ] && [ -n "$MBX_ID" ]; then
        CNT=$(fs_query "SELECT COUNT(*) FROM mailbox_user WHERE user_id=$RAJ_ID AND mailbox_id=$MBX_ID" 2>/dev/null || echo "0")
        if [ "$CNT" = "0" ]; then
            fs_query "INSERT IGNORE INTO mailbox_user (mailbox_id, user_id) VALUES ($MBX_ID, $RAJ_ID)" 2>/dev/null || true
        fi
    fi
done

# ---- Create Agent 2: Nina Kovacs (access to Customer Success only — correct) ----
NINA_EXISTS=$(fs_query "SELECT id FROM users WHERE email='nina.kovacs@helpdesk.local' LIMIT 1" 2>/dev/null || echo "")
if [ -z "$NINA_EXISTS" ]; then
    fs_tinker "
\$u = new \App\User();
\$u->first_name = 'Nina';
\$u->last_name = 'Kovacs';
\$u->email = 'nina.kovacs@helpdesk.local';
\$u->password = bcrypt('Agent123!');
\$u->role = 2;
\$u->status = 1;
\$u->save();
echo 'NINA_ID:' . \$u->id;
" 2>/dev/null || true
fi
NINA_ID=$(fs_query "SELECT id FROM users WHERE email='nina.kovacs@helpdesk.local' LIMIT 1" 2>/dev/null || echo "")
echo "Nina Kovacs ID: $NINA_ID"

# Grant Nina access to Customer Success only
if [ -n "$NINA_ID" ] && [ -n "$CS_MAILBOX_ID" ]; then
    CNT=$(fs_query "SELECT COUNT(*) FROM mailbox_user WHERE user_id=$NINA_ID AND mailbox_id=$CS_MAILBOX_ID" 2>/dev/null || echo "0")
    if [ "$CNT" = "0" ]; then
        fs_query "INSERT IGNORE INTO mailbox_user (mailbox_id, user_id) VALUES ($CS_MAILBOX_ID, $NINA_ID)" 2>/dev/null || true
    fi
fi
# Remove Nina from Tech and Sales if present
for MBX_ID in "$TECH_MAILBOX_ID" "$SALES_MAILBOX_ID"; do
    if [ -n "$NINA_ID" ] && [ -n "$MBX_ID" ]; then
        fs_query "DELETE FROM mailbox_user WHERE user_id=$NINA_ID AND mailbox_id=$MBX_ID" 2>/dev/null || true
    fi
done

# ---- Create Agent 3: Ben Harris (access to Sales Inquiries only — CS is missing, agent must add) ----
BEN_EXISTS=$(fs_query "SELECT id FROM users WHERE email='ben.harris@helpdesk.local' LIMIT 1" 2>/dev/null || echo "")
if [ -z "$BEN_EXISTS" ]; then
    fs_tinker "
\$u = new \App\User();
\$u->first_name = 'Ben';
\$u->last_name = 'Harris';
\$u->email = 'ben.harris@helpdesk.local';
\$u->password = bcrypt('Agent123!');
\$u->role = 2;
\$u->status = 1;
\$u->save();
echo 'BEN_ID:' . \$u->id;
" 2>/dev/null || true
fi
BEN_ID=$(fs_query "SELECT id FROM users WHERE email='ben.harris@helpdesk.local' LIMIT 1" 2>/dev/null || echo "")
echo "Ben Harris ID: $BEN_ID"

# Grant Ben access to Sales Inquiries only (no CS — agent must add CS access)
if [ -n "$BEN_ID" ] && [ -n "$SALES_MAILBOX_ID" ]; then
    CNT=$(fs_query "SELECT COUNT(*) FROM mailbox_user WHERE user_id=$BEN_ID AND mailbox_id=$SALES_MAILBOX_ID" 2>/dev/null || echo "0")
    if [ "$CNT" = "0" ]; then
        fs_query "INSERT IGNORE INTO mailbox_user (mailbox_id, user_id) VALUES ($SALES_MAILBOX_ID, $BEN_ID)" 2>/dev/null || true
    fi
fi
# Remove Ben from Tech and CS if somehow present
for MBX_ID in "$TECH_MAILBOX_ID" "$CS_MAILBOX_ID"; do
    if [ -n "$BEN_ID" ] && [ -n "$MBX_ID" ]; then
        fs_query "DELETE FROM mailbox_user WHERE user_id=$BEN_ID AND mailbox_id=$MBX_ID" 2>/dev/null || true
    fi
done

# ---- Seed Technical Support conversations ----
# Conv 1: Webhook failure (correct mailbox, unassigned, no reply)
TECH_CONV_1_EXISTS=$(fs_query "SELECT id FROM conversations WHERE subject='Webhook authentication failure' AND mailbox_id=$TECH_MAILBOX_ID LIMIT 1" 2>/dev/null || echo "")
if [ -z "$TECH_CONV_1_EXISTS" ]; then
    TECH_CONV_1=$(create_conversation_via_orm "Webhook authentication failure" "$TECH_MAILBOX_ID" "danielle.park@example.com" "" "We are experiencing intermittent webhook authentication failures on our production endpoint. The HMAC signature validation is failing despite using the correct secret key. Error code: 401 HMAC_INVALID. This is affecting our real-time inventory sync.")
else
    TECH_CONV_1="$TECH_CONV_1_EXISTS"
fi
echo "Tech conv 1 ID: $TECH_CONV_1"

# Conv 2: DB timeout (correct mailbox, unassigned, no reply)
TECH_CONV_2_EXISTS=$(fs_query "SELECT id FROM conversations WHERE subject='Database connection timeout in production' AND mailbox_id=$TECH_MAILBOX_ID LIMIT 1" 2>/dev/null || echo "")
if [ -z "$TECH_CONV_2_EXISTS" ]; then
    TECH_CONV_2=$(create_conversation_via_orm "Database connection timeout in production" "$TECH_MAILBOX_ID" "ethan.brooks@example.com" "" "Our application is throwing connection timeout exceptions when connecting to the primary database. This started 3 hours ago and is affecting approximately 20 percent of requests. Stack trace: ConnectionTimeoutException at db.connection.pool:443. Urgent assistance needed.")
else
    TECH_CONV_2="$TECH_CONV_2_EXISTS"
fi
echo "Tech conv 2 ID: $TECH_CONV_2"

# Conv 3: Enterprise license pricing (WRONG mailbox — should be Sales Inquiries)
TECH_CONV_3_EXISTS=$(fs_query "SELECT id FROM conversations WHERE subject='Enterprise license pricing inquiry' LIMIT 1" 2>/dev/null || echo "")
if [ -z "$TECH_CONV_3_EXISTS" ]; then
    TECH_CONV_3=$(create_conversation_via_orm "Enterprise license pricing inquiry" "$TECH_MAILBOX_ID" "carla.montez@example.com" "" "Hello, we are a large enterprise considering purchasing licenses for our 500-person engineering team. Could you please provide enterprise pricing tiers and any volume discount information? We would like to compare options before our Q2 budget decision. Please include multi-year contract pricing.")
else
    TECH_CONV_3="$TECH_CONV_3_EXISTS"
    # Ensure it's in Tech mailbox (for idempotency)
    if [ -n "$TECH_CONV_3" ] && [ -n "$TECH_MAILBOX_ID" ]; then
        fs_query "UPDATE conversations SET mailbox_id=$TECH_MAILBOX_ID WHERE id=$TECH_CONV_3" 2>/dev/null || true
    fi
fi
echo "Tech conv 3 ID (misrouted): $TECH_CONV_3"

# Conv 4: Reseller partnership (WRONG mailbox — should be Sales Inquiries)
TECH_CONV_4_EXISTS=$(fs_query "SELECT id FROM conversations WHERE subject='Reseller partnership program inquiry' LIMIT 1" 2>/dev/null || echo "")
if [ -z "$TECH_CONV_4_EXISTS" ]; then
    TECH_CONV_4=$(create_conversation_via_orm "Reseller partnership program inquiry" "$TECH_MAILBOX_ID" "jackson.webb@example.com" "" "We are a managed service provider interested in joining your reseller partner program. Could you share details about partner discounts, lead sharing arrangements, and co-marketing opportunities? We currently manage 80 clients who could benefit from your platform.")
else
    TECH_CONV_4="$TECH_CONV_4_EXISTS"
    # Ensure it's in Tech mailbox
    if [ -n "$TECH_CONV_4" ] && [ -n "$TECH_MAILBOX_ID" ]; then
        fs_query "UPDATE conversations SET mailbox_id=$TECH_MAILBOX_ID WHERE id=$TECH_CONV_4" 2>/dev/null || true
    fi
fi
echo "Tech conv 4 ID (misrouted): $TECH_CONV_4"

# ---- Seed Customer Success conversations ----
# Conv 5: Account upgrade (correct mailbox, unassigned, no reply)
CS_CONV_1_EXISTS=$(fs_query "SELECT id FROM conversations WHERE subject='Account upgrade to Enterprise tier' AND mailbox_id=$CS_MAILBOX_ID LIMIT 1" 2>/dev/null || echo "")
if [ -z "$CS_CONV_1_EXISTS" ]; then
    CS_CONV_1=$(create_conversation_via_orm "Account upgrade to Enterprise tier" "$CS_MAILBOX_ID" "priya.desai@example.com" "" "We have outgrown our current Professional plan and would like to upgrade to the Enterprise tier. We need SSO integration, dedicated support SLAs, and custom data retention policies. Please advise on the upgrade process and any data migration steps involved.")
else
    CS_CONV_1="$CS_CONV_1_EXISTS"
fi
echo "CS conv 1 ID: $CS_CONV_1"

# Conv 6: New client onboarding (correct mailbox, unassigned, no reply)
CS_CONV_2_EXISTS=$(fs_query "SELECT id FROM conversations WHERE subject='New client onboarding assistance' AND mailbox_id=$CS_MAILBOX_ID LIMIT 1" 2>/dev/null || echo "")
if [ -z "$CS_CONV_2_EXISTS" ]; then
    CS_CONV_2=$(create_conversation_via_orm "New client onboarding assistance" "$CS_MAILBOX_ID" "evan.liu@example.com" "" "We just signed up for your Enterprise plan last week and are beginning the onboarding process. We have a complex multi-department setup and need assistance configuring roles, permissions, SAML SSO, and data integrations with our existing CRM.")
else
    CS_CONV_2="$CS_CONV_2_EXISTS"
fi
echo "CS conv 2 ID: $CS_CONV_2"

# ---- Seed Sales Inquiries conversations ----
# Conv 7: Custom pricing (correct, no reply → should be tagged needs-follow-up)
SALES_CONV_1_EXISTS=$(fs_query "SELECT id FROM conversations WHERE subject='Custom pricing quote for startup bundle' AND mailbox_id=$SALES_MAILBOX_ID LIMIT 1" 2>/dev/null || echo "")
if [ -z "$SALES_CONV_1_EXISTS" ]; then
    SALES_CONV_1=$(create_conversation_via_orm "Custom pricing quote for startup bundle" "$SALES_MAILBOX_ID" "sofia.reyes@example.com" "" "We are a seed-stage startup with a team of 12. We saw your startup bundle offer and would like a custom pricing quote. Our budget is limited but we are projected to scale to 50 users within 6 months. Are there any startup-specific discounts available?")
else
    SALES_CONV_1="$SALES_CONV_1_EXISTS"
fi
echo "Sales conv 1 ID: $SALES_CONV_1"

# Conv 8: Annual renewal (correct, no reply → should be tagged needs-follow-up)
SALES_CONV_2_EXISTS=$(fs_query "SELECT id FROM conversations WHERE subject='Annual renewal options and discounts' AND mailbox_id=$SALES_MAILBOX_ID LIMIT 1" 2>/dev/null || echo "")
if [ -z "$SALES_CONV_2_EXISTS" ]; then
    SALES_CONV_2=$(create_conversation_via_orm "Annual renewal options and discounts" "$SALES_MAILBOX_ID" "marcus.holt@example.com" "" "Our annual subscription is up for renewal next month. We are very satisfied with the product but wanted to ask about any loyalty discounts or multi-year contract options before committing to another year at the current rate.")
else
    SALES_CONV_2="$SALES_CONV_2_EXISTS"
fi
echo "Sales conv 2 ID: $SALES_CONV_2"

# Conv 9: Invoice discrepancy (WRONG mailbox — should be Customer Success)
SALES_CONV_3_EXISTS=$(fs_query "SELECT id FROM conversations WHERE subject='Invoice discrepancy - overcharge on subscription' LIMIT 1" 2>/dev/null || echo "")
if [ -z "$SALES_CONV_3_EXISTS" ]; then
    SALES_CONV_3=$(create_conversation_via_orm "Invoice discrepancy - overcharge on subscription" "$SALES_MAILBOX_ID" "rachel.kim@example.com" "" "I noticed our invoice this month shows a charge of 2400 dollars for our Team plan, but we were quoted 1800 dollars when we signed up. There appears to be an overcharge of 600 dollars on our account. This needs to be investigated and corrected immediately as it has hit our budget.")
else
    SALES_CONV_3="$SALES_CONV_3_EXISTS"
    # Ensure it's in Sales mailbox for clean state
    if [ -n "$SALES_CONV_3" ] && [ -n "$SALES_MAILBOX_ID" ]; then
        fs_query "UPDATE conversations SET mailbox_id=$SALES_MAILBOX_ID WHERE id=$SALES_CONV_3" 2>/dev/null || true
    fi
fi
echo "Sales conv 3 ID (misrouted): $SALES_CONV_3"

# Conv 10: Team plan pricing comparison (correct, HAS agent reply → should NOT be tagged)
SALES_CONV_4_EXISTS=$(fs_query "SELECT id FROM conversations WHERE subject='Team plan upgrade pricing comparison' AND mailbox_id=$SALES_MAILBOX_ID LIMIT 1" 2>/dev/null || echo "")
if [ -z "$SALES_CONV_4_EXISTS" ]; then
    SALES_CONV_4=$(create_conversation_via_orm "Team plan upgrade pricing comparison" "$SALES_MAILBOX_ID" "brandon.lee@example.com" "" "We are currently on the Basic plan and considering upgrading to Team. Could you send a comparison of features between Basic, Team, and Pro plans? Also, what would our monthly cost be for 25 users on the Team plan?")
    # Add agent reply thread so this conversation shows as responded
    ADMIN_ID=$(fs_query "SELECT id FROM users WHERE role=1 LIMIT 1" 2>/dev/null || echo "")
    if [ -n "$SALES_CONV_4" ] && [ -n "$ADMIN_ID" ]; then
        fs_query "INSERT IGNORE INTO threads (conversation_id, user_id, type, status, state, body, source_via, created_at, updated_at) VALUES ($SALES_CONV_4, $ADMIN_ID, 2, 1, 1, 'Thank you for reaching out! I am happy to send over our plan comparison. For 25 users on the Team plan, your monthly cost would be 375 dollars. The Team plan includes advanced reporting, priority support, and API access. Would you like to schedule a demo?', 1, NOW(), NOW())" 2>/dev/null || true
        fs_query "UPDATE conversations SET threads_count=threads_count+1, first_reply_at=NOW() WHERE id=$SALES_CONV_4" 2>/dev/null || true
    fi
else
    SALES_CONV_4="$SALES_CONV_4_EXISTS"
fi
echo "Sales conv 4 ID (has reply): $SALES_CONV_4"

# ---- Ensure all conversations are unassigned ----
for CID in "$TECH_CONV_1" "$TECH_CONV_2" "$TECH_CONV_3" "$TECH_CONV_4" "$CS_CONV_1" "$CS_CONV_2" "$SALES_CONV_1" "$SALES_CONV_2" "$SALES_CONV_3"; do
    [ -n "$CID" ] && fs_query "UPDATE conversations SET user_id=NULL WHERE id=$CID" 2>/dev/null || true
done

# ---- Clear any pre-existing 'needs-follow-up' tag from these conversations ----
NFU_TAG_ID=$(fs_query "SELECT id FROM tags WHERE name='needs-follow-up' LIMIT 1" 2>/dev/null || echo "")
if [ -n "$NFU_TAG_ID" ]; then
    for CID in "$TECH_CONV_1" "$TECH_CONV_2" "$TECH_CONV_3" "$TECH_CONV_4" "$CS_CONV_1" "$CS_CONV_2" "$SALES_CONV_1" "$SALES_CONV_2" "$SALES_CONV_3" "$SALES_CONV_4"; do
        [ -n "$CID" ] && fs_query "DELETE FROM conversation_tag WHERE conversation_id=$CID AND tag_id=$NFU_TAG_ID" 2>/dev/null || true
    done
fi

# ---- Clear cache ----
docker exec freescout-app php /www/html/artisan cache:clear 2>/dev/null || true

# ---- Store IDs ----
echo "$CS_MAILBOX_ID" > /tmp/cs_mailbox_id_soc
echo "$TECH_MAILBOX_ID" > /tmp/tech_mailbox_id_soc
echo "$SALES_MAILBOX_ID" > /tmp/sales_mailbox_id_soc
echo "$RAJ_ID" > /tmp/raj_user_id
echo "$NINA_ID" > /tmp/nina_user_id
echo "$BEN_ID" > /tmp/ben_user_id
echo "$TECH_CONV_1" > /tmp/tech_conv_1_id
echo "$TECH_CONV_2" > /tmp/tech_conv_2_id
echo "$TECH_CONV_3" > /tmp/tech_conv_3_id
echo "$TECH_CONV_4" > /tmp/tech_conv_4_id
echo "$CS_CONV_1" > /tmp/cs_conv_1_id
echo "$CS_CONV_2" > /tmp/cs_conv_2_id
echo "$SALES_CONV_1" > /tmp/sales_conv_1_id
echo "$SALES_CONV_2" > /tmp/sales_conv_2_id
echo "$SALES_CONV_3" > /tmp/sales_conv_3_id
echo "$SALES_CONV_4" > /tmp/sales_conv_4_id

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Navigate to FreeScout
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
echo "CS Mailbox: $CS_MAILBOX_ID, Tech: $TECH_MAILBOX_ID, Sales: $SALES_MAILBOX_ID"
echo "Raj ID: $RAJ_ID (access: Tech+Sales — Sales should be removed)"
echo "Nina ID: $NINA_ID (access: CS — correct)"
echo "Ben ID: $BEN_ID (access: Sales only — CS should be added)"
echo "Tech convs (correct): $TECH_CONV_1, $TECH_CONV_2"
echo "Tech convs (misrouted to Sales): $TECH_CONV_3, $TECH_CONV_4"
echo "CS convs (correct): $CS_CONV_1, $CS_CONV_2"
echo "Sales convs (correct, no reply): $SALES_CONV_1, $SALES_CONV_2"
echo "Sales conv (misrouted to CS): $SALES_CONV_3"
echo "Sales conv (has reply, no tag): $SALES_CONV_4"
