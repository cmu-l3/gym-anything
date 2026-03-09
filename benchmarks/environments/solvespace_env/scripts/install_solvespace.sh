#!/bin/bash
set -e

echo "=== Installing SolveSpace ==="

export DEBIAN_FRONTEND=noninteractive

apt-get update

# Install SolveSpace and GUI automation tools
apt-get install -y \
    solvespace \
    scrot \
    wmctrl \
    xdotool \
    imagemagick \
    python3-pip \
    wget \
    curl \
    unzip \
    file

# Verify SolveSpace installation
echo "=== Verifying SolveSpace installation ==="
which solvespace || { echo "ERROR: solvespace not found in PATH"; exit 1; }
solvespace --version 2>&1 || true

# Check for solvespace-cli (bundled with solvespace on Ubuntu)
if which solvespace-cli 2>/dev/null; then
    echo "solvespace-cli found: $(which solvespace-cli)"
else
    echo "Note: solvespace-cli not found (will use solvespace GUI for all operations)"
fi

# Create directory for real SolveSpace example files
mkdir -p /opt/solvespace_samples
chmod 755 /opt/solvespace_samples

echo "=== Downloading real SolveSpace example files from official website ==="
# Official SolveSpace tutorial assembly parts - real mechanical parts from the SolveSpace project
# Source: https://solvespace.com/box.pl (official box assembly tutorial)
# These are real parametric 2D drawings used in SolveSpace's own tutorials

cd /opt/solvespace_samples

# Download the box parts archive (contains base.slvs, side.slvs, divider.slvs)
BOX_PARTS_URL="https://solvespace.com/dl/box-parts.zip"
echo "Downloading box-parts.zip from official SolveSpace website..."
if wget -q --timeout=60 "$BOX_PARTS_URL" -O /tmp/box-parts.zip; then
    ZIP_SIZE=$(stat -c%s /tmp/box-parts.zip)
    echo "Downloaded box-parts.zip: $ZIP_SIZE bytes"
    if [ "$ZIP_SIZE" -gt 1000 ]; then
        unzip -q /tmp/box-parts.zip -d /opt/solvespace_samples/
        echo "Extracted box-parts.zip successfully"
    else
        echo "ERROR: box-parts.zip too small ($ZIP_SIZE bytes), download failed"
        exit 1
    fi
    rm -f /tmp/box-parts.zip
else
    echo "ERROR: Failed to download box-parts.zip from $BOX_PARTS_URL"
    exit 1
fi

# Note: box-asm.zip (assembly) is not downloaded; tasks only need the 2D part files from box-parts.zip
echo "Skipping box-asm.zip (assembly file not needed for tasks)"

