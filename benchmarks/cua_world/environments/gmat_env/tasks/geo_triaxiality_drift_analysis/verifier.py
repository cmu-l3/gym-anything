#!/usr/bin/env python3
"""
Verifier for geo_triaxiality_drift_analysis@1

Agent must simulate the natural drift of a GEO satellite caused by Earth's triaxiality.
Using tesseral harmonics (Degree/Order >= 4), a satellite at 350E will accelerate eastwards 
towards the stable node at ~75E. Over 730 days, it should reach between 30E and 90E.
If a Point Mass model is used, it will stay exactly at 350E.

Scoring (total 100 pts, pass >= 60):
  - script_created (10): Script created during task window
  - force_model_correct (20): Gravity model Degree >= 4 and Order >= 4
  - initial_state_correct (20): Initialized at SMA=42164.17 and Longitude=350.0 (or -10.0)
  - propagation_correct (10): Propagated for exactly 730 days
  - report_generated (10): Report contains expected fields
  - final_longitude_valid (30): Final reported longitude is in [30.0, 90.0]

Pass condition: score >= 60 AND final_longitude_valid (proves physics worked).
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_geo_triaxiality_drift_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_sma = metadata.get('expected_sma_km', 42164.17)
    expected_duration = metadata.get('expected_duration_days', 730)
    min_deg_ord = metadata.get('min_degree_order', 4)
    fin_lon_min = metadata.get('final_longitude_min_deg', 30.0)
    fin_lon_max = metadata.get('final_longitude_max_deg', 90.0)

    scores = {
        "script_created": 10,
        "force_model_correct": 20,
        "initial_state_correct": 20,
        "propagation_correct": 10,
        "report_generated": 10,
        "final_longitude_valid": 30
    }

    total_score = 0
    feedback = []
    physics_passed = False

    # 1. Load task result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Check if files were created
    script_file = task_result.get('script_file', {})
    report_file = task_result.get('report_file', {})
    
    if isinstance(script_file, dict) and script_file.get('created_during_task'):
        total_score += scores["script_created"]
        feedback.append("Script created during task window.")
    else:
        feedback.append("Script not created or not modified during task.")

    # 3. Analyze the Report
    if isinstance(report_file, dict) and report_file.get('created_during_task'):
        total_score += scores["report_generated"]
        feedback.append("Analysis report generated.")
    else:
        feedback.append("Analysis report missing.")

    try:
        init_lon = float(task_result.get('reported_initial_lon', 0))
    except ValueError:
        init_lon = 0.0

    try:
        final_lon = float(task_result.get('reported_final_lon', 0))
    except ValueError:
        final_lon = 0.0

    # Handle modulo 360 for final longitude if agent outputs large accumulated angles
    final_lon_mod = final_lon % 360.0

    if fin_lon_min <= final_lon_mod <= fin_lon_max:
        total_score += scores["final_longitude_valid"]
        physics_passed = True
        feedback.append(f"Final longitude ({final_lon_mod:.2f} deg) shows correct triaxiality drift.")
    elif abs(final_lon_mod - 350.0) < 5.0 or abs(final_lon_mod - (-10.0)) < 5.0:
        feedback.append(f"Final longitude ({final_lon_mod:.2f} deg) indicates no drift. Point Mass model likely used.")
    else:
        feedback.append(f"Final longitude ({final_lon_mod:.2f} deg) is outside expected drifted range [{fin_lon_min}, {fin_lon_max}].")

    # 4. Analyze the Script for settings
    script_path = task_result.get('script_path', '/home/ga/GMAT_output/geo_drift_sim.script')
    if isinstance(script_file, dict) and script_file.get('exists'):
        temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.script')
        try:
            copy_from_env(script_path, temp_script.name)
            with open(temp_script.name, 'r', encoding='utf-8', errors='ignore') as f:
                script_content = f.read()

            # Check Force Model
            degree_match = re.search(r'\.Degree\s*=\s*([0-9]+)', script_content)
            order_match = re.search(r'\.Order\s*=\s*([0-9]+)', script_content)
            
            degree = int(degree_match.group(1)) if degree_match else 0
            order = int(order_match.group(1)) if order_match else 0
            
            if degree >= min_deg_ord and order >= min_deg_ord:
                total_score += scores["force_model_correct"]
                feedback.append(f"Force model Degree/Order ({degree}/{order}) is sufficient for tesseral harmonics.")
            else:
                feedback.append(f"Force model Degree/Order ({degree}/{order}) is too low to capture triaxiality.")

            # Check Initial State
            has_sma = bool(re.search(r'42164', script_content))
            has_lon = bool(re.search(r'(350|10)', script_content))
            uses_earthfixed = bool(re.search(r'EarthFixed', script_content))
            
            if has_sma and has_lon and uses_earthfixed:
                total_score += scores["initial_state_correct"]
                feedback.append("Initial state set with EarthFixed coordinates and appropriate SMA/Longitude.")
            elif has_sma and has_lon:
                total_score += scores["initial_state_correct"] // 2
                feedback.append("Initial SMA and Longitude numbers found, but EarthFixed coordinate system not explicitly detected.")
            else:
                feedback.append("Initial state configuration (SMA or Longitude) missing or incorrect.")

            # Check Propagation Duration
            if bool(re.search(r'ElapsedDays\s*=\s*730', script_content)):
                total_score += scores["propagation_correct"]
                feedback.append("Propagation correctly set to 730 days.")
            else:
                feedback.append("Propagation duration not explicitly 730 days.")
                
        except Exception as e:
            feedback.append(f"Failed to parse script content: {e}")
        finally:
            if os.path.exists(temp_script.name):
                os.unlink(temp_script.name)

    # 5. Optional VLM Check for Anti-Gaming
    try:
        import sys
        from pathlib import Path
        sys.path.insert(0, str(Path(__file__).parent.parent))
        from vlm_utils import sample_trajectory_frames, query_vlm
        
        frames = sample_trajectory_frames(traj, n=3)
        if frames:
            prompt = "Is the user interacting with the NASA GMAT graphical interface to set up an orbit propagation? Answer briefly."
            vlm_res = query_vlm(prompt=prompt, image=frames[-1])
            # We don't necessarily penalize if VLM fails, but we log it.
            logger.info(f"VLM Trajectory Check: {vlm_res}")
    except Exception as e:
        logger.warning(f"VLM trajectory check skipped or failed: {e}")

    # Determine final pass/fail
    passed = (total_score >= 60) and physics_passed

    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback)
    }