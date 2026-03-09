#!/bin/bash
set -e
echo "=== Setting up Secure Terminated Account Task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure LibreHealth is running
wait_for_librehealth 60

# 2. Reset/Create the target user 'ghouse' via PHP in the container
# This ensures a clean state: Active=1, Authorized=1, Password='OldPassword123'
echo "Resetting user 'ghouse'..."
docker exec librehealth-app php -r '
$user = "ghouse";
$pass = "OldPassword123";
$fname = "Gregory";
$lname = "House";
$hash = password_hash($pass, PASSWORD_BCRYPT, ["cost" => 10]);
$salt = substr($hash, 0, 29);

$m = new mysqli("librehealth-db", "libreehr", "s3cret", "libreehr");
if ($m->connect_error) { die("Connection failed: " . $m->connect_error); }

// Cleanup previous run
$m->query("DELETE FROM users WHERE username=\"$user\"");
$m->query("DELETE FROM users_secure WHERE username=\"$user\"");

// Insert into users (active=1, authorized=1)
// Note: facility_id 1 is usually the default clinic
$stmt = $m->prepare("INSERT INTO users (username, password, authorized, fname, lname, active, facility_id) VALUES (?, ?, 1, ?, ?, 1, 3)");
$stmt->bind_param("sssss", $user, $hash, $fname, $lname);
$stmt->execute();
$id = $stmt->insert_id;
$stmt->close();

// Insert into users_secure
$stmt = $m->prepare("INSERT INTO users_secure (id, username, password, salt, last_update) VALUES (?, ?, ?, ?, NOW())");
$stmt->bind_param("isss", $id, $user, $hash, $salt);
$stmt->execute();
$stmt->close();

echo "User $user created with ID $id\n";
'

# 3. Record task start time
date +%s > /tmp/task_start_time.txt

# 4. Start Firefox at the Login Page
restart_firefox "http://localhost:8000/interface/login/login.php?site=default"

# 5. Capture initial screenshot
echo "Capturing initial state..."
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="
echo "Target User: ghouse"
echo "Goal: Deactivate, Remove Provider Status, Change Password to 'Terminated!2025'"