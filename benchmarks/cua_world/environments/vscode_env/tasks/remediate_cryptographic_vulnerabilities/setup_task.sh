#!/bin/bash
set -e
echo "=== Setting up Cryptographic Vulnerabilities Task ==="

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# Install required Python packages globally
pip3 install --no-cache-dir pycryptodome PyJWT pandas

WORKSPACE="/home/ga/workspace/fintech_crypto"
mkdir -p "$WORKSPACE/crypto_utils"
mkdir -p "$WORKSPACE/data"

# 1. Download REAL dataset (UCI Bank Marketing Dataset)
echo "Downloading real financial dataset..."
cd "$WORKSPACE/data"
wget -qO bank.zip "https://archive.ics.uci.edu/ml/machine-learning-databases/00222/bank.zip"
unzip -q bank.zip
rm bank.zip
rm bank-full.csv  # Keep only the smaller bank.csv for faster processing (~4k rows)
cd "$WORKSPACE"

# 2. Generate Vulnerable Code Files
cat > crypto_utils/__init__.py << 'EOF'
# Crypto Utils Package
EOF

cat > crypto_utils/encryption.py << 'EOF'
from Crypto.Cipher import AES
import base64

# BUG 1: ECB Mode and no random IV/nonce
def encrypt_data(plaintext: str, key: bytes) -> str:
    cipher = AES.new(key, AES.MODE_ECB)
    pad_len = 16 - (len(plaintext) % 16)
    padded = plaintext + (chr(pad_len) * pad_len)
    ciphertext = cipher.encrypt(padded.encode('utf-8'))
    return base64.b64encode(ciphertext).decode('utf-8')

def decrypt_data(ciphertext_b64: str, key: bytes) -> str:
    cipher = AES.new(key, AES.MODE_ECB)
    ciphertext = base64.b64decode(ciphertext_b64)
    padded = cipher.decrypt(ciphertext).decode('utf-8')
    pad_len = ord(padded[-1])
    return padded[:-pad_len]
EOF

cat > crypto_utils/tokens.py << 'EOF'
import random
import string
import jwt

# BUG 2: Weak randomness (random instead of secrets)
def generate_session_token(length=32) -> str:
    characters = string.ascii_letters + string.digits
    return ''.join(random.choices(characters, k=length))

# BUG 3: JWT accepts 'none' algorithm
def verify_jwt(token: str, secret: str) -> dict:
    return jwt.decode(token, secret, algorithms=["HS256", "none"])
EOF

cat > crypto_utils/auth.py << 'EOF'
import hashlib

# BUG 4: Weak hashing algorithm (MD5) without salt
def hash_password(password: str) -> str:
    return hashlib.md5(password.encode('utf-8')).hexdigest()

# BUG 5: Timing attack vulnerability (using == instead of compare_digest)
def verify_password(stored_hash: str, provided_password: str) -> bool:
    provided_hash = hash_password(provided_password)
    return stored_hash == provided_hash
EOF

# 3. Generate Pipeline Script with Security Assertion
cat > process_dataset.py << 'EOF'
import pandas as pd
import os
from crypto_utils.encryption import encrypt_data

def main():
    print("Starting data pipeline...")
    key = b"16byte_secrt_key" # 16 byte key for AES
    
    # ---------------------------------------------------------
    # SECURITY ASSERTION: Fails if encryption is deterministic
    # ---------------------------------------------------------
    c1 = encrypt_data("test_balance", key)
    c2 = encrypt_data("test_balance", key)
    if c1 == c2:
        print("\n[!] FATAL ERROR: SECURITY AUDIT FAILURE")
        print("[!] encrypt_data() produced the identical ciphertext twice.")
        print("[!] This indicates the use of ECB mode or a static IV.")
        print("[!] Pipeline halted. Please fix crypto_utils/encryption.py first.\n")
        exit(1)
        
    print("Security assertions passed! Processing real dataset...")
    df = pd.read_csv("data/bank.csv", sep=";")
    
    # Encrypt sensitive columns before exporting
    print("Encrypting financial balances...")
    df["balance_encrypted"] = df["balance"].astype(str).apply(lambda x: encrypt_data(x, key))
    
    out_path = "data/output_encrypted.csv"
    df.to_csv(out_path, index=False)
    print(f"\nSuccess! Encrypted dataset written to {out_path}")

if __name__ == "__main__":
    main()
EOF

# 4. Generate Audit Report
cat > audit_report.txt << 'EOF'
PENETRATION TEST AUDIT REPORT
=============================
Target: crypto_utils library

CRITICAL FINDINGS:
1. Encryption Mode: `encryption.py` uses AES.MODE_ECB which is deterministic. 
   Remediation: Upgrade to AES.MODE_GCM or AES.MODE_CBC. Generate a dynamic, cryptographically secure IV/nonce for every encryption and prepend it to the ciphertext so it can be decrypted.
2. Weak Randomness: `tokens.py` uses the standard `random` module for session tokens.
   Remediation: Use the `secrets` module for cryptographically secure random number generation.
3. Algorithm Confusion: `tokens.py` allows the 'none' algorithm in jwt.decode.
   Remediation: Restrict algorithms strictly to ["HS256"]. Remove "none".
4. Weak Password Hashing: `auth.py` uses MD5.
   Remediation: Upgrade to a secure hashing algorithm (e.g., hashlib.pbkdf2_hmac or hashlib.sha256).
5. Timing Attacks: `auth.py` compares hashes using standard string equality (`==`).
   Remediation: Use a constant-time comparison function like `secrets.compare_digest` or `hmac.compare_digest`.
EOF

# Set permissions
chown -R ga:ga "$WORKSPACE"

# Start VS Code
if ! pgrep -f "code" > /dev/null; then
    echo "Starting VS Code..."
    su - ga -c "DISPLAY=:1 code $WORKSPACE &"
    sleep 5
fi

# Wait for window and maximize
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Visual Studio Code"; then
        DISPLAY=:1 wmctrl -r "Visual Studio Code" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        DISPLAY=:1 wmctrl -a "Visual Studio Code" 2>/dev/null || true
        break
    fi
    sleep 1
done

# Take initial screenshot showing the initial state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="