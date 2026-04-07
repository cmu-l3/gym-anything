#!/bin/bash
echo "=== Setting up Configure Branching Lesson task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Moodle is ready
echo "Waiting for Moodle web service..."
wait_for_moodle 120

# Create the course via PHP CLI
echo "Creating Hazmat First Responder Training course..."
sudo -u www-data php -r "
define('CLI_SCRIPT', true);
require('/var/www/html/moodle/config.php');

\$category = \$DB->get_record('course_categories', array('idnumber'=>'SCI'));
if (!\$category) {
    \$category = \$DB->get_records('course_categories', array()) ? reset(\$DB->get_records('course_categories')) : null;
}

if (!\$DB->get_record('course', array('shortname' => 'HAZMAT101'))) {
    \$course = new stdClass();
    \$course->fullname = 'Hazmat First Responder Training';
    \$course->shortname = 'HAZMAT101';
    \$course->category = \$category ? \$category->id : 1;
    \$course->visible = 1;
    \$course->startdate = time();
    \$course->summary = 'Training for first responders on hazardous materials incidents.';
    create_course(\$course);
    echo \"Course HAZMAT101 created successfully.\n\";
} else {
    echo \"Course HAZMAT101 already exists.\n\";
}
"

# Create Data Files
DATA_DIR="/home/ga/Documents/LessonData"
mkdir -p "$DATA_DIR"

cat > "$DATA_DIR/Scene_Arrival.txt" << 'EOF'
UN 1090 (Acetone) - Hazard Class 3 (Flammable Liquid)
You arrive at the scene of a overturned tanker truck leaking a clear liquid. The placard reads 1090.
The driver is unconscious near the cab. The wind is blowing towards the nearby residential area.
What is your immediate action?
EOF

cat > "$DATA_DIR/Failure.txt" << 'EOF'
You approached the scene without proper PPE and without identifying the wind direction. You were overcome by toxic and flammable vapors.
Never rush into a hazmat scene without isolation and proper assessment.
EOF

cat > "$DATA_DIR/Success.txt" << 'EOF'
You correctly stayed upwind, uphill, and isolated the area for 150 feet in all directions. You called for the Hazmat team and initiated evacuation of the downwind residential area.
Excellent job. You have secured the scene safely.
EOF

# Create image placard using ImageMagick
if command -v convert &> /dev/null; then
    convert -size 400x400 -background '#D22B2B' -fill white -font DejaVu-Sans-Bold -pointsize 40 -gravity center label:"\n  1090  \n\n FLAMMABLE \n LIQUID " "$DATA_DIR/placard_1090.jpg"
else
    # Fallback if imagemagick not installed
    apt-get update && apt-get install -y imagemagick
    convert -size 400x400 -background '#D22B2B' -fill white -font DejaVu-Sans-Bold -pointsize 40 -gravity center label:"\n  1090  \n\n FLAMMABLE \n LIQUID " "$DATA_DIR/placard_1090.jpg"
fi

# Set permissions
chown -R ga:ga "$DATA_DIR"

# Launch Firefox
echo "Starting Firefox..."
restart_firefox "http://localhost/course/view.php?name=HAZMAT101"

# Take initial screenshot for evidence
echo "Capturing initial state..."
sleep 5
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="