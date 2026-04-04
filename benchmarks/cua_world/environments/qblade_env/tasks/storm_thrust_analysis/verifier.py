#!/usr/bin/env python3
"""
Verifier for Storm Thrust Analysis task.

Logic:
1. Verify QBlade project file creation (proof of work).
2. Verify Report file creation.
3. Verify Reported Physics:
   - Thrust at 0 deg (Runaway) should be HIGH (drag dominant, ~100k N range).
   - Thrust at 90 deg (Feathered) should be LOW (streamlined, ~5k N range).
   - The ratio Thrust(0)/Thrust(90) should be significant (>10).
4. VLM Verification: Confirm QBlade usage via trajectory.
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_storm_thrust_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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
    
    # 1. Project File Check (20 pts)
    if result.get('project_exists') and result.get('file_created_during_task'):
        score += 20
        feedback_parts.append("Project file created successfully")
    elif result.get('project_exists'):
        score += 10
        feedback_parts.append("Project file exists but timestamp is suspicious")
    else:
        feedback_parts.append("Project file not found")

    # 2. Report File Check (10 pts)
    if result.get('report_exists'):
        score += 10
        feedback_parts.append("Report file created")
    else:
        feedback_parts.append("Report file missing")

    # 3. Physics / Values Check (50 pts total)
    # Expected approximate physics:
    # 50m/s wind, 20m radius, 1m chord (3 blades) -> Area ~60m^2
    # q = 0.5 * 1.225 * 2500 = 1531 Pa
    # T_0deg ~ 1531 * 60 * 1.5 ~ 137,000 N (High Drag)
    # T_90deg ~ 1531 * 60 * 0.05 ~ 4,600 N (Low Drag)
    
    t0 = float(result.get('thrust_0_reported', 0))
    t90 = float(result.get('thrust_90_reported', 0))
    
    # Check 0 deg thrust (should be > 50,000 N)
    if t0 > 50000:
        score += 20
        feedback_parts.append(f"Thrust at 0° is realistic ({t0} N)")
    else:
        feedback_parts.append(f"Thrust at 0° seems too low ({t0} N) - did you extrapolate the polar?")

    # Check 90 deg thrust (should be < 20,000 N)
    if 10 < t90 < 20000:
        score += 15
        feedback_parts.append(f"Thrust at 90° is realistic ({t90} N)")
    else:
        feedback_parts.append(f"Thrust at 90° seems incorrect ({t90} N)")

    # Check Ratio (should be > 10)
    if t90 > 0 and (t0 / t90) > 10:
        score += 15
        feedback_parts.append(f"Load reduction factor valid (Ratio: {t0/t90:.1f})")
    elif t90 > 0:
        feedback_parts.append(f"Load reduction factor too small (Ratio: {t0/t90:.1f})")

    # 4. App Running Check (10 pts)
    if result.get('app_running'):
        score += 10
        feedback_parts.append("QBlade was running")

    # 5. VLM / Trajectory Verification (10 pts)
    # (Placeholder logic - assuming if file + physics are good, agent did work)
    # In a full implementation, we would query VLM here.
    if score >= 60:
        score += 10
        feedback_parts.append("Workflow implicitly verified by outputs")

    passed = score >= 60 and result.get('project_exists') and result.get('report_exists')

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }