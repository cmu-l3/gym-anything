#!/bin/bash
echo "=== Setting up remove_card_from_user task ==="
source /workspace/scripts/task_utils.sh

wait_for_ac_demo
ac_login

# Clean up prior Leon Fischer
EXISTING=$(ac_api GET "/users" | jq -r '.[] | select(.firstName=="Leon" and .lastName=="Fischer") | .id' 2>/dev/null)
for uid in $EXISTING; do
    ac_api DELETE "/users/$uid" > /dev/null 2>&1 && echo "Deleted prior Leon Fischer" || true
done

# Create Leon Fischer
echo "Creating Leon Fischer..."
USER_RESP=$(ac_api POST "/users" '{"firstName":"Leon","lastName":"Fischer","email":"leon.fischer@example.com","company":"Fischer Industries","enabled":true}')
USER_ID=$(echo "$USER_RESP" | jq -r '.id // .userId // empty' 2>/dev/null)
echo "Created Leon Fischer id=$USER_ID"
echo "$USER_ID" > /tmp/task_leon_fischer_id.txt

# Assign card 0007654321 to Leon
# Try common credential add paths
if [ -n "$USER_ID" ] && [ "$USER_ID" != "null" ]; then
    # Add card via API (field names match seed_ac_data.py: type=card, cardNumber=...)
    CARD_RESP=$(ac_api POST "/users/${USER_ID}/credentials" '{"type":"card","cardNumber":"0007654321"}' 2>/dev/null)
    echo "Card add response: $CARD_RESP"

    # Alternative endpoint if primary fails
    if echo "$CARD_RESP" | grep -qi "error\|not found\|404"; then
        CARD_RESP=$(ac_api POST "/credentials" "{\"userId\":${USER_ID},\"type\":\"card\",\"cardNumber\":\"0007654321\"}" 2>/dev/null)
        echo "Alt card add response: $CARD_RESP"
    fi

    launch_firefox_to "${AC_URL}/#/users/${USER_ID}" 8
else
    launch_firefox_to "${AC_URL}/#/users" 8
fi

take_screenshot /tmp/task_remove_card_start.png
echo "=== Task remove_card_from_user setup complete ==="
