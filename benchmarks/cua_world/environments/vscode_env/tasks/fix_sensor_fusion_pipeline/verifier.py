#!/usr/bin/env python3
"""
Verifier for the fix_sensor_fusion_pipeline task.
Evaluates static code fixes for 5 distinct bugs in a sensor fusion pipeline.
Pass threshold: 60/100 points (20 points per bug).
"""

import os
import json
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_sensor_fusion_pipeline(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/sensor_fusion_result.json", temp_result.name)
        if not os.path.exists(temp_result.name) or os.path.getsize(temp_result.name) == 0:
            return {"passed": False, "score": 0, "feedback": "Result file not found or empty"}
        
        with open(temp_result.name, 'r') as f:
            file_contents = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # ── Bug 1: Kalman Filter Transition Matrix ──
    kf_src = file_contents.get("filters/kalman_filter.py", "")
    if kf_src.startswith("ERROR") or not kf_src:
        feedback.append("[-] kalman_filter.py: missing or could not be read")
    else:
        # Check if F[0,3], F[1,4], F[2,5] are correctly assigned dt
        has_f03 = re.search(r'F\[0,\s*3\]\s*=\s*dt', kf_src) or re.search(r'F\[0\]\[3\]\s*=\s*dt', kf_src)
        has_f14 = re.search(r'F\[1,\s*4\]\s*=\s*dt', kf_src) or re.search(r'F\[1\]\[4\]\s*=\s*dt', kf_src)
        has_f25 = re.search(r'F\[2,\s*5\]\s*=\s*dt', kf_src) or re.search(r'F\[2\]\[5\]\s*=\s*dt', kf_src)
        has_bug = re.search(r'F\[0,\s*4\]\s*=\s*dt', kf_src)
        
        if has_f03 and has_f14 and has_f25 and not has_bug:
            score += 20
            feedback.append("[+] kalman_filter.py: F matrix velocity coupling fixed (20/20)")
        else:
            feedback.append("[-] kalman_filter.py: F matrix indices still incorrect (0/20)")

    # ── Bug 2: Quaternion Normalization ──
    imu_src = file_contents.get("sensors/imu_processor.py", "")
    if imu_src.startswith("ERROR") or not imu_src:
        feedback.append("[-] imu_processor.py: missing or could not be read")
    else:
        # Look for sqrt, linalg.norm, or ** 0.5 in normalize_quaternion
        norm_func = re.search(r'def normalize_quaternion.*?return', imu_src, re.DOTALL)
        src_to_check = norm_func.group(0) if norm_func else imu_src
        
        has_sqrt = re.search(r'np\.sqrt', src_to_check)
        has_norm = re.search(r'np\.linalg\.norm', src_to_check)
        has_pow = re.search(r'\*\*\s*0\.5', src_to_check)
        
        if has_sqrt or has_norm or has_pow:
            score += 20
            feedback.append("[+] imu_processor.py: Quaternion normalization uses correct norm (20/20)")
        else:
            feedback.append("[-] imu_processor.py: Still dividing by squared norm (0/20)")

    # ── Bug 3: Coordinate Transform Order (ZYX) ──
    tf_src = file_contents.get("transforms/coordinate_transform.py", "")
    if tf_src.startswith("ERROR") or not tf_src:
        feedback.append("[-] coordinate_transform.py: missing or could not be read")
    else:
        # Check rotation multiplication order: Rz @ Ry @ Rx
        correct_order = re.search(r'Rz\s*@\s*Ry\s*@\s*Rx', tf_src)
        correct_dot = re.search(r'np\.dot\(\s*np\.dot\(\s*Rz\s*,\s*Ry\s*\)\s*,\s*Rx\s*\)', tf_src)
        buggy_order = re.search(r'Rx\s*@\s*Ry\s*@\s*Rz', tf_src)
        
        if (correct_order or correct_dot) and not buggy_order:
            score += 20
            feedback.append("[+] coordinate_transform.py: ZYX extrinsic rotation order correct (20/20)")
        else:
            feedback.append("[-] coordinate_transform.py: Rotation matrix multiplication order incorrect (0/20)")

    # ── Bug 4: Covariance Fusion ──
    fusion_src = file_contents.get("fusion/sensor_fusion.py", "")
    if fusion_src.startswith("ERROR") or not fusion_src:
        feedback.append("[-] sensor_fusion.py: missing or could not be read")
    else:
        # Check for inv(inv(P1) + inv(P2))
        inv_count = len(re.findall(r'inv\s*\(', fusion_src))
        linalg_solve = "np.linalg.solve" in fusion_src
        buggy_sum = re.search(r'return\s+P1\s*\+\s*P2', fusion_src)
        
        if (inv_count >= 2 or linalg_solve) and not buggy_sum:
            score += 20
            feedback.append("[+] sensor_fusion.py: Covariance intersection formula applied (20/20)")
        else:
            feedback.append("[-] sensor_fusion.py: Covariances still summed linearly (0/20)")

    # ── Bug 5: Time Synchronization Interpolation ──
    sync_src = file_contents.get("fusion/time_synchronizer.py", "")
    if sync_src.startswith("ERROR") or not sync_src:
        feedback.append("[-] time_synchronizer.py: missing or could not be read")
    else:
        # Check for linear interpolation vs argmin
        has_interp = re.search(r'np\.interp', sync_src) or re.search(r'interp1d', sync_src)
        has_manual_lerp = re.search(r'\+', sync_src) and re.search(r'\-', sync_src) and re.search(r'\*', sync_src) and re.search(r'/', sync_src)
        has_argmin = re.search(r'np\.argmin', sync_src)
        
        if (has_interp or has_manual_lerp) and not has_argmin:
            score += 20
            feedback.append("[+] time_synchronizer.py: Linear interpolation implemented (20/20)")
        else:
            feedback.append("[-] time_synchronizer.py: Still uses nearest neighbor (argmin) (0/20)")

    pass_threshold = 60
    passed = score >= pass_threshold
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }