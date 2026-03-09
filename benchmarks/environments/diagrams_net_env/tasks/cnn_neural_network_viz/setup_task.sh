#!/bin/bash
set -e

echo "=== Setting up CNN Neural Network Viz Task ==="

# 1. Create Directories
mkdir -p /home/ga/Desktop
mkdir -p /home/ga/Diagrams
chown -R ga:ga /home/ga/Desktop /home/ga/Diagrams

# 2. Create the Model Summary File
# This contains the specific architecture the agent must visualize
cat > /home/ga/Desktop/model_summary.txt << 'EOF'
Model: "SimpleNet-V2"
_________________________________________________________________
 Layer (type)                Output Shape              Param #   
=================================================================
 input_1 (InputLayer)        [(None, 32, 32, 3)]       0         
                                                                 
 conv2d_1 (Conv2D)           (None, 28, 28, 32)        896       
                                                                 
 max_pooling2d_1 (MaxPooling (None, 14, 14, 32)        0         
                                                                 
 conv2d_2 (Conv2D)           (None, 12, 12, 64)        18496     
                                                                 
 max_pooling2d_2 (MaxPooling (None, 6, 6, 64)          0         
                                                                 
 flatten_1 (Flatten)         (None, 2304)              0         
                                                                 
 dense_1 (Dense)             (None, 128)               295040    
                                                                 
 dense_2 (Dense)             (None, 10)                1290      
                                                                 
=================================================================
Total params: 315,722
Trainable params: 315,722
Non-trainable params: 0
_________________________________________________________________
EOF

chown ga:ga /home/ga/Desktop/model_summary.txt
chmod 644 /home/ga/Desktop/model_summary.txt

# 3. Clean previous results
rm -f /home/ga/Diagrams/cnn_architecture.drawio
rm -f /home/ga/Diagrams/cnn_architecture.pdf

# 4. Record task start time
date +%s > /tmp/task_start_time.txt

# 5. Launch Draw.io
echo "Launching draw.io..."
# Kill any existing instances
pkill -f drawio 2>/dev/null || true
sleep 1

# Launch as user ga
su - ga -c "DISPLAY=:1 /opt/drawio/drawio.AppImage --no-sandbox > /tmp/drawio.log 2>&1 &"

# Wait for window
echo "Waiting for draw.io window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "draw.io"; then
        echo "draw.io window detected"
        break
    fi
    sleep 1
done

# Dismiss Update Dialog (Aggressive)
# This is critical as the dialog blocks interaction
echo "Dismissing potential update dialogs..."
sleep 5 # Wait for it to pop up
for i in {1..5}; do
    # Try Escape
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    # Try navigating to Cancel
    DISPLAY=:1 xdotool key Tab Tab Return 2>/dev/null || true
    sleep 0.5
done

# Maximize window
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 6. Initial Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="