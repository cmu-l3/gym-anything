#!/bin/bash
# Setup script for Upload SCORM Training Module task

echo "=== Setting up Upload SCORM Task ==="

# Source shared utilities
. /workspace/scripts/task_utils.sh

# Fallback definitions if sourcing fails
if ! type moodle_query &>/dev/null; then
    echo "Warning: task_utils.sh functions not available, using inline definitions"
    _get_mariadb_method() { cat /tmp/mariadb_method 2>/dev/null || echo "native"; }
    moodle_query() {
        local query="$1"
        local method=$(_get_mariadb_method)
        if [ "$method" = "docker" ]; then
            docker exec moodle-mariadb mysql -u moodleuser -pmoodlepass moodle -N -B -e "$query" 2>/dev/null
        else
            mysql -u moodleuser -pmoodlepass moodle -N -B -e "$query" 2>/dev/null
        fi
    }
fi

# 1. Create the specific course (FIRE101) if it doesn't exist
echo "Checking for FIRE101 course..."
COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='FIRE101'" | tr -d '[:space:]')

if [ -z "$COURSE_ID" ]; then
    echo "Creating FIRE101 course..."
    # Insert course record
    TIME=$(date +%s)
    moodle_query "INSERT INTO mdl_course (category, sortorder, fullname, shortname, summary, format, visible, startdate, timecreated, timemodified, enablecompletion) VALUES (1, 10000, 'Firefighter Certification Program', 'FIRE101', 'Training course for fire safety certification.', 'topics', 1, $TIME, $TIME, $TIME, 1);"
    COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='FIRE101'" | tr -d '[:space:]')
    echo "Created FIRE101 with ID: $COURSE_ID"
    
    # Rebuild course cache (optional but good practice, though hard to do via raw SQL - Moodle usually handles it on access)
else
    echo "FIRE101 exists with ID: $COURSE_ID"
fi

# 2. Generate a valid SCORM 1.2 Package
echo "Generating SCORM package..."
SCORM_DIR="/tmp/scorm_build"
rm -rf "$SCORM_DIR"
mkdir -p "$SCORM_DIR"

# Create imsmanifest.xml (Minimal valid SCORM 1.2)
cat > "$SCORM_DIR/imsmanifest.xml" <<EOF
<?xml version="1.0" standalone="no" ?>
<manifest identifier="com.scorm.manifesttemplates.scorm12" version="1.0"
          xmlns="http://www.imsproject.org/xsd/imscp_rootv1p1p2"
          xmlns:adlcp="http://www.adlnet.org/xsd/adlcp_rootv1p2"
          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
          xsi:schemaLocation="http://www.imsproject.org/xsd/imscp_rootv1p1p2 imscp_rootv1p1p2.xsd
                              http://www.imsglobal.org/xsd/imsmd_rootv1p2p1 imsmd_rootv1p2p1.xsd
                              http://www.adlnet.org/xsd/adlcp_rootv1p2 adlcp_rootv1p2.xsd">
  <organizations default="default_org">
    <organization identifier="default_org">
      <title>Fire Safety Training</title>
      <item identifier="item_1" identifierref="resource_1">
        <title>Fire Safety Module</title>
      </item>
    </organization>
  </organizations>
  <resources>
    <resource identifier="resource_1" type="webcontent" adlcp:scormtype="sco" href="index.html">
      <file href="index.html"/>
    </resource>
  </resources>
</manifest>
EOF

# Create index.html (Content)
cat > "$SCORM_DIR/index.html" <<EOF
<html>
<head><title>Fire Safety</title></head>
<body>
<h1>Fire Safety Certification</h1>
<p>This is the content for Module 1.</p>
</body>
</html>
EOF

# Zip it up
DOCS_DIR="/home/ga/Documents"
mkdir -p "$DOCS_DIR"
chown -R ga:ga "$DOCS_DIR"
TARGET_ZIP="$DOCS_DIR/fire_safety_scorm.zip"

cd "$SCORM_DIR"
zip -r "$TARGET_ZIP" * > /dev/null
cd /
rm -rf "$SCORM_DIR"

# Ensure user owns the zip
chown ga:ga "$TARGET_ZIP"
echo "Created SCORM package at $TARGET_ZIP"

# 3. Record initial state
INITIAL_SCORM_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_scorm WHERE course=$COURSE_ID" | tr -d '[:space:]')
echo "$INITIAL_SCORM_COUNT" > /tmp/initial_scorm_count
date +%s > /tmp/task_start_timestamp

# 4. Start Firefox
echo "Starting Firefox..."
if ! pgrep -f firefox > /dev/null 2>&1; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/moodle/' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "Moodle\|Firefox"; then
        break
    fi
    sleep 1
done

# Focus Firefox
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i 'firefox\|mozilla' | awk '{print $1; exit}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take screenshot
DISPLAY=:1 scrot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== Setup Complete ==="