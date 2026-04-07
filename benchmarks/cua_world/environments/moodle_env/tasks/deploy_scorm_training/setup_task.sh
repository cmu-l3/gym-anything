#!/bin/bash
echo "=== Setting up Deploy SCORM Task ==="

source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# Wait for Moodle web service to be fully responsive
wait_for_moodle 120

# 1. Provide the SCORM Package (Real standard SCORM 1.2 wrapper)
mkdir -p /home/ga/Documents
SCORM_PATH="/home/ga/Documents/golf_scorm12.zip"

echo "Downloading/Generating SCORM 1.2 sample package..."
# Try to download the official Rustici golf sample, fallback to generating a valid minimal wrapper
if ! curl -sL -o "$SCORM_PATH" "https://scorm.com/wp-content/assets/golf_samples/PIFS/Golf_Explained_SCORM_12_PIF.zip"; then
    echo "Download failed, generating valid SCORM fallback..."
    mkdir -p /tmp/scorm_temp/shared
    cat > /tmp/scorm_temp/imsmanifest.xml << 'EOF'
<?xml version="1.0" standalone="no" ?>
<manifest identifier="com.scorm.minimal.12" version="1"
          xmlns="http://www.imsproject.org/xsd/imscp_rootv1p1p2"
          xmlns:adlcp="http://www.adlnet.org/xsd/adlcp_rootv1p2"
          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
          xsi:schemaLocation="http://www.imsproject.org/xsd/imscp_rootv1p1p2 imscp_rootv1p1p2.xsd">
   <metadata><schema>ADL SCORM</schema><schemaversion>1.2</schemaversion></metadata>
   <organizations default="default_org">
      <organization identifier="default_org">
         <title>Compliance Training</title>
         <item identifier="item_1" identifierref="resource_1"><title>Module 1</title></item>
      </organization>
   </organizations>
   <resources>
      <resource identifier="resource_1" type="webcontent" adlcp:scormtype="sco" href="shared/index.html">
         <file href="shared/index.html"/>
      </resource>
   </resources>
</manifest>
EOF
    echo "<html><body><h1>Compliance Module Complete</h1></body></html>" > /tmp/scorm_temp/shared/index.html
    cd /tmp/scorm_temp && zip -q -r "$SCORM_PATH" ./*
    rm -rf /tmp/scorm_temp
fi
chown ga:ga "$SCORM_PATH"
chmod 644 "$SCORM_PATH"

# 2. Create the target Course via Moodle PHP API
echo "Creating target course..."
COURSE_ID=$(sudo -u www-data php -r "
define('CLI_SCRIPT', true);
require('/var/www/html/moodle/config.php');
require_once(\$CFG->dirroot.'/course/lib.php');
\$category = \$DB->get_record('course_categories', array(), '*', IGNORE_MULTIPLE);
if (!\$course = \$DB->get_record('course', array('shortname' => 'COMP101'))) {
    \$c = new stdClass();
    \$c->fullname = 'Annual Compliance Training';
    \$c->shortname = 'COMP101';
    \$c->category = \$category->id;
    \$c->visible = 1;
    \$course = create_course(\$c);
}
echo \$course->id;
")

echo "Course 'Annual Compliance Training' created with ID: $COURSE_ID"
echo "$COURSE_ID" > /tmp/target_course_id.txt

# 3. Record Initial State (Count of SCORM modules)
INITIAL_SCORM_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_scorm" 2>/dev/null || echo "0")
echo "$INITIAL_SCORM_COUNT" > /tmp/initial_scorm_count.txt

# 4. Launch Firefox directly to the course page
echo "Launching Firefox..."
pkill -f firefox 2>/dev/null || true
sleep 2

COURSE_URL="http://localhost/course/view.php?id=$COURSE_ID"
su - ga -c "DISPLAY=:1 firefox '$COURSE_URL' > /tmp/firefox.log 2>&1 &"

# Wait for Firefox and maximize
for i in {1..30}; do
    WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla" | awk '{print $1}' | head -1)
    if [ -n "$WID" ]; then
        echo "Firefox window detected."
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

# Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png ga

echo "=== Setup Complete ==="