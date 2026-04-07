#!/usr/bin/env python3
"""
Verifier for ocean_gyre_thermal_asymmetry task.

Scoring criteria (100 pts total, pass threshold = 70):
  1. Map Plot Exported (15 pts): north_atlantic_feb.png >15KB, newer than task_start.
  2. Report Formatted (10 pts): All requested keys exist in thermal_asymmetry_report.txt.
  3. Subtropical Temps (15 pts): 30N values fall in validated climatology ranges.
  4. Mid-latitude Temps (15 pts): 45N values fall in validated climatology ranges.
  5. Subtropical Logic (15 pts): Identifies WEST as warmer.
  6. Mid-latitude Logic (15 pts): Identifies EAST as warmer.
  7. VLM Workflow Check (15 pts): Trajectory frames show the agent interacting 
     with Panoply data arrays or plot tooltips to extract data.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are evaluating an agent performing a data extraction task in NASA Panoply.
The agent was asked to find the exact Sea Surface Temperature at specific coordinates.

Look at these trajectory frames and determine:
Did the agent actively interrogate the data to find specific values? 
Evidence of this includes:
- Hovering the mouse cursor over the map to read the 'Data' tooltip at the bottom of the plot window.
- Opening the "Array 1" or "Array 2" tab to look at the raw spreadsheet/matrix of numerical data.
- Adjusting the time step to February (Index 1 or 'Feb').

Respond in JSON format:
{
    "interrogated_data": true/false,
    "reasoning": "Brief explanation of what the agent did to find the values."
}
"""

def verify_ocean_gyre_thermal_asymmetry(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # 1. Retrieve the parsed result JSON
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env('/tmp/ocean_gyre_thermal_asymmetry_result.json', tmp.name)
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
    metadata = task_info.get('metadata', {})
    bounds = metadata.get('validation_bounds', {})
    logic = metadata.get('expected_logic', {})

    # ----------------------------------------------------------------
    # Criterion 1: Map Plot Exported (15 pts)
    # ----------------------------------------------------------------
    map_exists = result.get('map_plot_exists', False)
    map_mtime = int(result.get('map_plot_mtime', 0))
    map_size = int(result.get('map_plot_size', 0))

    if map_exists and map_mtime >= task_start and map_size >= 15000:
        score += 15
        feedback.append(f"Map plot exported successfully ({map_size//1024} KB).")
    elif map_exists and map_mtime >= task_start:
        score += 5
        feedback.append(f"Map plot exported but small ({map_size} bytes).")
    else:
        feedback.append("Map plot missing or not created during task.")

    # ----------------------------------------------------------------
    # Criterion 2: Report Formatted (10 pts)
    # ----------------------------------------------------------------
    report_exists = result.get('report_exists', False)
    report_mtime = int(result.get('report_mtime', 0))
    
    # Check if all keys had some extracted data
    vals = [
        result.get('sub_west'), result.get('sub_east'),
        result.get('mid_west'), result.get('mid_east'),
        result.get('sub_logic'), result.get('mid_logic')
    ]
    has_all_keys = all(v != '' for v in vals)

    if report_exists and report_mtime >= task_start:
        if has_all_keys:
            score += 10
            feedback.append("Report successfully parsed with all keys present.")
        else:
            score += 5
            feedback.append("Report present but some keys are missing or malformed.")
    else:
        feedback.append("Report missing or not created during task.")

    # Helper function to validate floats within bounds
    def check_bound(val_str, bound_key):
        if not val_str:
            return False, 0.0
        try:
            val = float(val_str)
            b = bounds.get(bound_key, {"min": 0, "max": 0})
            if b["min"] <= val <= b["max"]:
                return True, val
            return False, val
        except ValueError:
            return False, None

    # ----------------------------------------------------------------
    # Criterion 3: Subtropical Temps (15 pts)
    # ----------------------------------------------------------------
    w_30_ok, w_30_v = check_bound(result.get('sub_west'), 'SUB_WEST_30N_78W_C')
    e_30_ok, e_30_v = check_bound(result.get('sub_east'), 'SUB_EAST_30N_12W_C')
    
    if w_30_ok and e_30_ok:
        score += 15
        feedback.append(f"Subtropical temps physically plausible ({w_30_v}°C and {e_30_v}°C).")
    elif w_30_ok or e_30_ok:
        score += 7
        feedback.append("Partial match on Subtropical temps.")
    else:
        feedback.append(f"Subtropical temps out of bounds or missing (Extracted: W={w_30_v}, E={e_30_v}).")

    # ----------------------------------------------------------------
    # Criterion 4: Mid-latitude Temps (15 pts)
    # ----------------------------------------------------------------
    w_45_ok, w_45_v = check_bound(result.get('mid_west'), 'MID_WEST_45N_60W_C')
    e_45_ok, e_45_v = check_bound(result.get('mid_east'), 'MID_EAST_45N_12W_C')
    
    if w_45_ok and e_45_ok:
        score += 15
        feedback.append(f"Mid-latitude temps physically plausible ({w_45_v}°C and {e_45_v}°C).")
    elif w_45_ok or e_45_ok:
        score += 7
        feedback.append("Partial match on Mid-latitude temps.")
    else:
        feedback.append(f"Mid-latitude temps out of bounds or missing (Extracted: W={w_45_v}, E={e_45_v}).")

    # ----------------------------------------------------------------
    # Criterion 5: Subtropical Logic (15 pts)
    # ----------------------------------------------------------------
    sub_logic = result.get('sub_logic', '')
    if 'WEST' in sub_logic:
        score += 15
        feedback.append("Subtropical logic correct (WEST is warmer).")
    else:
        feedback.append(f"Subtropical logic incorrect (Got '{sub_logic}', expected WEST).")

    # ----------------------------------------------------------------
    # Criterion 6: Mid-latitude Logic (15 pts)
    # ----------------------------------------------------------------
    mid_logic = result.get('mid_logic', '')
    if 'EAST' in mid_logic:
        score += 15
        feedback.append("Mid-latitude logic correct (EAST is warmer).")
    else:
        feedback.append(f"Mid-latitude logic incorrect (Got '{mid_logic}', expected EAST).")

    # ----------------------------------------------------------------
    # Criterion 7: VLM Workflow Check (15 pts)
    # ----------------------------------------------------------------
    if query_vlm:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        # Sample frames to see if they interacted with the array/tooltips
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        if final:
            frames.append(final)
            
        vlm_res = query_vlm(prompt=VLM_PROMPT, images=frames)
        if vlm_res.get("success"):
            parsed = vlm_res.get("parsed", {})
            if parsed.get("interrogated_data", False):
                score += 15
                feedback.append("VLM confirms agent interrogated the data arrays/tooltips.")
            else:
                feedback.append(f"VLM did not detect data interrogation: {parsed.get('reasoning', '')}")
        else:
            feedback.append("VLM query failed, skipping workflow verification points.")
    else:
        feedback.append("VLM not available; skipping workflow verification points.")

    # ----------------------------------------------------------------
    # Final Result
    # ----------------------------------------------------------------
    # Need at least 70 to pass. 
    # Must have actually exported the report with at least some correct physical values
    key_criteria_met = report_exists and (w_30_ok or e_30_ok or w_45_ok or e_45_ok)
    
    passed = score >= 70 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "w_30_ok": w_30_ok,
            "e_30_ok": e_30_ok,
            "w_45_ok": w_45_ok,
            "e_45_ok": e_45_ok
        }
    }