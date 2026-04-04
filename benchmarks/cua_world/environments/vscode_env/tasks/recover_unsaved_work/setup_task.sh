#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up VSCode Recovery Task ==="

WORKSPACE="/home/ga/workspace/bugfix-project"
BACKUPS_DIR="/home/ga/.config/Code/Backups"
WORKSPACE_HASH="1a2b3c4d5e6f7g8h"  # Simulated workspace hash

# Create workspace structure
echo "Creating workspace directories..."
sudo -u ga mkdir -p "$WORKSPACE/src"
sudo -u ga mkdir -p "$WORKSPACE/config"
sudo -u ga mkdir -p "$WORKSPACE/docs"

# Create VSCode backups directory structure
echo "Creating backup directory structure..."
BACKUP_WORKSPACE="$BACKUPS_DIR/$WORKSPACE_HASH"
sudo -u ga mkdir -p "$BACKUP_WORKSPACE"

# Create backup files with cryptic names (simulate VSCode's backup format)
echo "Creating backup files..."

# 1. Authentication.py backup
cat > "$BACKUP_WORKSPACE/authentication.py.a1b2c3d4.bak" << 'EOF'
"""
Authentication module with bcrypt password hashing
RECOVERED FROM CRASH - Urgent security fix
"""
import bcrypt
from datetime import datetime
from typing import Optional

class AuthManager:
    """Manages user authentication with secure password hashing"""
    
    def __init__(self, salt_rounds: int = 12):
        self.salt_rounds = salt_rounds
    
    def hash_password(self, password: str) -> bytes:
        """Hash password using bcrypt with proper salt"""
        salt = bcrypt.gensalt(rounds=self.salt_rounds)
        return bcrypt.hashpw(password.encode('utf-8'), salt)
    
    def verify_password(self, password: str, hashed: bytes) -> bool:
        """Verify password against hash"""
        return bcrypt.checkpw(password.encode('utf-8'), hashed)
    
    def update_password(self, user_id: int, new_password: str) -> bool:
        """Update user password with new hash"""
        hashed = self.hash_password(new_password)
        # Database update logic here
        return True
EOF

# 2. User settings JSON backup
cat > "$BACKUP_WORKSPACE/user_settings.json.e5f6g7h8.bak" << 'EOF'
{
  "api_timeout": 30,
  "max_retries": 3,
  "retry_backoff": 2,
  "enable_logging": true,
  "log_level": "INFO",
  "cache_ttl": 3600,
  "auth_token_expiry": 86400,
  "rate_limit_requests": 1000,
  "rate_limit_window": 3600
}
EOF

# 3. Urgent notes markdown backup
cat > "$BACKUP_WORKSPACE/URGENT_NOTES.md.i9j0k1l2.bak" << 'EOF'
# Authentication Bug Investigation - URGENT

## Timeline
- 14:32 - Reports of failed logins from production
- 14:45 - Identified root cause: missing salt validation in bcrypt
- 15:00 - Started implementing fix
- 15:15 - System crashed, recovering work

## Root Cause
The authentication module was not properly using bcrypt salts for password hashing.
Users were unable to login due to inconsistent hash generation.

**root cause: missing salt validation**

The previous implementation did not use bcrypt.gensalt() properly, causing
password verification to fail intermittently.

## Fix Implemented
1. Import bcrypt library correctly
2. Use bcrypt.gensalt() for each password hash
3. Update user_settings.json to increase API timeout (was timing out during hash computation)
4. Add proper error handling for hash failures

## Testing Checklist
- [ ] Test with various password lengths (8-128 characters)
- [ ] Test with special characters (!@#$%^&*)
- [ ] Performance test with high load (1000 concurrent users)
- [ ] Verify backward compatibility with existing password hashes

## Deployment Plan
1. Deploy to staging environment first
2. Monitor for 1 hour
3. Run automated test suite
4. Deploy to production during low-traffic window
5. Monitor error rates for 24 hours

## Related Issues
- Issue #1234: Users unable to login
- Issue #1235: Password reset not working
- CVE-2024-XXXX: Weak password hashing (addressed by this fix)
EOF

# Set proper ownership
sudo chown -R ga:ga "$BACKUP_WORKSPACE"

# Create recovery instructions
cat > "$WORKSPACE/RECOVERY_INSTRUCTIONS.md" << 'EOF'
# VSCode Recovery Instructions

## 🚨 What Happened?
VSCode crashed while you were working on critical bug fixes. Some of your unsaved changes may be in VSCode's backup directory.

## 📁 Where to Look
VSCode stores automatic backups in: `/home/ga/.config/Code/Backups/`

The directory structure is: