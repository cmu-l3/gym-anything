#!/bin/bash
# Do NOT use set -e: draw.io startup commands may return non-zero

echo "=== Setting up logic_circuit_adder task ==="

# Find draw.io binary
DRAWIO_BIN=""
if command -v drawio &>/dev/null; then
    DRAWIO_BIN="drawio"
elif [ -f /opt/drawio/drawio ]; then
    DRAWIO_BIN="/opt/drawio/drawio"
elif [ -f /usr/bin/drawio ]; then
    DRAWIO_BIN="/usr/bin/drawio"
fi

if [ -z "$DRAWIO_BIN" ]; then
    echo "ERROR: draw.io binary not found!"
    exit 1
fi

# Clean up any previous outputs
rm -f /home/ga/Desktop/ripple_carry_adder.drawio 2>/dev/null || true
rm -f /home/ga/Desktop/ripple_carry_adder.png 2>/dev/null || true

# Create the specification file
cat > /home/ga/Desktop/adder_specification.txt << 'SPECEOF'
ECEN 2350 - Digital Logic Design
Lab 4: 4-Bit Ripple Carry Adder Specification

OBJECTIVE:
Design and document a 4-bit parallel adder using full adder components.

PART 1: BLOCK DIAGRAM (Page 1)
------------------------------
Create a high-level block diagram connecting 4 Full Adder (FA) modules.
- Components: 4 blocks labeled FA0 (LSB), FA1, FA2, FA3 (MSB).
- Inputs:
  * Operand A: A0, A1, A2, A3
  * Operand B: B0, B1, B2, B3
  * Carry In: Cin (connect to 0/Ground)
- Outputs:
  * Sum: S0, S1, S2, S3
  * Carry Out: Cout (or C4)
- Interconnections:
  * The Carry Out of FA0 connects to Carry In of FA1
  * FA1 -> FA2
  * FA2 -> FA3
  * FA3 Carry Out is the final Carry Out

PART 2: GATE LEVEL SCHEMATIC (Page 2)
-------------------------------------
Draw the internal logic for ONE single Full Adder.
- Inputs: A, B, Cin
- Outputs: Sum, Cout
- Logic Equations:
  Sum = A ⊕ B ⊕ Cin
  Cout = (A · B) + (Cin · (A ⊕ B))
- Components:
  * XOR gates (for Sum and intermediate A⊕B)
  * AND gates
  * OR gate

DELIVERABLES:
1. File saved as "~/Desktop/ripple_carry_adder.drawio"
2. Page 1 exported as "~/Desktop/ripple_carry_adder.png"
SPECEOF

chown ga:ga /home/ga/Desktop/adder_specification.txt
chmod 644 /home/ga/Desktop/adder_specification.txt

# Record baseline state
INITIAL_COUNT=$(ls /home/ga/Desktop/*.drawio 2>/dev/null | wc -l || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_drawio_count

# Record start time for anti-gaming
date +%s > /tmp/task_start_timestamp

# Launch draw.io (startup dialog will appear)
echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true $DRAWIO_BIN --no-sandbox --disable-update > /tmp/drawio_adder.log 2>&1 &"

# Wait for draw.io window
echo "Waiting for draw.io window..."
for i in $(seq 1 30); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "draw.io"; then
        echo "draw.io window detected after ${i} seconds"
        break
    fi
    sleep 1
done

# Additional wait for UI to fully load
sleep 5

# Maximize the window
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Dismiss startup dialog (creates blank diagram)
echo "Dismissing startup dialog..."
DISPLAY=:1 xdotool key Escape
sleep 2

# Verify draw.io is running
if pgrep -f "drawio" > /dev/null; then
    echo "draw.io is running"
else
    echo "Warning: draw.io may not have started properly"
fi

# Take initial screenshot
DISPLAY=:1 import -window root /tmp/adder_task_start.png 2>/dev/null || true

echo "=== Setup complete ==="