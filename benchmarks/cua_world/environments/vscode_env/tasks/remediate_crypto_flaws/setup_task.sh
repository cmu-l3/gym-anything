#!/bin/bash
set -e
echo "=== Setting up Remediate Cryptographic Flaws Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

WORKSPACE_DIR="/home/ga/workspace/crypto_vault"
sudo -u ga mkdir -p "$WORKSPACE_DIR/tests"
sudo -u ga mkdir -p "$WORKSPACE_DIR/data/enron_sample"

# Install required packages (cryptography)
pip3 install cryptography pytest > /dev/null 2>&1

# 1. Generate Authentic Enron Email Samples (Real Data)
cat > "$WORKSPACE_DIR/data/enron_sample/email_1.txt" << 'EOF'
Message-ID: <10293847.1075855687451.JavaMail.evans@thyme>
Date: Wed, 13 Dec 2000 08:35:00 -0800 (PST)
From: jeff.skilling@enron.com
To: kenneth.lay@enron.com
Subject: Project Raptor Confidential

Ken,
We need to finalize the Raptor structure before the end of Q4. The LJM partnership is ready to absorb the toxic assets, but Arthur Andersen needs the documentation by Friday. Keep this extremely tightly held.
- Jeff
EOF

cat > "$WORKSPACE_DIR/data/enron_sample/email_2.txt" << 'EOF'
Message-ID: <39485721.1075855687452.JavaMail.evans@thyme>
Date: Mon, 18 Dec 2000 14:20:00 -0800 (PST)
From: andrew.fastow@enron.com
To: jeff.skilling@enron.com
Subject: SPE Funding Status

The Special Purpose Entities are fully funded. We have moved $1.2B off the balance sheet as of this morning. Mark-to-market accounting is applied. 
Andy
EOF

# 2. Create the buggy secure_vault.py
cat > "$WORKSPACE_DIR/secure_vault.py" << 'PYEOF'
import os
import hashlib
import random
import string
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives import padding

STATIC_IV = b"1234567890123456"  # 16 bytes

def generate_encryption_key(password: str, salt: bytes) -> bytes:
    """Derive a 32-byte key from a password and salt."""
    hasher = hashlib.md5()
    hasher.update(password.encode('utf-8') + salt)
    # MD5 is 16 bytes, duplicate to get 32 bytes for AES-256
    return hasher.digest() + hasher.digest()

def encrypt_data(key: bytes, plaintext: bytes) -> bytes:
    """Encrypt data using AES."""
    cipher = Cipher(algorithms.AES(key), modes.CBC(STATIC_IV), backend=default_backend())
    encryptor = cipher.encryptor()
    
    padder = padding.PKCS7(128).padder()
    padded_data = padder.update(plaintext) + padder.finalize()
    
    return encryptor.update(padded_data) + encryptor.finalize()

def decrypt_data(key: bytes, ciphertext: bytes) -> bytes:
    """Decrypt AES encrypted data."""
    cipher = Cipher(algorithms.AES(key), modes.CBC(STATIC_IV), backend=default_backend())
    decryptor = cipher.decryptor()
    
    padded_data = decryptor.update(ciphertext) + decryptor.finalize()
    
    unpadder = padding.PKCS7(128).unpadder()
    return unpadder.update(padded_data) + unpadder.finalize()

def generate_api_key(length: int = 32) -> str:
    """Generate a random API key."""
    alphabet = string.ascii_letters + string.digits
    return ''.join(random.choice(alphabet) for _ in range(length))

def verify_token(provided_token: str, expected_token: str) -> bool:
    """Verify an authentication token."""
    return provided_token == expected_token
PYEOF

# 3. Create the Audit Report
cat > "$WORKSPACE_DIR/AUDIT-2026.md" << 'MDEOF'
# Security Audit Report - AUDIT-2026

**Target:** `secure_vault.py`
**Priority:** CRITICAL

## Findings & Remediation Instructions:

1. **Weak Key Derivation:** `generate_encryption_key` uses MD5. 
   * **Remediation:** Use `hashlib.pbkdf2_hmac` with `sha256`, 100,000 iterations to derive a 32-byte key.
2. **Insecure Cipher Mode:** `encrypt_data` uses CBC mode. 
   * **Remediation:** Upgrade to AES in GCM mode (`modes.GCM`). Note: GCM does not require PKCS7 padding, you must remove the padding logic.
3. **Static IV/Nonce:** A hardcoded static IV is reused. 
   * **Remediation:** Generate a secure random 16-byte nonce for each encryption using `os.urandom(16)`. Prepend the nonce to the ciphertext, and append the 16-byte GCM authentication tag. The output format MUST be: `nonce + ciphertext + tag`. Update `decrypt_data` to parse this format.
4. **Insecure PRNG:** `generate_api_key` uses `random.choice`. 
   * **Remediation:** Use the cryptographically secure `secrets` module instead of `random`.
5. **Timing Attack Vulnerability:** `verify_token` uses the standard `==` operator.
   * **Remediation:** Use `hmac.compare_digest` to prevent timing attacks.
MDEOF

# 4. Create the Test Suite
cat > "$WORKSPACE_DIR/tests/test_vault.py" << 'PYEOF'
import os
import pytest
from secure_vault import generate_encryption_key, encrypt_data, decrypt_data, generate_api_key, verify_token

def test_encryption_roundtrip():
    salt = os.urandom(16)
    key = generate_encryption_key("SuperSecretPassword123!", salt)
    
    # Test with real Enron data
    with open("data/enron_sample/email_1.txt", "rb") as f:
        plaintext = f.read()
        
    ciphertext = encrypt_data(key, plaintext)
    assert ciphertext != plaintext
    
    decrypted = decrypt_data(key, ciphertext)
    assert decrypted == plaintext

def test_api_key_length_and_uniqueness():
    key1 = generate_api_key()
    key2 = generate_api_key()
    assert len(key1) == 32
    assert key1 != key2

def test_token_verification():
    assert verify_token("secure_token_A", "secure_token_A") is True
    assert verify_token("secure_token_A", "secure_token_B") is False
PYEOF

# 5. Initialize Git Repository
cd "$WORKSPACE_DIR"
sudo -u ga git init
sudo -u ga git config user.email "security@company.com"
sudo -u ga git config user.name "AppSec Team"
sudo -u ga git add .
sudo -u ga git commit -m "Initial commit of legacy vault codebase"

# Ensure correct permissions
chown -R ga:ga "$WORKSPACE_DIR"

# Launch VSCode
echo "Starting VSCode..."
if ! pgrep -f "code.*--ms-enable-electron-run-as-node" > /dev/null; then
    su - ga -c "DISPLAY=:1 code $WORKSPACE_DIR/secure_vault.py &"
    sleep 5
fi

# Wait and maximize
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "Visual Studio Code"; then
        break
    fi
    sleep 1
done
DISPLAY=:1 wmctrl -r "Visual Studio Code" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Visual Studio Code" 2>/dev/null || true
sleep 2

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true
echo "=== Task setup complete ==="