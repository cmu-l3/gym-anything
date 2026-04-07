#!/bin/bash
echo "=== Setting up customize_home_dashboard task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/task_start_time.txt

# Create a PHP script to query the current dashboard configuration directly from the database
cat > /tmp/check_dashlets.php << 'EOF'
<?php
error_reporting(0);
if (file_exists('/var/www/html/config.php')) {
    require_once('/var/www/html/config.php');
} else {
    echo json_encode(["error" => "config.php not found"]);
    exit(1);
}

$dbconfig = $sugar_config['dbconfig'];
$conn = new mysqli($dbconfig['db_host_name'], $dbconfig['db_user_name'], $dbconfig['db_password'], $dbconfig['db_name']);

if ($conn->connect_error) {
    echo json_encode(["error" => "DB connection failed"]);
    exit(1);
}

$res = $conn->query("SELECT contents, date_modified FROM user_preferences WHERE category = 'Home' AND assigned_user_id = '1' AND deleted = 0");
if ($row = $res->fetch_assoc()) {
    $prefs = unserialize(base64_decode($row['contents']));
    $dashlets = isset($prefs['dashlets']) ? $prefs['dashlets'] : array();
    $modules = array();
    foreach ($dashlets as $id => $dashlet) {
        if (isset($dashlet['module'])) {
            $modules[] = $dashlet['module'];
        } elseif (isset($dashlet['className'])) {
            $modules[] = $dashlet['className'];
        }
    }
    echo json_encode(array(
        "count" => count($dashlets),
        "modules" => $modules,
        "date_modified" => $row['date_modified']
    ));
} else {
    echo json_encode(array("count" => 0, "modules" => array(), "date_modified" => ""));
}
$conn->close();
?>
EOF

# Copy script to the application container and execute it
docker cp /tmp/check_dashlets.php suitecrm-app:/tmp/check_dashlets.php
docker exec suitecrm-app php /tmp/check_dashlets.php > /tmp/initial_dashlets.json 2>/dev/null || echo '{"count": 0, "modules": []}' > /tmp/initial_dashlets.json

chmod 666 /tmp/initial_dashlets.json 2>/dev/null || true
echo "Initial dashlet configuration:"
cat /tmp/initial_dashlets.json
echo ""

# Ensure logged in and navigate to the Home dashboard
ensure_suitecrm_logged_in "http://localhost:8000/index.php?module=Home&action=index"
sleep 5

# Take initial screenshot
take_screenshot /tmp/customize_dashboard_initial.png

echo "=== customize_home_dashboard task setup complete ==="