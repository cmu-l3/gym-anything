#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Transform API Response Task ==="

# Create workspace
WORKSPACE_DIR="/home/ga/workspace/data"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Generate the JSON file with 50 records
cat > "$WORKSPACE_DIR/api_response.json" << 'EOF'
{
  "data": [
    {"id": 1001, "user_name": "alice_smith", "user_email": "alice@example.com", "profile": {"department": "Engineering", "level": "Senior"}, "last_login": "2024-01-15T14:23:45Z", "status": "active", "tags": ["premium", "verified"]},
    {"id": 1002, "user_name": "bob_jones", "user_email": "bob@example.com", "profile": {"department": "Sales", "level": "Junior"}, "last_login": null, "status": "inactive", "tags": ["trial"]},
    {"id": 1003, "user_name": "charlie_brown", "user_email": "charlie@example.com", "profile": {"department": "Marketing", "level": "Mid"}, "last_login": "2024-02-10T09:15:30Z", "status": "active", "tags": ["premium"]},
    {"id": 1004, "user_name": "diana_prince", "user_email": "diana@example.com", "profile": {"department": "Engineering", "level": "Staff"}, "last_login": "2024-03-05T16:45:12Z", "status": "active", "tags": ["premium", "verified", "beta"]},
    {"id": 1005, "user_name": "evan_thomas", "user_email": "evan@example.com", "profile": {"department": "Support", "level": "Junior"}, "last_login": "2024-01-20T11:30:00Z", "status": "active", "tags": []},
    {"id": 1006, "user_name": "fiona_green", "user_email": "fiona@example.com", "profile": {"department": "Sales", "level": "Senior"}, "last_login": null, "status": "inactive", "tags": ["trial"]},
    {"id": 1007, "user_name": "george_martin", "user_email": "george@example.com", "profile": {"department": "Engineering", "level": "Mid"}, "last_login": "2024-02-28T13:20:45Z", "status": "active", "tags": ["verified"]},
    {"id": 1008, "user_name": "hannah_lee", "user_email": "hannah@example.com", "profile": {"department": "Marketing", "level": "Senior"}, "last_login": "2024-03-10T10:00:00Z", "status": "active", "tags": ["premium", "verified"]},
    {"id": 1009, "user_name": "ian_wright", "user_email": "ian@example.com", "profile": {"department": "Engineering", "level": "Junior"}, "last_login": "2024-01-05T08:15:30Z", "status": "active", "tags": ["trial"]},
    {"id": 1010, "user_name": "jane_doe", "user_email": "jane@example.com", "profile": {"department": "Support", "level": "Mid"}, "last_login": null, "status": "inactive", "tags": ["premium"]},
    {"id": 1011, "user_name": "kevin_ng", "user_email": "kevin@example.com", "profile": {"department": "Sales", "level": "Mid"}, "last_login": "2024-02-15T15:30:20Z", "status": "active", "tags": ["verified"]},
    {"id": 1012, "user_name": "laura_palmer", "user_email": "laura@example.com", "profile": {"department": "Engineering", "level": "Staff"}, "last_login": "2024-03-08T12:45:00Z", "status": "active", "tags": ["premium", "verified", "beta"]},
    {"id": 1013, "user_name": "mike_ross", "user_email": "mike@example.com", "profile": {"department": "Marketing", "level": "Junior"}, "last_login": "2024-01-25T09:00:00Z", "status": "active", "tags": []},
    {"id": 1014, "user_name": "nancy_drew", "user_email": "nancy@example.com", "profile": {"department": "Support", "level": "Senior"}, "last_login": "2024-02-20T14:15:45Z", "status": "active", "tags": ["premium", "verified"]},
    {"id": 1015, "user_name": "oscar_wilde", "user_email": "oscar@example.com", "profile": {"department": "Engineering", "level": "Senior"}, "last_login": null, "status": "inactive", "tags": ["trial"]},
    {"id": 1016, "user_name": "paula_abdul", "user_email": "paula@example.com", "profile": {"department": "Sales", "level": "Junior"}, "last_login": "2024-03-01T11:20:30Z", "status": "active", "tags": ["trial"]},
    {"id": 1017, "user_name": "quinn_hayes", "user_email": "quinn@example.com", "profile": {"department": "Marketing", "level": "Mid"}, "last_login": "2024-02-05T10:30:15Z", "status": "active", "tags": ["premium"]},
    {"id": 1018, "user_name": "rachel_green", "user_email": "rachel@example.com", "profile": {"department": "Engineering", "level": "Mid"}, "last_login": "2024-01-30T16:45:00Z", "status": "active", "tags": ["verified"]},
    {"id": 1019, "user_name": "steve_jobs", "user_email": "steve@example.com", "profile": {"department": "Support", "level": "Staff"}, "last_login": "2024-03-12T09:15:20Z", "status": "active", "tags": ["premium", "verified", "beta"]},
    {"id": 1020, "user_name": "tina_fey", "user_email": "tina@example.com", "profile": {"department": "Sales", "level": "Senior"}, "last_login": null, "status": "inactive", "tags": ["premium"]},
    {"id": 1021, "user_name": "uma_thurman", "user_email": "uma@example.com", "profile": {"department": "Engineering", "level": "Junior"}, "last_login": "2024-02-12T13:00:00Z", "status": "active", "tags": []},
    {"id": 1022, "user_name": "victor_hugo", "user_email": "victor@example.com", "profile": {"department": "Marketing", "level": "Senior"}, "last_login": "2024-01-18T14:30:45Z", "status": "active", "tags": ["premium", "verified"]},
    {"id": 1023, "user_name": "wendy_wang", "user_email": "wendy@example.com", "profile": {"department": "Support", "level": "Mid"}, "last_login": "2024-03-03T11:45:30Z", "status": "active", "tags": ["trial"]},
    {"id": 1024, "user_name": "xander_cage", "user_email": "xander@example.com", "profile": {"department": "Engineering", "level": "Staff"}, "last_login": "2024-02-25T15:20:10Z", "status": "active", "tags": ["premium", "verified", "beta"]},
    {"id": 1025, "user_name": "yara_shahidi", "user_email": "yara@example.com", "profile": {"department": "Sales", "level": "Mid"}, "last_login": null, "status": "inactive", "tags": ["verified"]},
    {"id": 1026, "user_name": "zoe_kravitz", "user_email": "zoe@example.com", "profile": {"department": "Marketing", "level": "Junior"}, "last_login": "2024-01-22T10:15:00Z", "status": "active", "tags": ["premium"]},
    {"id": 1027, "user_name": "aaron_paul", "user_email": "aaron@example.com", "profile": {"department": "Engineering", "level": "Senior"}, "last_login": "2024-03-06T12:30:45Z", "status": "active", "tags": ["verified"]},
    {"id": 1028, "user_name": "betty_white", "user_email": "betty@example.com", "profile": {"department": "Support", "level": "Senior"}, "last_login": "2024-02-18T09:45:20Z", "status": "active", "tags": ["premium", "verified"]},
    {"id": 1029, "user_name": "chris_evans", "user_email": "chris@example.com", "profile": {"department": "Sales", "level": "Junior"}, "last_login": "2024-01-28T14:00:00Z", "status": "active", "tags": []},
    {"id": 1030, "user_name": "debra_messing", "user_email": "debra@example.com", "profile": {"department": "Marketing", "level": "Mid"}, "last_login": null, "status": "inactive", "tags": ["trial"]},
    {"id": 1031, "user_name": "ethan_hawke", "user_email": "ethan@example.com", "profile": {"department": "Engineering", "level": "Mid"}, "last_login": "2024-03-09T11:20:30Z", "status": "active", "tags": ["premium"]},
    {"id": 1032, "user_name": "felicity_jones", "user_email": "felicity@example.com", "profile": {"department": "Support", "level": "Staff"}, "last_login": "2024-02-22T15:45:15Z", "status": "active", "tags": ["premium", "verified", "beta"]},
    {"id": 1033, "user_name": "grant_gustin", "user_email": "grant@example.com", "profile": {"department": "Sales", "level": "Senior"}, "last_login": "2024-01-12T10:30:00Z", "status": "active", "tags": ["verified"]},
    {"id": 1034, "user_name": "halle_berry", "user_email": "halle@example.com", "profile": {"department": "Engineering", "level": "Junior"}, "last_login": "2024-03-04T13:15:45Z", "status": "active", "tags": ["trial"]},
    {"id": 1035, "user_name": "idris_elba", "user_email": "idris@example.com", "profile": {"department": "Marketing", "level": "Senior"}, "last_login": null, "status": "inactive", "tags": ["premium", "verified"]},
    {"id": 1036, "user_name": "jennifer_lawrence", "user_email": "jennifer@example.com", "profile": {"department": "Support", "level": "Mid"}, "last_login": "2024-02-08T09:00:20Z", "status": "active", "tags": []},
    {"id": 1037, "user_name": "keanu_reeves", "user_email": "keanu@example.com", "profile": {"department": "Engineering", "level": "Staff"}, "last_login": "2024-01-16T14:45:30Z", "status": "active", "tags": ["premium", "verified", "beta"]},
    {"id": 1038, "user_name": "lucy_liu", "user_email": "lucy@example.com", "profile": {"department": "Sales", "level": "Mid"}, "last_login": "2024-03-11T12:00:00Z", "status": "active", "tags": ["premium"]},
    {"id": 1039, "user_name": "morgan_freeman", "user_email": "morgan@example.com", "profile": {"department": "Marketing", "level": "Junior"}, "last_login": "2024-02-14T11:30:45Z", "status": "active", "tags": ["verified"]},
    {"id": 1040, "user_name": "natalie_portman", "user_email": "natalie@example.com", "profile": {"department": "Engineering", "level": "Senior"}, "last_login": null, "status": "inactive", "tags": ["trial"]},
    {"id": 1041, "user_name": "owen_wilson", "user_email": "owen@example.com", "profile": {"department": "Support", "level": "Senior"}, "last_login": "2024-01-24T10:15:20Z", "status": "active", "tags": ["premium", "verified"]},
    {"id": 1042, "user_name": "penelope_cruz", "user_email": "penelope@example.com", "profile": {"department": "Sales", "level": "Junior"}, "last_login": "2024-03-07T15:30:00Z", "status": "active", "tags": []},
    {"id": 1043, "user_name": "quentin_tarantino", "user_email": "quentin@example.com", "profile": {"department": "Marketing", "level": "Mid"}, "last_login": "2024-02-11T13:45:15Z", "status": "active", "tags": ["premium"]},
    {"id": 1044, "user_name": "reese_witherspoon", "user_email": "reese@example.com", "profile": {"department": "Engineering", "level": "Mid"}, "last_login": "2024-01-19T09:20:30Z", "status": "active", "tags": ["verified"]},
    {"id": 1045, "user_name": "samuel_jackson", "user_email": "samuel@example.com", "profile": {"department": "Support", "level": "Staff"}, "last_login": "2024-03-13T14:00:45Z", "status": "active", "tags": ["premium", "verified", "beta"]},
    {"id": 1046, "user_name": "tessa_thompson", "user_email": "tessa@example.com", "profile": {"department": "Sales", "level": "Senior"}, "last_login": null, "status": "inactive", "tags": ["premium"]},
    {"id": 1047, "user_name": "vin_diesel", "user_email": "vin@example.com", "profile": {"department": "Engineering", "level": "Junior"}, "last_login": "2024-02-16T11:45:00Z", "status": "active", "tags": ["trial"]},
    {"id": 1048, "user_name": "will_smith", "user_email": "will@example.com", "profile": {"department": "Marketing", "level": "Senior"}, "last_login": "2024-01-26T12:30:20Z", "status": "active", "tags": ["premium", "verified"]},
    {"id": 1049, "user_name": "zendaya_coleman", "user_email": "zendaya@example.com", "profile": {"department": "Support", "level": "Mid"}, "last_login": "2024-03-02T10:00:15Z", "status": "active", "tags": ["verified"]},
    {"id": 1050, "user_name": "adam_driver", "user_email": "adam@example.com", "profile": {"department": "Engineering", "level": "Staff"}, "last_login": "2024-02-24T16:15:30Z", "status": "active", "tags": ["premium", "verified", "beta"]}
  ]
}
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"

# Open VSCode with the workspace
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR' '$WORKSPACE_DIR/api_response.json'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Transform API Response Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Review the JSON file structure in api_response.json"
echo "  2. Transform it to CSV format with flattened data"
echo "  3. Save as users_export.csv in the same directory"
echo "  4. Apply required transformations:"
echo "     - Flatten nested profile object"
echo "     - Convert timestamps to YYYY-MM-DD format"
echo "     - Handle null values as 'N/A'"
echo "     - Convert tags arrays to comma-separated strings"
echo ""
echo "Input: /home/ga/workspace/data/api_response.json"
echo "Output: /home/ga/workspace/data/users_export.csv"