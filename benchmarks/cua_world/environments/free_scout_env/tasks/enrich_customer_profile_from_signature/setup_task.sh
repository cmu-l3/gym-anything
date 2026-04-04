#!/bin/bash
set -e
echo "=== Setting up enrich_customer_profile task ==="

source /workspace/scripts/task_utils.sh

# 1. Generate Random Persona Data
FIRST_NAMES=("Thomas" "James" "Sarah" "Emily" "Michael" "Jessica" "David" "Jennifer")
LAST_NAMES=("Simpson" "Chen" "Rodriguez" "Taylor" "Nguyen" "Wright" "Patel" "Kim")
TITLES=("Senior Architect" "Marketing Director" "Software Engineer" "Operations Manager" "Legal Counsel" "Financial Analyst")
COMPANIES=("Creative Solutions" "TechFlow Inc." "Apex Logistics" "City Planning Dept" "Global Trade Co." "Summit Systems")

# Seed random generator
RANDOM=$$$(date +%s)

RAND_IDX=$((RANDOM % ${#FIRST_NAMES[@]}))
TRUE_FIRST="${FIRST_NAMES[$RAND_IDX]}"
TRUE_LAST="${LAST_NAMES[$RAND_IDX]}"

RAND_IDX=$((RANDOM % ${#TITLES[@]}))
TRUE_TITLE="${TITLES[$RAND_IDX]}"

RAND_IDX=$((RANDOM % ${#COMPANIES[@]}))
TRUE_COMPANY="${COMPANIES[$RAND_IDX]}"

# Generate a phone number (Format: (555) XXX-XXXX)
PH_A=$((100 + RANDOM % 899))
PH_B=$((1000 + RANDOM % 8999))
TRUE_PHONE="(555) $PH_A-$PH_B"

# Initial "Bad" Data (what the agent sees initially)
INITIAL_FIRST="${TRUE_FIRST:0:1}."
INITIAL_LAST="$TRUE_LAST"
CUSTOMER_EMAIL="$(echo "${TRUE_FIRST:0:1}${TRUE_LAST}" | tr '[:upper:]' '[:lower:]')@tenant-portal.net"

# Save ground truth for export_result.sh to pick up later
mkdir -p /tmp/task_data
cat > /tmp/task_data/ground_truth.json <<EOF
{
  "first_name": "$TRUE_FIRST",
  "last_name": "$TRUE_LAST",
  "phone": "$TRUE_PHONE",
  "title": "$TRUE_TITLE",
  "company": "$TRUE_COMPANY",
  "email": "$CUSTOMER_EMAIL"
}
EOF
chmod 644 /tmp/task_data/ground_truth.json

echo "Generated Persona: $TRUE_FIRST $TRUE_LAST, $TRUE_TITLE, $TRUE_PHONE"

# 2. Create Mailbox
MAILBOX_ID=$(ensure_mailbox_exists "Leasing Office" "leasing@skyline-heights.local")
echo "Mailbox ID: $MAILBOX_ID"

# 3. Create Customer (with incomplete data) via ORM
# We use tinker to create customer to ensure ID is captured correctly
CUST_ID=$(fs_tinker "
\$c = new \\App\\Customer();
\$c->first_name = '$INITIAL_FIRST';
\$c->last_name = '$INITIAL_LAST';
\$c->type = 1;
\$c->save();
\$e = new \\App\\Email();
\$e->email = '$CUSTOMER_EMAIL';
\$e->type = 1;
\$e->customer_id = \$c->id;
\$e->save();
echo 'CUST_ID:' . \$c->id;
" | grep 'CUST_ID:' | sed 's/CUST_ID://' | tr -cd '0-9')

echo "Created Customer ID: $CUST_ID ($INITIAL_FIRST $INITIAL_LAST)"

# 4. Create Conversation with Signature containing the info
# Note: We include <br> for HTML formatting in body
BODY="Hi Property Management,<br><br>
I have a question about the lease renewal terms for Unit 402, specifically regarding the pet deposit clause.<br><br>
Could you please give me a call to discuss?<br><br>
Thanks,<br><br>
<strong>$TRUE_FIRST $TRUE_LAST</strong><br>
$TRUE_TITLE<br>
$TRUE_COMPANY<br>
Direct: $TRUE_PHONE"

# Create the conversation
CONV_ID=$(create_conversation_via_orm "Lease Renewal Question" "$MAILBOX_ID" "$CUSTOMER_EMAIL" "$CUST_ID" "$BODY")
echo "Created Conversation ID: $CONV_ID"

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clear cache to ensure data appears
docker exec freescout-app php /www/html/artisan cache:clear 2>/dev/null || true

# 5. Launch Firefox
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080' > /dev/null 2>&1 &"
    sleep 5
fi

# Wait for Firefox and navigate
wait_for_window "firefox|mozilla|freescout" 30
focus_firefox
navigate_to_url "http://localhost:8080/mailbox/$MAILBOX_ID"
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="