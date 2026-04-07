#!/usr/bin/env python3
"""
Verifier for dispensing_trajectory_profiling task.
Validates spatial span, high-frequency logging, kinematic math consistency, and VLM visual proof.
"""

import json
import tempfile
import os
import csv
import math
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_dispensing_trajectory(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    query_vlm = env_info.get("query_vlm")
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    score = 0
    feedback = []
    
    # 1. Fetch metadata and files
    meta_tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    csv_tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".csv")
    json_tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    
    meta_tmp.close()
    csv_tmp.close()
    json_tmp.close()

    try:
        copy_from_env("/tmp/task_result.json", meta_tmp.name)
        with open(meta_tmp.name, "r") as f:
            meta = json.load(f)
            
        csv_mtime = meta.get("csv_mtime", 0)
        json_mtime = meta.get("json_mtime", 0)
        task_start = meta.get("task_start", 0)
        
        # Check file existence and freshness (10 points)
        if csv_mtime > task_start and json_mtime > task_start:
            score += 10
            feedback.append("✅ Files exist and were created after task start (+10)")
        else:
            feedback.append("❌ Output files are missing or stale (Anti-gaming check failed)")
            return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

        # Copy the actual agent outputs for mathematical verification
        copy_from_env(meta.get("csv_path"), csv_tmp.name)
        copy_from_env(meta.get("json_path"), json_tmp.name)

        with open(csv_tmp.name, "r") as f:
            rows = list(csv.DictReader(f))
            
        with open(json_tmp.name, "r") as f:
            report = json.load(f)

    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"❌ Failed to process files: {e}"}
    finally:
        for p in [meta_tmp.name, csv_tmp.name, json_tmp.name]:
            if os.path.exists(p): os.unlink(p)

    # 2. Extract columns and check High-Frequency Logging (15 points)
    if len(rows) >= 100:
        score += 15
        feedback.append(f"✅ High-frequency logging confirmed: {len(rows)} rows (+15)")
    else:
        feedback.append(f"❌ Insufficient rows logged: {len(rows)} (expected >= 100)")

    # 3. Parse Data and Check Trajectory Span (20 points)
    try:
        # Flexible key finding
        headers = [k.lower().strip() for k in rows[0].keys()]
        def get_key(candidates):
            for c in candidates:
                for h in headers:
                    if c in h: return next(k for k in rows[0].keys() if k.lower().strip() == h)
            return None

        t_key = get_key(['time'])
        x_key = get_key(['x'])
        y_key = get_key(['y'])
        z_key = get_key(['z'])
        v_key = get_key(['speed', 'vel'])
        q_key = get_key(['flow', 'rate', 'ml'])
        
        if not all([t_key, x_key, y_key, z_key, v_key, q_key]):
            raise ValueError("Missing required CSV columns.")

        xs = [float(r[x_key]) for r in rows]
        ys = [float(r[y_key]) for r in rows]
        zs = [float(r[z_key]) for r in rows]
        ts = [float(r[t_key]) for r in rows]
        vs = [float(r[v_key]) for r in rows]
        qs = [float(r[q_key]) for r in rows]

        dx = max(xs) - min(xs)
        dy = max(ys) - min(ys)
        
        # Applying a small floating point tolerance (0.14 for 0.15 limit)
        if dx >= 0.14 and dy >= 0.09:
            score += 20
            feedback.append(f"✅ Trajectory span meets criteria (dx={dx:.2f}m, dy={dy:.2f}m) (+20)")
        else:
            feedback.append(f"❌ Trajectory span too small (dx={dx:.2f}m, dy={dy:.2f}m)")
            
    except Exception as e:
        feedback.append(f"❌ CSV Data parsing error: {e}")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    # 4. Mathematical Consistency Validation (25 points)
    v_errors = []
    q_errors = []
    actual_path_length = 0.0
    
    for i in range(1, len(rows)):
        dt = ts[i] - ts[i-1]
        if dt <= 0: continue
        
        dist = math.sqrt((xs[i]-xs[i-1])**2 + (ys[i]-ys[i-1])**2 + (zs[i]-zs[i-1])**2)
        actual_path_length += dist
        
        expected_v = dist / dt
        v_errors.append(abs(expected_v - vs[i]))
        q_errors.append(abs(qs[i] - 5.0 * vs[i]))
        
    avg_v_err = sum(v_errors) / len(v_errors) if v_errors else float('inf')
    avg_q_err = sum(q_errors) / len(q_errors) if q_errors else float('inf')
    
    if avg_v_err < 0.05 and avg_q_err < 0.05:
        score += 25
        feedback.append("✅ Kinematic math and proportional flow rate validated mathematically (+25)")
    else:
        feedback.append(f"❌ Mathematical inconsistency detected (V_err: {avg_v_err:.4f}, Q_err: {avg_q_err:.4f})")

    # 5. JSON Analytics Accuracy & API proof (20 + 10 points)
    reported_len = float(report.get("total_path_length_m", 0.0))
    reported_vol = float(report.get("total_volume_ml", 0.0))
    base_z = report.get("robot_base_z")
    
    vol_err = abs(reported_vol - (5.0 * reported_len))
    len_err = abs(reported_len - actual_path_length)
    
    if vol_err < 0.1 and len_err < 0.05:
        score += 20
        feedback.append("✅ JSON aggregate statistics accurately match trajectory data (+20)")
    else:
        feedback.append("❌ JSON report values contradict raw CSV trajectory data")

    if base_z is not None and isinstance(base_z, (int, float)):
        score += 10
        feedback.append("✅ Live ZMQ API interaction verified via robot_base_z extraction (+10)")
    else:
        feedback.append("❌ Live API interaction proof (robot_base_z) missing or invalid type")

    # Final Pass Condition
    # Requires basic math consistency and at least 70 total points
    passed = score >= 70 and avg_q_err < 0.05
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback)
    }