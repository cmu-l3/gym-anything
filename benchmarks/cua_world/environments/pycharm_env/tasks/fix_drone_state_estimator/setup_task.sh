#!/bin/bash
set -e
echo "=== Setting up fix_drone_state_estimator task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_NAME="fix_drone_state_estimator"
PROJECT_DIR="/home/ga/PycharmProjects/drone_estimator"

# 1. Clean up previous run
rm -rf "$PROJECT_DIR"
rm -f /tmp/${TASK_NAME}_* 2>/dev/null || true

# 2. Create project structure
su - ga -c "mkdir -p $PROJECT_DIR/estimator $PROJECT_DIR/tests $PROJECT_DIR/scripts $PROJECT_DIR/data"

# 3. Create requirements.txt
cat > "$PROJECT_DIR/requirements.txt" << 'EOF'
numpy>=1.24.0
pandas>=2.0.0
pytest>=7.0
EOF

# 4. Generate Physics-Based Flight Data (Generator Script)
# We generate a realistic trajectory (square path) with IMU noise and GPS noise.
cat > /tmp/generate_data.py << 'PYEOF'
import numpy as np
import pandas as pd

def generate_flight_log():
    dt = 0.01  # 100 Hz
    duration = 60
    t = np.arange(0, duration, dt)
    n_steps = len(t)

    # State: [x, y, z, vx, vy, vz]
    gt_state = np.zeros((n_steps, 6))
    
    # Define a square path: 0-10s hover, 10-20s North, 20-30s East, 30-40s South, 40-50s West
    # Accel inputs (body frame, simplified to NED for this synthetic gen)
    accel_true = np.zeros((n_steps, 3))
    
    # Velocity setpoints for the square
    for i in range(n_steps):
        ti = t[i]
        if 10 <= ti < 20: gt_state[i, 3] = 5.0  # Vx = 5 (North)
        elif 20 <= ti < 30: gt_state[i, 4] = 5.0 # Vy = 5 (East)
        elif 30 <= ti < 40: gt_state[i, 3] = -5.0 # Vx = -5 (South)
        elif 40 <= ti < 50: gt_state[i, 4] = -5.0 # Vy = -5 (West)
        
        # Integrate position
        if i > 0:
            gt_state[i, 0:3] = gt_state[i-1, 0:3] + gt_state[i-1, 3:6] * dt

    # Calculate true acceleration (derivative of velocity)
    # This is rough Euler differentiation for the IMU 'ground truth'
    gt_vel = gt_state[:, 3:6]
    accel_true[1:, :] = (gt_vel[1:] - gt_vel[:-1]) / dt
    
    # Add gravity to accel (IMU measures specific force)
    accel_true[:, 2] -= 9.81

    # Simulate Sensors
    # IMU: Bias + White Noise
    accel_bias = np.array([0.1, -0.1, 0.05])
    gyro_bias = np.array([0.01, 0.01, 0.01])
    
    accel_noise_std = 0.1
    gyro_noise_std = 0.01
    gps_noise_std = 2.0
    
    imu_accel = accel_true + accel_bias + np.random.normal(0, accel_noise_std, size=(n_steps, 3))
    imu_gyro = np.zeros((n_steps, 3)) + gyro_bias + np.random.normal(0, gyro_noise_std, size=(n_steps, 3))
    
    # GPS: Lower frequency (10 Hz), Position only
    gps_data = []
    gps_step = int(0.1 / dt) # Every 10 steps
    
    data = []
    
    for i in range(n_steps):
        row = {
            'timestamp': t[i],
            'accel_x': imu_accel[i, 0], 'accel_y': imu_accel[i, 1], 'accel_z': imu_accel[i, 2],
            'gyro_x': imu_gyro[i, 0], 'gyro_y': imu_gyro[i, 1], 'gyro_z': imu_gyro[i, 2],
            'gt_n': gt_state[i, 0], 'gt_e': gt_state[i, 1], 'gt_d': gt_state[i, 2]
        }
        
        # Add GPS if step matches
        if i % gps_step == 0:
            row['gps_n'] = gt_state[i, 0] + np.random.normal(0, gps_noise_std)
            row['gps_e'] = gt_state[i, 1] + np.random.normal(0, gps_noise_std)
            row['gps_d'] = gt_state[i, 2] + np.random.normal(0, gps_noise_std)
        else:
            row['gps_n'] = np.nan
            row['gps_e'] = np.nan
            row['gps_d'] = np.nan
            
        data.append(row)
        
    df = pd.DataFrame(data)
    df.to_csv('flight_log.csv', index=False)

