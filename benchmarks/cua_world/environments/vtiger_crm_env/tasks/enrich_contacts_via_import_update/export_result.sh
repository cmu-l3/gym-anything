#!/bin/bash
echo "=== Exporting enrich_contacts results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/enrich_contacts_final.png

# 2. Get task start time and initial count
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_contact_count.txt 2>/dev/null || echo "0")

# 3. Get current total contact count
CURRENT_COUNT=$(docker exec vtiger-db mysql -u vtiger -pvtiger_pass vtiger -N -e "SELECT COUNT(*) FROM vtiger_crmentity WHERE setype='Contacts' AND deleted=0" 2>/dev/null || echo "0")

# 4. Query the 10 target contacts
TARGET_EMAILS="'m.scott@example.com','p.beesly@example.com','j.halpert@example.com','d.schrute@example.com','a.martin@example.com','k.malone@example.com','o.martinez@example.com','s.hudson@example.com','p.vance@example.com','k.kapoor@example.com'"

QUERY="SELECT c.email, c.title, c.phone, UNIX_TIMESTAMP(e.modifiedtime) 
       FROM vtiger_contactdetails c 
       JOIN vtiger_crmentity e ON c.contactid = e.crmid 
       WHERE c.email IN ($TARGET_EMAILS) AND e.deleted=0"

CONTACTS_DATA=$(docker exec vtiger-db mysql -u vtiger -pvtiger_pass vtiger -N -e "$QUERY" 2>/dev/null)

# 5. Build JSON array of results
CONTACTS_JSON="["
while IFS=$'\t' read -r email title phone modtime; do
    if [ -z "$email" ]; then continue; fi
    # Escape quotes
    title_esc=$(json_escape "$title")
    phone_esc=$(json_escape "$phone")
    CONTACTS_JSON="${CONTACTS_JSON}{\"email\":\"$email\", \"title\":\"$title_esc\", \"phone\":\"$phone_esc\", \"modifiedtime\":${modtime:-0}},"
done <<< "$CONTACTS_DATA"

# Remove trailing comma and close array
CONTACTS_JSON="${CONTACTS_JSON%,}]"
if [ "$CONTACTS_JSON" = "]" ]; then CONTACTS_JSON="[]"; fi

# 6. Construct final JSON
RESULT_JSON=$(cat << JSONEOF
{
  "task_start_time": ${TASK_START},
  "initial_count": ${INITIAL_COUNT},
  "current_count": ${CURRENT_COUNT},
  "contacts_data": ${CONTACTS_JSON}
}
JSONEOF
)

# 7. Write to temp file then move to secure location
TEMP_FILE=$(mktemp)
echo "$RESULT_JSON" > "$TEMP_FILE"
rm -f /tmp/enrich_contacts_result.json 2>/dev/null || sudo rm -f /tmp/enrich_contacts_result.json 2>/dev/null || true
cp "$TEMP_FILE" /tmp/enrich_contacts_result.json 2>/dev/null || sudo cp "$TEMP_FILE" /tmp/enrich_contacts_result.json
chmod 666 /tmp/enrich_contacts_result.json 2>/dev/null || sudo chmod 666 /tmp/enrich_contacts_result.json 2>/dev/null || true
rm -f "$TEMP_FILE"

echo "Result saved to /tmp/enrich_contacts_result.json"
cat /tmp/enrich_contacts_result.json
echo "=== enrich_contacts export complete ==="