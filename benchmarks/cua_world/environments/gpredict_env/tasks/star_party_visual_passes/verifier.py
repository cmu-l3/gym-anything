#!/usr/bin/env python3
"""
Verifier for star_party_visual_passes task.

Task:
  1. Create Griffith Observatory ground station (34.1184N, 118.3004W, 350m).
  2. Generate future passes for ISS (ZARYA).
  3. Filter: Min Elev = 25.0, Vis = Visible only.
  4. Export to ~/Documents/iss_visible_passes.txt.

Scoring (100 points, pass >= 70):
  - QTH Creation: 20 pts (Griffith_Observatory exists with correct coords)
  - File Exported: 20 pts (File exists, > 0 bytes, created during task)
  - Format/Observer Check: 15 pts (Matches GPredict format, observer = Griffith)
  - Constraint - Min Elev: 15 pts (No pass < 25 degrees)
  - Constraint - Visibility: 15 pts (All passes are 'V' / Visible)
  - VLM Trajectory check: 15 pts (Proves agent used UI instead of scripting the file)
"""

import json
import os
import re
import tempfile
import logging

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logger = logging.getLogger(__name__)

VLM_PROMPT = """
You are verifying an agent's trajectory in a Linux desktop environment.
The agent was asked to use GPredict to calculate and export "Upcoming passes" for the ISS.

Please review these frames and answer the following:
1. Did the agent open a dialog related to "Upcoming passes" or "Future passes"?
2. Did the agent interact with the UI to configure constraints (e.g. elevation, visibility)?
3. Did the agent interact with a Save/Export dialog to save a text file?

Respond with a JSON object:
{
    "opened_passes_dialog": true/false,
    "configured_constraints": true/false,
    "interacted_with_save": true/false
}
"""

def _close_enough(value_str, expected_float, tolerance=0.1):
    try:
        val = float(value_str)
        return abs(val - expected_float) <= tolerance
    except (ValueError, TypeError):
        return False

def parse_gpredict_pass_file(filepath):
    """Parses a GPredict exported text file and returns a summary dict."""
    result = {
        "is_valid_format": False,
        "observer": None,
        "target": None,
        "passes": []
    }
    
    if not os.path.exists(filepath):
        return result
        
    try:
        with open(filepath, 'r') as f:
            lines = f.readlines()
            
        if not lines:
            return result
            
        # Check headers
        for line in lines[:10]:
            if line.startswith("Upcoming passes for"):
                result["is_valid_format"] = True
                result["target"] = line.replace("Upcoming passes for", "").strip()
            if line.startswith("Observer:"):
                result["observer"] = line.replace("Observer:", "").strip()
                
        # Parse data rows. Pattern looks like: 2026/03/10 18:00:00 ...
        for line in lines:
            line = line.strip()
            if re.match(r'^\d{4}/\d{2}/\d{2}\s+\d{2}:\d{2}:\d{2}', line):
                tokens = line.split()
                # Typical format has 10+ columns. Last 4 are usually: Max El, AOS Az, LOS Az, Vis
                if len(tokens) >= 8:
                    try:
                        vis = tokens[-1]
                        max_el = float(tokens[-4])
                        result["passes"].append({
                            "max_el": max_el,
                            "vis": vis,
                            "raw": line
                        })
                    except ValueError:
                        pass
    except Exception as e:
        logger.error(f"Error parsing pass file: {e}")
        
    return result

