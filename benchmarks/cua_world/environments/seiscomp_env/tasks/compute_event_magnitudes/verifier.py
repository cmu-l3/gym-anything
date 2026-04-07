#!/usr/bin/env python3
"""
Verifier for compute_event_magnitudes task.
Evaluates both the SeisComP database state and the generated report file.
Includes VLM evaluation of the trajectory for anti-gaming.
"""

import os
import json
import re
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_compute_event_magnitudes(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get results from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    event_id = result.get("event_id", "")
    amp_count = int(result.get("final_amp_count", 0))
    mag_count = int(result.get("final_mag_count", 0))
    db_mb_val = result.get("db_mb_val", "")
    db_mlv_val = result.get("db_mlv_val", "")
    report_exists = result.get("report_exists", False)
    report_content = result.get("report_content", "")
    file_created_during_task = result.get("file_created_during_task", False)

    # 1. Verify Amplitudes and Magnitudes created in DB (40 points)
    db_success = False
    if amp_count > 0:
        score += 15
        feedback_parts.append(f"Amplitudes computed in DB ({amp_count} found).")
    else:
        feedback_parts.append("No amplitudes found in DB.")

    if mag_count > 0 and (db_mb_val or db_mlv_val):
        score += 25
        db_success = True
        feedback_parts.append(f"Magnitudes computed in DB (mb: {db_mb_val or 'N/A'}, MLv: {db_mlv_val or 'N/A'}).")
    else:
        feedback_parts.append("Magnitudes (mb/MLv) not found in DB.")

    # 2. Verify Report File (40 points)
    report_success = False
    if report_exists and file_created_during_task:
        score += 10
        feedback_parts.append("Report file created.")
        
        # Check Event ID
        if event_id and event_id in report_content:
            score += 10
            feedback_parts.append("Report contains correct Event ID.")
        else:
            feedback_parts.append("Report missing correct Event ID.")

        # Parse magnitudes from report
        mb_match = re.search(r'mb:\s*([0-9.]+)', report_content)
        mlv_match = re.search(r'MLv:\s*([0-9.]+)', report_content)
        
        rep_mb = float(mb_match.group(1)) if mb_match else None
        rep_mlv = float(mlv_match.group(1)) if mlv_match else None
        
        mb_ok = False
        mlv_ok = False

        try:
            if rep_mb is not None and db_mb_val:
                if abs(rep_mb - float(db_mb_val)) <= 0.1:
                    score += 10
                    mb_ok = True
                    feedback_parts.append(f"Report mb matches DB ({rep_mb}).")
                else:
                    feedback_parts.append(f"Report mb ({rep_mb}) differs from DB ({db_mb_val}).")
            
            if rep_mlv is not None and db_mlv_val:
                if abs(rep_mlv - float(db_mlv_val)) <= 0.1:
                    score += 10
                    mlv_ok = True
                    feedback_parts.append(f"Report MLv matches DB ({rep_mlv}).")
                else:
                    feedback_parts.append(f"Report MLv ({rep_mlv}) differs from DB ({db_mlv_val}).")
        except ValueError:
            feedback_parts.append("Failed to parse magnitudes as floats.")
            
        if mb_ok and mlv_ok:
            report_success = True
    elif report_exists:
        feedback_parts.append("Report file exists but wasn't created during task run (stale).")
    else:
        feedback_parts.append("Report file not found.")

    # 3. VLM Trajectory Verification for Anti-Gaming (20 points)
    # Proves the agent actually used the terminal or UI to compute the values.
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        frames = sample_trajectory_frames(traj, n=4)
        
        prompt = """Look at these screenshots of an agent operating a seismology workstation.
Does the agent actively run terminal commands (like `scamp`, `scmag`, or `seiscomp exec`) OR use the SeisComP GUI application (`scolv`) to compute amplitudes and magnitudes?
Reply in JSON: {"workflow_observed": true/false, "tools_used": "terminal/scolv/none"}"""
        
        vlm_result = query_vlm(images=frames, prompt=prompt)
        
        if vlm_result.get("success"):
            parsed = vlm_result.get("parsed", {})
            if parsed.get("workflow_observed", False):
                score += 20
                feedback_parts.append(f"VLM verified computation workflow via {parsed.get('tools_used', 'system')}.")
            else:
                feedback_parts.append("VLM did not observe the computation workflow.")
        else:
            # Fallback if VLM fails but programmatic passes perfectly
            if db_success and report_success:
                score += 20
                feedback_parts.append("VLM query failed, but strict programmatic DB checks passed.")
    except Exception as e:
        logger.warning(f"VLM verification skipped or failed: {e}")
        # Give benefit of doubt if DB and file are perfectly matching
        if db_success and report_success:
            score += 20

    # Final Evaluation
    passed = (score >= 80) and db_success and report_success
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }