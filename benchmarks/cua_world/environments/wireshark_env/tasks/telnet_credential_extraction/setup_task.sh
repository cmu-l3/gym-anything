#!/bin/bash
# Setup script for Telnet Credential Extraction task
echo "=== Setting up Telnet Credential Extraction ==="

. /workspace/scripts/task_utils.sh

if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        local path="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 scrot "$path" 2>/dev/null || DISPLAY=:1 import -window root "$path" 2>/dev/null || true
    }
fi

# Clean previous task state
rm -f /tmp/task_result.json /tmp/ground_truth_* /tmp/initial_* /tmp/task_start_*

PCAP="/home/ga/Documents/captures/telnet-cooked.pcap"

if [ ! -f "$PCAP" ]; then
    echo "ERROR: $PCAP not found!"
    exit 1
fi

# Remove previous output
rm -f /home/ga/Documents/captures/telnet_incident_report.txt

# --- Compute ground truth using tshark + Python for robust parsing ---

# Extract the full TCP stream for reference
tshark -r "$PCAP" -q -z "follow,tcp,ascii,0" 2>/dev/null > /tmp/ground_truth_telnet_stream

# Count Telnet packets
GT_TELNET_COUNT=$(tshark -r "$PCAP" -Y "telnet" 2>/dev/null | wc -l)
echo "$GT_TELNET_COUNT" > /tmp/ground_truth_telnet_count

# Use telnet.data fields for credential extraction (much cleaner than follow output)
tshark -r "$PCAP" -Y "telnet.data" -T fields -e telnet.data 2>/dev/null > /tmp/telnet_data_fields.txt

# Parse credentials and session details with Python
python3 << 'PYEOF'
import re

# Read telnet data fields
with open("/tmp/telnet_data_fields.txt") as f:
    lines = f.readlines()

# Parse the session: telnet data fields come as server->client and client->server
# "login: " is a prompt, the NEXT field is the username
# "Password:" is a prompt, the NEXT field is the password
username = ""
password = ""

for i, line in enumerate(lines):
    line_stripped = line.strip()

    # Match the LOGIN PROMPT specifically (not "Last login:")
    # The login prompt line should be exactly/mostly "login: " (short line)
    if re.match(r'^login:\s*$', line_stripped, re.IGNORECASE):
        # Next non-empty line is the username
        for j in range(i+1, min(i+3, len(lines))):
            next_val = lines[j].strip().replace("\\r\\n", "").replace("\\r", "").replace("\\n", "").strip()
            if next_val and not re.match(r'^(password|login):', next_val, re.IGNORECASE):
                username = next_val
                break

    # Match password prompt
    if re.match(r'^password:\s*$', line_stripped, re.IGNORECASE):
        for j in range(i+1, min(i+3, len(lines))):
            next_val = lines[j].strip().replace("\\r\\n", "").replace("\\r", "").replace("\\n", "").strip()
            if next_val:
                password = next_val
                break

# Get banner and commands from the raw stream (more reliable)
with open("/tmp/ground_truth_telnet_stream") as f:
    stream_text = f.read()

# Banner: look for OS identification lines
banner = ""
banner_match = re.search(r'OpenBSD[^\n]+', stream_text)
if banner_match:
    banner = banner_match.group(0).strip()
if not banner:
    for pattern in [r'(Linux|FreeBSD|SunOS|Solaris|AIX|HP-UX)[^\n]+',
                    r'Welcome to[^\n]+']:
        m = re.search(pattern, stream_text, re.IGNORECASE)
        if m:
            banner = m.group(0).strip()
            break

# Commands: find lines after "$ " prompts in the tshark follow output
# Format: "$ \n<byte_count>\n<command>"
commands = []
cmd_matches = re.findall(r'\$ \n\d+\n(.+)', stream_text)
for cmd in cmd_matches:
    cmd = cmd.strip()
    if cmd and len(cmd) > 1:
        commands.append(cmd)

# Write ground truth files
with open("/tmp/ground_truth_telnet_username", "w") as f:
    f.write(username)
with open("/tmp/ground_truth_telnet_password", "w") as f:
    f.write(password)
with open("/tmp/ground_truth_telnet_banner", "w") as f:
    f.write(banner)
with open("/tmp/ground_truth_telnet_commands", "w") as f:
    f.write("\n".join(commands))

# Generate keywords for verification
keywords = set()
for item in [username, password, banner] + commands:
    for word in re.findall(r'[a-z]{3,}', item.lower()):
        keywords.add(word)
with open("/tmp/ground_truth_telnet_keywords", "w") as f:
    f.write("\n".join(sorted(keywords)[:50]))

print(f"Username: {username}")
print(f"Password: {password[:3]}***" if password else "Password: (empty)")
print(f"Banner: {banner}")
print(f"Commands: {commands}")
PYEOF

date +%s > /tmp/task_start_timestamp

echo "Ground truth computed:"
echo "  Username: $(cat /tmp/ground_truth_telnet_username)"
echo "  Password: $(cat /tmp/ground_truth_telnet_password | head -c 3)***"
echo "  Banner: $(cat /tmp/ground_truth_telnet_banner)"
echo "  Commands found: $(cat /tmp/ground_truth_telnet_commands | wc -l)"
echo "  Telnet packets: $GT_TELNET_COUNT"

# Launch Wireshark with the PCAP
pkill -f wireshark 2>/dev/null || true
sleep 1
su - ga -c "DISPLAY=:1 wireshark '$PCAP' > /tmp/wireshark_task.log 2>&1 &"
sleep 5

take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