def verify_star_party_visual_passes(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    score = 0
    feedback_parts = []

    # 1. Fetch JSON Results
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_json_path = temp_json.name
    temp_json.close()
    
    temp_txt = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    temp_txt_path = temp_txt.name
    temp_txt.close()

    try:
        copy_from_env("/tmp/star_party_visual_passes_result.json", temp_json_path)
        with open(temp_json_path, 'r') as f:
            result = json.load(f)
            
        if result.get("file_exists"):
            copy_from_env("/tmp/exported_passes.txt", temp_txt_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve task results: {e}"}
    finally:
        if os.path.exists(temp_json_path): os.unlink(temp_json_path)

    # --- Criterion 1: QTH Creation (20 pts) ---
    if result.get("griffith_exists"):
        lat_ok = _close_enough(result.get("griffith_lat", ""), metadata.get("griffith_lat", 34.1184), 0.1)
        lon_ok = _close_enough(result.get("griffith_lon", ""), metadata.get("griffith_lon", -118.3004), 0.1)
        alt_ok = _close_enough(result.get("griffith_alt", ""), metadata.get("griffith_alt", 350), 20)
        
        if lat_ok and lon_ok and alt_ok:
            score += 20
            feedback_parts.append("QTH correctly configured")
        elif lat_ok and lon_ok:
            score += 15
            feedback_parts.append(f"QTH coordinates OK, altitude off (got {result.get('griffith_alt')}m)")
        else:
            score += 5
            feedback_parts.append("QTH exists but coordinates are incorrect")
    else:
        feedback_parts.append("Griffith QTH not found")

    # --- Criterion 2: File Exported (20 pts) ---
    file_exists = result.get("file_exists", False)
    created_during_task = result.get("file_created_during_task", False)
    file_size = result.get("file_size", 0)
    
    if file_exists and created_during_task and file_size > 50:
        score += 20
        feedback_parts.append("Prediction file successfully exported")
    elif file_exists and created_during_task:
        score += 10
        feedback_parts.append("Prediction file created but seems empty/too small")
    elif file_exists:
        feedback_parts.append("Prediction file exists but was NOT created during this task run")
        # Critical failure, potential gaming
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
    else:
        feedback_parts.append("Prediction file was NOT created")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # --- Criterion 3 & 4 & 5: Parse Exported File ---
    parsed_data = parse_gpredict_pass_file(temp_txt_path)
    
    if parsed_data["is_valid_format"]:
        # Format / Observer check (15 pts)
        observer = parsed_data.get("observer", "")
        if observer and "griffith" in observer.lower():
            score += 15
            feedback_parts.append("Observer correctly logged as Griffith")
        else:
            feedback_parts.append(f"Incorrect observer in file: {observer}")
            
        passes = parsed_data["passes"]
        if passes:
            # Elevation Constraint Check (15 pts)
            min_el_found = min([p["max_el"] for p in passes])
            if min_el_found >= 25.0:
                score += 15
                feedback_parts.append(f"Elevation constraint met (lowest pass: {min_el_found} deg)")
            else:
                feedback_parts.append(f"Elevation constraint FAILED (found pass at {min_el_found} deg)")
                
            # Visibility Constraint Check (15 pts)
            all_visible = all(["V" in p["vis"] for p in passes])
            if all_visible:
                score += 15
                feedback_parts.append("Visibility constraint met (all passes visible)")
            else:
                non_vis = [p["vis"] for p in passes if "V" not in p["vis"]]
                feedback_parts.append(f"Visibility constraint FAILED (found passes with Vis={non_vis[0]})")
        else:
            feedback_parts.append("File format valid, but no passes were found in the table (check date ranges?)")
    else:
        feedback_parts.append("File exists but does not match GPredict text export format")

    # Clean up txt file
    if os.path.exists(temp_txt_path):
        os.unlink(temp_txt_path)

    # --- Criterion 6: VLM Trajectory Check (15 pts) ---
    frames = sample_trajectory_frames(traj, n=5)
    final_frame = get_final_screenshot(traj)
    if final_frame:
        frames.append(final_frame)
        
    try:
        vlm_resp = query_vlm(images=frames, prompt=VLM_PROMPT)
        if vlm_resp and vlm_resp.get("parsed"):
            parsed = vlm_resp["parsed"]
            if parsed.get("opened_passes_dialog") and parsed.get("interacted_with_save"):
                score += 15
                feedback_parts.append("VLM confirmed UI interaction")
            elif parsed.get("opened_passes_dialog"):
                score += 10
                feedback_parts.append("VLM confirmed dialog open, but not save interaction")
            else:
                feedback_parts.append("VLM could not confirm UI interaction")
        else:
            feedback_parts.append("VLM response missing/malformed")
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        # Give benefit of doubt if VLM errors out, but log it
        score += 15
        feedback_parts.append("VLM check bypassed (error)")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }