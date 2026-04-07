#!/bin/bash
echo "=== Setting up fix_raytracer_prototype task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

PROJECT_DIR="/home/ga/PycharmProjects/pytracer"
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR/pytracer"
mkdir -p "$PROJECT_DIR/tests"
mkdir -p "$PROJECT_DIR/scenes"
mkdir -p "$PROJECT_DIR/output"

# Install Pillow for image handling
pip3 install --quiet Pillow numpy pytest

# ==============================================================================
# 1. vector.py (Correct)
# ==============================================================================
cat > "$PROJECT_DIR/pytracer/vector.py" << 'EOF'
import math

class Vec3:
    def __init__(self, x, y, z):
        self.x = float(x)
        self.y = float(y)
        self.z = float(z)

    def __add__(self, other):
        return Vec3(self.x + other.x, self.y + other.y, self.z + other.z)

    def __sub__(self, other):
        return Vec3(self.x - other.x, self.y - other.y, self.z - other.z)

    def __mul__(self, other):
        if isinstance(other, Vec3):
            return Vec3(self.x * other.x, self.y * other.y, self.z * other.z)
        return Vec3(self.x * other, self.y * other, self.z * other)

    def dot(self, other):
        return self.x * other.x + self.y * other.y + self.z * other.z

    def length(self):
        return math.sqrt(self.dot(self))

    def normalize(self):
        l = self.length()
        return Vec3(self.x / l, self.y / l, self.z / l)
    
    def to_tuple(self):
        return (self.x, self.y, self.z)
EOF

# ==============================================================================
# 2. ray.py (Correct)
# ==============================================================================
cat > "$PROJECT_DIR/pytracer/ray.py" << 'EOF'
from .vector import Vec3

class Ray:
    def __init__(self, origin: Vec3, direction: Vec3):
        self.origin = origin
        self.direction = direction

    def at(self, t):
        return self.origin + self.direction * t
EOF

# ==============================================================================
# 3. camera.py (BUG 1: FOV)
# ==============================================================================
cat > "$PROJECT_DIR/pytracer/camera.py" << 'EOF'
import math
from .vector import Vec3
from .ray import Ray

class Camera:
    def __init__(self, lookfrom, lookat, vup, vfov, aspect_ratio):
        # BUG: vfov is in degrees, but we treat it as radians directly here
        # FIX: theta = math.radians(vfov)
        theta = vfov 
        h = math.tan(theta / 2)
        viewport_height = 2.0 * h
        viewport_width = aspect_ratio * viewport_height

        self.w = (lookfrom - lookat).normalize()
        self.u = vup.x  # Simplified cross product placeholder for prototype
        # Real implementation for cross product
        w = (lookfrom - lookat).normalize()
        u = Vec3(vup.y * w.z - vup.z * w.y,
                 vup.z * w.x - vup.x * w.z,
                 vup.x * w.y - vup.y * w.x).normalize()
        v = Vec3(w.y * u.z - w.z * u.y,
                 w.z * u.x - w.x * u.z,
                 w.x * u.y - w.y * u.x)

        self.origin = lookfrom
        self.horizontal = u * viewport_width
        self.vertical = v * viewport_height
        self.lower_left_corner = self.origin - self.horizontal * 0.5 - self.vertical * 0.5 - w

    def get_ray(self, s, t):
        return Ray(self.origin, self.lower_left_corner + self.horizontal * s + self.vertical * t - self.origin)
EOF

# ==============================================================================
# 4. geometry.py (BUG 2: Sphere Root)
# ==============================================================================
cat > "$PROJECT_DIR/pytracer/geometry.py" << 'EOF'
import math
from .vector import Vec3

class HitRecord:
    def __init__(self, t, p, normal, material):
        self.t = t
        self.p = p
        self.normal = normal
        self.material = material

class Sphere:
    def __init__(self, center, radius, material):
        self.center = center
        self.radius = radius
        self.material = material

    def hit(self, ray, t_min, t_max):
        oc = ray.origin - self.center
        a = ray.direction.length() ** 2
        half_b = oc.dot(ray.direction)
        c = oc.length() ** 2 - self.radius ** 2
        discriminant = half_b * half_b - a * c

        if discriminant < 0:
            return None

        sqrtd = math.sqrt(discriminant)
        
        # BUG: Always choosing the far root (plus sign).
        # This renders the back surface of the sphere (inside out).
        # FIX: Check (-half_b - sqrtd) / a first.
        root = (-half_b + sqrtd) / a
        
        if root < t_min or t_max < root:
             return None

        t = root
        p = ray.at(t)
        normal = (p - self.center) * (1.0 / self.radius)
        return HitRecord(t, p, normal, self.material)
