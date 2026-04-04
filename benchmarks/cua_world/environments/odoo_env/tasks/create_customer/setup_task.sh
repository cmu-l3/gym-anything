#!/bin/bash
# Setup script for Create Customer task

echo "=== Setting up Create Customer Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record initial partner count for verification (via Docker)
echo "Recording initial partner count..."
INITIAL_COUNT=$(odoo_query "SELECT COUNT(*) FROM res_partner" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_partner_count
echo "Initial partner count: $INITIAL_COUNT"

# Ensure Firefox is running and focused on Odoo
echo "Ensuring Firefox is running..."
ODOO_LOGIN_URL="http://localhost:8069/web/login?db=odoo_demo"

if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$ODOO_LOGIN_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Wait for Firefox window
if ! wait_for_window "firefox\|mozilla\|Odoo" 30; then
    echo "WARNING: Firefox window not detected"
fi

# Focus Firefox window
echo "Focusing Firefox window..."
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    # Maximize window
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Click on center of screen to ensure desktop is selected
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 960 540 click 1" || true
sleep 0.5

# Focus Firefox again
if [ -n "$WID" ]; then
    focus_window "$WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Create Customer Task Setup Complete ==="
echo ""
echo "Task Instructions:"
echo "  1. Log in to Odoo if not already logged in"
echo "     - Email: admin@example.com"
echo "     - Password: admin"
echo "     - Database: odoo_demo"
echo ""
echo "  2. Click on the 'Contacts' app (or search for it)"
echo ""
echo "  3. Click 'Create' or 'New' button"
echo ""
echo "  4. Fill in the customer details:"
echo "     - Name: Acme Corporation"
echo "     - Select 'Company' (not Individual)"
echo "     - Email: contact@acme.com"
echo "     - Phone: +1-555-0123"
echo "     - City: New York"
echo ""
echo "  5. Save the contact (click 'Save' or press Ctrl+S)"
echo ""
