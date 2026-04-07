#!/usr/bin/env python3
"""
Verifier for Export Noto Earthquake as FDSN QuakeML task.
Uses multi-signal verification:
1. Programmatic file/XML checks (75 pts)
2. VLM Trajectory Process Verification (25 pts)
"""

import os
import json
import logging
import tempfile
from gym_anything.vlm import sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are evaluating an AI agent's trajectory performing a task in a SeisComP seismology environment.
The agent's goal was to export earthquake data from the database into a standard QuakeML XML file.

Look at the provided chronological sequence of screenshots from the agent's screen.
We need to verify that the agent actually worked to extract/format the data (e.g., using terminal commands, Python scripts, scxmldump, or database queries) rather than just waiting and doing nothing.

Did the agent visibly use the terminal to run commands, edit scripts, or query data during this trajectory?
(Look for text in the terminal window, commands like `scxmldump`, `python`, `mysql`, `cat`, or text editors like `nano`/`vim`).

Respond exactly with JSON:
{
    "used_terminal_for_work": true/false,
    "reasoning": "brief explanation of what commands or work is visible"
}
"""

def verify_export_quakeml(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    metadata = task_info.get('metadata', {})
    coord_tol = metadata.get('coord_tolerance', 1.0)
    mag_tol = metadata.get('mag_tolerance', 0.5)
    
    # ─── 1. Retrieve Programmatic Export Data ──────────────────────────────
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
    
    file_exists = result.get('file_exists', False)
    file_created = result.get('file_created_during_task', False)
    xml = result.get('xml_analysis', {})
    gt = result.get('ground_truth', {})
    
    # Check 1: File Existence & Anti-Gaming (15 pts)
    if not file_exists:
        return {"passed": False, "score": 0, "feedback": "Failure: Target file ~/exports/noto_quakeml.xml was not created."}
    
    if file_created:
        score += 15
        feedback_parts.append("File newly created (+15)")
    else:
        feedback_parts.append("Warning: File timestamp indicates it may have existed prior to task.")
        
    # Check 2: XML Validity & Namespaces (15 pts)
    if xml.get('is_valid_xml'):
        score += 5
        feedback_parts.append("Valid XML (+5)")
        
        ns_score = 0
        if xml.get('has_quakeml_ns'): ns_score += 5
        if xml.get('has_bed_ns'): ns_score += 5
        
        if ns_score > 0:
            score += ns_score
            feedback_parts.append(f"Namespaces present (+{ns_score})")
        else:
            feedback_parts.append("Missing required QuakeML namespaces.")
    else:
        feedback_parts.append("Invalid or unparseable XML.")
        
    # Check 3: Basic Hierarchy (15 pts)
    if xml.get('has_event_structure'):
        score += 15
        feedback_parts.append("Event hierarchy correct (+15)")
    else:
        feedback_parts.append("Missing <event> element structure.")
        
    # Check 4: Coordinates (15 pts)
    lat = xml.get('extracted_lat')
    lon = xml.get('extracted_lon')
    gt_lat = gt.get('lat', 37.23)
    gt_lon = gt.get('lon', 136.99)
    
    if lat is not None and lon is not None:
        lat_diff = abs(lat - gt_lat)
        lon_diff = abs(lon - gt_lon)
        if lat_diff <= coord_tol and lon_diff <= coord_tol:
            score += 15
            feedback_parts.append(f"Coordinates matched GT (+15) [Lat: {lat}, Lon: {lon}]")
        else:
            feedback_parts.append(f"Coordinates out of bounds. Expected ~({gt_lat}, {gt_lon}), got ({lat}, {lon})")
    else:
        feedback_parts.append("Could not extract latitude/longitude from XML.")
        
    # Check 5: Magnitude (15 pts)
    mag = xml.get('extracted_mag')
    gt_mag = gt.get('mag', 7.5)
    
    if mag is not None:
        if abs(mag - gt_mag) <= mag_tol:
            score += 15
            feedback_parts.append(f"Magnitude matched GT (+15) [Mag: {mag}]")
        else:
            feedback_parts.append(f"Magnitude out of bounds. Expected ~{gt_mag}, got {mag}")
    else:
        feedback_parts.append("Could not extract magnitude from XML.")

    # ─── 2. VLM Trajectory Verification (25 pts) ───────────────────────────
    vlm_passed = False
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=5)
        if frames:
            try:
                vlm_resp = query_vlm(images=frames, prompt=VLM_PROMPT)
                if vlm_resp and vlm_resp.get("success"):
                    parsed = vlm_resp.get("parsed", {})
                    vlm_passed = parsed.get("used_terminal_for_work", False)
                    reasoning = parsed.get("reasoning", "No reasoning provided")
                    
                    if vlm_passed:
                        score += 25
                        feedback_parts.append(f"VLM verified workflow (+25): {reasoning}")
                    else:
                        feedback_parts.append(f"VLM rejected workflow: {reasoning}")
            except Exception as e:
                logger.warning(f"VLM query failed: {e}")
                feedback_parts.append("VLM verification skipped/failed.")
    else:
        # Fallback if VLM unavailable, give partial credit to not block completely
        score += 15
        feedback_parts.append("VLM not available (gave partial fallback credit).")

    # ─── 3. Final Evaluation ───────────────────────────────────────────────
    # Passing requires key extraction elements to be correct
    key_elements_present = (
        file_created and 
        xml.get('is_valid_xml') and 
        xml.get('has_event_structure') and
        lat is not None and
        mag is not None
    )
    
    passed = score >= 70 and key_elements_present
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }