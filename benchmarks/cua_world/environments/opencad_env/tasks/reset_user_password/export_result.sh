#!/bin/bash
echo "=== Exporting reset_user_password result ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Get timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_HASH=$(cat /tmp/initial_hash.txt 2>/dev/null || echo "")

# Execute PHP script inside the container to verify the password hash
# We must use PHP's password_verify() because we can't reproduce the bcrypt hash externally
echo "Verifying password hash inside container..."

PHP_VERIFY_SCRIPT=$(cat << 'PHP_EOF'
<?php
// Connect to database
$mysqli = new mysqli("opencad-db", "opencad", "opencadpass", "opencad");

if ($mysqli->connect_errno) {
    echo json_encode(["error" => "Failed to connect to MySQL: " . $mysqli->connect_error]);
    exit();
}

$email = "james.rodriguez@opencad.local";
$target_pass = "TemporaryPass2026!";

// Get current user data
$stmt = $mysqli->prepare("SELECT id, name, password, approved FROM users WHERE email = ?");
$stmt->bind_param("s", $email);
$stmt->execute();
$result = $stmt->get_result();
$user = $result->fetch_assoc();

if (!$user) {
    echo json_encode(["found" => false]);
    exit();
}

// Verify password
$is_match = password_verify($target_pass, $user['password']);

// Return JSON result
echo json_encode([
    "found" => true,
    "id" => $user['id'],
    "name" => $user['name'],
    "current_hash" => $user['password'],
    "approved" => (int)$user['approved'],
    "password_match" => $is_match
]);
PHP_EOF
)

# Run the PHP script in the opencad-app container
# We pipe the script to php
VERIFICATION_JSON=$(echo "$PHP_VERIFY_SCRIPT" | docker exec -i opencad-app php 2>/dev/null)

# Fallback if docker exec failed
if [ -z "$VERIFICATION_JSON" ]; then
    VERIFICATION_JSON='{"found": false, "error": "Docker execution failed"}'
fi

# Combine with other metadata for the verifier
RESULT_JSON=$(cat << EOF
{
    "task_start": $TASK_START,
    "initial_hash": "$(json_escape "$INITIAL_HASH")",
    "verification": $VERIFICATION_JSON,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

# Write result securely
safe_write_result "$RESULT_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="