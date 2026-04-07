#!/bin/bash
# Setup script for encrypted_archive_discovery_and_bruteforce task

echo "=== Setting up Encrypted Archive Discovery task ==="
source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time

# Clean up previous states
kill_autopsy 2>/dev/null || true
rm -f /tmp/encrypted_archive_result.json 2>/dev/null || true
rm -rf /home/ga/Cases/Encrypted_Triage_2024* 2>/dev/null || true
rm -rf /home/ga/Reports/exported_archives 2>/dev/null || true
rm -rf /home/ga/Reports/uncovered_evidence 2>/dev/null || true
mkdir -p /home/ga/Reports/exported_archives
mkdir -p /home/ga/Reports/uncovered_evidence
mkdir -p /home/ga/evidence
mkdir -p /var/lib/app/ground_truth/
chown -R ga:ga /home/ga/Reports/

# Ensure zip is available
if ! command -v zip &> /dev/null; then
    echo "zip command not found, attempting to install..."
    apt-get update -qq && apt-get install -y -qq zip unzip || true
fi

echo "Dynamically generating evidence..."
python3 << 'PYEOF'
import os, random, string, subprocess, json

# 1. Generate Dictionary & Select True Password
passwords = [
    "admin123", "password", "letmein", "hunter2", "qwerty",
    "dragon", "baseball", "sunshine", "iloveyou", "princess",
    "shadow", "peanut", "monkey", "starwars", "superman",
    "mustang", "football", "joshua", "secret", "cheese",
    "p@ssw0rd", "12345678", "bulldog", "matrix", "freedom"
]
# Generate some random complex ones to pad the dictionary
for _ in range(50):
    passwords.append(''.join(random.choices(string.ascii_lowercase + string.digits, k=random.randint(6, 10))))

true_password = random.choice(passwords)
random.shuffle(passwords)

with open("/home/ga/evidence/suspect_passwords.txt", "w") as f:
    for p in passwords:
        f.write(p + "\n")

# 2. Generate Secret Files
os.makedirs("/tmp/secrets", exist_ok=True)
secret_files = ["financial_ledgers_2023.csv", "project_titan_src.py"]
with open("/tmp/secrets/financial_ledgers_2023.csv", "w") as f:
    f.write("Account,Balance,Location\n1001,5400000,Cayman\n1002,120000,Swiss\n")
with open("/tmp/secrets/project_titan_src.py", "w") as f:
    f.write("def launch_titan():\n    print('Stealing IP...')\n    return True\n")

# 3. Zip and Encrypt
zip_filename = f"backup_{random.randint(1000,9999)}.zip"
zip_path = os.path.join("/tmp", zip_filename)

try:
    subprocess.run(["zip", "-P", true_password, "-j", zip_path, "/tmp/secrets/financial_ledgers_2023.csv", "/tmp/secrets/project_titan_src.py"], check=True)
except Exception as e:
    print(f"ERROR creating zip: {e}")
    # Fallback if zip fails, create dummy unencrypted file to not completely crash setup
    with open(zip_path, "wb") as f:
        f.write(b"PK\x03\x04DummyArchive")

# 4. Create FAT32 Disk Image
dd_path = "/home/ga/evidence/suspect_usb.dd"
subprocess.run(["dd", "if=/dev/zero", f"of={dd_path}", "bs=1M", "count=20"], check=True)
subprocess.run(["mkfs.vfat", "-F", "32", "-n", "SUSPECT_USB", dd_path], check=True)

# 5. Mount and copy files
os.makedirs("/tmp/mnt_usb", exist_ok=True)
subprocess.run(["mount", "-o", "loop", dd_path, "/tmp/mnt_usb"], check=True)

# Copy the encrypted zip
subprocess.run(["cp", zip_path, "/tmp/mnt_usb/"], check=True)

# Copy some decoy files
with open("/tmp/mnt_usb/readme.txt", "w") as f:
    f.write("Just a normal USB drive. Nothing to see here.\n")
with open("/tmp/mnt_usb/vacation_plans.txt", "w") as f:
    f.write("Flight to Hawaii on the 12th.\n")

# Copy some system binaries as realism decoys
subprocess.run(["cp", "/bin/ls", "/tmp/mnt_usb/ls_backup.bin"], check=True, stderr=subprocess.DEVNULL)

subprocess.run(["umount", "/tmp/mnt_usb"], check=True)

# 6. Save Ground Truth (hidden from agent)
gt = {
    "true_password": true_password,
    "archive_name": zip_filename,
    "secret_files": secret_files
}
os.makedirs("/var/lib/app/ground_truth/", exist_ok=True)
with open("/var/lib/app/ground_truth/encrypted_archive_gt.json", "w") as f:
    json.dump(gt, f)

# Set permissions
os.system("chown ga:ga /home/ga/evidence/*")
os.system("chmod 644 /home/ga/evidence/*")
os.system("chmod 700 /var/lib/app/ground_truth/")
PYEOF

echo "Evidence generation complete."

# Launch Autopsy and wait for Welcome screen
echo "Launching Autopsy..."
launch_autopsy
wait_for_autopsy_window 180

# Brief sleep to allow UI to settle
sleep 10
take_screenshot /tmp/task_initial_state.png

echo "=== Setup complete ==="