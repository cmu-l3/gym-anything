#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Generate Parameterized Fixtures Task ==="

WORKSPACE_DIR="/home/ga/workspace/test_fixtures"
TASK_ASSETS="/workspace/tasks/generate_parameterized_fixtures/assets"

# Create workspace directory
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create template_user.json
cat > "$WORKSPACE_DIR/template_user.json" << 'EOF'
{
  "userId": 1001,
  "profile": {
    "firstName": "Alice",
    "lastName": "Johnson",
    "email": "alice.johnson@example.com",
    "age": 28
  },
  "membership": {
    "tier": "bronze",
    "registeredDate": "2023-03-15"
  },
  "location": {
    "city": "New York",
    "country": "USA"
  },
  "accountBalance": 125.50
}
EOF

# Create requirements.txt
cat > "$WORKSPACE_DIR/requirements.txt" << 'EOF'
Generate Parameterized User Fixtures - Requirements
====================================================

Total users: 20
User IDs: 1001-1020 (sequential, all unique)

Name Requirements:
- At least 15 different first names across 20 users
- Each email must be unique
- Email format: firstname.lastname@example.com (lowercase)

Age Requirements:
- All ages between 18-65 (inclusive)

Membership Distribution:
- Bronze tier: 8 users (±1 acceptable)
- Silver tier: 7 users (±1 acceptable)
- Gold tier: 5 users (±1 acceptable)

Location Requirements:
- Use at least 4 different cities from this list:
  * New York
  * London
  * Tokyo
  * Berlin
  * Toronto
  * Sydney

Date Requirements:
- Registration dates spanning at least 6 different months
- Use dates from 2023-2024
- Format: YYYY-MM-DD

Account Balance:
- Range: $0 to $500
- Can use decimal values

Output File:
- Path: /home/ga/workspace/test_fixtures/users_fixture.json
- Format: Valid JSON array containing 20 user objects
- Each object should follow the structure in template_user.json
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"

# Open VSCode with workspace
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

# Open template and requirements files
sleep 1
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR/template_user.json'" || true
sleep 1
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR/requirements.txt'" || true
sleep 1

echo "=== Generate Parameterized Fixtures Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Review template_user.json for the structure to follow"
echo "  2. Review requirements.txt for all constraints"
echo "  3. Create users_fixture.json with 20 varied user objects"
echo "  4. Use multi-cursor editing, find/replace for efficiency"
echo "  5. Ensure all requirements are met (IDs, emails, names, tiers, etc.)"
echo ""
echo "💡 Tips:"
echo "  - Duplicate template 20 times into JSON array structure"
echo "  - Use multi-cursor (Alt+Click) to edit multiple fields at once"
echo "  - Use find/replace (Ctrl+H) for systematic updates"
echo "  - Verify JSON syntax is valid before saving"