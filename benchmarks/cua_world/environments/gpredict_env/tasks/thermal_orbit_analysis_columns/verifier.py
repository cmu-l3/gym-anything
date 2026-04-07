#!/usr/bin/env python3
"""
Verifier for thermal_orbit_analysis_columns task.

Task:
  1. Delete Amateur.mod
  2. Create Thermal_Monitor.mod with ISS (25544) and CSS (48274)
  3. Configure to show ONLY a List View (no map/polar)
  4. Customize columns: add Vis, Orbit, Alt, Footp; remove Az, El, Dir
  5. Enable Imperial units globally

Scoring System (100 points, pass >= 70):
  Programmatic Checks (50 points):
    - Thermal_Monitor module created with correct satellites: 20 pts
    - Amateur module successfully deleted: 15 pts
    - Imperial units enabled in config: 15 pts
  VLM Visual Checks (50 points):
    - Layout is exclusively a List View (no maps/radars): 20 pts
    - Columns customized (Az/El removed, Vis/Alt/Orbit/Footp present): 30 pts
"""

import json
import os
import tempfile
import logging

# Import VLM utilities gracefully
try:
    from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False
    logging.warning("VLM utilities not available. Visual verification will fail.")

logger = logging.getLogger(__name__)

VLM_PROMPT = """
Analyze the provided screenshots of the GPredict satellite tracking software interface.
This task required the user to customize an orbital tracking dashboard for thermal engineers.

Analyze the FINAL visual state (the last screenshot) and evaluate these specific criteria:

1. List-Only Layout: Does the main module tracking window display ONLY a tabular data list? (There should be no world map view and no circular polar radar plot visible).
2. Forbidden Columns Removed: Look closely at the table column headers. Are "Az" (Azimuth), "El" (Elevation), and "Dir" (Direction) COMPLETELY REMOVED from the headers?
3. Required Columns Present: Are the "Vis" (Visibility/Eclipse), "Orbit", "Alt" (Altitude), and "Footp" (Footprint) columns present in the table headers?
4. Imperial Units Visible: Look at the values in the "Alt" (Altitude) column. Do they end in "mi" (miles) indicating Imperial units, rather than "km" (kilometers)?

Respond ONLY with a valid JSON object matching this schema:
{
    "is_list_only": boolean,
    "forbidden_cols_removed": boolean,
    "required_cols_present": boolean,
    "imperial_units_visible": boolean,
    "confidence": "high|medium|low",
    "reasoning": "Brief explanation of what you see in the headers and layout"
}
"""

def verify_thermal_orbit_analysis(traj, env_info, task_info):
    """
    Verify the thermal orbit analysis task using hybrid programmatic and VLM signals.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    score = 0
    feedback_parts = []

    # ================================================================
    # 1. PROGRAMMATIC VERIFICATION
    # ================================================================
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/thermal_orbit_result.json", temp_path)
            with open(temp_path, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not read result file: {e}"}
    finally:
        if os.path.exists(temp_path):
            os.unlink(temp_path)

    # Check Module Deletion (15 pts)
    if not result.get('amateur_exists', True):
        score += 15
        feedback_parts.append("Amateur module deleted")
    else:
        feedback_parts.append("Amateur module was NOT deleted")

    # Check Module Creation & Satellites (20 pts)
    thermal_exists = result.get('thermal_exists', False)
    if thermal_exists:
        has_iss = result.get('thermal_has_iss', False)
        has_css = result.get('thermal_has_css', False)
        
        if has_iss and has_css:
            score += 20
            feedback_parts.append("Thermal_Monitor module created with ISS and CSS")
        elif has_iss or has_css:
            score += 10
            feedback_parts.append("Thermal_Monitor module created, but missing a space station")
        else:
            feedback_parts.append("Thermal_Monitor module created, but missing both space stations")
    else:
        feedback_parts.append("Thermal_Monitor module NOT created")

    # Check Imperial Units Config (15 pts)
    if result.get('imperial_units_enabled', False):
        score += 15
        feedback_parts.append("Imperial units enabled in gpredict.cfg")
    else:
        feedback_parts.append("Imperial units NOT enabled in config")

    # ================================================================
    # 2. VLM VISUAL VERIFICATION
    # ================================================================
    vlm_results_str = ""
    if VLM_AVAILABLE and thermal_exists:
        frames = sample_trajectory_frames(traj, n=3)
        final_frame = get_final_screenshot(traj)
        images = frames + [final_frame] if final_frame else frames

        if images:
            try:
                vlm_response = query_vlm(images=images, prompt=VLM_PROMPT)
                vlm_data = vlm_response.get("parsed", {})
                
                # Check List Only Layout (20 pts)
                # (Fallback to config if VLM fails/rejects, but VLM preferred)
                if vlm_data.get("is_list_only"):
                    score += 20
                    feedback_parts.append("VLM: Layout is exclusively List View")
                else:
                    # Programmatic fallback
                    if result.get("thermal_showmap") == "0" and result.get("thermal_showpolarplot") == "0":
                        score += 15
                        feedback_parts.append("Config: Layout flags show list-only, but VLM disagreed")
                    else:
                        feedback_parts.append("VLM: Map or Polar views still visible")

                # Check Column Customization (30 pts)
                cols_removed = vlm_data.get("forbidden_cols_removed", False)
                cols_present = vlm_data.get("required_cols_present", False)
                
                if cols_removed and cols_present:
                    score += 30
                    feedback_parts.append("VLM: Columns correctly customized")
                elif cols_present:
                    score += 15
                    feedback_parts.append("VLM: Thermal columns added, but Az/El not removed")
                elif cols_removed:
                    score += 15
                    feedback_parts.append("VLM: Az/El removed, but thermal columns missing")
                else:
                    feedback_parts.append("VLM: List columns were not customized correctly")
                
                vlm_results_str = f" [VLM Reasoning: {vlm_data.get('reasoning', 'None')}]"
                
            except Exception as e:
                logger.error(f"VLM verification failed: {e}")
                feedback_parts.append("VLM Error")
        else:
            feedback_parts.append("No screenshots for VLM")
    else:
        if not thermal_exists:
            feedback_parts.append("VLM skipped (Thermal module not created)")
        else:
            feedback_parts.append("VLM Unavailable")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) + vlm_results_str
    }