#!/bin/bash
# Setup: create_person_attribute_type task
# Ensures the "Driver's License Number" attribute type does NOT exist, then logs in.

echo "=== Setting up create_person_attribute_type task ==="
source /workspace/scripts/task_utils.sh

# 1. Record task start time (anti-gaming)
# We use the DB server's time if possible to align with date_created, but 
# since both are on the same machine/docker host, date +%s is fine.
date +%s > /tmp/task_start_timestamp

# 2. Clean up: Remove the attribute type if it already exists
echo "Checking for existing 'Driver's License Number' attribute type..."

# We use the direct DB query utility to clean up to ensure a clean slate
# Note: Escape single quotes in the SQL value
omrs_db_query "DELETE FROM person_attribute_type WHERE name = 'Driver\'s License Number';" 2>/dev/null

# Verify it's gone
COUNT=$(omrs_db_query "SELECT COUNT(*) FROM person_attribute_type WHERE name = 'Driver\'s License Number';" 2>/dev/null)
if [ "$COUNT" != "0" ]; then
    echo "WARNING: Failed to delete existing attribute type. Task verification might be ambiguous."
else
    echo "Clean state confirmed: Attribute type does not exist."
fi

# 3. Open Firefox and log in
# We start at the O3 Home page. The agent needs to find the Admin link.
# Alternatively, we could start them at the Legacy Admin page, but finding it is part of the admin task.
ensure_openmrs_logged_in "http://localhost/openmrs/spa/home"

# 4. Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo ""
echo "=== create_person_attribute_type task setup complete ==="
echo ""
echo "TASK: Create Person Attribute Type"
echo "  Name:        Driver's License Number"
echo "  Format:      java.lang.String"
echo "  Description: Government issued driver license ID"
echo ""
echo "You need to access the Legacy Administration UI to perform this task."