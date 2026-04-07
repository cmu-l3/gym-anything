#!/bin/bash
set -e
echo "=== Setting up refactor_robot_kinematics task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

PROJECT_DIR="/home/ga/PycharmProjects/robot_control"
rm -rf "$PROJECT_DIR" 2>/dev/null || true
mkdir -p "$PROJECT_DIR/tests"

# Create requirements.txt
echo "numpy>=1.24.0" > "$PROJECT_DIR/requirements.txt"
echo "pytest>=7.0" >> "$PROJECT_DIR/requirements.txt"

# --- 1. Create the Monolithic robot_arm.py ---
cat > "$PROJECT_DIR/robot_arm.py" << 'PYEOF'
"""Monolithic robot arm controller — needs refactoring."""
import math
import numpy as np

class RobotArm:
    """Controls a 3-DOF planar robotic arm.
    
    This class handles everything: kinematics, trajectory planning,
    safety monitoring, and arm state management. It should be split
    into focused modules.
    """
    
    def __init__(self, link_lengths=None, joint_limits=None,
                 max_velocity=1.0, workspace_radius=None):
        self.link_lengths = link_lengths or [1.0, 0.8, 0.5]
        self.joint_limits = joint_limits or [
            (-math.pi, math.pi),
            (-math.pi/2, math.pi/2),
            (-math.pi/2, math.pi/2),
        ]
        self.max_velocity = max_velocity
        self.workspace_radius = workspace_radius or sum(self.link_lengths)
        self.current_angles = [0.0, 0.0, 0.0]
        self._error_log = []
    
    # --- Kinematics methods ---
    def forward_kinematics(self, joint_angles):
        """Calculate end-effector position (x, y, theta) from joint angles."""
        t1, t2, t3 = joint_angles
        l1, l2, l3 = self.link_lengths
        
        # Calculate sum of angles
        s1 = t1
        s2 = t1 + t2
        s3 = t1 + t2 + t3
        
        x = l1 * math.cos(s1) + l2 * math.cos(s2) + l3 * math.cos(s3)
        y = l1 * math.sin(s1) + l2 * math.sin(s2) + l3 * math.sin(s3)
        theta = s3
        
        return x, y, theta

    def inverse_kinematics(self, x, y, theta):
        """Calculate joint angles for target pose. Simplified analytical solution."""
        l1, l2, l3 = self.link_lengths
        
        # Wrist position
        wx = x - l3 * math.cos(theta)
        wy = y - l3 * math.sin(theta)
        
        # Law of cosines for first two links
        r_sq = wx**2 + wy**2
        
        # Check reachability
        if r_sq > (l1 + l2)**2 or r_sq < (l1 - l2)**2:
            raise ValueError("Target unreachable")
            
        c2 = (r_sq - l1**2 - l2**2) / (2 * l1 * l2)
        # Numerical stability clamp
        c2 = max(min(c2, 1.0), -1.0)
        t2 = math.acos(c2)  # Elbow up solution
        
        t1 = math.atan2(wy, wx) - math.atan2(l2 * math.sin(t2), l1 + l2 * math.cos(t2))
        t3 = theta - t1 - t2
        
        return [self._clamp_angle(a) for a in [t1, t2, t3]]

    def _clamp_angle(self, angle):
        """Normalize angle to [-pi, pi]."""
        return (angle + math.pi) % (2 * math.pi) - math.pi
    
    # --- Safety methods ---
    def check_joint_limits(self, joint_angles):
        """Return True if all angles are within limits."""
        for i, angle in enumerate(joint_angles):
            min_lim, max_lim = self.joint_limits[i]
            if not (min_lim <= angle <= max_lim):
                return False
        return True

    def check_velocity(self, current_angles, target_angles, dt):
        """Return True if move does not exceed max velocity."""
        if dt <= 0:
            return False
        for c, t in zip(current_angles, target_angles):
            velocity = abs(t - c) / dt
            if velocity > self.max_velocity:
                return False
        return True

    def check_workspace(self, x, y):
        """Return True if point is within workspace radius."""
        return (x**2 + y**2) <= self.workspace_radius**2

    def _validate_move_internal(self, target_angles, dt):
        """Internal helper to validate a move."""
        if not self.check_joint_limits(target_angles):
            return False, ["Joint limits exceeded"]
        if not self.check_velocity(self.current_angles, target_angles, dt):
            return False, ["Velocity limit exceeded"]
        return True, []
    
    # --- Trajectory methods ---
    def plan_linear(self, start_angles, end_angles, num_steps):
        """Plan a linear trajectory in joint space."""
        path = []
        for i in range(num_steps):
            t = i / (num_steps - 1)
            point = [self._interpolate_step(s, e, t) for s, e in zip(start_angles, end_angles)]
            path.append(point)
        return path

    def plan_via_waypoints(self, waypoints, steps_per_segment):
        """Plan trajectory through multiple waypoints."""
        full_path = []
        for i in range(len(waypoints) - 1):
            segment = self.plan_linear(waypoints[i], waypoints[i+1], steps_per_segment)
            if i > 0:
                segment = segment[1:]  # Avoid duplicate points
            full_path.extend(segment)
        return full_path

    def _interpolate_step(self, a, b, t):
        """Linear interpolation."""
        return a + (b - a) * t
    
    # --- Arm control methods ---
    def move_to(self, x, y, theta, dt=1.0):
        """Move arm to target pose."""
        if not self.check_workspace(x, y):
            print("Target outside workspace")
            return False
            
        try:
            target_angles = self.inverse_kinematics(x, y, theta)
        except ValueError as e:
            print(f"IK Failed: {e}")
            return False
            
        valid, errors = self._validate_move_internal(target_angles, dt)
        if not valid:
            self._error_log.extend(errors)
            print(f"Move invalid: {errors}")
            return False
            
        self.current_angles = target_angles
        return True

    def execute_trajectory(self, waypoints, dt=0.1):
        """Execute a list of joint angle waypoints."""
        for point in waypoints:
            valid, errors = self._validate_move_internal(point, dt)
            if not valid:
                self._error_log.extend(errors)
                return False
            self.current_angles = point
        return True

    def get_position(self):
        """Get current end-effector pose."""
        return self.forward_kinematics(self.current_angles)

    def home(self):
        """Return to home position."""
        self.current_angles = [0.0, 0.0, 0.0]

    def status(self):
        """Return dict of current status."""
        return {
            "angles": self.current_angles,
            "position": self.get_position(),
            "errors": len(self._error_log)
        }
