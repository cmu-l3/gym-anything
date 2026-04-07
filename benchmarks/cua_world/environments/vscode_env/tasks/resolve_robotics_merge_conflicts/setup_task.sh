#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up Resolve Robotics Merge Conflicts Task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

WORKSPACE_DIR="/home/ga/workspace/robocontrol"
mkdir -p "$WORKSPACE_DIR/config"
mkdir -p "$WORKSPACE_DIR/src/utils"
mkdir -p "$WORKSPACE_DIR/tests"

# Configure git identity for the user
sudo -u ga git config --global user.name "Developer"
sudo -u ga git config --global user.email "dev@robocontrol.local"

# ==========================================
# 1. GENERATE BASE REPOSITORY
# ==========================================
cat > "$WORKSPACE_DIR/config/robot_params.yaml" << 'EOF'
chassis:
  type: "differential_drive"
  wheel_radius_m: 0.1
  track_width_m: 0.45
EOF

cat > "$WORKSPACE_DIR/src/robot_controller.py" << 'EOF'
class RobotController:
    def __init__(self):
        self.state = "INIT"
        self.active = False

    def read_sensors(self):
        # Base sensor reading
        pass

    def compute_control(self):
        # Base control logic
        return 0.0
EOF

cat > "$WORKSPACE_DIR/src/utils/transforms.py" << 'EOF'
import math

def normalize_angle(angle):
    while angle > math.pi:
        angle -= 2.0 * math.pi
    while angle < -math.pi:
        angle += 2.0 * math.pi
    return angle
EOF

cat > "$WORKSPACE_DIR/tests/test_controller.py" << 'EOF'
import pytest
from src.robot_controller import RobotController

def test_init():
    ctrl = RobotController()
    assert ctrl.state == "INIT"

def setup_controller():
    return {}
EOF

cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Robocontrol
A basic robotics control package for warehouse automation.

## Features
- Differential drive support
- Basic kinematic modeling
EOF

cat > "$WORKSPACE_DIR/requirements.txt" << 'EOF'
numpy==1.24.3
pytest==7.3.1
EOF

chown -R ga:ga "$WORKSPACE_DIR"

cd "$WORKSPACE_DIR"
sudo -u ga git init
sudo -u ga git add .
sudo -u ga git commit -m "Initial commit of base robotics package"

# ==========================================
# 2. CREATE BRANCH: feature/pid-tuning
# ==========================================
sudo -u ga git checkout -b feature/pid-tuning

cat > "$WORKSPACE_DIR/config/robot_params.yaml" << 'EOF'
chassis:
  type: "differential_drive"
  wheel_radius_m: 0.1
  track_width_m: 0.45
motors:
  pid:
    kp: 2.8
    ki: 0.15
    kd: 0.95
  max_velocity_ms: 1.5
  acceleration_limit_ms2: 0.8
  deadband_threshold: 0.02
EOF

cat > "$WORKSPACE_DIR/src/robot_controller.py" << 'EOF'
import time

class RobotController:
    def __init__(self):
        self.state = "INIT"
        self.active = False
        self.pid = {"kp": 2.8, "ki": 0.15, "kd": 0.95}
        self.last_time = time.time()

    def read_sensors(self):
        # Calculate dt for precise PID control
        now = time.time()
        self.dt = now - self.last_time
        self.last_time = now

    def compute_control(self):
        # Advanced PID control logic
        error = 0.0 # Placeholder
        p_out = self.pid["kp"] * error
        return p_out
EOF

cat > "$WORKSPACE_DIR/src/utils/transforms.py" << 'EOF'
import math
from collections import deque

def normalize_angle(angle):
    while angle > math.pi:
        angle -= 2.0 * math.pi
    while angle < -math.pi:
        angle += 2.0 * math.pi
    return angle

def clamp_value(value, min_val, max_val):
    return max(min_val, min(value, max_val))

def moving_average(values, window_size):
    if not values: return 0.0
    return sum(values) / len(values)
EOF

cat > "$WORKSPACE_DIR/tests/test_controller.py" << 'EOF'
import pytest
from src.robot_controller import RobotController

def test_init():
    ctrl = RobotController()
    assert ctrl.state == "INIT"

