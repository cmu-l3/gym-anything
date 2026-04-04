#!/bin/bash
# Do NOT use set -e: draw.io startup commands may return non-zero

echo "=== Setting up Active Directory Trust Topology task ==="

# 1. Create the Audit Report
cat > /home/ga/Desktop/ad_trust_audit.txt << 'EOF'
ACTIVE DIRECTORY TRUST AUDIT REPORT
===================================
Generated: 2024-05-15
Scope: Merger Integration (Contoso + Fabrikam)

FOREST 1: CONTOSO.COM
---------------------
Forest Functional Level: Windows Server 2016

Domains:
1. contoso.com (Forest Root)
2. corp.contoso.com (Child of contoso.com)
3. research.contoso.com (Child of contoso.com)

FOREST 2: FABRIKAM.NET
----------------------
Forest Functional Level: Windows Server 2012 R2

Domains:
1. fabrikam.net (Forest Root)
2. legacy.fabrikam.net (Child of fabrikam.net)

CONFIGURED TRUST RELATIONSHIPS
------------------------------
1. Intra-Forest:
   - Standard Parent-Child trusts exist within both forests.

2. Inter-Forest (Transitive):
   - Type: Forest Trust
   - Source: contoso.com
   - Target: fabrikam.net
   - Direction: Two-way / Bidirectional

3. External (Non-transitive, Shortcut):
   - Type: External Trust
   - Purpose: Allow 'corp' users to access legacy app in 'legacy' domain
   - Trusting Domain: corp.contoso.com
   - Trusted Domain: legacy.fabrikam.net
   - Direction: One-way (Incoming to legacy)
   
NOTE FOR ARCHITECTS:
Please map this topology. Use standard triangle notation for domains.
Ensure the direction of the External Trust is visualized correctly 
(Arrow points to the Trusted domain).
EOF

# Set permissions
chown ga:ga /home/ga/Desktop/ad_trust_audit.txt
chmod 644 /home/ga/Desktop/ad_trust_audit.txt

# 2. Cleanup previous artifacts
rm -f /home/ga/Desktop/ad_topology.drawio 2>/dev/null || true
rm -f /home/ga/Desktop/ad_topology.png 2>/dev/null || true

# 3. Record start time for anti-gaming
date +%s > /tmp/task_start_timestamp

# 4. Launch draw.io
# Find draw.io binary
DRAWIO_BIN=""
if command -v drawio &>/dev/null; then
    DRAWIO_BIN="drawio"
elif [ -f /opt/drawio/drawio ]; then
    DRAWIO_BIN="/opt/drawio/drawio"
elif [ -f /usr/bin/drawio ]; then
    DRAWIO_BIN="/usr/bin/drawio"
fi

echo "Launching draw.io..."
# Launch without file to get blank canvas (startup dialog)
su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true $DRAWIO_BIN --no-sandbox --disable-update > /tmp/drawio_launch.log 2>&1 &"

# Wait for window
for i in $(seq 1 30); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "draw.io"; then
        echo "draw.io window detected"
        break
    fi
    sleep 1
done

sleep 5

# Maximize window
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Dismiss startup dialog (Esc creates blank diagram)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Open the text file so the agent sees the requirements immediately
if command -v gedit &>/dev/null; then
    su - ga -c "DISPLAY=:1 gedit /home/ga/Desktop/ad_trust_audit.txt &"
    sleep 3
    # Organize windows: text on left, drawio on right (roughly)
    # We'll just focus draw.io so it's ready
    DISPLAY=:1 wmctrl -a "draw.io" 2>/dev/null || true
fi

# 5. Capture Initial State
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="