PYEOF

# --- 2. Create the Tests ---
cat > "$PROJECT_DIR/tests/conftest.py" << 'PYEOF'
import sys
import os
# Add project root to sys.path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))
PYEOF

cat > "$PROJECT_DIR/tests/test_robot.py" << 'PYEOF'
import pytest
import math
from robot_arm import RobotArm  # This import must be changed by the agent

@pytest.fixture
def arm():
    return RobotArm()

def test_forward_kinematics_zero(arm):
    # L1=1.0, L2=0.8, L3=0.5. Angles 0,0,0 -> x = 1+0.8+0.5 = 2.3
    x, y, t = arm.forward_kinematics([0, 0, 0])
    assert x == pytest.approx(2.3)
    assert y == pytest.approx(0.0)
    assert t == pytest.approx(0.0)

def test_forward_kinematics_90deg(arm):
    # t1=pi/2 -> Arm points up Y axis
    x, y, t = arm.forward_kinematics([math.pi/2, 0, 0])
    assert x == pytest.approx(0.0, abs=1e-10)
    assert y == pytest.approx(2.3)

def test_inverse_kinematics_reachable(arm):
    target = [0.5, 0.5, 0.5]
    x, y, t = arm.forward_kinematics(target)
    calculated_angles = arm.inverse_kinematics(x, y, t)
    # Check round trip
    x2, y2, t2 = arm.forward_kinematics(calculated_angles)
    assert x2 == pytest.approx(x)
    assert y2 == pytest.approx(y)
    assert t2 == pytest.approx(t)

def test_inverse_kinematics_unreachable(arm):
    with pytest.raises(ValueError):
        arm.inverse_kinematics(5.0, 5.0, 0)

def test_joint_limits_valid(arm):
    assert arm.check_joint_limits([0, 0, 0]) is True

def test_joint_limits_exceeded(arm):
    assert arm.check_joint_limits([4.0, 0, 0]) is False  # Limit is pi (3.14)

def test_check_workspace_inside(arm):
    assert arm.check_workspace(1.0, 0.5) is True

def test_check_workspace_outside(arm):
    assert arm.check_workspace(5.0, 5.0) is True  # Fails check logic? No, wait.
    # Logic: x^2 + y^2 <= radius^2 (2.3^2 = 5.29). 5,5 is 25+25=50.
    assert arm.check_workspace(5.0, 5.0) is False

def test_velocity_check(arm):
    current = [0, 0, 0]
    target = [0.1, 0, 0]
    dt = 1.0
    assert arm.check_velocity(current, target, dt) is True
    
    # Velocity > 1.0 (limit)
    target_fast = [2.0, 0, 0]
    assert arm.check_velocity(current, target_fast, dt) is False

def test_plan_linear_trajectory(arm):
    path = arm.plan_linear([0,0,0], [1,1,1], 5)
    assert len(path) == 5
    assert path[0] == [0,0,0]
    assert path[-1] == [1,1,1]

def test_move_to_updates_position(arm):
    # Move to x=2.3, y=0 (home)
    assert arm.move_to(2.3, 0.0, 0.0) is True
    assert arm.current_angles == pytest.approx([0,0,0], abs=1e-5)

def test_home_resets_position(arm):
    arm.current_angles = [1, 1, 1]
    arm.home()
    assert arm.current_angles == [0.0, 0.0, 0.0]
PYEOF

# --- 3. Setup Environment ---
echo "Installing dependencies..."
pip3 install -q numpy pytest

# Record start time
date +%s > /tmp/task_start_time.txt

# Verify initial tests pass (sanity check)
echo "Running baseline tests..."
cd "$PROJECT_DIR"
if python3 -m pytest tests/; then
    echo "Baseline tests passed."
else
    echo "ERROR: Baseline tests failed. Task setup is broken."
    exit 1
fi

# Set permissions
chown -R ga:ga "$PROJECT_DIR"

# Launch PyCharm with the project
setup_pycharm_project "$PROJECT_DIR" "robot_control" 180

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="