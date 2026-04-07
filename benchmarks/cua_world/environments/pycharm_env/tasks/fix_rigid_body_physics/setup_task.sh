#!/bin/bash
echo "=== Setting up fix_rigid_body_physics task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

PROJECT_DIR="/home/ga/PycharmProjects/box_sim"

# Clean previous runs
rm -rf "$PROJECT_DIR" 2>/dev/null || true
rm -f /tmp/fix_physics_start_ts /tmp/fix_physics_result.json 2>/dev/null || true

# Create project structure
mkdir -p "$PROJECT_DIR/engine"
mkdir -p "$PROJECT_DIR/tests"

# Create requirements.txt
cat > "$PROJECT_DIR/requirements.txt" << 'EOF'
pytest>=7.0
numpy>=1.24.0
EOF

# --- engine/__init__.py ---
touch "$PROJECT_DIR/engine/__init__.py"

# --- engine/vectors.py (CORRECT) ---
cat > "$PROJECT_DIR/engine/vectors.py" << 'EOF'
"""Vector math utilities."""
import math

class Vec2:
    def __init__(self, x, y):
        self.x = float(x)
        self.y = float(y)

    def __add__(self, other):
        return Vec2(self.x + other.x, self.y + other.y)

    def __sub__(self, other):
        return Vec2(self.x - other.x, self.y - other.y)

    def __mul__(self, scalar):
        return Vec2(self.x * scalar, self.y * scalar)
    
    def __rmul__(self, scalar):
        return self.__mul__(scalar)

    def dot(self, other):
        return self.x * other.x + self.y * other.y

    def length_squared(self):
        return self.x**2 + self.y**2

    def length(self):
        return math.sqrt(self.length_squared())

    def normalize(self):
        l = self.length()
        if l > 0:
            return Vec2(self.x / l, self.y / l)
        return Vec2(0, 0)

    def __repr__(self):
        return f"Vec2({self.x:.2f}, {self.y:.2f})"
EOF

# --- engine/body.py (BUG 1: Integration) ---
cat > "$PROJECT_DIR/engine/body.py" << 'EOF'
"""Rigid body definition and integration."""
from engine.vectors import Vec2

class RigidBody:
    def __init__(self, x, y, mass, restitution=0.5):
        self.position = Vec2(x, y)
        self.velocity = Vec2(0, 0)
        self.force = Vec2(0, 0)
        self.mass = float(mass)
        self.restitution = restitution  # Bounciness (0=sticky, 1=elastic)
        
        if self.mass == 0:
            self.inv_mass = 0.0
        else:
            self.inv_mass = 1.0 / self.mass

    def apply_force(self, force: Vec2):
        self.force = self.force + force

    def integrate(self, dt: float):
        """Update position and velocity using Semi-Implicit Euler integration."""
        if self.mass == 0:
            return

        # Acceleration = Force / Mass
        acceleration = self.force * self.inv_mass
        
        # Update Velocity
        self.velocity = self.velocity + acceleration * dt
        
        # Update Position
        # BUG 1: Missing multiplication by dt!
        # Objects will move way too fast/far per frame.
        self.position = self.position + self.velocity
        
        # Reset forces
        self.force = Vec2(0, 0)
EOF

# --- engine/solver.py (BUG 2: Impulse, BUG 3: Correction) ---
cat > "$PROJECT_DIR/engine/solver.py" << 'EOF'
"""Collision resolution solver."""
from engine.vectors import Vec2
from engine.body import RigidBody

def resolve_collision(a: RigidBody, b: RigidBody, normal: Vec2):
    """
    Resolve velocity for a collision between two bodies along a normal.
    Uses impulse-based resolution.
    """
    # Relative velocity
    rv = b.velocity - a.velocity
    
    # Velocity along the normal
    vel_along_normal = rv.dot(normal)
    
    # Do not resolve if velocities are separating
    if vel_along_normal > 0:
        return

    # Calculate restitution (min of both bodies)
    e = min(a.restitution, b.restitution)
    
    # Calculate impulse scalar
    j = -(1 + e) * vel_along_normal
    
    # BUG 2: Incorrect denominator logic.
    # Impulse formula requires sum of INVERSE masses (1/ma + 1/mb).
    # This uses sum of raw masses, which breaks physics for objects of different weights.
    j = j / (a.mass + b.mass)
    
    # Apply impulse
    impulse = normal * j
    
    # Apply velocity change
    a.velocity = a.velocity - impulse * a.inv_mass
    b.velocity = b.velocity + impulse * b.inv_mass


def positional_correction(a: RigidBody, b: RigidBody, normal: Vec2, penetration: float):
    """
    Prevent objects from sinking into each other (Linear Projection).
    """
    percent = 0.2  # Penetration percentage to correct
    slop = 0.01    # Penetration allowance
    
    if penetration < slop:
        return
        
    # Calculate correction vector magnitude
    # We use inv_mass to push lighter objects more than heavy ones
    total_inv_mass = a.inv_mass + b.inv_mass
    if total_inv_mass == 0:
        return
        
    magnitude = (max(penetration - slop, 0.0) / total_inv_mass) * percent
    correction = normal * magnitude
    
    # BUG 3: Swapped signs in positional correction.
    # Instead of pushing bodies APART, this pulls them TOGETHER (or pushes wrong way).
    # Since 'normal' points from A to B (usually), A should move -correction, B should move +correction.
    a.position = a.position + correction * a.inv_mass
    b.position = b.position - correction * b.inv_mass
EOF

# --- tests/test_physics.py ---
cat > "$PROJECT_DIR/tests/test_physics.py" << 'EOF'
import pytest
import math
from engine.vectors import Vec2
from engine.body import RigidBody
from engine.solver import resolve_collision, positional_correction

