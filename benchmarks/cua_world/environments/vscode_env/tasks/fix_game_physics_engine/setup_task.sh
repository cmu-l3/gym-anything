#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up Game Physics Engine Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

WORKSPACE_DIR="/home/ga/workspace/physics_engine"
sudo -u ga mkdir -p "$WORKSPACE_DIR/engine"
sudo -u ga mkdir -p "$WORKSPACE_DIR/tests"

# ──────────────────────────────────────────────────────────
# 1. Generate engine/vector2d.py (BUG: negated cross product)
# ──────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/engine/vector2d.py" << 'EOF'
import math

class Vector2D:
    def __init__(self, x=0.0, y=0.0):
        self.x = float(x)
        self.y = float(y)

    def __add__(self, other):
        return Vector2D(self.x + other.x, self.y + other.y)

    def __sub__(self, other):
        return Vector2D(self.x - other.x, self.y - other.y)

    def __mul__(self, scalar):
        return Vector2D(self.x * scalar, self.y * scalar)

    def dot(self, other):
        return self.x * other.x + self.y * other.y

    def cross(self, other):
        """Returns the scalar Z-component of the 2D cross product."""
        # BUG: The sign is negated here, which causes collision normals to invert.
        return -(self.x * other.y - self.y * other.x)
EOF

# ──────────────────────────────────────────────────────────
# 2. Generate engine/rigid_body.py (BUG: missing squares in inertia)
# ──────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/engine/rigid_body.py" << 'EOF'
from engine.vector2d import Vector2D

class RigidBody:
    def __init__(self, mass, width, height):
        self.mass = float(mass)
        self.width = float(width)
        self.height = float(height)

        self.position = Vector2D()
        self.velocity = Vector2D()
        self.force = Vector2D()

        self.rotation = 0.0
        self.angular_velocity = 0.0
        self.torque = 0.0

        self.restitution = 1.0  # Default to perfectly elastic for tests

        if self.mass > 0:
            self.inv_mass = 1.0 / self.mass
            # BUG: Rectangle moment of inertia should be mass * (width^2 + height^2) / 12
            self.inertia = self.mass * (self.width + self.height) / 12.0
            self.inv_inertia = 1.0 / self.inertia
        else:
            self.inv_mass = 0.0
            self.inertia = 0.0
            self.inv_inertia = 0.0
EOF

# ──────────────────────────────────────────────────────────
# 3. Generate engine/integrator.py (BUG: explicit Euler instead of semi-implicit)
# ──────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/engine/integrator.py" << 'EOF'
def integrate(body, dt):
    """Integrates forces and velocities to update body position."""
    if body.inv_mass <= 0:
        return

    # BUG: Explicit Euler updates position before velocity. 
    # For physics stability, it must be Semi-Implicit Euler (velocity updated first).
    body.position.x += body.velocity.x * dt
    body.position.y += body.velocity.y * dt

    body.velocity.x += (body.force.x * body.inv_mass) * dt
    body.velocity.y += (body.force.y * body.inv_mass) * dt

    body.rotation += body.angular_velocity * dt
    body.angular_velocity += (body.torque * body.inv_inertia) * dt

    # Clear forces for next frame
    body.force.x = 0.0
    body.force.y = 0.0
    body.torque = 0.0
EOF

# ──────────────────────────────────────────────────────────
# 4. Generate engine/collision.py (BUG: strict inequalities)
# ──────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/engine/collision.py" << 'EOF'
def aabb_intersect(a_min, a_max, b_min, b_max):
    """
    Axis-Aligned Bounding Box (AABB) intersection test.
    Returns True if the two boxes overlap.
    """
    # BUG: Strict inequalities (>) fail to detect resting/touching boundaries.
    if (a_max.x > b_min.x and a_min.x < b_max.x and
        a_max.y > b_min.y and a_min.y < b_max.y):
        return True

    return False
EOF

