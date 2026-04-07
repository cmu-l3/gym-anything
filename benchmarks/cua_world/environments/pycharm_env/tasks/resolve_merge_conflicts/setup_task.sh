#!/bin/bash
echo "=== Setting up resolve_merge_conflicts task ==="

source /workspace/scripts/task_utils.sh

# Configuration
PROJECT_DIR="/home/ga/PycharmProjects/motor_control"
TASK_START_FILE="/tmp/task_start_time.txt"

# Record start time
date +%s > "$TASK_START_FILE" 2>/dev/null || true

# Clean previous run
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR/control"
mkdir -p "$PROJECT_DIR/tests"

# Configure git for ga user
su - ga -c "git config --global user.email 'ga@example.com'"
su - ga -c "git config --global user.name 'Ga Agent'"
su - ga -c "git config --global init.defaultBranch main"

# Helper: run git commands in the project dir as user ga
git_in_project() {
    su - ga -c "cd '$PROJECT_DIR' && git $*"
}

# ==============================================================================
# 1. CREATE BASE STATE (Common ancestor)
# ==============================================================================
cat > "$PROJECT_DIR/requirements.txt" << EOF
pytest
numpy
EOF

cat > "$PROJECT_DIR/control/__init__.py" << EOF
# Motor control package
EOF

# Base PID
cat > "$PROJECT_DIR/control/pid.py" << 'EOF'
class PIDController:
    def __init__(self, kp, ki, kd):
        self.kp = kp
        self.ki = ki
        self.kd = kd
        self._integral = 0
        self._prev_error = 0

    def compute(self, setpoint, measured, dt):
        error = setpoint - measured
        self._integral += error * dt
        derivative = (error - self._prev_error) / dt
        
        output = (self.kp * error) + (self.ki * self._integral) + (self.kd * derivative)
        
        self._prev_error = error
        return output
EOF

# Base Motor Driver
cat > "$PROJECT_DIR/control/motor_driver.py" << 'EOF'
class MotorDriver:
    def __init__(self, max_speed=100):
        self.max_speed = max_speed
        self._current = 0

    def set_speed(self, speed):
        # Basic direct setting
        self._current = speed
        return self._current
EOF

# Base Filters
cat > "$PROJECT_DIR/control/filters.py" << 'EOF'
def low_pass_filter(data, alpha):
    """Simple IIR filter: y[n] = alpha*x[n] + (1-alpha)*y[n-1]"""
    result = []
    prev = data[0]
    for x in data:
        y = alpha * x + (1 - alpha) * prev
        result.append(y)
        prev = y
    return result
EOF

# Initialize Git
chown -R ga:ga "$PROJECT_DIR"
git_in_project init
git_in_project add .
git_in_project "commit -m 'Initial commit: Base control library'"

# ==============================================================================
# 2. CREATE FEATURE BRANCH (adaptive-control)
# ==============================================================================
git_in_project "checkout -b feature/adaptive-control"

# Feature: Adaptive PID (adds adaptive_rate and error_history)
cat > "$PROJECT_DIR/control/pid.py" << 'EOF'
from collections import deque

class PIDController:
    def __init__(self, kp, ki, kd, adaptive_rate=0.01):
        self.kp = kp
        self.ki = ki
        self.kd = kd
        self.adaptive_rate = adaptive_rate
        self.error_history = deque(maxlen=50)
        self._integral = 0
        self._prev_error = 0

    def compute(self, setpoint, measured, dt):
        error = setpoint - measured
        self.error_history.append(abs(error))
        
        self._integral += error * dt
        derivative = (error - self._prev_error) / dt
        
        # Adaptive scaling based on error history
        scale = 1.0
        if len(self.error_history) > 10:
            avg_err = sum(self.error_history) / len(self.error_history)
            scale = 1.0 + (avg_err * self.adaptive_rate)
            
        output = scale * ((self.kp * error) + (self.ki * self._integral) + (self.kd * derivative))
        
        self._prev_error = error
        return output
EOF

# Feature: Ramp Rate Limiting in Motor Driver
cat > "$PROJECT_DIR/control/motor_driver.py" << 'EOF'
class MotorDriver:
    def __init__(self, max_speed=100, ramp_rate=5):
        self.max_speed = max_speed
        self.ramp_rate = ramp_rate
        self._current = 0

    def set_speed(self, speed):
        # Apply ramp rate limiting
        delta = speed - self._current
        if delta > self.ramp_rate:
            delta = self.ramp_rate
        elif delta < -self.ramp_rate:
            delta = -self.ramp_rate
            
        self._current += delta
        return self._current
