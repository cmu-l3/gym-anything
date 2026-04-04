#!/bin/bash
set -e

echo "=== Setting up Digital Logic Full Adder Task ==="

# 1. Prepare Data
# Create the specification file on the desktop
cat > /home/ga/Desktop/full_adder_spec.txt << 'EOF'
DIGITAL COMPONENT SPECIFICATION: 1-BIT FULL ADDER
=================================================

DESCRIPTION:
A 1-bit full adder adds three one-bit numbers (A, B, and Cin) 
and outputs two one-bit numbers, a Sum and a Carry-out (Cout).

TRUTH TABLE:
| A | B | Cin | Sum | Cout |
|---|---|-----|-----|------|
| 0 | 0 | 0   | 0   | 0    |
| 0 | 0 | 1   | 1   | 0    |
| 0 | 1 | 0   | 1   | 0    |
| 0 | 1 | 1   | 0   | 1    |
| 1 | 0 | 0   | 1   | 0    |
| 1 | 0 | 1   | 0   | 1    |
| 1 | 1 | 0   | 0   | 1    |
| 1 | 1 | 1   | 1   | 1    |

BOOLEAN EQUATIONS:
Sum  = (A XOR B) XOR Cin
Cout = (A AND B) OR (Cin AND (A XOR B))

IMPLEMENTATION REQUIREMENTS:
- Use standard Logic Gate symbols (IEEE/ANSI or IEC).
- Required Gates:
  * 2 XOR Gates
  * 2 AND Gates
  * 1 OR Gate
- Inputs: Label terminals 'A', 'B', 'Cin'
- Outputs: Label terminals 'Sum', 'Cout'
EOF

# Set permissions
chown ga:ga /home/ga/Desktop/full_adder_spec.txt

# Ensure Directories Exist
su - ga -c "mkdir -p /home/ga/Diagrams/exports"

# Remove any previous attempts
rm -f /home/ga/Diagrams/full_adder.drawio
rm -f /home/ga/Diagrams/exports/full_adder.png

# 2. Record Initial State
date +%s > /tmp/task_start_time.txt
echo "0" > /tmp/initial_drawio_exists

# 3. Launch draw.io
echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 /opt/drawio/drawio.AppImage --no-sandbox > /dev/null 2>&1 &"

# Wait for window
echo "Waiting for draw.io window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "draw.io"; then
        echo "Window detected."
        break
    fi
    sleep 1
done
sleep 5

# 4. Handle Update Dialogs (Anti-Blocking)
echo "Checking for update dialogs..."
for i in {1..5}; do
    if DISPLAY=:1 wmctrl -l | grep -qiE "update|confirm"; then
        echo "Dismissing update dialog..."
        DISPLAY=:1 xdotool key Escape
        sleep 0.5
    fi
done

# Focus window
DISPLAY=:1 wmctrl -a "draw.io" 2>/dev/null || true

# 5. Capture Initial Evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="