# ──────────────────────────────────────────────────────────
# 5. Generate engine/resolver.py (BUG: inverse mass sum)
# ──────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/engine/resolver.py" << 'EOF'
def resolve_collision(body_a, body_b, normal):
    """
    Impulse-based collision resolution.
    Applies impulses to prevent objects from penetrating.
    """
    rel_vel = body_b.velocity - body_a.velocity
    vel_along_normal = rel_vel.dot(normal)

    # Do not resolve if velocities are separating
    if vel_along_normal > 0:
        return

    e = min(body_a.restitution, body_b.restitution)
    j = -(1.0 + e) * vel_along_normal

    # BUG: Incorrect reduced mass calculation.
    # Impulse formula denominator should be the sum of inverse masses: (1/m1 + 1/m2)
    inv_mass_sum = 1.0 / (body_a.mass + body_b.mass)

    if inv_mass_sum == 0:
        return

    j /= inv_mass_sum
    impulse = normal * j

    body_a.velocity.x -= impulse.x * body_a.inv_mass
    body_a.velocity.y -= impulse.y * body_a.inv_mass

    body_b.velocity.x += impulse.x * body_b.inv_mass
    body_b.velocity.y += impulse.y * body_b.inv_mass
EOF

# ──────────────────────────────────────────────────────────
# 6. Generate tests/test_physics.py
# ──────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/tests/test_physics.py" << 'EOF'
import unittest
from engine.vector2d import Vector2D
from engine.rigid_body import RigidBody
from engine.integrator import integrate
from engine.collision import aabb_intersect
from engine.resolver import resolve_collision

class TestPhysicsEngine(unittest.TestCase):
    def test_vector_cross_product(self):
        a = Vector2D(1, 0)
        b = Vector2D(0, 1)
        self.assertEqual(a.cross(b), 1.0, "Vector cross product sign is incorrect. Check right-hand rule.")

    def test_semi_implicit_euler_integration(self):
        body = RigidBody(1.0, 1.0, 1.0)
        body.force.x = 10.0
        integrate(body, 1.0)
        # Expected: velocity updates by 10, then position updates by NEW velocity (10)
        self.assertEqual(body.velocity.x, 10.0)
        self.assertEqual(body.position.x, 10.0, "Position integrated incorrectly. Are you using Semi-Implicit Euler (velocity first)?")

    def test_aabb_boundary_collision(self):
        a_min = Vector2D(0, 0)
        a_max = Vector2D(1, 1)
        b_min = Vector2D(1, 0)
        b_max = Vector2D(2, 1)
        self.assertTrue(aabb_intersect(a_min, a_max, b_min, b_max), "AABBs that share an exact boundary should intersect.")

    def test_collision_impulse_conservation(self):
        a = RigidBody(10.0, 1.0, 1.0)
        a.velocity.x = 10.0
        
        b = RigidBody(1.0, 1.0, 1.0)
        b.velocity.x = 0.0
        
        normal = Vector2D(-1, 0)
        resolve_collision(a, b, normal)
        self.assertAlmostEqual(b.velocity.x, 18.1818, places=3, msg="Collision impulse violates conservation of momentum. Check reduced mass calculation.")

    def test_moment_of_inertia(self):
        body = RigidBody(12.0, 2.0, 3.0)
        # I = 12 * (2^2 + 3^2) / 12 = 13
        self.assertAlmostEqual(body.inertia, 13.0, places=3, msg="Moment of inertia for rectangle is incorrect.")

if __name__ == "__main__":
    unittest.main()
EOF

# ──────────────────────────────────────────────────────────
# 7. Generate run_tests.py
# ──────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/run_tests.py" << 'EOF'
import unittest
import sys

if __name__ == '__main__':
    tests = unittest.TestLoader().discover('tests')
    result = unittest.TextTestRunner(verbosity=2).run(tests)
    if not result.wasSuccessful():
        sys.exit(1)
EOF

# Set permissions
chown -R ga:ga "$WORKSPACE_DIR"

# Launch VS Code explicitly for the user
echo "Starting VS Code..."
su - ga -c "DISPLAY=:1 code $WORKSPACE_DIR" &
sleep 5

# Maximize and focus
DISPLAY=:1 wmctrl -r "Visual Studio Code" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Visual Studio Code" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="