#!/bin/bash
set -e

echo "=== Setting up Robotic Arm Controller Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

WORKSPACE_DIR="/home/ga/workspace/robotic_arm_sim"
sudo -u ga mkdir -p "$WORKSPACE_DIR/controller"
sudo -u ga mkdir -p "$WORKSPACE_DIR/sensors"
sudo -u ga mkdir -p "$WORKSPACE_DIR/kinematics"
sudo -u ga mkdir -p "$WORKSPACE_DIR/safety"
sudo -u ga mkdir -p "$WORKSPACE_DIR/tests"

# 1. Controller: PID (BUG: derivative kick)
cat > "$WORKSPACE_DIR/controller/pid.py" << 'EOF'
class PIDController:
    def __init__(self, kp, ki, kd):
        self.kp = kp
        self.ki = ki
        self.kd = kd
        self.prev_error = 0.0
        self.prev_pv = 0.0
        self.integral = 0.0

    def compute(self, setpoint, pv, dt):
        error = setpoint - pv
        self.integral += error * dt
        
        # Calculate derivative
        derivative = (error - self.prev_error) / dt
        
        output = self.kp * error + self.ki * self.integral + self.kd * derivative
        
        self.prev_error = error
        self.prev_pv = pv
        return output
EOF

# 2. Sensors: Filter (BUG: inverted alpha)
cat > "$WORKSPACE_DIR/sensors/filter.py" << 'EOF'
class EMAFilter:
    def __init__(self, alpha=0.05):
        self.alpha = alpha
        self.value = None

    def update(self, raw_value):
        if self.value is None:
            self.value = raw_value
            return self.value
            
        # Update exponential moving average
        self.value = (1 - self.alpha) * raw_value + self.alpha * self.value
        return self.value
EOF

# 3. Kinematics: Inverse (BUG: swapped atan2)
cat > "$WORKSPACE_DIR/kinematics/inverse.py" << 'EOF'
import math

def solve_2dof(x, y, l1, l2):
    """Solve inverse kinematics for 2-link planar arm."""
    # Cosine rule for theta2
    cos_q2 = (x**2 + y**2 - l1**2 - l2**2) / (2 * l1 * l2)
    cos_q2 = max(-1.0, min(1.0, cos_q2))
    q2 = math.acos(cos_q2)

    # Solve for theta1
    k1 = l1 + l2 * math.cos(q2)
    k2 = l2 * math.sin(q2)
    
    q1 = math.atan2(x, y) - math.atan2(k2, k1)
    
    return q1, q2
EOF

# 4. Controller: Trajectory Planner (BUG: missing 2.0 divisor causing overshoot)
cat > "$WORKSPACE_DIR/controller/trajectory_planner.py" << 'EOF'
class TrapezoidalPlanner:
    def __init__(self, vmax, amax):
        self.vmax = vmax
        self.amax = amax
        self.current_v = 0.0

    def step(self, current_pos, target_pos, dt):
        dist = target_pos - current_pos
        direction = 1.0 if dist > 0 else -1.0
        abs_dist = abs(dist)

        # Calculate stopping distance required at current velocity
        decel_dist = (self.current_v ** 2) / self.amax
        
        if abs_dist > decel_dist:
            # Accelerate
            self.current_v += self.amax * dt
            if self.current_v > self.vmax:
                self.current_v = self.vmax
        else:
            # Decelerate
            self.current_v -= self.amax * dt
            if self.current_v < 0:
                self.current_v = 0.0

        return self.current_v * direction
EOF

# 5. Safety: Limits (BUG: applied after position update)
cat > "$WORKSPACE_DIR/safety/limits.py" << 'EOF'
class SafetyMonitor:
    def __init__(self, pos_limit, vel_limit):
        self.pos_limit = pos_limit
        self.vel_limit = vel_limit

    def enforce(self, current_pos, commanded_vel, dt):
        # Update position
        new_pos = current_pos + commanded_vel * dt
        
        # Enforce velocity limits
        if abs(commanded_vel) > self.vel_limit:
            commanded_vel = self.vel_limit if commanded_vel > 0 else -self.vel_limit
            
        # Enforce position limits
        if abs(new_pos) > self.pos_limit:
            new_pos = self.pos_limit if new_pos > 0 else -self.pos_limit
            commanded_vel = 0.0
            
        return new_pos, commanded_vel
EOF

# Create Tests
cat > "$WORKSPACE_DIR/tests/test_pid.py" << 'EOF'
import pytest
from controller.pid import PIDController

def test_no_derivative_kick():
    pid = PIDController(1.0, 0.0, 1.0)
    pid.compute(0.0, 0.0, 0.1)
    # Setpoint step change
    out = pid.compute(10.0, 0.0, 0.1)
    assert out <= 15.0, f"Derivative kick detected! Output spiked to {out}"
EOF

cat > "$WORKSPACE_DIR/tests/test_filter.py" << 'EOF'
import pytest
import math
from sensors.filter import EMAFilter

def test_noise_attenuation():
    f = EMAFilter(alpha=0.1)
    outputs = []
    for i in range(100):
        noise = math.sin(i * 10) * 5.0
        outputs.append(f.update(10.0 + noise))
    variance = sum((x - 10.0)**2 for x in outputs[-20:]) / 20
    assert variance < 2.0, f"Filter failed to attenuate noise, variance: {variance}"
EOF

cat > "$WORKSPACE_DIR/tests/test_kinematics.py" << 'EOF'
import pytest
import math
from kinematics.inverse import solve_2dof

def test_known_positions():
    q1, q2 = solve_2dof(0.0, 2.0, 1.0, 1.0)
    assert math.isclose(q1, math.pi/2, abs_tol=1e-3), f"Incorrect theta1: {q1}"
EOF

cat > "$WORKSPACE_DIR/tests/test_trajectory.py" << 'EOF'
import pytest
from controller.trajectory_planner import TrapezoidalPlanner

def test_endpoint_accuracy():
    planner = TrapezoidalPlanner(vmax=2.0, amax=1.0)
    pos = 0.0
    target = 4.0
    for _ in range(100):
        vel = planner.step(pos, target, 0.1)
        pos += vel * 0.1
    assert abs(pos - target) < 0.05, f"Planner overshot, final pos: {pos}"
EOF

cat > "$WORKSPACE_DIR/tests/test_safety.py" << 'EOF'
import pytest
from safety.limits import SafetyMonitor

def test_velocity_precheck():
    monitor = SafetyMonitor(pos_limit=10.0, vel_limit=5.0)
    new_pos, vel = monitor.enforce(current_pos=0.0, commanded_vel=100.0, dt=0.1)
    assert abs(new_pos) <= 0.51, f"Position jumped dangerously to {new_pos}"
EOF

chown -R ga:ga "$WORKSPACE_DIR"

# Ensure pytest is installed
pip3 install pytest > /dev/null 2>&1

# Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Start VS Code
if ! pgrep -f "code" > /dev/null; then
    su - ga -c "DISPLAY=:1 code --new-window $WORKSPACE_DIR &"
    sleep 5
fi

# Wait and maximize
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Visual Studio Code"; then
        DISPLAY=:1 wmctrl -r "Visual Studio Code" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        DISPLAY=:1 wmctrl -a "Visual Studio Code" 2>/dev/null || true
        break
    fi
    sleep 1
done

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="