EOF

# ==============================================================================
# 5. material.py (BUG 3: Reflection)
# ==============================================================================
cat > "$PROJECT_DIR/pytracer/material.py" << 'EOF'
from .vector import Vec3
from .ray import Ray

def reflect(v, n):
    # BUG: Wrong reflection formula. Missing factor of 2.
    # FIX: return v - n * v.dot(n) * 2
    return v - n * v.dot(n)

class Metal:
    def __init__(self, albedo):
        self.albedo = albedo

    def scatter(self, r_in, rec):
        reflected = reflect(r_in.direction.normalize(), rec.normal)
        scattered = Ray(rec.p, reflected)
        return (True, self.albedo, scattered)

class Lambertian:
    def __init__(self, albedo):
        self.albedo = albedo
    
    def scatter(self, r_in, rec):
        # Simple diffuse for prototype
        target = rec.p + rec.normal + Vec3(1,1,1).normalize() # Pseudo-random
        scattered = Ray(rec.p, target - rec.p)
        return (True, self.albedo, scattered)
EOF

# ==============================================================================
# 6. engine.py (BUG 4: Shadow Acne)
# ==============================================================================
cat > "$PROJECT_DIR/pytracer/engine.py" << 'EOF'
import math
from .vector import Vec3

def ray_color(ray, world, depth):
    if depth <= 0:
        return Vec3(0,0,0)

    rec = None
    closest_so_far = 999999.0
    
    # BUG: Shadow Acne / Self-Intersection
    # t_min should be a small epsilon (e.g., 0.001) to avoid re-intersecting 
    # the surface at the origin of the scattered ray.
    # FIX: Change 0 to 0.001
    t_min = 0

    for obj in world:
        temp_rec = obj.hit(ray, t_min, closest_so_far)
        if temp_rec:
            closest_so_far = temp_rec.t
            rec = temp_rec

    if rec:
        did_scatter, attenuation, scattered = rec.material.scatter(ray, rec)
        if did_scatter:
            return attenuation * ray_color(scattered, world, depth-1)
        return Vec3(0,0,0)

    unit_direction = ray.direction.normalize()
    t = 0.5 * (unit_direction.y + 1.0)
    return Vec3(1.0, 1.0, 1.0) * (1.0 - t) + Vec3(0.5, 0.7, 1.0) * t

def render(scene, cam, width, height, samples):
    pixels = []
    print(f"Rendering {width}x{height}...")
    for j in range(height-1, -1, -1):
        row = []
        for i in range(width):
            u = float(i) / (width - 1)
            v = float(j) / (height - 1)
            r = cam.get_ray(u, v)
            col = ray_color(r, scene, 5)
            row.append((int(col.x*255), int(col.y*255), int(col.z*255)))
        pixels.extend(row)
    return pixels
EOF

# ==============================================================================
# 7. main.py
# ==============================================================================
cat > "$PROJECT_DIR/main.py" << 'EOF'
import sys
from PIL import Image
from pytracer.vector import Vec3
from pytracer.camera import Camera
from pytracer.geometry import Sphere
from pytracer.material import Metal, Lambertian
from pytracer.engine import render

def main():
    # Image
    aspect_ratio = 16.0 / 9.0
    image_width = 320
    image_height = int(image_width / aspect_ratio)

    # World
    material_ground = Lambertian(Vec3(0.8, 0.8, 0.0))
    material_center = Lambertian(Vec3(0.7, 0.3, 0.3))
    material_left   = Metal(Vec3(0.8, 0.8, 0.8))

    world = []
    world.append(Sphere(Vec3(0.0, -100.5, -1.0), 100.0, material_ground))
    world.append(Sphere(Vec3(0.0, 0.0, -1.0), 0.5, material_center))
    world.append(Sphere(Vec3(-1.0, 0.0, -1.0), 0.5, material_left))

    # Camera
    lookfrom = Vec3(3, 3, 2)
    lookat = Vec3(0, 0, -1)
    vup = Vec3(0, 1, 0)
    dist_to_focus = (lookfrom - lookat).length()
    
    # FOV 20 degrees
    cam = Camera(lookfrom, lookat, vup, 20, aspect_ratio)

    # Render
    pixels = render(world, cam, image_width, image_height, 10)

    # Save
    img = Image.new('RGB', (image_width, image_height))
    img.putdata(pixels)
    img.save("output/render.png")
    print("Saved to output/render.png")

if __name__ == "__main__":
    main()
EOF

