#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up Fix Sensor Fusion Pipeline Task ==="

WORKSPACE_DIR="/home/ga/workspace/sensor_fusion"
sudo -u ga mkdir -p "$WORKSPACE_DIR/filters"
sudo -u ga mkdir -p "$WORKSPACE_DIR/sensors"
sudo -u ga mkdir -p "$WORKSPACE_DIR/transforms"
sudo -u ga mkdir -p "$WORKSPACE_DIR/fusion"
sudo -u ga mkdir -p "$WORKSPACE_DIR/tests"

# ──────────────────────────────────────────────
# filters/kalman_filter.py (BUG: Swapped F matrix indices)
# ──────────────────────────────────────────────
cat > "$WORKSPACE_DIR/filters/kalman_filter.py" << 'EOF'
import numpy as np

class ExtendedKalmanFilter:
    def __init__(self, dt):
        self.dt = dt
        # State vector: [x, y, z, vx, vy, vz]
        self.F = np.eye(6)
        
        # BUG: Velocity to position coupling is swapped/incorrect.
        # Should be F[0,3] = dt, F[1,4] = dt, F[2,5] = dt
        self.F[0, 4] = dt
        self.F[1, 5] = dt
        self.F[2, 3] = dt

    def predict(self, x, P, Q):
        """Predict step of the Kalman Filter."""
        x_pred = self.F @ x
        P_pred = self.F @ P @ self.F.T + Q
        return x_pred, P_pred
EOF

# ──────────────────────────────────────────────
# sensors/imu_processor.py (BUG: Squared norm instead of norm)
# ──────────────────────────────────────────────
cat > "$WORKSPACE_DIR/sensors/imu_processor.py" << 'EOF'
import numpy as np

def normalize_quaternion(q):
    """
    Normalizes a quaternion q = [qw, qx, qy, qz] to unit length.
    """
    # BUG: Dividing by the squared norm instead of the actual norm
    norm_sq = np.dot(q, q)
    if norm_sq < 1e-8:
        return np.array([1.0, 0.0, 0.0, 0.0])
    
    return q / norm_sq

def integrate_gyro(q, gyro, dt):
    """Integrates angular velocity into quaternion."""
    wx, wy, wz = gyro
    omega = np.array([
        [0, -wx, -wy, -wz],
        [wx, 0, wz, -wy],
        [wy, -wz, 0, wx],
        [wz, wy, -wx, 0]
    ])
    q_new = q + 0.5 * dt * (omega @ q)
    return normalize_quaternion(q_new)
EOF

# ──────────────────────────────────────────────
# transforms/coordinate_transform.py (BUG: XYZ instead of ZYX)
# ──────────────────────────────────────────────
cat > "$WORKSPACE_DIR/transforms/coordinate_transform.py" << 'EOF'
import numpy as np

def euler_to_rotation_matrix(roll, pitch, yaw):
    """
    Converts Euler angles to a rotation matrix.
    The pipeline uses the NED (North-East-Down) convention,
    which requires a ZYX extrinsic rotation order.
    """
    cx, sx = np.cos(roll), np.sin(roll)
    cy, sy = np.cos(pitch), np.sin(pitch)
    cz, sz = np.cos(yaw), np.sin(yaw)

    Rx = np.array([
        [1, 0, 0],
        [0, cx, -sx],
        [0, sx, cx]
    ])
    
    Ry = np.array([
        [cy, 0, sy],
        [0, 1, 0],
        [-sy, 0, cy]
    ])
    
    Rz = np.array([
        [cz, -sz, 0],
        [sz, cz, 0],
        [0, 0, 1]
    ])

    # BUG: Applied in XYZ order instead of ZYX
    return Rx @ Ry @ Rz
EOF

# ──────────────────────────────────────────────
# fusion/sensor_fusion.py (BUG: Simple addition instead of harmonic mean)
# ──────────────────────────────────────────────
cat > "$WORKSPACE_DIR/fusion/sensor_fusion.py" << 'EOF'
import numpy as np

def fuse_covariances(P1, P2):
    """
    Fuses two covariance matrices using Covariance Intersection.
    Assume omega = 0.5 for equal weighting.
    Formula: P_fused = inv(inv(P1) + inv(P2))
    """
    # BUG: Simply summing the covariances leads to overconfidence and divergence
    return P1 + P2
EOF

# ──────────────────────────────────────────────
# fusion/time_synchronizer.py (BUG: Nearest neighbor instead of linear)
# ──────────────────────────────────────────────
cat > "$WORKSPACE_DIR/fusion/time_synchronizer.py" << 'EOF'
import numpy as np