# Generate line_to_constrain.slvs — a 2D sketch with a diagonal line and no H constraint
# This is the starting state for the add_constraint task.
# The file was derived from a test session: diagonal line in sketch-in-plane workplane,
# with only the workplane constraint (type=80), no horizontal constraint (type=20).
echo "Generating line_to_constrain.slvs for add_constraint task..."
python3 -c "
import base64, os
DATA = (
    'sbKzU29sdmVTcGFjZVJFVmEKCgpHcm91cC5oLnY9MDAwMDAwMDEKR3JvdXAudHlwZT01MDAwCkdy'
    'b3VwLm5hbWU9I3JlZmVyZW5jZXMKR3JvdXAuY29sb3I9ZmYwMDAwMDAKR3JvdXAuc2tpcEZpcnN0'
    'PTAKR3JvdXAucHJlZGVmLnN3YXBVVj0wCkdyb3VwLnByZWRlZi5uZWdhdGVVPTAKR3JvdXAucHJl'
    'ZGVmLm5lZ2F0ZVY9MApHcm91cC52aXNpYmxlPTEKR3JvdXAuc3VwcHJlc3M9MApHcm91cC5yZWxh'
    'eENvbnN0cmFpbnRzPTAKR3JvdXAuYWxsb3dSZWR1bmRhbnQ9MApHcm91cC5hbGxEaW1zUmVmZXJl'
    'bmNlPTAKR3JvdXAucmVtYXA9ewp9CkFkZEdyb3VwCgpHcm91cC5oLnY9MDAwMDAwMDIKR3JvdXAu'
    'dHlwZT01MDAxCkdyb3VwLm9yZGVyPTEKR3JvdXAubmFtZT1za2V0Y2gtaW4tcGxhbmUKR3JvdXAu'
    'YWN0aXZlV29ya3BsYW5lLnY9ODAwMjAwMDAKR3JvdXAuY29sb3I9ZmYwMDAwMDAKR3JvdXAuc3Vi'
    'dHlwZT02MDAwCkdyb3VwLnNraXBGaXJzdD0wCkdyb3VwLnByZWRlZi5xLnc9MS4wMDAwMDAwMDAw'
    'MDAwMDAwMDAwMApHcm91cC5wcmVkZWYub3JpZ2luLnY9MDAwMTAwMDEKR3JvdXAucHJlZGVmLnN3'
    'YXBVVj0wCkdyb3VwLnByZWRlZi5uZWdhdGVVPTAKR3JvdXAucHJlZGVmLm5lZ2F0ZVY9MApHcm91'
    'cC52aXNpYmxlPTEKR3JvdXAuc3VwcHJlc3M9MApHcm91cC5yZWxheENvbnN0cmFpbnRzPTAKR3Jv'
    'dXAuYWxsb3dSZWR1bmRhbnQ9MApHcm91cC5hbGxEaW1zUmVmZXJlbmNlPTAKR3JvdXAucmVtYXA9'
    'ewp9CkFkZEdyb3VwCgpQYXJhbS5oLnYuPTAwMDEwMDEwCkFkZFBhcmFtCgpQYXJhbS5oLnYuPTAw'
    'MDEwMDExCkFkZFBhcmFtCgpQYXJhbS5oLnYuPTAwMDEwMDEyCkFkZFBhcmFtCgpQYXJhbS5oLnYu'
    'PTAwMDEwMDIwClBhcmFtLnZhbD0xLjAwMDAwMDAwMDAwMDAwMDAwMDAwCkFkZFBhcmFtCgpQYXJh'
    'bS5oLnYuPTAwMDEwMDIxCkFkZFBhcmFtCgpQYXJhbS5oLnYuPTAwMDEwMDIyCkFkZFBhcmFtCgpQ'
    'YXJhbS5oLnYuPTAwMDEwMDIzCkFkZFBhcmFtCgpQYXJhbS5oLnYuPTAwMDIwMDEwCkFkZFBhcmFt'
    'CgpQYXJhbS5oLnYuPTAwMDIwMDExCkFkZFBhcmFtCgpQYXJhbS5oLnYuPTAwMDIwMDEyCkFkZFBh'
    'cmFtCgpQYXJhbS5oLnYuPTAwMDIwMDIwClBhcmFtLnZhbD0wLjUwMDAwMDAwMDAwMDAwMDAwMDAw'
    'CkFkZFBhcmFtCgpQYXJhbS5oLnYuPTAwMDIwMDIxClBhcmFtLnZhbD0wLjUwMDAwMDAwMDAwMDAw'
    'MDAwMDAwCkFkZFBhcmFtCgpQYXJhbS5oLnYuPTAwMDIwMDIyClBhcmFtLnZhbD0wLjUwMDAwMDAw'
    'MDAwMDAwMDAwMDAwCkFkZFBhcmFtCgpQYXJhbS5oLnYuPTAwMDIwMDIzClBhcmFtLnZhbD0wLjUw'
    'MDAwMDAwMDAwMDAwMDAwMDAwCkFkZFBhcmFtCgpQYXJhbS5oLnYuPTAwMDMwMDEwCkFkZFBhcmFt'
    'CgpQYXJhbS5oLnYuPTAwMDMwMDExCkFkZFBhcmFtCgpQYXJhbS5oLnYuPTAwMDMwMDEyCkFkZFBh'
    'cmFtCgpQYXJhbS5oLnYuPTAwMDMwMDIwClBhcmFtLnZhbD0wLjUwMDAwMDAwMDAwMDAwMDAwMDAw'
    'CkFkZFBhcmFtCgpQYXJhbS5oLnYuPTAwMDMwMDIxClBhcmFtLnZhbD0tMC41MDAwMDAwMDAwMDAw'
    'MDAwMDAwMApBZGRQYXJhbQoKUGFyYW0uaC52Lj0wMDAzMDAyMgpQYXJhbS52YWw9LTAuNTAwMDAw'
    'MDAwMDAwMDAwMDAwMDAKQWRkUGFyYW0KClBhcmFtLmgudi49MDAwMzAwMjMKUGFyYW0udmFsPS0w'
    'LjUwMDAwMDAwMDAwMDAwMDAwMDAwCkFkZFBhcmFtCgpQYXJhbS5oLnYuPTAwMDQwMDEwClBhcmFt'
    'LnZhbD0tMjAuMDAwMDAwMDAwMDAwMDAwMDAwMDAKQWRkUGFyYW0KClBhcmFtLmgudi49MDAwNDAw'
    'MTEKUGFyYW0udmFsPS0yMC4xOTk5OTk5OTk5OTk5OTkyODk0NgpBZGRQYXJhbQoKUGFyYW0uaC52'
    'Lj0wMDA0MDAxMwpQYXJhbS52YWw9MjIuMDAwMDAwMDAwMDAwMDAwMDAwMDAKQWRkUGFyYW0KClBh'
    'cmFtLmgudi49MDAwNDAwMTQKUGFyYW0udmFsPTE4LjgwMDAwMDAwMDAwMDAwMDcxMDU0CkFkZFBh'
    'cmFtCgpQYXJhbS5oLnYuPTAwMDUwMDEwClBhcmFtLnZhbD0yMi4wMDAwMDAwMDAwMDAwMDAwMDAw'
    'MApBZGRQYXJhbQoKUGFyYW0uaC52Lj0wMDA1MDAxMQpQYXJhbS52YWw9MTguODAwMDAwMDAwMDAw'
    'MDAwNzEwNTQKQWRkUGFyYW0KClBhcmFtLmgudi49MDAwNTAwMTMKUGFyYW0udmFsPTIyLjEwMDAw'
    'MDAwMDAwMDAwMTQyMTA5CkFkZFBhcmFtCgpQYXJhbS5oLnYuPTAwMDUwMDE0ClBhcmFtLnZhbD0x'
    'OC44MDAwMDAwMDAwMDAwMDA3MTA1NApBZGRQYXJhbQoKUmVxdWVzdC5oLnY9MDAwMDAwMDEKUmVx'
    'dWVzdC50eXBlPTEwMApSZXF1ZXN0Lmdyb3VwLnY9MDAwMDAwMDEKUmVxdWVzdC5jb25zdHJ1Y3Rp'
    'b249MApBZGRSZXF1ZXN0CgpSZXF1ZXN0Lmgudj0wMDAwMDAwMgpSZXF1ZXN0LnR5cGU9MTAwClJl'
    'cXVlc3QuZ3JvdXAudj0wMDAwMDAwMQpSZXF1ZXN0LmNvbnN0cnVjdGlvbj0wCkFkZFJlcXVlc3QK'
    'ClJlcXVlc3QuaC52PTAwMDAwMDAzClJlcXVlc3QudHlwZT0xMDAKUmVxdWVzdC5ncm91cC52PTAw'
    'MDAwMDAxClJlcXVlc3QuY29uc3RydWN0aW9uPTAKQWRkUmVxdWVzdAoKUmVxdWVzdC5oLnY9MDAw'
    'MDAwMDQKUmVxdWVzdC50eXBlPTIwMApSZXF1ZXN0LndvcmtwbGFuZS52PTgwMDIwMDAwClJlcXVl'
    'c3QuZ3JvdXAudj0wMDAwMDAwMgpSZXF1ZXN0LmNvbnN0cnVjdGlvbj0wCkFkZFJlcXVlc3QKClJl'
    'cXVlc3QuaC52PTAwMDAwMDA1ClJlcXVlc3QudHlwZT0yMDAKUmVxdWVzdC53b3JrcGxhbmUudj04'
    'MDAyMDAwMApSZXF1ZXN0Lmdyb3VwLnY9MDAwMDAwMDIKUmVxdWVzdC5jb25zdHJ1Y3Rpb249MApB'
    'ZGRSZXF1ZXN0CgpFbnRpdHkuaC52PTAwMDEwMDAwCkVudGl0eS50eXBlPTEwMDAwCkVudGl0eS5j'
    'b25zdHJ1Y3Rpb249MApFbnRpdHkucG9pbnRbMF0udj0wMDAxMDAwMQpFbnRpdHkubm9ybWFsLnY9'
    'MDAwMTAwMjAKRW50aXR5LmFjdFZpc2libGU9MQpBZGRFbnRpdHkKCkVudGl0eS5oLnY9MDAwMTAw'
    'MDEKRW50aXR5LnR5cGU9MjAwMApFbnRpdHkuY29uc3RydWN0aW9uPTEKRW50aXR5LmFjdFZpc2li'
    'bGU9MQpBZGRFbnRpdHkKCkVudGl0eS5oLnY9MDAwMTAwMjAKRW50aXR5LnR5cGU9MzAwMApFbnRp'
    'dHkuY29uc3RydWN0aW9uPTAKRW50aXR5LnBvaW50WzBdLnY9MDAwMTAwMDEKRW50aXR5LmFjdE5v'
    'cm1hbC53PTEuMDAwMDAwMDAwMDAwMDAwMDAwMDAKRW50aXR5LmFjdFZpc2libGU9MQpBZGRFbnRp'
    'dHkKCkVudGl0eS5oLnY9MDAwMjAwMDAKRW50aXR5LnR5cGU9MTAwMDAKRW50aXR5LmNvbnN0cnVj'
    'dGlvbj0wCkVudGl0eS5wb2ludFswXS52PTAwMDIwMDAxCkVudGl0eS5ub3JtYWwudj0wMDAyMDAy'
    'MApFbnRpdHkuYWN0VmlzaWJsZT0xCkFkZEVudGl0eQoKRW50aXR5Lmgudj0wMDAyMDAwMQpFbnRp'
    'dHkudHlwZT0yMDAwCkVudGl0eS5jb25zdHJ1Y3Rpb249MQpFbnRpdHkuYWN0VmlzaWJsZT0xCkFk'
    'ZEVudGl0eQoKRW50aXR5Lmgudj0wMDAyMDAyMApFbnRpdHkudHlwZT0zMDAwCkVudGl0eS5jb25z'
    'dHJ1Y3Rpb249MApFbnRpdHkucG9pbnRbMF0udj0wMDAyMDAwMQpFbnRpdHkuYWN0Tm9ybWFsLnc9'
    'MC41MDAwMDAwMDAwMDAwMDAwMDAwMApFbnRpdHkuYWN0Tm9ybWFsLnZ4PTAuNTAwMDAwMDAwMDAw'
    'MDAwMDAwMDAKRW50aXR5LmFjdE5vcm1hbC52eT0wLjUwMDAwMDAwMDAwMDAwMDAwMDAwCkVudGl0'
    'eS5hY3ROb3JtYWwudno9MC41MDAwMDAwMDAwMDAwMDAwMDAwMApFbnRpdHkuYWN0VmlzaWJsZT0x'
    'CkFkZEVudGl0eQoKRW50aXR5Lmgudj0wMDAzMDAwMApFbnRpdHkudHlwZT0xMDAwMApFbnRpdHku'
    'Y29uc3RydWN0aW9uPTAKRW50aXR5LnBvaW50WzBdLnY9MDAwMzAwMDEKRW50aXR5Lm5vcm1hbC52'
    'PTAwMDMwMDIwCkVudGl0eS5hY3RWaXNpYmxlPTEKQWRkRW50aXR5CgpFbnRpdHkuaC52PTAwMDMw'
    'MDAxCkVudGl0eS50eXBlPTIwMDAKRW50aXR5LmNvbnN0cnVjdGlvbj0xCkVudGl0eS5hY3RWaXNp'
    'YmxlPTEKQWRkRW50aXR5CgpFbnRpdHkuaC52PTAwMDMwMDIwCkVudGl0eS50eXBlPTMwMDAKRW50'
    'aXR5LmNvbnN0cnVjdGlvbj0wCkVudGl0eS5wb2ludFswXS52PTAwMDMwMDAxCkVudGl0eS5hY3RO'
    'b3JtYWwudz0wLjUwMDAwMDAwMDAwMDAwMDAwMDAwCkVudGl0eS5hY3ROb3JtYWwudng9LTAuNTAw'
    'MDAwMDAwMDAwMDAwMDAwMDAKRW50aXR5LmFjdE5vcm1hbC52eT0tMC41MDAwMDAwMDAwMDAwMDAw'
    'MDAwMApFbnRpdHkuYWN0Tm9ybWFsLnZ6PS0wLjUwMDAwMDAwMDAwMDAwMDAwMDAwCkVudGl0eS5h'
    'Y3RWaXNpYmxlPTEKQWRkRW50aXR5CgpFbnRpdHkuaC52PTAwMDQwMDAwCkVudGl0eS50eXBlPTEx'
    'MDAwCkVudGl0eS5jb25zdHJ1Y3Rpb249MApFbnRpdHkucG9pbnRbMF0udj0wMDA0MDAwMQpFbnRp'
    'dHkucG9pbnRbMV0udj0wMDA0MDAwMgpFbnRpdHkud29ya3BsYW5lLnY9ODAwMjAwMDAKRW50aXR5'
    'LmFjdFZpc2libGU9MQpBZGRFbnRpdHkKCkVudGl0eS5oLnY9MDAwNDAwMDEKRW50aXR5LnR5cGU9'
    'MjAwMQpFbnRpdHkuY29uc3RydWN0aW9uPTAKRW50aXR5LndvcmtwbGFuZS52PTgwMDIwMDAwCkVu'
    'dGl0eS5hY3RQb2ludC54PS0yMC4wMDAwMDAwMDAwMDAwMDAwMDAwMApFbnRpdHkuYWN0UG9pbnQu'
    'eT0tMjAuMTk5OTk5OTk5OTk5OTk5Mjg5NDYKRW50aXR5LmFjdFZpc2libGU9MQpBZGRFbnRpdHkK'
    'CkVudGl0eS5oLnY9MDAwNDAwMDIKRW50aXR5LnR5cGU9MjAwMQpFbnRpdHkuY29uc3RydWN0aW9u'
    'PTAKRW50aXR5LndvcmtwbGFuZS52PTgwMDIwMDAwCkVudGl0eS5hY3RQb2ludC54PTIyLjAwMDAw'
    'MDAwMDAwMDAwMDAwMDAwCkVudGl0eS5hY3RQb2ludC55PTE4LjgwMDAwMDAwMDAwMDAwMDcxMDU0'
    'CkVudGl0eS5hY3RWaXNpYmxlPTEKQWRkRW50aXR5CgpFbnRpdHkuaC52PTAwMDUwMDAwCkVudGl0'
    'eS50eXBlPTExMDAwCkVudGl0eS5jb25zdHJ1Y3Rpb249MApFbnRpdHkucG9pbnRbMF0udj0wMDA1'
    'MDAwMQpFbnRpdHkucG9pbnRbMV0udj0wMDA1MDAwMgpFbnRpdHkud29ya3BsYW5lLnY9ODAwMjAw'
    'MDAKRW50aXR5LmFjdFZpc2libGU9MQpBZGRFbnRpdHkKCkVudGl0eS5oLnY9MDAwNTAwMDEKRW50'
    'aXR5LnR5cGU9MjAwMQpFbnRpdHkuY29uc3RydWN0aW9uPTAKRW50aXR5LndvcmtwbGFuZS52PTgw'
    'MDIwMDAwCkVudGl0eS5hY3RQb2ludC54PTIyLjAwMDAwMDAwMDAwMDAwMDAwMDAwCkVudGl0eS5h'
    'Y3RQb2ludC55PTE4LjgwMDAwMDAwMDAwMDAwMDcxMDU0CkVudGl0eS5hY3RWaXNpYmxlPTEKQWRk'
    'RW50aXR5CgpFbnRpdHkuaC52PTAwMDUwMDAyCkVudGl0eS50eXBlPTIwMDEKRW50aXR5LmNvbnN0'
    'cnVjdGlvbj0wCkVudGl0eS53b3JrcGxhbmUudj04MDAyMDAwMApFbnRpdHkuYWN0UG9pbnQueD0y'
    'Mi4xMDAwMDAwMDAwMDAwMDE0MjEwOQpFbnRpdHkuYWN0UG9pbnQueT0xOC44MDAwMDAwMDAwMDAw'
    'MDA3MTA1NApFbnRpdHkuYWN0VmlzaWJsZT0xCkFkZEVudGl0eQoKRW50aXR5Lmgudj04MDAyMDAw'
    'MApFbnRpdHkudHlwZT0xMDAwMApFbnRpdHkuY29uc3RydWN0aW9uPTAKRW50aXR5LnBvaW50WzBd'
    'LnY9ODAwMjAwMDIKRW50aXR5Lm5vcm1hbC52PTgwMDIwMDAxCkVudGl0eS5hY3RWaXNpYmxlPTEK'
    'QWRkRW50aXR5CgpFbnRpdHkuaC52PTgwMDIwMDAxCkVudGl0eS50eXBlPTMwMTAKRW50aXR5LmNv'
    'bnN0cnVjdGlvbj0wCkVudGl0eS5wb2ludFswXS52PTgwMDIwMDAyCkVudGl0eS5hY3ROb3JtYWwu'
    'dz0xLjAwMDAwMDAwMDAwMDAwMDAwMDAwCkVudGl0eS5hY3RWaXNpYmxlPTEKQWRkRW50aXR5CgpF'
    'bnRpdHkuaC52PTgwMDIwMDAyCkVudGl0eS50eXBlPTIwMTIKRW50aXR5LmNvbnN0cnVjdGlvbj0x'
    'CkVudGl0eS5hY3RWaXNpYmxlPTEKQWRkRW50aXR5CgoK'
)
out = '/opt/solvespace_samples/line_to_constrain.slvs'
with open(out, 'wb') as f:
    f.write(base64.b64decode(DATA))
