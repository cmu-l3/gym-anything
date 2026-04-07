#!/bin/bash
echo "=== Setting up Cohort Sync task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming timestamps
date +%s > /tmp/task_start_time.txt

# Wait for Moodle web service
wait_for_moodle 60

# =============================================================================
# 1. Create the Health Assessment course programmatically
# =============================================================================
echo "Preparing Health Assessment course (NURS200)..."
sudo -u www-data php -r "
define('CLI_SCRIPT', true);
require('/var/www/html/moodle/config.php');
require_once(\$CFG->dirroot.'/course/lib.php');

if (!\$DB->record_exists('course', ['shortname' => 'NURS200'])) {
    \$cat = \$DB->get_record('course_categories', [], '*', IGNORE_MULTIPLE);
    if (!\$cat) {
        \$cat = new stdClass();
        \$cat->name = 'General';
        \$cat = \core_course_category::create(\$cat);
    }
    
    \$course = new stdClass();
    \$course->category = \$cat->id;
    \$course->fullname = 'Health Assessment';
    \$course->shortname = 'NURS200';
    \$course->visible = 1;
    \$course->summary = 'Nursing assessment guidelines and techniques.';
    create_course(\$course);
    echo 'Course created successfully.\n';
} else {
    echo 'Course already exists.\n';
}
" || echo "Note: Course verification/creation encountered an issue."

# =============================================================================
# 2. Prepare the real PDF document
# =============================================================================
echo "Downloading real clinical PDF document..."
mkdir -p /home/ga/Documents
# Using a widely available open PDF as a proxy for the clinical guidelines
curl -sL -o /home/ga/Documents/Clinical_Guidelines.pdf "https://raw.githubusercontent.com/mozilla/pdf.js/master/web/compressed.tracemonkey-pldi-09.pdf"

# Fallback in case the network download fails
if [ ! -s /home/ga/Documents/Clinical_Guidelines.pdf ]; then
    echo "Network download failed, generating fallback PDF..."
    apt-get install -y enscript ghostscript
    echo "Clinical Guidelines for Nursing Assessment. Version 2026." | enscript -p - | ps2pdf - /home/ga/Documents/Clinical_Guidelines.pdf
fi
chown -R ga:ga /home/ga/Documents
chmod 644 /home/ga/Documents/Clinical_Guidelines.pdf

# =============================================================================
# 3. Clean up any existing state (if restarting)
# =============================================================================
# Clean up cohort if it already exists to provide a pristine state
sudo -u www-data php -r "
define('CLI_SCRIPT', true);
require('/var/www/html/moodle/config.php');
if (\$cohort = \$DB->get_record('cohort', ['idnumber' => 'NURS-F26'])) {
    require_once(\$CFG->dirroot.'/cohort/lib.php');
    cohort_delete_cohort(\$cohort);
    echo 'Deleted existing cohort for clean state.\n';
}
" 2>/dev/null || true

# =============================================================================
# 4. Launch Firefox and establish initial state
# =============================================================================
echo "Launching Firefox..."
restart_firefox "http://localhost/login/index.php"

# Allow Firefox to fully render
sleep 3
take_screenshot /tmp/task_initial_state.png

echo "=== Setup complete ==="