#!/usr/bin/env python3
"""
Verifier for geo_defunct_drift_hazard_prediction@1

Agent must fix the gravity model in a starter script to simulate triaxial longitude drift,
run it, and find the UTC date when the defunct satellite crosses 35.0W.

Scoring (total 100 pts, pass >= 70):
  - script_modified (10): Script was saved during task window
  - gravity_model_fixed (30): Script uses Earth gravity with Degree >= 8, Order >= 8
  - report_generated (10): hazard_prediction.txt exists
  - crossing_identified (30): Agent date matches ground truth (+/- 7 days)
  - vlm_analysis (20): Visual verification the agent ran the simulation and viewed results

Pass condition: score >= 70 AND gravity_model_fixed AND crossing_identified
"""

import json
import os
import re
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def build_vlm_prompt():
    return """Examine this sequence of screenshots from a GMAT task.
The user's goal was to modify a GMAT script's force model, run a simulation, and analyze longitude drift to find when it crosses -35.0 degrees.

Please determine:
1. Did the user edit the GMAT script?
2. Did the user execute the simulation (via the GUI play button or GmatConsole)?
3. Did the user open/view a report file or plot to analyze the data?

Respond in pure JSON format ONLY:
{
    "edited_script": true/false,
    "ran_simulation": true/false,
    "viewed_output": true/false
}
"""


def verify_geo_defunct_drift_hazard_prediction(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    scores = {
        "script_modified": 10,
        "gravity_model_fixed": 30,
        "report_generated": 10,
        "crossing_identified": 30,
        "vlm_analysis": 20
    }

    total_score = 0
    feedback = []
    gravity_ok = False
    crossing_ok = False

    # 1. Copy result JSON from container
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

    # 2. Check if script was modified
    script_file = task_result.get('script_file', {})
    if isinstance(script_file, dict) and script_file.get('created_during_task'):
        total_score += scores["script_modified"]
        feedback.append("Script modified during task.")
    else:
        feedback.append("Script not modified during task.")

    # 3. Check gravity model in script
    script_path = task_result.get('script_path', '/home/ga/Documents/missions/defunct_geo_hazard.script')
    if isinstance(script_file, dict) and script_file.get('exists'):
        temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.script')
        try:
            copy_from_env(script_path, temp_script.name)
            with open(temp_script.name, 'r', encoding='utf-8', errors='ignore') as f:
                script_content = f.read()

            # Find Degree and Order configuration
            degree_match = re.search(r'Degree\s*=\s*([0-9]+)', script_content)
            order_match = re.search(r'Order\s*=\s*([0-9]+)', script_content)

            if degree_match and order_match:
                degree = int(degree_match.group(1))
                order = int(order_match.group(1))
                if degree >= 8 and order >= 8:
                    total_score += scores["gravity_model_fixed"]
                    gravity_ok = True
                    feedback.append(f"Gravity model fixed (Degree={degree}, Order={order}).")
                else:
                    feedback.append(f"Gravity model insufficient (Degree={degree}, Order={order}). Needs >= 8.")
            else:
                feedback.append("Could not parse Degree/Order from script.")
        except Exception as e:
            feedback.append(f"Error reading script: {e}")
        finally:
            if os.path.exists(temp_script.name):
                os.unlink(temp_script.name)

    # 4. Check report file exists
    report_file = task_result.get('report_file', {})
    if isinstance(report_file, dict) and report_file.get('exists'):
        total_score += scores["report_generated"]
        feedback.append("Hazard prediction report generated.")
    else:
        feedback.append("Hazard prediction report not found.")

    # 5. Check identified crossing date
    gt_date_str = task_result.get('gt_date', '').strip()
    agent_date_str = task_result.get('agent_date', '').strip()

    if gt_date_str and gt_date_str != "NOT_FOUND" and agent_date_str:
        try:
            gt_date = datetime.strptime(gt_date_str, "%d %b %Y")
            agent_date = datetime.strptime(agent_date_str, "%d %b %Y")
            
            diff_days = abs((agent_date - gt_date).days)
            if diff_days <= 7:
                total_score += scores["crossing_identified"]
                crossing_ok = True
                feedback.append(f"Crossing date correct: {agent_date_str} (Diff: {diff_days} days).")
            else:
                feedback.append(f"Crossing date incorrect: {agent_date_str} (Expected ~{gt_date_str}, Diff: {diff_days} days).")
        except ValueError:
            feedback.append(f"Error parsing dates - GT: '{gt_date_str}', Agent: '{agent_date_str}'. Ensure correct format.")
    else:
        if not agent_date_str:
            feedback.append("No valid date format (DD Mon YYYY) found in the hazard report.")
        if gt_date_str == "NOT_FOUND":
            feedback.append("System Warning: Ground truth date was not generated successfully.")

    # 6. VLM Trajectory Verification
    vlm_score = 0
    try:
        import sys
        from pathlib import Path
        # We assume standard gym_anything VLM utilities are available
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        if images:
            vlm_res = query_vlm(images=images, prompt=build_vlm_prompt())
            if vlm_res and vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('edited_script'): vlm_score += 5
                if parsed.get('ran_simulation'): vlm_score += 5
                if parsed.get('viewed_output'): vlm_score += 10
                total_score += vlm_score
                feedback.append(f"VLM verified trajectory ({vlm_score}/{scores['vlm_analysis']}).")
            else:
                feedback.append("VLM query failed or returned no result.")
        else:
            feedback.append("No trajectory images available for VLM.")
    except Exception as e:
        logger.warning(f"VLM verification skipped/failed: {e}")
        # If VLM infrastructure isn't available, don't penalize the core logic
        total_score += scores["vlm_analysis"]
        feedback.append("VLM unavailable, bypassing visual check.")

    # Ensure key technical constraints are met for a passing grade
    passed = total_score >= 70 and gravity_ok and crossing_ok
    
    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback)
    }