if __name__ == "__main__":
    generate_flight_log()
PYEOF

echo "Generating flight data..."
cd "$PROJECT_DIR/data" && python3 /tmp/generate_data.py

# 5. Create estimator/ekf.py with BUGS
cat > "$PROJECT_DIR/estimator/ekf.py" << 'PYEOF'
"""
Extended Kalman Filter for Drone State Estimation.

State Vector: [x, y, z, vx, vy, vz]
"""
import numpy as np

class EKF:
    def __init__(self):
        # State: [pos_x, pos_y, pos_z, vel_x, vel_y, vel_z]
        self.x = np.zeros(6)
        
        # Covariance Matrix
        self.P = np.eye(6) * 100.0
        
        # Process Noise Covariance (Q)
        self.Q = np.eye(6) * 0.1
        
        # Measurement Noise Covariance (R) for GPS
        self.R_gps = np.eye(3) * 2.0**2
        
        # Gravity vector
        self.g = np.array([0, 0, 9.81])

    def predict(self, accel, gyro, dt):
        """
        Prediction step using IMU data.
        accel: [ax, ay, az] in m/s^2
        dt: time step in seconds
        """
        # 1. State Prediction (Motion Model)
        # x_pos = x_pos + vx * dt
        # v = v + (accel - g) * dt
        
        new_x = self.x.copy()
        
        # Update Position
        # BUG 1: Missing dt in velocity integration for position
        # Should be: new_x[0:3] += self.x[3:6] * dt
        new_x[0:3] += self.x[3:6]
        
        # Update Velocity (Assume body frame aligned with NED for simplicity in this task)
        # In a full EKF we'd use a rotation matrix from quaternions, but let's keep it linear for this specific task scope
        accel_world = accel + self.g  # Remove gravity
        new_x[3:6] += accel_world * dt
        
        self.x = new_x
        
        # 2. Covariance Prediction
        # F is Jacobian of state transition
        F = np.eye(6)
        F[0, 3] = dt
        F[1, 4] = dt
        F[2, 5] = dt
        
        self.P = F @ self.P @ F.T + self.Q

    def update_gps(self, measurement):
        """
        Update step using GPS measurement [n, e, d].
        """
        z = np.array(measurement)
        
        # Measurement Matrix H
        # Maps state vector [x, y, z, vx, vy, vz] to measurement [x, y, z]
        
        # BUG 2: Incorrect H matrix mapping
        # This maps velocity (indices 3,4,5) to position measurement instead of position (indices 0,1,2)
        H = np.zeros((3, 6))
        H[0, 3] = 1
        H[1, 4] = 1
        H[2, 5] = 1
        
        # Innovation
        y = z - H @ self.x
        
        # Innovation Covariance
        S = H @ self.P @ H.T + self.R_gps
        
        # Kalman Gain
        K = self.P @ H.T @ np.linalg.inv(S)
        
        # State Update
        self.x = self.x + K @ y
        
        # Covariance Update
        # P = (I - KH)P
        I = np.eye(6)
        
        # BUG 3: Sign error in covariance update
        # Should be (I - K@H), but is (I + K@H)
        self.P = (I + K @ H) @ self.P
PYEOF

# 6. Create tests/test_ekf.py
cat > "$PROJECT_DIR/tests/test_ekf.py" << 'PYEOF'
import numpy as np
import pytest
from estimator.ekf import EKF

def test_initialization():
    ekf = EKF()
    assert ekf.x.shape == (6,)
    assert ekf.P.shape == (6, 6)

def test_predict_constant_velocity():
    """Test if position updates correctly given a velocity and dt."""
    ekf = EKF()
    ekf.x[3] = 10.0  # Vx = 10 m/s
    dt = 0.5
    
    # Predict with zero acceleration
    # accel must counteract gravity to have 0 net accel
    accel_input = np.array([0, 0, -9.81]) 
    ekf.predict(accel_input, np.zeros(3), dt)
    
    # Expected Pos X = 0 + 10 * 0.5 = 5.0
    # BUG 1 cause: If dt missing, Pos X = 0 + 10 = 10.0
    assert np.isclose(ekf.x[0], 5.0), f"Position prediction incorrect. Expected 5.0, got {ekf.x[0]}"

