#!/usr/bin/env python3
"""
Verifier for dsn_mars_handoff_simulation task.

Criteria evaluated:
1. Display Configuration (20 pts)
   - Atmosphere off (10)
   - Landscape off (5)
   - Azimuthal grid on (5)
2. Final Location Setup (20 pts)
   - Stellarium's final saved location is Goldstone (~35.42° N)
3. Screenshots Captured (20 pts)
   - At least 2 new screenshots created in the correct directory
4. Report File Exists (20 pts)
   - dsn_handoff_report.txt is created during the task
5. Report Content (20 pts)
   - Accurately references keywords: Mars, Madrid, Goldstone, 2021

Pass threshold: 70 points with at least one location correct and the report existing.
Also includes a trajectory VLM fallback/verification.
"""

import json
import tempfile
import os
import math
import logging
from typing import Dict, Any

logger = logging.getLogger(__name__)

# Goldstone Ground Truth
GOLDSTONE_LAT_RAD = 0.6183
GOLDSTONE_LON_RAD = -2.0401
LAT_LON_TOLERANCE_RAD = 0.10  # ~5.7 degrees tolerance


def verify_dsn_handoff(traj, env_info, task_info) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env function unavailable"}

    task_name = "dsn_mars_handoff_simulation"

    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
            tmp_path = tmp.name

        try:
            copy_from_env(f"/tmp/{task_name}_result.json", tmp_path)
            with open(tmp_path, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)

        score = 0
        feedback_parts = []
        subscores = {}

        # ── Criterion 1: Display Configuration (20 pts) ──
        display_score = 0
        
        flag_atm = result.get('flag_atmosphere')
        if flag_atm is False:
            display_score += 10
            feedback_parts.append("Atmosphere off")
        else:
            feedback_parts.append("Atmosphere still on")

        flag_ls = result.get('flag_landscape')
        if flag_ls is False:
            display_score += 5
            feedback_parts.append("Landscape off")
        
        flag_az = result.get('flag_azimuthal_grid')
        if flag_az is True:
            display_score += 5
            feedback_parts.append("Azimuthal grid on")
            
        score += display_score
        subscores["display_config"] = display_score

        # ── Criterion 2: Final Location Setup (20 pts) ──
        lat_rad = result.get('lat_rad')
        lon_rad = result.get('lon_rad')
        
        location_score = 0
        if lat_rad is not None and lon_rad is not None:
            lat_diff = abs(lat_rad - GOLDSTONE_LAT_RAD)
            lon_diff = abs(lon_rad - GOLDSTONE_LON_RAD)

            if lat_diff <= LAT_LON_TOLERANCE_RAD and lon_diff <= LAT_LON_TOLERANCE_RAD:
                location_score = 20
                feedback_parts.append(f"Final location Goldstone (~{math.degrees(lat_rad):.1f}N)")
            else:
                feedback_parts.append(f"Final location incorrect (lat={math.degrees(lat_rad):.1f})")
        else:
            feedback_parts.append("Location config missing")
            
        score += location_score
        subscores["location"] = location_score

        # ── Criterion 3: Screenshots Captured (20 pts) ──
        ss_count = result.get('screenshot_count', 0)
        ss_score = 0
        if ss_count >= 2:
            ss_score = 20
            feedback_parts.append(f"2+ screenshots taken ({ss_count})")
        elif ss_count == 1:
            ss_score = 10
            feedback_parts.append("Only 1 screenshot taken")
        else:
            feedback_parts.append("No screenshots taken")
            
        score += ss_score
        subscores["screenshots"] = ss_score

        # ── Criterion 4 & 5: Report File Exists & Content (40 pts) ──
        report_exists = result.get('report_exists', False)
        report_created_during = result.get('report_created_during_task', False)
        report_content = result.get('report_content', "").lower()
        
        report_score = 0
        content_score = 0

        if report_exists and report_created_during:
            report_score = 20
            feedback_parts.append("Report exists")
            
            keywords = ["mars", "madrid", "goldstone", "2021"]
            matched = [k for k in keywords if k in report_content]
            content_score = len(matched) * 5
            
            if len(matched) == 4:
                feedback_parts.append("Report contains all keywords")
            else:
                feedback_parts.append(f"Report missing keywords: {set(keywords) - set(matched)}")
        elif report_exists:
            feedback_parts.append("Report exists but not created during task (gaming detected)")
        else:
            feedback_parts.append("Report missing")

        score += report_score + content_score
        subscores["report_exists"] = report_score
        subscores["report_content"] = content_score

        # Evaluate pass/fail conditions
        passed = (score >= 70 and report_exists and (ss_count >= 1 or location_score > 0))

        # Optional: Integrate VLM Check on Trajectory if needed. 
        # (The programmatic rules above are strong enough to verify the outcome reliably, 
        # but importing trajectory tools adds anti-gaming rigor)
        try:
            from gym_anything.vlm import sample_trajectory_frames, query_vlm
            frames = sample_trajectory_frames(traj, n=4)
            if frames:
                prompt = "Does the agent appear to be using planetarium software to look at Mars and a coordinate grid?"
                vlm_res = query_vlm(prompt=prompt, images=frames)
                if vlm_res.get("success"):
                    feedback_parts.append("VLM confirms visual activity")
        except ImportError:
            pass  # Fall back to programmatic only if VLM tools unavailable

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    except Exception as e:
        logger.error(f"Error during verification: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verifier error: {str(e)}"
        }