EOF

# Feature: Rename filters and add moving average
cat > "$PROJECT_DIR/control/filters.py" << 'EOF'
def exponential_filter(data, alpha):
    """Renamed from low_pass_filter for clarity"""
    result = []
    prev = data[0] if data else 0
    for x in data:
        y = alpha * x + (1 - alpha) * prev
        result.append(y)
        prev = y
    return result

def moving_average_filter(data, window_size):
    """Simple moving average"""
    result = []
    for i in range(len(data)):
        start = max(0, i - window_size + 1)
        window = data[start:i+1]
        result.append(sum(window) / len(window))
    return result
EOF

chown -R ga:ga "$PROJECT_DIR"
git_in_project add .
git_in_project "commit -m 'Add adaptive features, ramp limiting, and new filters'"

# ==============================================================================
# 3. UPDATE MAIN BRANCH (Divergent changes)
# ==============================================================================
git_in_project "checkout main"

# Main update: Integral windup clamp in PID
cat > "$PROJECT_DIR/control/pid.py" << 'EOF'
class PIDController:
    def __init__(self, kp, ki, kd, integral_clamp=100):
        self.kp = kp
        self.ki = ki
        self.kd = kd
        self.integral_clamp = integral_clamp
        self._integral = 0
        self._prev_error = 0

    def compute(self, setpoint, measured, dt):
        error = setpoint - measured
        
        # Integral with clamp
        self._integral += error * dt
        self._integral = max(-self.integral_clamp, min(self.integral_clamp, self._integral))
        
        derivative = (error - self._prev_error) / dt
        
        output = (self.kp * error) + (self.ki * self._integral) + (self.kd * derivative)
        
        self._prev_error = error
        return output
EOF

# Main update: Absolute safety clamp in Motor Driver
cat > "$PROJECT_DIR/control/motor_driver.py" << 'EOF'
class MotorDriver:
    def __init__(self, max_speed=100):
        self.max_speed = max_speed
        self._current = 0

    def set_speed(self, speed):
        # Safety clamp
        speed = max(-self.max_speed, min(self.max_speed, speed))
        
        self._current = speed
        return self._current
EOF

# Main update: Just a docstring change in filters (keeps old name)
cat > "$PROJECT_DIR/control/filters.py" << 'EOF'
def low_pass_filter(data, alpha):
    """
    Standard single-pole IIR low pass filter.
    y[n] = alpha*x[n] + (1-alpha)*y[n-1]
    """
    result = []
    prev = data[0]
    for x in data:
        y = alpha * x + (1 - alpha) * prev
        result.append(y)
        prev = y
    return result
EOF

chown -R ga:ga "$PROJECT_DIR"
git_in_project add .
git_in_project "commit -m 'Add integral clamp and safety limits'"

# ==============================================================================
# 4. SETUP TESTS (These expect the MERGED behavior)
# ==============================================================================

# Test PID: Expects BOTH adaptive scaling AND integral clamp
cat > "$PROJECT_DIR/tests/test_pid.py" << 'EOF'
import pytest
from control.pid import PIDController

def test_pid_initialization():
    # Should accept both new params (adaptive_rate) and old params (integral_clamp)
    # The merged constructor signature is flexible, but attributes must exist
    pid = PIDController(1.0, 0.1, 0.01, adaptive_rate=0.5, integral_clamp=50)
    assert pid.adaptive_rate == 0.5
    assert pid.integral_clamp == 50
    assert hasattr(pid, 'error_history')

def test_integral_clamp():
    # From main branch
    pid = PIDController(0, 1.0, 0, integral_clamp=10)
    # Large error over time to force integral buildup
    pid.compute(100, 0, 1.0) # Integral = 100 -> clamped to 10
    
    # Access private integral to verify clamp (implementation detail, but acceptable for this task)
    assert -10.1 <= pid._integral <= 10.1

