#!/bin/bash
echo "=== Setting up Bulk Password Reset Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create specific users for this task using PHP CLI
# This ensures we have known targets (Canada) and controls (US/UK)
echo "Creating task-specific users..."

sudo -u www-data php -r "
define('CLI_SCRIPT', true);
require('/var/www/html/moodle/config.php');
require_once(\$CFG->dirroot . '/user/lib.php');

// List of users to create
\$users = [
    ['username'=>'liam.smith', 'firstname'=>'Liam', 'lastname'=>'Smith', 'email'=>'liam@example.com', 'country'=>'CA'],
    ['username'=>'olivia.tremblay', 'firstname'=>'Olivia', 'lastname'=>'Tremblay', 'email'=>'olivia@example.com', 'country'=>'CA'],
    ['username'=>'noah.gauthier', 'firstname'=>'Noah', 'lastname'=>'Gauthier', 'email'=>'noah@example.com', 'country'=>'CA'],
    ['username'=>'james.johnson', 'firstname'=>'James', 'lastname'=>'Johnson', 'email'=>'james@example.com', 'country'=>'US'],
    ['username'=>'emma.williams', 'firstname'=>'Emma', 'lastname'=>'Williams', 'email'=>'emma@example.com', 'country'=>'US'],
    ['username'=>'charlie.brown', 'firstname'=>'Charlie', 'lastname'=>'Brown', 'email'=>'charlie@example.com', 'country'=>'GB']
];

foreach (\$users as \$u) {
    // Check if user exists
    \$existing = \$DB->get_record('user', array('username' => \$u['username']));
    if (!\$existing) {
        \$user = new stdClass();
        \$user->username = \$u['username'];
        \$user->firstname = \$u['firstname'];
        \$user->lastname = \$u['lastname'];
        \$user->email = \$u['email'];
        \$user->country = \$u['country'];
        \$user->password = 'Student1234!';
        \$user->confirmed = 1;
        \$user->mnethostid = \$CFG->mnet_localhost_id;
        
        try {
            user_create_user(\$user);
            echo 'Created user: ' . \$u['username'] . ' (' . \$u['country'] . ')\n';
        } catch (Exception \$e) {
            echo 'Error creating ' . \$u['username'] . ': ' . \$e->getMessage() . '\n';
        }
    } else {
        // Reset state for existing users - ensure country is correct and forcepasswordchange is 0
        \$update = new stdClass();
        \$update->id = \$existing->id;
        \$update->country = \$u['country'];
        \$DB->update_record('user', \$update);
        unset_user_preference('auth_forcepasswordchange', \$existing);
        echo 'Reset user: ' . \$u['username'] . '\n';
    }
}
"

# Ensure Firefox is running
echo "Ensuring Firefox is running..."
MOODLE_URL="http://localhost/"

if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$MOODLE_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Wait for and focus Firefox
if ! wait_for_window "firefox\|mozilla\|Moodle" 30; then
    echo "WARNING: Firefox window not detected"
fi

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="