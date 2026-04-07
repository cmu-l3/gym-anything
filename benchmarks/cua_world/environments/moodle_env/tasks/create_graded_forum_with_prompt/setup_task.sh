#!/bin/bash
echo "=== Setting up Create Graded Forum task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming validation
date +%s > /tmp/task_start_time.txt

# 1. Generate the real-world literature prompt file
mkdir -p /home/ga/Documents
cat > /home/ga/Documents/hamlet_prompt.txt << 'EOF'
To be, or not to be, that is the question:
Whether 'tis nobler in the mind to suffer
The slings and arrows of outrageous fortune,
Or to take arms against a sea of troubles
And by opposing end them.

Prompt: Analyze the thematic significance of Hamlet's hesitation in this soliloquy. How does his contemplation of mortality reflect the broader themes of the play?
EOF
chown ga:ga /home/ga/Documents/hamlet_prompt.txt

# 2. Wait for Moodle web service to be fully ready
wait_for_moodle 120

# 3. Ensure "Literature 101" course exists via Moodle PHP API
echo "Ensuring Literature 101 course exists..."
sudo -u www-data php -r "
define('CLI_SCRIPT', true);
require('/var/www/html/moodle/config.php');
require_once(\$CFG->dirroot.'/course/lib.php');

\$c = \$DB->get_record('course', array('shortname'=>'LIT101'));
if (!\$c) {
    \$cat = \$DB->get_record('course_categories', array(), '*', IGNORE_MULTIPLE);
    if (!\$cat) {
        // Create a default category if none exist
        \$cat_data = new stdClass();
        \$cat_data->name = 'General';
        \$cat = \core_course_category::create(\$cat_data);
    }
    
    \$course = new stdClass();
    \$course->fullname = 'Literature 101';
    \$course->shortname = 'LIT101';
    \$course->category = \$cat->id;
    \$course->visible = 1;
    \$c = create_course(\$course);
    echo 'Course created with ID: ' . \$c->id . \"\n\";
} else {
    echo 'Course already exists with ID: ' . \$c->id . \"\n\";
}
file_put_contents('/tmp/course_id.txt', \$c->id);
"

# 4. Start Firefox and navigate to the Moodle login page
echo "Launching Firefox..."
restart_firefox "http://localhost/login/index.php"

# Wait a moment for rendering, then take the initial screenshot
sleep 3
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="