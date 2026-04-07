#!/bin/bash
echo "=== Exporting service_desk_ticket_resolution result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# We need to find the tickets in the database and their statuses and comments.
# To be robust against schema differences, we will search all text fields in tables containing 'service'.

TEMP_JSON=$(mktemp /tmp/service_desk_result.XXXXXX.json)

# Initialize JSON with start/end times
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

echo "{" > "$TEMP_JSON"
echo "  \"task_start\": $TASK_START," >> "$TEMP_JSON"
echo "  \"task_end\": $TASK_END," >> "$TEMP_JSON"
echo "  \"tickets\": {" >> "$TEMP_JSON"

# Find table names
REQ_TABLE=$(docker exec sentrifugo-db mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" -N -e "SHOW TABLES LIKE '%servicerequest%';" | head -1)
COM_TABLE=$(docker exec sentrifugo-db mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" -N -e "SHOW TABLES LIKE '%servicecomment%';" | head -1)
if [ -z "$REQ_TABLE" ]; then REQ_TABLE="main_servicerequests"; fi
if [ -z "$COM_TABLE" ]; then COM_TABLE="main_servicerequestcomments"; fi

# Function to get ticket status and comments
get_ticket_data() {
    local subject_like="$1"
    
    # Get status and ID
    local ticket_info=$(docker exec sentrifugo-db mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" -N -e "SELECT id, status FROM $REQ_TABLE WHERE subject LIKE '%$subject_like%' ORDER BY id DESC LIMIT 1;" 2>/dev/null || echo "")
    
    local tid=""
    local tstatus=""
    local comments=""
    
    if [ -n "$ticket_info" ]; then
        tid=$(echo "$ticket_info" | awk '{print $1}')
        tstatus=$(echo "$ticket_info" | awk '{$1=""; print $0}' | sed 's/^[ \t]*//')
        
        # Get comments
        if [ -n "$tid" ]; then
            comments=$(docker exec sentrifugo-db mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" -N -e "SELECT comment FROM $COM_TABLE WHERE request_id=$tid OR servicerequest_id=$tid;" 2>/dev/null | tr '\n' ' ' | sed 's/"/\\"/g' || echo "")
            # If the comment table schema is different, just dump the whole table and grep
            if [ -z "$comments" ]; then
                comments=$(docker exec sentrifugo-db mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" -N -e "SELECT * FROM $COM_TABLE WHERE request_id=$tid OR servicerequest_id=$tid;" 2>/dev/null | tr '\n' ' ' | sed 's/"/\\"/g' || echo "")
            fi
        fi
    fi
    
    # Fallback if status not found, try to dump the request table row
    if [ -z "$tstatus" ]; then
        local row_dump=$(docker exec sentrifugo-db mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" -N -e "SELECT * FROM $REQ_TABLE WHERE subject LIKE '%$subject_like%';" 2>/dev/null || echo "")
        if echo "$row_dump" | grep -qi "Closed"; then
            tstatus="Closed"
        elif echo "$row_dump" | grep -qi "Open"; then
            tstatus="Open"
        fi
    fi
    
    # Fallback for comments if not found in comment table: check the request table itself (maybe updated description)
    if [ -z "$comments" ] && [ -n "$tid" ]; then
        local req_row=$(docker exec sentrifugo-db mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" -N -e "SELECT * FROM $REQ_TABLE WHERE id=$tid;" 2>/dev/null | tr '\n' ' ' | sed 's/"/\\"/g' || echo "")
        comments="$req_row"
    fi
    
    echo "{\"status\": \"$tstatus\", \"comments\": \"$comments\"}"
}

echo "    \"vpn\": $(get_ticket_data 'VPN access failing')," >> "$TEMP_JSON"
echo "    \"monitor\": $(get_ticket_data 'secondary monitor')," >> "$TEMP_JSON"
echo "    \"ac\": $(get_ticket_data 'AC in zone')," >> "$TEMP_JSON"
echo "    \"payroll\": $(get_ticket_data 'Payroll tax deduction')," >> "$TEMP_JSON"
echo "    \"desk\": $(get_ticket_data 'ergonomic standing desk')" >> "$TEMP_JSON"

echo "  }," >> "$TEMP_JSON"
echo "  \"screenshot_path\": \"/tmp/task_end_screenshot.png\"" >> "$TEMP_JSON"
echo "}" >> "$TEMP_JSON"

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="