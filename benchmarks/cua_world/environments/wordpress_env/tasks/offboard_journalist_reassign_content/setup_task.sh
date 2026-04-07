#!/bin/bash
# Setup script for offboard_journalist_reassign_content task (pre_task hook)

echo "=== Setting up offboard_journalist_reassign_content task ==="

source /workspace/scripts/task_utils.sh
cd /var/www/html/wordpress

# Record task start timestamp
date +%s > /tmp/task_start_timestamp
chmod 666 /tmp/task_start_timestamp

echo "Cleaning up any previous state..."
wp user delete jdoe --yes --allow-root 2>/dev/null || true
wp user delete editorial_archives --yes --allow-root 2>/dev/null || true
wp user delete asmith --yes --allow-root 2>/dev/null || true

echo "Creating users..."
wp user create jdoe john.doe@localnews.com --role=author --first_name="John" --last_name="Doe" --user_pass="Jdoe2026!" --allow-root
JDOE_ID=$(wp user get jdoe --field=ID --allow-root)

wp user create asmith alice.smith@localnews.com --role=author --first_name="Alice" --last_name="Smith" --user_pass="Asmith2026!" --allow-root
ASMITH_ID=$(wp user get asmith --field=ID --allow-root)

echo "Injecting realistic published content for John Doe (Target)..."
P1_ID=$(wp post create --post_title="City Council Approves New Transit Budget" --post_content="After three weeks of intense debate, the city council has officially approved the $4.2 million transit expansion budget. The new funding will prioritize the extension of the light rail system into the northern suburbs, a project that has been delayed since 2022. Mayor Thomas called the vote 'a historic step forward for regional connectivity.' Construction is slated to begin early next spring." --post_status=publish --post_author=$JDOE_ID --porcelain --allow-root)

P2_ID=$(wp post create --post_title="Downtown Tech Hub Announces Expansion" --post_content="The downtown innovation district is growing. Tech conglomerate SynergyCorp announced today they have signed a lease for an additional 40,000 square feet in the historic Apex Building. This move is expected to bring over 200 new engineering jobs to the city center over the next 18 months. Local businesses are already preparing for the influx of daytime foot traffic." --post_status=publish --post_author=$JDOE_ID --porcelain --allow-root)

P3_ID=$(wp post create --post_title="Local High School Wins State Championship" --post_content="In a stunning upset, the Oakridge Eagles defeated the reigning champion Spartans 3-2 in overtime to claim their first state soccer title in over two decades. Senior forward Marcus Chen scored the winning goal in the 94th minute, sending the traveling student section into an absolute frenzy." --post_status=publish --post_author=$JDOE_ID --porcelain --allow-root)

P4_ID=$(wp post create --post_title="Annual Food Festival Draws Record Crowds" --post_content="Despite the overcast weather, this year's Taste of the Valley food festival saw record-breaking attendance, with organizers estimating over 15,000 visitors throughout the weekend. Over 50 local vendors participated, with the 'Best in Show' award going to newcomers Mama Rosa's Empanadas." --post_status=publish --post_author=$JDOE_ID --porcelain --allow-root)

echo "Injecting realistic drafts for John Doe..."
D1_ID=$(wp post create --post_title="Local Election Results Preview" --post_content="Draft notes: Need to interview the incumbent on Tuesday. The polling data suggests a tight race in District 4. [TODO: Add demographic breakdown table here]." --post_status=draft --post_author=$JDOE_ID --porcelain --allow-root)

D2_ID=$(wp post create --post_title="Opinion: The Future of Remote Work" --post_content="It's been years since the pandemic shifted our working habits, but local downtown businesses are still feeling the squeeze. As commercial real estate vacancies hover around 18%, we have to ask: is the five-day office week gone forever? [Need to flesh out the second paragraph]." --post_status=draft --post_author=$JDOE_ID --porcelain --allow-root)

echo "Injecting content for Alice Smith (Bystander/Anti-gaming check)..."
A1_ID=$(wp post create --post_title="Review: The Best Coffee Shops Downtown" --post_content="We spent the last month visiting every independent coffee roaster within the city limits. Here are the top five places to get your morning espresso fix." --post_status=publish --post_author=$ASMITH_ID --porcelain --allow-root)

A2_ID=$(wp post create --post_title="Interview: Mayor Discusses Infrastructure" --post_content="We sat down with Mayor Thomas to discuss the recent pothole repair initiative and what residents can expect from the upcoming summer construction season." --post_status=publish --post_author=$ASMITH_ID --porcelain --allow-root)

A3_ID=$(wp post create --post_title="Weekend Weather Outlook: Rain Expected" --post_content="Keep your umbrellas handy. Meteorologists are predicting a heavy band of showers moving through the region starting late Friday night and continuing into Sunday morning." --post_status=publish --post_author=$ASMITH_ID --porcelain --allow-root)

# Save the IDs for the export script to use
cat > /tmp/task_post_ids.sh << EOF
JDOE_PUB_IDS=($P1_ID $P2_ID $P3_ID $P4_ID)
JDOE_DRAFT_IDS=($D1_ID $D2_ID)
ASMITH_PUB_IDS=($A1_ID $A2_ID $A3_ID)
EOF
chmod 666 /tmp/task_post_ids.sh

echo "Checking Firefox status..."
if ! pgrep -x "firefox" > /dev/null 2>&1; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/users.php' > /tmp/firefox_restart.log 2>&1 &"
    sleep 8
fi

WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|wordpress" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="