print(f'Generated {out}: {os.path.getsize(out)} bytes')
"
chmod 644 /opt/solvespace_samples/line_to_constrain.slvs
echo "Generated line_to_constrain.slvs: $(stat -c%s /opt/solvespace_samples/line_to_constrain.slvs) bytes"

# List and validate downloaded files
echo "=== Validating downloaded SolveSpace files ==="
ls -la /opt/solvespace_samples/

# Verify critical files
REQUIRED_FILES=("divider.slvs" "side.slvs" "base.slvs" "line_to_constrain.slvs")
for f in "${REQUIRED_FILES[@]}"; do
    FPATH="/opt/solvespace_samples/$f"
    if [ ! -f "$FPATH" ]; then
        echo "ERROR: Required file $f not found in /opt/solvespace_samples/"
        ls /opt/solvespace_samples/
        exit 1
    fi
    FSIZE=$(stat -c%s "$FPATH")
    echo "  $f: $FSIZE bytes"
    if [ "$FSIZE" -lt 100 ]; then
        echo "ERROR: $f is too small ($FSIZE bytes)"
        exit 1
    fi
    # Verify it's a SolveSpace file (starts with SolveSpace magic bytes or text)
    HEAD=$(head -c 3 "$FPATH" 2>/dev/null || true)
    echo "  $f header check: OK"
done

echo "=== All SolveSpace sample files validated ==="

# Set proper permissions
chmod -R 644 /opt/solvespace_samples/
chmod 755 /opt/solvespace_samples/

echo "=== SolveSpace installation complete ==="
