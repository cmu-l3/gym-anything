#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Cybersecurity Key Ceremony Formatting Task ==="

kill_calligra_processes

install -d -o ga -g ga /home/ga/Documents
install -d -o ga -g ga /home/ga/Desktop

rm -f /home/ga/Documents/root_ca_ceremony.odt
rm -f /home/ga/Desktop/ceremony_formatting_rules.txt

# --- Generate the formatting rules ---
cat > /home/ga/Desktop/ceremony_formatting_rules.txt << 'EOF'
# AUDIT DOCUMENT STYLE GUIDE
# Applies to: Root CA Key Generation Ceremony

1. Document Title: Must be Centered, Bold, and at least 16pt font size.
2. Table of Contents: Must be inserted immediately after the Title and Metadata section.
3. Phase Headings: The 5 major phases (Pre-Ceremony Environment Setup, HSM Initialization, Root Key Generation, Root Certificate Issuance, Backup and Teardown) must be formatted as Heading 1.
4. Action Steps (Roles): Every action step begins with a Role (e.g., "Key Administrator:", "Internal Auditor:", "Security Officer:"). You MUST apply Bold formatting ONLY to the Role and its colon. The rest of the instruction text in that paragraph must remain normal (not bold).
5. Terminal Commands: Every console command begins with a ">". You must format the entire line with a Monospace font (e.g., Liberation Mono, Courier, Consolas) and apply a left indent (margin).
6. Sign-off Block: The comma-separated list of roles at the end of the document must be converted into a 3-column table with the headers: "Role", "Printed Name", "Signature".
EOF

chown ga:ga /home/ga/Desktop/ceremony_formatting_rules.txt

# --- Generate the unformatted ODT document ---
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.text import P

doc = OpenDocumentText()

def add(text=""):
    doc.text.addElement(P(text=text))

add("Root Certificate Authority Key Generation Ceremony")
add("Date: October 12, 2026")
add("Location: Secure Facility Vault B")
add("Target System: Offline Root CA")
add("")
add("Pre-Ceremony Environment Setup")
add("Internal Auditor: Verify the seals on the secure cage and confirm the air-gapped status of the target machine.")
add("Key Administrator: Boot the air-gapped laptop from the verified live USB OS media.")
add("> sha256sum /dev/cdrom")
add("")
add("HSM Initialization")
add("Security Officer: Connect the Hardware Security Module (HSM) to the USB port.")
add("Key Administrator: Initialize the HSM and set the Security Officer PIN.")
add("> pkcs11-tool --module /usr/lib/opensc-pkcs11.so --init-token --label \"RootCA_HSM\" --so-pin <SO_PIN>")
add("Security Officer: Generate the User PIN and provide it to the Key Administrator.")
add("> pkcs11-tool --module /usr/lib/opensc-pkcs11.so --login --login-type so --so-pin <SO_PIN> --init-pin --pin <USER_PIN>")
add("")
add("Root Key Generation")
add("Key Administrator: Log into the HSM and generate the 4096-bit RSA key pair.")
add("> pkcs11-tool --module /usr/lib/opensc-pkcs11.so --login --pin <USER_PIN> --keypairgen --key-type rsa:4096 --label \"RootCA_Key\"")
add("Internal Auditor: Verify the key was successfully generated on the token.")
add("> pkcs11-tool --module /usr/lib/opensc-pkcs11.so --list-objects")
add("")
add("Root Certificate Issuance")
add("Key Administrator: Generate the self-signed Root CA certificate valid for 20 years.")
add("> openssl req -engine pkcs11 -new -key \"pkcs11:object=RootCA_Key\" -keyform engine -x509 -days 7300 -out RootCA.crt -subj \"/CN=Nexus Root CA G1/O=Nexus Systems Corp./C=US\"")
add("Internal Auditor: Verify the certificate details and thumbprint.")
add("> openssl x509 -in RootCA.crt -text -noout")
add("")
add("Backup and Teardown")
add("Security Officer: Export the public certificate to a transfer USB drive.")
add("> cp RootCA.crt /mnt/transfer_usb/")
add("Key Administrator: Shut down the air-gapped laptop and disconnect the HSM.")
add("> shutdown -h now")
add("")
add("Sign-off Block")
add("Role, Printed Name, Signature")
add("Key Administrator, , ")
add("Internal Auditor, , ")
add("Security Officer, , ")

doc.save("/home/ga/Documents/root_ca_ceremony.odt")
PYEOF

chown ga:ga /home/ga/Documents/root_ca_ceremony.odt

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time

# Launch Calligra Words
launch_calligra_document "/home/ga/Documents/root_ca_ceremony.odt"

# Wait and maximize
if wait_for_window "Calligra Words" 30; then
    WID=$(get_calligra_window_id)
    if [ -n "$WID" ]; then
        focus_window "$WID"
        DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        sleep 2
    fi
fi

# Take baseline screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Setup complete ==="