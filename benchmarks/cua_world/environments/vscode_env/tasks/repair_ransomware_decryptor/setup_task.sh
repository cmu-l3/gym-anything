#!/bin/bash
set -e

echo "=== Setting up Repair Ransomware Decryptor Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure cryptography package is installed
pip3 install cryptography --quiet

WORKSPACE_DIR="/home/ga/workspace/ransomware_recovery"
GT_DIR="/var/lib/app/ground_truth"

mkdir -p "$WORKSPACE_DIR"
mkdir -p "$WORKSPACE_DIR/infected_drive"
mkdir -p "$GT_DIR"

# Hide ground truth from the agent
chmod 700 "$GT_DIR"

# ─────────────────────────────────────────────────────────────
# Generate Ground Truth and Encrypted Files using Python
# ─────────────────────────────────────────────────────────────
python3 << 'PYGEN'
import os
import secrets
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives import padding, hashes
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
from cryptography.hazmat.backends import default_backend

gt_dir = '/var/lib/app/ground_truth'
inf_dir = '/home/ga/workspace/ransomware_recovery/infected_drive'

os.makedirs(os.path.join(gt_dir, 'subdir'), exist_ok=True)
os.makedirs(os.path.join(inf_dir, 'subdir'), exist_ok=True)

# Create mock file contents
# Note: The PNG and PDF mock files intentionally end with bytes that 
# would be stripped by a naive `rstrip` to trigger the padding bug.
files = {
    'notes.txt': b"CONFIDENTIAL: Q3 Financial Results.\n",
    'diagram.png': b"\x89PNG\r\n\x1a\n" + os.urandom(50) + b"\x01\x02\x03",
    'subdir/config.txt': b"Nested system credentials.\n",
    'subdir/report.pdf': b"%PDF-1.4\n" + os.urandom(50) + b"\x0a\x0a"
}

password = b"admin123"

for rel_path, content in files.items():
    # Save ground truth
    gt_path = os.path.join(gt_dir, rel_path)
    with open(gt_path, 'wb') as f:
        f.write(content)

    # Encrypt
    salt = secrets.token_bytes(16)
    iv = secrets.token_bytes(16)
    
    kdf = PBKDF2HMAC(
        algorithm=hashes.SHA256(),
        length=32,
        salt=salt,
        iterations=100000,
        backend=default_backend()
    )
    key = kdf.derive(password)

    cipher = Cipher(algorithms.AES(key), modes.CBC(iv), backend=default_backend())
    encryptor = cipher.encryptor()

    padder = padding.PKCS7(128).padder()
    padded = padder.update(content) + padder.finalize()
    ciphertext = encryptor.update(padded) + encryptor.finalize()

    # Save encrypted file: Salt(16) + IV(16) + Ciphertext
    enc_path = os.path.join(inf_dir, rel_path + '.crypt26')
    with open(enc_path, 'wb') as f:
        f.write(salt + iv + ciphertext)
PYGEN

# ─────────────────────────────────────────────────────────────
# Create Task Files
# ─────────────────────────────────────────────────────────────

# Create the spec document
cat > "$WORKSPACE_DIR/ransomware_spec.md" << 'EOF'
# CryptLocker-26 Analysis Report

**Malware Family:** CryptLocker-26
**Encryption Algorithm:** AES-256 in CBC mode
**Block Padding:** PKCS7
**Key Derivation Function:** PBKDF2 HMAC-SHA256
**KDF Iterations:** 100,000

**File Structure:**
Each encrypted file prepends the cryptographic parameters to the ciphertext:
`[16 bytes Salt] + [16 bytes IV] + [Ciphertext]`

**Notes:**
The master password for this endpoint was recovered: `admin123`.
A junior analyst drafted `decryptor.py`, but it is failing to decrypt subdirectories and is permanently corrupting our binary files (PDFs, PNGs). Please review the script against this specification and fix the bugs.
EOF

# Create the buggy decryptor
cat > "$WORKSPACE_DIR/decryptor.py" << 'EOF'
#!/usr/bin/env python3
import os
import argparse
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives import hashes, padding
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC

def derive_key(password: bytes, salt: bytes) -> bytes:
    kdf = PBKDF2HMAC(
        algorithm=hashes.SHA256(),
        length=32,
        salt=salt,
        iterations=10000,
        backend=default_backend()
    )
    return kdf.derive(password)

def decrypt_file(filepath: str, password: str):
    with open(filepath, 'rb') as f:
        data = f.read()

    salt = data[:16]
    iv = data[16:48]
    ciphertext = data[48:]

    key = derive_key(password.encode(), salt)

    cipher = Cipher(algorithms.AES(key), modes.CBC(iv), backend=default_backend())
    decryptor = cipher.decryptor()
    padded_plaintext = decryptor.update(ciphertext) + decryptor.finalize()

    # Remove padding
    plaintext = padded_plaintext.rstrip(bytes(range(1, 17)))

    original_path = filepath[:-8]
    
    with open(original_path, 'w') as f:
        try:
            f.write(plaintext.decode('utf-8'))
        except UnicodeDecodeError:
            f.write(str(plaintext))
            
    os.remove(filepath)

def recover_drive(directory: str, password: str):
    for filename in os.listdir(directory):
        filepath = os.path.join(directory, filename)
        if os.path.isfile(filepath) and filepath.endswith('.crypt26'):
            try:
                decrypt_file(filepath, password)
                print(f"Decrypted {filepath}")
            except Exception as e:
                print(f"Failed to decrypt {filepath}: {e}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="CryptLocker-26 Decryptor")
    parser.add_argument("--dir", required=True, help="Directory to decrypt")
    parser.add_argument("--password", required=True, help="Master password")
    args = parser.parse_args()
    
    recover_drive(args.dir, args.password)
EOF

# Set permissions
chown -R ga:ga "$WORKSPACE_DIR"
chmod +x "$WORKSPACE_DIR/decryptor.py"

# Start VS Code
su - ga -c "DISPLAY=:1 code $WORKSPACE_DIR/decryptor.py"

# Wait for VS Code to load
wait_for_window "Visual Studio Code" 30
focus_vscode_window 2>/dev/null || true
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Capture initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png ga

echo "=== Task Setup Complete ==="