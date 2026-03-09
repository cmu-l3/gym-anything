#!/bin/bash
# Setup script for Transformer Architecture Diagram task
set -e

echo "=== Setting up transformer_architecture_diagram task ==="

# 1. Clean up any previous runs
rm -f /home/ga/Desktop/transformer_arch.drawio
rm -f /home/ga/Desktop/transformer_arch.png
rm -f /home/ga/Desktop/transformer_spec.txt

# 2. Create the architecture specification file
cat > /home/ga/Desktop/transformer_spec.txt << 'EOF'
TRANSFORMER ARCHITECTURE SPECIFICATION
======================================
Based on "Attention Is All You Need" (Vaswani et al.)

OVERVIEW
--------
The model consists of an Encoder Stack (left) and a Decoder Stack (right).
Both stacks communicate via an attention mechanism.

1. ENCODER STACK (Left Side)
   - Bottom input: "Inputs"
   - Layer 1: "Input Embedding"
   - Layer 2: "Positional Encoding"
   - REPEATING BLOCK (Label this stack "Nx"):
     * Sub-layer A: "Multi-Head Attention"
     * Sub-layer B: "Feed Forward"
     * CRITICAL: Each sub-layer has a residual connection around it followed by Layer Normalization.
       Represent this as a block labeled "Add & Norm" above each sub-layer.
       (Arrow flows: Input -> Split -> [Sub-layer] -> Add & Norm <- Split)

2. DECODER STACK (Right Side)
   - Bottom input: "Outputs (shifted right)"
   - Layer 1: "Output Embedding"
   - Layer 2: "Positional Encoding"
   - REPEATING BLOCK (Label this stack "Nx"):
     * Sub-layer A: "Masked Multi-Head Attention"
     * Sub-layer B: "Multi-Head Attention" (This layer receives input from the Encoder stack)
     * Sub-layer C: "Feed Forward"
     * CRITICAL: Each sub-layer has a residual connection and "Add & Norm" block.

3. FINAL OUTPUTS (Top of Decoder)
   - "Linear" layer
   - "Softmax" layer
   - Final output: "Output Probabilities"

CONNECTIONS
-----------
- Encoder output connects to the "Multi-Head Attention" sub-layer of the Decoder.
- Residual connections (skip connections) jump over the attention/feed-forward layers into the "Add & Norm" blocks.
EOF

chown ga:ga /home/ga/Desktop/transformer_spec.txt
chmod 644 /home/ga/Desktop/transformer_spec.txt

# 3. Record task start timestamp (anti-gaming)
date +%s > /tmp/task_start_time.txt

# 4. Launch draw.io
# We launch it with NO arguments so it opens the startup dialog.
# The agent is expected to handle the "Create New / Open Existing" flow (usually by pressing Cancel/Escape to get a blank canvas).
echo "Launching draw.io..."
if command -v drawio &>/dev/null; then
    CMD="drawio"
elif [ -f /opt/drawio/drawio ]; then
    CMD="/opt/drawio/drawio"
else
    CMD="drawio" # Hope it's in path
fi

# Use wrapper to suppress updates if available, else direct
su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true $CMD --no-sandbox --disable-update > /tmp/drawio.log 2>&1 &"

# 5. Wait for window
echo "Waiting for draw.io window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "draw.io"; then
        echo "Window detected."
        break
    fi
    sleep 1
done

# 6. Maximize window
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 7. Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="