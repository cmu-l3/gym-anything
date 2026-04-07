#!/usr/bin/env python3
"""
Verifier for sh_frost_viticulture_planning task.

Occupation: Agricultural Meteorologist / Viticultural Climate Advisor
Industry: Precision Agriculture / Viticulture
Difficulty: hard

Verification Strategy:
  1. July SH temperature plot exported (exists, size >= 15KB, newer than task start).
  2. June SH temperature plot exported (exists, size >= 15KB, newer than task start).
  3. Report completeness (contains required parsed fields).
  4. Scientific correctness:
     - ANALYSIS_SEASON must reflect Southern Hemisphere winter (JJA).
     - COLDEST_MONTH should correctly be July.
     - HIGHEST_RISK_REGION should be Mendoza (due to continental/elevation effects).
  5. VLM trajectory verification: confirms agent actually used Panoply visually.

If VLM is unavailable, scores are scaled across the 4 programmatic criteria.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_sh_frost_viticulture_planning(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Retrieve result JSON from the environment
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env('/tmp/sh_frost_viticulture_planning_result.json', tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result JSON: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback = []
    task_start = int(result.get('task_start', 0))

    # Check if VLM is available
    query_vlm = env_info.get('query_vlm')
    use_vlm = False
    images = []
    
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=3)
            final = get_final_screenshot(traj)
            if frames or final:
                images = frames + [final] if final else frames
                use_vlm = True
        except ImportError:
            logger.warning("gym_anything.vlm not available, skipping VLM check.")

    # Base weights based on VLM availability
    w_july = 20 if use_vlm else 25
    w_june = 20 if use_vlm else 25
    w_rep  = 20 if use_vlm else 25
    w_sci  = 20 if use_vlm else 25
    w_vlm  = 20 if use_vlm else 0

    # ----------------------------------------------------------------
    # Criterion 1: July SH temperature plot exported
    # ----------------------------------------------------------------
    july_exists = result.get('july_plot_exists', False)
    july_mtime = int(result.get('july_plot_mtime', 0))
    july_size = int(result.get('july_plot_size', 0))

    if july_exists and july_mtime >= task_start and july_size >= 15000:
        score += w_july
        feedback.append(f"July plot exported ({july_size} bytes)")
    elif july_exists and july_mtime >= task_start and july_size >= 5000:
        score += w_july * 0.5
        feedback.append(f"July plot present but small ({july_size} bytes)")
    else:
        feedback.append(f"July plot missing or stale (exists={july_exists}, size={july_size})")

    # ----------------------------------------------------------------
    # Criterion 2: June SH temperature plot exported
    # ----------------------------------------------------------------
    june_exists = result.get('june_plot_exists', False)
    june_mtime = int(result.get('june_plot_mtime', 0))
    june_size = int(result.get('june_plot_size', 0))

    if june_exists and june_mtime >= task_start and june_size >= 15000:
        score += w_june
        feedback.append(f"June plot exported ({june_size} bytes)")
    elif june_exists and june_mtime >= task_start and june_size >= 5000:
        score += w_june * 0.5
        feedback.append(f"June plot present but small ({june_size} bytes)")
    else:
        feedback.append(f"June plot missing or stale (exists={june_exists}, size={june_size})")

    # ----------------------------------------------------------------
    # Criterion 3: Frost Risk Report Completeness
    # ----------------------------------------------------------------
    report_exists = result.get('report_exists', False)
    report_mtime = int(result.get('report_mtime', 0))
    
    season = result.get('analysis_season', '').strip().upper()
    coldest = result.get('coldest_month', '').strip().upper()
    highest = result.get('highest_risk_region', '').strip().upper()
    mendoza = result.get('mendoza_risk', '').strip()
    cape = result.get('western_cape_risk', '').strip()
    aus = result.get('south_australia_risk', '').strip()

    has_core_fields = bool(season) and bool(coldest) and bool(highest)
    has_risk_fields = bool(mendoza) and bool(cape) and bool(aus)

    if report_exists and report_mtime >= task_start:
        if has_core_fields and has_risk_fields:
            score += w_rep
            feedback.append("Frost risk report is complete with all required fields")
        elif has_core_fields or has_risk_fields:
            score += w_rep * 0.5
            feedback.append("Frost risk report is partially complete (missing some fields)")
        else:
            feedback.append("Frost risk report exists but is missing key fields")
    else:
        feedback.append("Frost risk report missing or stale")

    # ----------------------------------------------------------------
    # Criterion 4: Scientific Correctness
    # ----------------------------------------------------------------
    correct_sci = 0
    if "JJA" in season:
        correct_sci += 1
    if "JULY" in coldest or "JUL" in coldest:
        correct_sci += 1
    if "MENDOZA" in highest or "ARGENTINA" in highest:
        correct_sci += 1

    if correct_sci == 3:
        score += w_sci
        feedback.append("Scientific reasoning correct: Identified SH Winter (JJA), July as coldest, and Mendoza as highest risk.")
    elif correct_sci > 0:
        score += (w_sci * (correct_sci / 3.0))
        feedback.append(f"Scientific reasoning partially correct ({correct_sci}/3 key points).")
    else:
        feedback.append("Scientific reasoning incorrect (did not identify JJA, July, or Mendoza).")

    # ----------------------------------------------------------------
    # Criterion 5: VLM Verification (if available)
    # ----------------------------------------------------------------
    if use_vlm and images:
        vlm_prompt = """
        Review these screenshots from a computer agent's trajectory. 
        Did the agent use the NASA Panoply application to view geographic plots (maps with coastlines/lat-lon grids)?
        Respond with a JSON object containing a single boolean key:
        {"used_panoply_maps": true/false}
        """
        try:
            vlm_res = query_vlm(images=images, prompt=vlm_prompt)
            if vlm_res and vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('used_panoply_maps', False):
                    score += w_vlm
                    feedback.append("VLM confirmed visual interaction with Panoply maps.")
                else:
                    feedback.append("VLM did not detect interaction with Panoply geographic maps.")
            else:
                feedback.append("VLM verification failed to parse.")
        except Exception as e:
            logger.error(f"VLM exception: {e}")
            feedback.append("VLM verification encountered an error.")

    # Ensure max score doesn't exceed 100 due to float math
    score = min(100, round(score))
    
    # Passing requires basic artifact creation and some scientific reasoning
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }