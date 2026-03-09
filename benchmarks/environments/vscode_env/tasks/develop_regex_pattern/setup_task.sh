#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Develop Regex Pattern Task ==="

WORKSPACE_DIR="/home/ga/workspace/log_parser"
sudo -u ga mkdir -p "$WORKSPACE_DIR"
sudo -u ga mkdir -p "$WORKSPACE_DIR/.vscode"

# Create sample log file
cat > "$WORKSPACE_DIR/sample_logs.txt" << 'EOF'
[2024-01-15 14:23:45.123] INFO auth.login - User john.doe@example.com logged in from 192.168.1.100
[2024-01-15 14:23:46.234] INFO auth.login - User alice+shopping@example.com logged in from 10.0.0.5
[2024-01-15 14:24:12.456] ERROR auth.password - Failed login attempt for admin@example.com (reason: invalid_password)
[2024-01-15 14:25:01.789] WARN auth.session - Session timeout for user@test.com after 3600s
[2024-01-15 14:25:15.901] ERROR auth.mfa - MFA challenge failed for bob.smith@company.org (attempts: 3)
[2024-01-15 14:26:30.112] INFO auth.logout - User jane_doe@example.com logged out (session_duration: 125s)
[2024-01-15 14:27:45.223] DEBUG auth.token - Token refresh for service-account@internal.local
[2024-01-15 14:28:01.334] ERROR auth.rate_limit - Rate limit exceeded for attacker@malicious.net from 203.0.113.42
EOF

# Create README with task instructions
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Log Parser Regex Pattern

## Task
Develop a regex pattern that extracts the following from each log line:
- Timestamp (full datetime with milliseconds)
- Log level (INFO, WARN, ERROR, DEBUG)
- Component (e.g., auth.login, auth.password)
- Message (everything after the dash)

## Requirements
1. Create a file `pattern.txt` with your final regex pattern
2. Create a file `test_results.txt` showing your pattern tested against sample logs
3. Add documentation in `pattern_explanation.md` explaining what each part of the regex does

## Expected Groups
Your regex should have capturing groups for:
- Group 1: Full timestamp (e.g., "2024-01-15 14:23:45.123")
- Group 2: Log level (e.g., "INFO", "ERROR")
- Group 3: Component name (e.g., "auth.login")
- Group 4: Message text (e.g., "User john.doe@example.com logged in from 192.168.1.100")

## Sample Log Format