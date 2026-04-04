#!/bin/bash
set -e
echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Query Database for User Status
# We need to check: active status, authorized status, and verify the password hash
# We do this via a PHP script inside the container to use password_verify()
echo "Verifying user state in database..."

docker exec librehealth-app php -r '
$target_user = "ghouse";
$target_pass = "Terminated!2025";

$m = new mysqli("librehealth-db", "libreehr", "s3cret", "libreehr");
if ($m->connect_error) { die("DB Connection Failed"); }

$result = [];

// Check users table for flags
$stmt = $m->prepare("SELECT id, active, authorized FROM users WHERE username = ?");
$stmt->bind_param("s", $target_user);
$stmt->execute();
$res = $stmt->get_result();
$row = $res->fetch_assoc();

if ($row) {
    $result["user_found"] = true;
    $result["active"] = (int)$row["active"];
    $result["authorized"] = (int)$row["authorized"];
    
    // Check password hash in users_secure
    $stmt_sec = $m->prepare("SELECT password FROM users_secure WHERE username = ?");
    $stmt_sec->bind_param("s", $target_user);
    $stmt_sec->execute();
    $res_sec = $stmt_sec->get_result();
    $row_sec = $res_sec->fetch_assoc();
    
    if ($row_sec) {
        $hash = $row_sec["password"];
        $result["password_valid"] = password_verify($target_pass, $hash);
    } else {
        $result["password_valid"] = false;
    }
} else {
    $result["user_found"] = false;
    $result["active"] = -1;
    $result["authorized"] = -1;
    $result["password_valid"] = false;
}

echo json_encode($result);
' > /tmp/db_verification.json

# 3. Combine with timestamp info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Merge JSONs
jq -s '.[0] + {task_start: .[1], task_end: .[2], screenshot_path: "/tmp/task_final.png"}' \
    /tmp/db_verification.json \
    <(echo "$TASK_START") \
    <(echo "$TASK_END") > /tmp/task_result.json

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Result exported:"
cat /tmp/task_result.json
echo "=== Export Complete ==="