def setup_controller():
    return {"pid": "mock_pid"}

def test_pid_response_convergence():
    assert True # Verify PID tuning converges

def test_deadband_filtering():
    assert True # Verify deadband ignores small noise
EOF

cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Robocontrol
A basic robotics control package for warehouse automation.

## Features
- Differential drive support
- Basic kinematic modeling
- Adaptive PID Control

## PID Tuning Guide
Use the Ziegler-Nichols method for initial tuning. Ensure the deadband is set appropriately to avoid motor jitter.
EOF

sudo -u ga git add .
sudo -u ga git commit -m "Add PID tuning parameters and control logic"

# ==========================================
# 3. CREATE BRANCH: feature/sensor-upgrade
# ==========================================
sudo -u ga git checkout main
sudo -u ga git checkout -b feature/sensor-upgrade

cat > "$WORKSPACE_DIR/config/robot_params.yaml" << 'EOF'
chassis:
  type: "differential_drive"
  wheel_radius_m: 0.1
  track_width_m: 0.45
imu:
  type: "BNO055"
  update_rate_hz: 100
  calibration_offsets:
    gyro: [0.012, -0.008, 0.003]
    accel: [0.05, -0.02, 0.01]
  fusion_algorithm: "madgwick"
  beta: 0.041
lidar:
  max_range_m: 12.0
EOF

cat > "$WORKSPACE_DIR/src/robot_controller.py" << 'EOF'
class RobotController:
    def __init__(self):
        self.state = "INIT"
        self.active = False
        self.imu = {"type": "BNO055", "ready": True}

    def read_sensors(self):
        # Read IMU quaternion
        self.orientation = [0.0, 0.0, 0.0, 1.0]
        self.fuse_orientation()

    def fuse_orientation(self):
        # Sensor fusion logic
        pass

    def compute_control(self):
        # Base control logic
        return 0.0
EOF

cat > "$WORKSPACE_DIR/src/utils/transforms.py" << 'EOF'
import math
import numpy as np
from math import atan2, asin

def normalize_angle(angle):
    while angle > math.pi:
        angle -= 2.0 * math.pi
    while angle < -math.pi:
        angle += 2.0 * math.pi
    return angle

def quaternion_to_euler(q):
    # Convert quaternion to euler angles
    sinr_cosp = 2 * (q[3] * q[0] + q[1] * q[2])
    cosr_cosp = 1 - 2 * (q[0] * q[0] + q[1] * q[1])
    roll = atan2(sinr_cosp, cosr_cosp)
    return [roll, 0.0, 0.0]
EOF

cat > "$WORKSPACE_DIR/tests/test_controller.py" << 'EOF'
import pytest
from src.robot_controller import RobotController

def test_init():
    ctrl = RobotController()
    assert ctrl.state == "INIT"

def setup_controller():
    return {"imu": "mock_imu_sensor"}

def test_imu_data_integration():
    assert True # Verify IMU reads correctly

def test_orientation_fusion_accuracy():
    assert True # Verify fusion math
EOF

cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Robocontrol
A basic robotics control package for warehouse automation.

## Features
- Differential drive support
- Basic kinematic modeling
- IMU Sensor Fusion

## Sensor Configuration
Ensure BNO055 is connected to I2C bus 1. Calibrate gyro offsets before operation.
EOF

sudo -u ga git add .
sudo -u ga git commit -m "Add IMU sensor fusion and coordinate transforms"

# ==========================================
# 4. TRIGGER MERGE CONFLICT
# ==========================================
# We expect this to fail with conflicts
sudo -u ga git merge feature/pid-tuning || true

# ==========================================
# 5. CONFIGURE VS CODE
# ==========================================
# Start VS Code in the workspace
if ! pgrep -f "code.*--ms-enable-electron-run-as-node" > /dev/null; then
    echo "Starting VS Code..."
    su - ga -c "DISPLAY=:1 code $WORKSPACE_DIR &"
    sleep 5
fi

# Wait for window and maximize
for i in {1..30}; do
    WID=$(wmctrl -l | grep -i "Visual Studio Code" | awk '{print $1; exit}')
    if [ -n "$WID" ]; then
        echo "VS Code window detected"
        wmctrl -ia "$WID" 2>/dev/null
        wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="