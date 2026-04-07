#!/usr/bin/env python3
"""
Verifier for reroute_insert_resupply_point task.

VERIFICATION STRATEGY:
1. File Verification (15 pts): Output file exists and was created during the task.
2. Route Integrity (15 pts): XML is valid GPX and contains the `<rte>` "Fells_Survey".
3. Sequence Verification (40 pts): Route points must be in exact order: South Gate -> Water Cache -> Bear Hill.
4. VLM Verification (30 pts): Agent used UI dialogs to achieve this.

The Activity Profile check acts as a modifier (+/-) since BaseCamp's XML extension output can be highly variable depending on internal app state.
"""

import json
import os
import tempfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are analyzing a trajectory of screenshots from a Garmin BaseCamp task.
The goal of the user was to modify a route named "Fells_Survey".
They needed to:
1. Open the Route Properties dialog.
2. Insert a waypoint named "Water Cache" into the route itinerary.
3. Change the routing Activity Profile from "Direct" to "Hiking" (or Pedestrian).

Look through the frames and answer:
1. Is the Route Properties dialog opened?
2. Can you see "Water Cache" added to the sequence list?
3. Is there evidence they interacted with the Activity Profile dropdown (changed to Hiking/Pedestrian)?

Respond with JSON:
{
    "route_dialog_opened": true/false,
    "waypoint_inserted": true/false,
    "activity_changed": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation."
}
"""

def get_tag_name(element):
    """Strip namespace from XML tags."""
    return element.tag.split('}')[-1] if '}' in element.tag else element.tag

def verify_reroute(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error: copy_from_env not available."}

    score = 0
    feedback = []

    # 1. Read JSON result
    result_tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:/tmp/task_result.json", result_tmp.name)
        with open(result_tmp.name, 'r') as f:
            export_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load export JSON: {e}"}
    finally:
        if os.path.exists(result_tmp.name):
            os.unlink(result_tmp.name)

    # Verify anti-gaming
    if not export_data.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output GPX file was not found."}
    
    if not export_data.get("file_created_during_task", False):
        feedback.append("Warning: File timestamp indicates it might not have been created during the task.")
    else:
        score += 15
        feedback.append("Output file verified and created during task.")

    # 2. Parse GPX File
    gpx_tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.gpx')
    route_found = False
    sequence = []
    has_hiking_profile = False

    try:
        copy_from_env("C:/workspace/output/updated_survey_route.gpx", gpx_tmp.name)
        tree = ET.parse(gpx_tmp.name)
        root = tree.getroot()

        for el in root.iter():
            if get_tag_name(el) == 'rte':
                name_el = None
                for child in el:
                    if get_tag_name(child) == 'name':
                        name_el = child
                        break
                
                if name_el is not None and name_el.text == 'Fells_Survey':
                    route_found = True
                    score += 15
                    feedback.append("Route 'Fells_Survey' found in export.")
                    
                    # Extract sequence and profile
                    for child in el:
                        tag = get_tag_name(child)
                        if tag == 'rtept':
                            pt_name = child.find('.//name')
                            # Handle namespaced sub-elements safely
                            if pt_name is None:
                                for sub in child:
                                    if get_tag_name(sub) == 'name':
                                        pt_name = sub
                                        break
                            if pt_name is not None and pt_name.text:
                                sequence.append(pt_name.text.strip())
                        
                        elif tag == 'extensions':
                            ext_str = ET.tostring(child, encoding='unicode').lower()
                            if 'hiking' in ext_str or 'pedestrian' in ext_str:
                                has_hiking_profile = True
                    break # Processed the target route

    except Exception as e:
        feedback.append(f"Failed to parse GPX file: {e}")
    finally:
        if os.path.exists(gpx_tmp.name):
            os.unlink(gpx_tmp.name)

    if not route_found:
        return {"passed": False, "score": score, "feedback": " | ".join(feedback) + " | Route 'Fells_Survey' missing."}

    # 3. Sequence Verification
    expected_seq = ["South Gate", "Water Cache", "Bear Hill"]
    if sequence == expected_seq:
        score += 40
        feedback.append(f"Perfect sequence achieved: {sequence}")
    elif len(sequence) == 3 and "Water Cache" in sequence:
        score += 20
        feedback.append(f"Water Cache added but sequence wrong: {sequence}")
    else:
        feedback.append(f"Incorrect sequence or missing waypoints: {sequence}")

    # 4. Profile Verification (XML)
    if has_hiking_profile:
        feedback.append("Activity Profile successfully set to Hiking/Pedestrian in GPX.")
        score += 10 # Bonus for achieving it in XML
    else:
        feedback.append("Activity Profile 'Hiking/Pedestrian' not found in GPX extensions (checking VLM...).")

    # 5. VLM Trajectory Verification
    import sys
    from pathlib import Path
    
    # Safely try to import VLM utilities
    try:
        sys.path.insert(0, str(Path(__file__).parent.parent))
        from vlm_utils import sample_trajectory_frames, query_vlm
        
        frames = sample_trajectory_frames(traj, n=5)
        if frames:
            vlm_res = query_vlm(images=frames, prompt=VLM_PROMPT)
            if vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("route_dialog_opened", False):
                    score += 10
                    if parsed.get("waypoint_inserted", False):
                        score += 10
                    if parsed.get("activity_changed", False):
                        score += 10
                        feedback.append("VLM confirmed Activity Profile change via UI.")
                else:
                    feedback.append("VLM did not detect use of the Route Properties dialog.")
    except Exception as e:
        logger.warning(f"VLM verification skipped or failed: {e}")
        # If VLM is unavailable, grade purely on XML completeness
        if sequence == expected_seq:
            score += 20 

    # Cap score at 100
    score = min(100, score)
    passed = score >= 70 and sequence == expected_seq

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "sequence": sequence,
            "profile_changed": has_hiking_profile
        }
    }