# ==============================================================================
# 8. Test Suite (failing initially)
# ==============================================================================
cat > "$PROJECT_DIR/tests/test_camera.py" << 'EOF'
import math
from pytracer.camera import Camera
from pytracer.vector import Vec3

def test_fov_radians_conversion():
    # A 90 degree FOV should result in a viewport height of 2 * tan(45deg) = 2 * 1 = 2
    cam = Camera(Vec3(0,0,0), Vec3(0,0,-1), Vec3(0,1,0), 90, 16/9)
    # Lower left corner calculation involves the viewport dimensions
    # If using degrees directly (90) instead of radians(90), tan(45) vs tan(0.78) is huge diff
    # We check if the internal calculation was reasonable
    # Ideally we'd inspect internal h, but simpler to check the vector magnitude of vertical
    # vertical = 2 * h * v (normalized)
    # If FOV=90, h=1.0. vertical length should be 2.0.
    
    vert_len = cam.vertical.length()
    # Tolerance for float comparison
    assert abs(vert_len - 2.0) < 0.1, f"Vertical viewport size wrong. Expected ~2.0, got {vert_len}. Did you convert degrees to radians?"
EOF

cat > "$PROJECT_DIR/tests/test_geometry.py" << 'EOF'
from pytracer.geometry import Sphere
from pytracer.ray import Ray
from pytracer.vector import Vec3

def test_sphere_intersection_nearest():
    # Sphere at z = -5, radius = 1.
    s = Sphere(Vec3(0,0,-5), 1, None)
    # Ray from origin to -z.
    r = Ray(Vec3(0,0,0), Vec3(0,0,-1))
    
    # Intersections are at t=4 (near) and t=6 (far)
    rec = s.hit(r, 0, 10)
    
    assert rec is not None
    # If bug exists, it returns the far root (6)
    assert abs(rec.t - 4.0) < 0.001, f"Hit t={rec.t}, expected 4.0. Are you checking the nearest root?"
EOF

cat > "$PROJECT_DIR/tests/test_material.py" << 'EOF'
from pytracer.material import reflect
from pytracer.vector import Vec3

def test_reflection_vector():
    # Incident vector coming down at 45 degrees: (1, -1, 0)
    v = Vec3(1, -1, 0)
    # Normal pointing up: (0, 1, 0)
    n = Vec3(0, 1, 0)
    
    # Perfect reflection should be (1, 1, 0)
    # Formula: v - 2*dot(v,n)*n
    # dot = -1
    # v - 2*(-1)*n = (1,-1,0) + 2*(0,1,0) = (1, 1, 0)
    
    # Buggy formula: v - dot*n = (1,-1,0) + (0,1,0) = (1, 0, 0) -> Flattened!
    
    r = reflect(v, n)
    assert abs(r.x - 1.0) < 0.001 and abs(r.y - 1.0) < 0.001, f"Reflection {r.to_tuple()} incorrect. Expected (1, 1, 0)."
EOF

cat > "$PROJECT_DIR/tests/test_engine.py" << 'EOF'
from pytracer.engine import ray_color
# Note: Testing t_min/bias directly via unit test is hard without inspecting the function local vars
# We can check if a ray starting ON the surface intersects itself immediately if t_min=0
from pytracer.geometry import Sphere, HitRecord
from pytracer.ray import Ray
from pytracer.vector import Vec3

class MockMaterial:
    def scatter(self, r_in, rec):
        # Scatter outward
        return (True, Vec3(1,1,1), Ray(rec.p, rec.normal))

def test_shadow_acne_bias():
    # This is a bit indirect. We rely on the fact that if t_min is 0,
    # a ray spawned exactly at intersection might hit the same object at t ~ 0
    # But Python floats might be precise enough for simple cases.
    # A better check is inspecting the source code or visual output, 
    # but for this "unit test" we will fail if we can detect 0 passed to hit().
    # Since we can't easily mock inner functions in this setup without complex libs,
    # we will rely on the visual verification or the user fixing it.
    # HOWEVER, we can provide a test that *suggests* the fix.
    
    # We'll just define a passing test here that encourages the user to run the render.
    # Real verification is in verify_fix_raytracer_prototype logic (checking code or render).
    pass 
EOF

# Timestamp
date +%s > /tmp/task_start_time.txt

# Open PyCharm
echo "Launching PyCharm..."
su - ga -c "DISPLAY=:1 /opt/pycharm/bin/pycharm.sh '$PROJECT_DIR' > /tmp/pycharm.log 2>&1 &"

wait_for_pycharm 60
setup_pycharm_project "$PROJECT_DIR"
dismiss_dialogs 5

take_screenshot /tmp/task_initial.png
echo "=== Setup complete ==="