def test_adaptive_scaling():
    # From feature branch
    pid = PIDController(1.0, 0, 0, adaptive_rate=1.0)
    # Feed errors to build history
    for _ in range(20):
        pid.compute(10, 0, 1.0) # Error 10
    
    # Base P-term would be 1.0 * 10 = 10
    # Avg error = 10. Scale = 1 + (10 * 1.0) = 11
    # Output should be 11 * 10 = 110
    output = pid.compute(10, 0, 1.0)
    assert output > 100 # Verify scaling is active (exact value depends on exact impl details)

def test_combined_behavior():
    # Both working together
    pid = PIDController(1.0, 1.0, 0, adaptive_rate=0.0, integral_clamp=5)
    output = pid.compute(100, 0, 1.0)
    # Integral clamped to 5
    # P-term = 100
    # Scale = 1.0
    # Output = 1.0 * (100 + 5) = 105
    assert 104 < output < 106

def test_error_history_limit():
    pid = PIDController(1,1,1)
    for i in range(100):
        pid.compute(i, 0, 1)
    assert len(pid.error_history) == 50
EOF

# Test Motor: Expects Ramp THEN Clamp
cat > "$PROJECT_DIR/tests/test_motor_driver.py" << 'EOF'
import pytest
from control.motor_driver import MotorDriver

def test_initialization():
    # Expects merged attributes
    driver = MotorDriver(max_speed=100, ramp_rate=10)
    assert driver.max_speed == 100
    assert driver.ramp_rate == 10

def test_ramp_limiting():
    # Feature branch logic
    driver = MotorDriver(max_speed=100, ramp_rate=5)
    speed = driver.set_speed(50) # From 0 to 50
    assert speed == 5
    speed = driver.set_speed(50) # From 5 to 50
    assert speed == 10

def test_safety_clamp():
    # Main branch logic
    driver = MotorDriver(max_speed=20, ramp_rate=100) # High ramp to ignore it
    speed = driver.set_speed(50)
    assert speed == 20

def test_combined_ramp_and_clamp():
    # Critical: ramp applies to delta, then result clamped
    driver = MotorDriver(max_speed=12, ramp_rate=5)
    # 0 -> 5 (ramp ok)
    assert driver.set_speed(100) == 5
    # 5 -> 10 (ramp ok)
    assert driver.set_speed(100) == 10
    # 10 -> 15 (ramp would allow 15, but clamp limits to 12)
    assert driver.set_speed(100) == 12
EOF

# Test Filters: Expects new names
cat > "$PROJECT_DIR/tests/test_filters.py" << 'EOF'
import pytest
from control import filters

def test_exponential_filter_exists():
    # Should be renamed from low_pass_filter
    assert hasattr(filters, 'exponential_filter')
    assert not hasattr(filters, 'low_pass_filter')

def test_exponential_filter_logic():
    data = [0, 10, 10, 10]
    # y[0] = 0.5*0 + 0.5*0 = 0
    # y[1] = 0.5*10 + 0.5*0 = 5
    # y[2] = 0.5*10 + 0.5*5 = 7.5
    result = filters.exponential_filter(data, 0.5)
    assert result == [0, 5, 7.5, 8.75]

def test_moving_average_exists():
    data = [1, 2, 3, 4, 5]
    res = filters.moving_average_filter(data, 3)
    # [1, 1.5, 2, 3, 4] roughly
    assert len(res) == 5
    assert res[-1] == 4.0
EOF

# Checksum the tests to ensure agent doesn't modify them
cd "$PROJECT_DIR/tests"
md5sum *.py > /tmp/tests_checksum.md5

# ==============================================================================
# 5. TRIGGER CONFLICTS
# ==============================================================================
cd "$PROJECT_DIR"
# Attempt merge - this WILL fail and leave repo in conflicted state
git_in_project "merge feature/adaptive-control" || true

# Verify we are in a conflicted state
if ! grep -q "<<<<<<<" "$PROJECT_DIR/control/pid.py"; then
    echo "ERROR: Setup failed to generate conflicts in pid.py"
    echo "Git status:"
    git_in_project status
    exit 1
fi

echo "Repo is now in conflicted state (as expected)."

# ==============================================================================
# 6. LAUNCH ENVIRONMENT
# ==============================================================================
# Open PyCharm with the project
wait_for_pycharm 60 || echo "PyCharm took too long, proceeding..."
setup_pycharm_project "$PROJECT_DIR" "motor_control" 60

# Take setup screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="