def test_integration_moves_correct_distance():
    """Verify integration uses dt correctly."""
    body = RigidBody(0, 0, mass=10)
    body.velocity = Vec2(100, 0)
    dt = 0.1
    
    body.integrate(dt)
    
    # Expected: 0 + 100 * 0.1 = 10.0
    # Buggy: 0 + 100 = 100.0
    assert abs(body.position.x - 10.0) < 0.001, \
        f"Integration failed. Expected pos x=10.0, got {body.position.x}. Did you forget * dt?"

def test_elastic_collision_equal_mass():
    """Verify perfectly elastic collision swaps velocities for equal mass."""
    # Head on collision
    a = RigidBody(0, 0, mass=10, restitution=1.0)
    b = RigidBody(10, 0, mass=10, restitution=1.0)
    
    a.velocity = Vec2(10, 0)
    b.velocity = Vec2(-10, 0)
    
    # Normal points from A to B
    normal = Vec2(1, 0)
    
    resolve_collision(a, b, normal)
    
    # Should swap velocities
    assert abs(a.velocity.x - (-10)) < 0.001
    assert abs(b.velocity.x - 10) < 0.001

def test_collision_heavy_vs_light():
    """Verify impulse handles mass correctly (Bug 2 check)."""
    # Heavy object hitting stationary light object
    # m1 = 100, v1 = 10
    # m2 = 1,   v2 = 0
    # e = 1.0
    # If formula uses (m1+m2) in denominator, impulse is tiny.
    # If formula uses (1/m1 + 1/m2) in denominator, impulse is large.
    
    heavy = RigidBody(0, 0, mass=100, restitution=1.0)
    light = RigidBody(10, 0, mass=1, restitution=1.0)
    
    heavy.velocity = Vec2(10, 0)
    light.velocity = Vec2(0, 0)
    normal = Vec2(1, 0)
    
    resolve_collision(heavy, light, normal)
    
    # With correct physics:
    # v1' ≈ 9.8 (continues forward)
    # v2' ≈ 19.8 (shoots forward fast)
    # With Bug 2 (sum of masses):
    # j = -2 * -10 / 101 ≈ 0.2
    # v2' = 0 + 0.2 * 1 = 0.2 (light object barely moves)
    
    assert light.velocity.x > 15.0, \
        f"Light object didn't bounce fast enough ({light.velocity.x}). Check impulse denominator."

def test_positional_correction_separation():
    """Verify objects are pushed APART, not together (Bug 3 check)."""
    # A at 0, B at 0.5. Radius implies they overlap.
    # Normal A->B is (1, 0)
    a = RigidBody(0, 0, mass=10)
    b = RigidBody(0.5, 0, mass=10)
    
    normal = Vec2(1, 0)
    penetration = 0.5
    
    start_dist = (b.position - a.position).length()
    
    positional_correction(a, b, normal, penetration)
    
    end_dist = (b.position - a.position).length()
    
    assert end_dist > start_dist, \
        "Objects moved closer together! Positional correction signs are likely swapped."

def test_energy_conservation():
    """Verify system energy doesn't explode."""
    # Two balls bouncing
    a = RigidBody(0, 0, mass=2, restitution=1.0)
    b = RigidBody(5, 0, mass=2, restitution=1.0)
    a.velocity = Vec2(5, 0)
    b.velocity = Vec2(-5, 0)
    
    initial_ke = 0.5 * a.mass * a.velocity.length_squared() + \
                 0.5 * b.mass * b.velocity.length_squared()
                 
    resolve_collision(a, b, Vec2(1, 0))
    
    final_ke = 0.5 * a.mass * a.velocity.length_squared() + \
               0.5 * b.mass * b.velocity.length_squared()
               
    # Allow tiny float error
    assert abs(final_ke - initial_ke) < 0.1, "Energy was created or destroyed significantly during elastic collision."
EOF

# --- demo.py ---
cat > "$PROJECT_DIR/demo.py" << 'EOF'
"""
Simple visual demo script (runs in terminal output).
Simulates a ball bouncing on floor.
"""
from engine.body import RigidBody
from engine.vectors import Vec2
from engine.solver import resolve_collision, positional_correction
import time

def run_sim():
    ball = RigidBody(0, 10, mass=5, restitution=0.8)
    floor = RigidBody(0, 0, mass=0) # Infinite mass (static)
    
    dt = 0.016 # 60 FPS
    
    print("Simulating ball drop (y position):")
    for i in range(20):
        # Gravity
        ball.apply_force(Vec2(0, -9.81 * ball.mass))
        ball.integrate(dt)
        
        # Simple floor collision check
        if ball.position.y < 0:
            normal = Vec2(0, 1)
            penetration = -ball.position.y
            resolve_collision(floor, ball, normal)
            positional_correction(floor, ball, normal, penetration)
            
        print(f"Frame {i}: y={ball.position.y:.2f} v={ball.velocity.y:.2f}")

if __name__ == "__main__":
    run_sim()
EOF

# Record start time
date +%s > /tmp/fix_physics_start_ts

# Setup PyCharm project
su - ga -c "mkdir -p /home/ga/.config/JetBrains/PyCharmCE2023.3/options" 2>/dev/null || true

# Wait for PyCharm (standard pattern)
source /workspace/scripts/task_utils.sh 2>/dev/null || true
if ! pgrep -f "pycharm" > /dev/null; then
    echo "Starting PyCharm..."
    su - ga -c "DISPLAY=:1 /opt/pycharm/bin/pycharm.sh '$PROJECT_DIR' > /tmp/pycharm_log.txt 2>&1 &"
    wait_for_pycharm 60
    focus_pycharm_window
fi

# Take initial screenshot
take_screenshot /tmp/fix_physics_initial.png

echo "=== Setup complete ==="