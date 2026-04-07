#!/usr/bin/env python3
"""
Verifier for payload_acceleration_profiling task.

Scoring (100 points):
  - Criterion 1 (15 pts): Both files exist and were newly created.
  - Criterion 2 (20 pts): Sufficient data volume (>= 50 rows in CSV).
  - Criterion 3 (30 pts): Significant movement (distance >= 0.2m, max vel >= 0.1 m/s).
  - Criterion 4 (20 pts): Kinematic consistency (Anti-gaming): Numerical derivative of 
                          velocity matches reported acceleration.
  - Criterion 5 (15 pts): Safety report JSON is valid and logically correct.

Pass threshold: 70 AND Kinematic Consistency must be met.
"""

import json
import csv
import math
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def find_col(headers, candidates):
    """Helper to flexibly find a column index/name based on standard variants."""
    hl = [h.strip().lower() for h in headers]
    for c in candidates:
        if c in hl:
            return headers[hl.index(c)]
    return None

def verify_payload_acceleration_profiling(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Temporary files for copied content
    tmp_res = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp_csv = tempfile.NamedTemporaryFile(delete=False, suffix=".csv")
    tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp_res.close()
    tmp_csv.close()
    tmp_json.close()

    try:
        # 1. Load basic task export result
        try:
            copy_from_env("/tmp/payload_acceleration_result.json", tmp_res.name)
            with open(tmp_res.name, "r") as f:
                result = json.load(f)
        except Exception:
            return {"passed": False, "score": 0, "feedback": "Result state file not found."}

        score = 0
        feedback = []
        kinematic_consistency_met = False
        
        csv_exists = result.get("csv_exists", False)
        csv_new = result.get("csv_is_new", False)
        json_exists = result.get("json_exists", False)
        json_new = result.get("json_is_new", False)

        # Criterion 1: Files Exist & New (15 pts)
        if csv_exists and csv_new and json_exists and json_new:
            score += 15
            feedback.append("✅ Output files created after task start.")
        elif csv_exists or json_exists:
            feedback.append("❌ Output files exist but are missing or stale.")
        else:
            return {"passed": False, "score": 0, "feedback": "❌ No output files found."}

        # Early exit if CSV doesn't exist to prevent copy failure
        if not csv_exists:
            return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

        # 2. Load and parse CSV Data
        copy_from_env("/home/ga/Documents/CoppeliaSim/exports/payload_kinematics.csv", tmp_csv.name)
        times, positions, velocities, accelerations, accel_mags = [], [], [], [], []
        
        try:
            with open(tmp_csv.name, "r") as f:
                reader = list(csv.DictReader(f))
                if not reader:
                    raise ValueError("Empty CSV")
                headers = list(reader[0].keys())
                
                # Identify columns flexibly
                tc = find_col(headers, ['time_s', 'time'])
                px = find_col(headers, ['pos_x', 'px', 'x'])
                py = find_col(headers, ['pos_y', 'py', 'y'])
                pz = find_col(headers, ['pos_z', 'pz', 'z'])
                vx = find_col(headers, ['vel_x', 'vx'])
                vy = find_col(headers, ['vel_y', 'vy'])
                vz = find_col(headers, ['vel_z', 'vz'])
                ax = find_col(headers, ['accel_x', 'ax'])
                ay = find_col(headers, ['accel_y', 'ay'])
                az = find_col(headers, ['accel_z', 'az'])
                amag = find_col(headers, ['accel_mag', 'mag'])

                if not all([tc, px, py, pz, vx, vy, vz, ax, ay, az, amag]):
                    feedback.append("❌ CSV is missing required kinematic columns.")
                else:
                    for row in reader:
                        try:
                            t = float(row[tc])
                            p = (float(row[px]), float(row[py]), float(row[pz]))
                            v = (float(row[vx]), float(row[vy]), float(row[vz]))
                            a = (float(row[ax]), float(row[ay]), float(row[az]))
                            m = float(row[amag])
                            times.append(t)
                            positions.append(p)
                            velocities.append(v)
                            accelerations.append(a)
                            accel_mags.append(m)
                        except (ValueError, TypeError):
                            continue
        except Exception as e:
            feedback.append(f"❌ Could not parse CSV: {e}")

        # Criterion 2: Sufficient Data Volume (20 pts)
        num_samples = len(times)
        if num_samples >= 50:
            score += 20
            feedback.append(f"✅ Sufficient data volume ({num_samples} rows).")
        elif num_samples > 0:
            score += 10
            feedback.append(f"⚠️ Insufficient data volume ({num_samples} rows, need >= 50).")
            
        if num_samples < 2:
            feedback.append("❌ Not enough valid rows to evaluate physics.")
            return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

        # Criterion 3: Significant Movement (30 pts)
        max_dist = max(math.dist(positions[0], p) for p in positions)
        max_vel = max(math.dist((0, 0, 0), v) for v in velocities)
        
        if max_dist >= 0.2 and max_vel >= 0.1:
            score += 30
            feedback.append(f"✅ Significant movement detected (dist={max_dist:.2f}m, max_v={max_vel:.2f}m/s).")
        else:
            feedback.append(f"❌ Movement too small (dist={max_dist:.2f}m, max_v={max_vel:.2f}m/s).")

        # Criterion 4: Kinematic Consistency (20 pts)
        # Checks if reported acceleration matches numeric derivative of velocity
        # Computes forward, backward, and central diff to be extremely fair to any algorithm
        mae_sum = 0
        valid_steps = 0
        
        for i in range(1, len(times) - 1):
            dt_b = times[i] - times[i-1]
            dt_f = times[i+1] - times[i]
            dt_c = times[i+1] - times[i-1]
            
            v_curr = velocities[i]
            v_prev = velocities[i-1]
            v_next = velocities[i+1]
            agent_a = accelerations[i]

            # Backward diff
            ab = [(v_curr[j] - v_prev[j]) / dt_b if dt_b > 0 else 0 for j in range(3)]
            err_b = math.dist(ab, agent_a)
            
            # Forward diff
            af = [(v_next[j] - v_curr[j]) / dt_f if dt_f > 0 else 0 for j in range(3)]
            err_f = math.dist(af, agent_a)
            
            # Central diff
            ac = [(v_next[j] - v_prev[j]) / dt_c if dt_c > 0 else 0 for j in range(3)]
            err_c = math.dist(ac, agent_a)
            
            mae_sum += min(err_b, err_f, err_c)
            valid_steps += 1

        avg_error = (mae_sum / valid_steps) if valid_steps > 0 else float('inf')
        
        # High error threshold (e.g. 2.0 m/s^2) blocks random numbers but allows genuine numerical diff noise
        if avg_error < 2.0:
            score += 20
            kinematic_consistency_met = True
            feedback.append(f"✅ Kinematics are mathematically consistent (MAE={avg_error:.3f}).")
        else:
            feedback.append(f"❌ Kinematic inconsistency detected (MAE={avg_error:.3f} is too high) - suspected fake data.")

        # Criterion 5: Valid Safety Report (15 pts)
        if json_exists and json_new:
            copy_from_env("/home/ga/Documents/CoppeliaSim/exports/payload_safety_report.json", tmp_json.name)
            try:
                with open(tmp_json.name, "r") as f:
                    report = json.load(f)
                    
                req_fields = ['total_samples', 'movement_duration_s', 'max_velocity_mag_m_s', 
                              'max_acceleration_mag_m_s2', 'safe_for_wafer']
                
                if all(k in report for k in req_fields):
                    ts = int(report['total_samples'])
                    # Check logical consistency
                    agent_max_a = float(report['max_acceleration_mag_m_s2'])
                    expected_safe = agent_max_a < 15.0
                    actual_safe = bool(report['safe_for_wafer'])
                    
                    if abs(ts - num_samples) <= 5 and expected_safe == actual_safe:
                        score += 15
                        feedback.append("✅ Safety report JSON is valid and logically correct.")
                    else:
                        feedback.append("⚠️ Safety report has logical flaws or mismatches CSV row count.")
                else:
                    feedback.append("❌ Safety report is missing required fields.")
            except Exception as e:
                feedback.append(f"❌ Failed to parse safety report JSON: {e}")

        # Final Evaluation
        passed = (score >= 70) and kinematic_consistency_met
        
        return {
            "passed": passed,
            "score": min(score, 100),
            "feedback": " | ".join(feedback)
        }

    finally:
        # Cleanup temp files
        for tmp in [tmp_res, tmp_csv, tmp_json]:
            if os.path.exists(tmp.name):
                try:
                    os.unlink(tmp.name)
                except Exception:
                    pass