def interpolate_sensor_data(target_time, times, data):
    """
    Interpolates 1D sensor data to match a target_time.
    times: array of timestamps (sorted)
    data: array of sensor readings
    """
    if target_time <= times[0]:
        return data[0]
    if target_time >= times[-1]:
        return data[-1]
        
    # BUG: Uses nearest neighbor instead of linear interpolation
    idx = np.argmin(np.abs(times - target_time))
    return data[idx]
EOF

# ──────────────────────────────────────────────
# tests/test_pipeline.py (Test Suite)
# ──────────────────────────────────────────────
cat > "$WORKSPACE_DIR/tests/test_pipeline.py" << 'EOF'
import numpy as np
import pytest
from filters.kalman_filter import ExtendedKalmanFilter
from sensors.imu_processor import normalize_quaternion
from transforms.coordinate_transform import euler_to_rotation_matrix
from fusion.sensor_fusion import fuse_covariances
from fusion.time_synchronizer import interpolate_sensor_data

def test_kalman_filter_transition():
    dt = 0.1
    kf = ExtendedKalmanFilter(dt)
    x = np.array([1.0, 2.0, 3.0, 10.0, 20.0, 30.0]) # pos and vel
    P = np.eye(6)
    Q = np.zeros((6,6))
    
    x_pred, _ = kf.predict(x, P, Q)
    
    # Expected: pos = pos + vel * dt
    assert np.isclose(x_pred[0], 1.0 + 10.0 * dt), "X position prediction failed"
    assert np.isclose(x_pred[1], 2.0 + 20.0 * dt), "Y position prediction failed"
    assert np.isclose(x_pred[2], 3.0 + 30.0 * dt), "Z position prediction failed"

def test_quaternion_normalization():
    q = np.array([2.0, 0.0, 0.0, 0.0])
    q_norm = normalize_quaternion(q)
    assert np.isclose(np.linalg.norm(q_norm), 1.0), "Quaternion is not unit length"
    assert np.isclose(q_norm[0], 1.0), "Quaternion scaling is incorrect"

def test_coordinate_transform_zyx():
    roll = np.pi/4
    pitch = np.pi/6
    yaw = np.pi/3
    R = euler_to_rotation_matrix(roll, pitch, yaw)
    
    # Expected R[0,0] for ZYX is cos(yaw)*cos(pitch)
    expected_r00 = np.cos(yaw) * np.cos(pitch)
    assert np.isclose(R[0,0], expected_r00), "Rotation matrix order is incorrect (expects ZYX)"

def test_covariance_fusion():
    P1 = np.array([[2.0, 0], [0, 2.0]])
    P2 = np.array([[2.0, 0], [0, 2.0]])
    
    P_fused = fuse_covariances(P1, P2)
    # inv(inv(P1) + inv(P2)) should be [[1.0, 0], [0, 1.0]]
    assert np.isclose(P_fused[0,0], 1.0), "Covariance fusion formula is incorrect"

def test_time_synchronizer():
    times = np.array([0.0, 1.0, 2.0, 3.0])
    data = np.array([10.0, 20.0, 30.0, 40.0])
    
    val = interpolate_sensor_data(1.5, times, data)
    assert np.isclose(val, 25.0), f"Expected 25.0 from linear interpolation, got {val}"
EOF

# ──────────────────────────────────────────────
# README.md
# ──────────────────────────────────────────────
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Sensor Fusion Pipeline

This repository contains the core state estimation stack for our autonomous vehicle. It fuses high-frequency IMU data with lower-frequency GPS and LiDAR updates using an Extended Kalman Filter (EKF).

## Current Issues
The vehicle's localization is currently failing field tests. We suspect issues in:
1. **Kalman Filter**: Position diverges rapidly during constant-velocity motion.
2. **IMU Processing**: Orientation scale drifts over time.
3. **Coordinate Transforms**: The world-frame orientation is incorrect (we use ZYX NED extrinsic convention).
4. **Sensor Fusion**: The fused covariance matrices are growing instead of shrinking.
5. **Time Synchronization**: We are seeing discontinuities (jumps) in the trajectory at sensor boundaries.

Fix the bugs across these modules and ensure `python -m pytest tests/` passes.
EOF

chown -R ga:ga "$WORKSPACE_DIR"

# Launch VSCode
su - ga -c "code --new-window $WORKSPACE_DIR" &
sleep 5

# Anti-gaming timestamp
date +%s > /tmp/task_start_time.txt

echo "=== Setup complete ==="