def test_gps_update_matrix():
    """Test if H matrix correctly maps state to measurement."""
    ekf = EKF()
    # Set state: Pos=[10, 20, 30], Vel=[1, 2, 3]
    ekf.x = np.array([10.0, 20.0, 30.0, 1.0, 2.0, 3.0])
    
    # We want to check H implicitly by checking the innovation y = z - Hx
    # Measurement z = [10, 20, 30]
    z = np.array([10.0, 20.0, 30.0])
    
    # Temporarily instrument update to check H or check result
    # If H maps velocity (indices 3,4,5), Hx = [1, 2, 3]. y = [10,20,30] - [1,2,3] = [9,18,27]
    # If H maps position (indices 0,1,2), Hx = [10, 20, 30]. y = 0
    
    # Since we can't easily access H local var, we check the state update direction
    # If H is wrong, K will be wrong, and the update will behave strangely.
    # But simpler: let's reproduce the logic inside the test to verify expected behavior
    
    H_correct = np.zeros((3, 6))
    H_correct[0,0] = 1
    H_correct[1,1] = 1
    H_correct[2,2] = 1
    
    # We can inspect the code behavior by running a step where pos matches meas, but vel does not.
    # If H is correct (maps pos), error should be 0, no update.
    # If H is incorrect (maps vel), error will be large, state will update.
    
    ekf.P = np.eye(6) * 0.1 # Small covariance
    initial_x = ekf.x.copy()
    ekf.update_gps(z)
    
    # If H was correct, Hx = z, so y=0, so x shouldn't change
    assert np.allclose(ekf.x, initial_x, atol=0.1), "State changed despite measurement matching position. Check H matrix."

def test_covariance_reduction():
    """Test that covariance decreases after a perfect measurement update."""
    ekf = EKF()
    initial_trace = np.trace(ekf.P)
    
    z = np.zeros(3)
    ekf.update_gps(z)
    
    final_trace = np.trace(ekf.P)
    
    # BUG 3: (I + KH)P makes covariance grow instead of shrink
    assert final_trace < initial_trace, f"Covariance increased after update! {initial_trace} -> {final_trace}"
PYEOF

# 7. Create scripts/evaluate_trajectory.py
cat > "$PROJECT_DIR/scripts/evaluate_trajectory.py" << 'PYEOF'
import pandas as pd
import numpy as np
import sys
import os

# Add project root to path
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from estimator.ekf import EKF

def run_evaluation():
    df = pd.read_csv('data/flight_log.csv')
    ekf = EKF()
    
    estimated_pos = []
    ground_truth = []
    
    # Initialize with first GT
    ekf.x[0] = df.iloc[0]['gt_n']
    ekf.x[1] = df.iloc[0]['gt_e']
    ekf.x[2] = df.iloc[0]['gt_d']
    
    prev_time = df.iloc[0]['timestamp']
    
    for i, row in df.iterrows():
        dt = row['timestamp'] - prev_time
        prev_time = row['timestamp']
        
        if dt > 0:
            accel = np.array([row['accel_x'], row['accel_y'], row['accel_z']])
            gyro = np.array([row['gyro_x'], row['gyro_y'], row['gyro_z']])
            ekf.predict(accel, gyro, dt)
            
        if not np.isnan(row['gps_n']):
            gps = np.array([row['gps_n'], row['gps_e'], row['gps_d']])
            ekf.update_gps(gps)
            
        estimated_pos.append(ekf.x[0:3])
        ground_truth.append([row['gt_n'], row['gt_e'], row['gt_d']])
        
    est = np.array(estimated_pos)
    gt = np.array(ground_truth)
    
    # Calculate RMSE
    error = est - gt
    rmse = np.sqrt(np.mean(error**2, axis=0))
    total_rmse = np.sqrt(np.mean(np.sum(error**2, axis=1)))
    
    print(f"RMSE N: {rmse[0]:.2f} m")
    print(f"RMSE E: {rmse[1]:.2f} m")
    print(f"RMSE D: {rmse[2]:.2f} m")
    print(f"Total Position RMSE: {total_rmse:.2f} m")
    
    return total_rmse

if __name__ == "__main__":
    rmse = run_evaluation()
    if rmse < 1.0:
        print("STATUS: PASS")
    else:
        print("STATUS: FAIL")
PYEOF

# 8. Set ownership
chown -R ga:ga "$PROJECT_DIR"

# 9. Record task start time
date +%s > /tmp/${TASK_NAME}_start_ts

# 10. Launch PyCharm
source /workspace/scripts/task_utils.sh
setup_pycharm_project "$PROJECT_DIR" "drone_estimator" 120

# 11. Initial Screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="