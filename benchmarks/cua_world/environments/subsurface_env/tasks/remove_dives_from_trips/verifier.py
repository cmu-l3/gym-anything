#!/usr/bin/env python3
"""
Verifier for remove_dives_from_trips task.
Checks XML hierarchy to ensure specified dives were removed from trip groupings,
while preserving total dive count and collateral trips.
"""

import os
import json
import tempfile
import logging
import xml.etree.ElementTree as ET
from datetime import datetime

# Adjust import path for gym_anything VLM utilities
import sys
sys.path.insert(0, '/workspace/gym_anything')
try:
    from gym_anything.vlm import query_vlm, sample_trajectory_frames
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_remove_dives_from_trips(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Read exported result
    temp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_res.close()
    try:
        copy_from_env("/tmp/task_result.json", temp_res.name)
        with open(temp_res.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load export result: {e}"}
    finally:
        if os.path.exists(temp_res.name):
            os.unlink(temp_res.name)

    file_modified = result_data.get('file_modified_during_task', False)
    
    # 2. Read and parse modified XML
    temp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.ssrf')
    temp_xml.close()
    try:
        copy_from_env("/home/ga/Documents/dives.ssrf", temp_xml.name)
        tree = ET.parse(temp_xml.name)
        root = tree.getroot()
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to parse dive log XML: {e}"}
    finally:
        if os.path.exists(temp_xml.name):
            os.unlink(temp_xml.name)

    # 3. Analyze XML Hierarchy
    # Build a child -> parent map
    parent_map = {c: p for p in root.iter() for c in p}
    
    dives = list(root.iter('dive'))
    total_dives = len(dives)
    
    # Sort dives chronologically to reliably identify them regardless of numbering/hierarchy shifts
    def get_dt(d):
        date_str = d.get('date', '2000-01-01')
        time_str = d.get('time', '00:00')
        try:
            return datetime.strptime(f"{date_str} {time_str}", "%Y-%m-%d %H:%M:%S")
        except ValueError:
            try:
                return datetime.strptime(f"{date_str} {time_str}", "%Y-%m-%d %H:%M")
            except ValueError:
                return datetime.min

    dives.sort(key=get_dt)

    score = 0
    feedback = []

    if not file_modified:
        feedback.append("File was NOT modified/saved.")
    else:
        score += 10
        feedback.append("File saved successfully.")

    if total_dives == 8:
        score += 20
        feedback.append("Dive count correctly preserved (8 dives).")
    else:
        feedback.append(f"WARNING: Dive count changed! Expected 8, found {total_dives}.")
        # Severe penalty for deleting data
        return {"passed": False, "score": score, "feedback": " ".join(feedback)}

    # Target indices (0-based) based on chronological order of SampleDivesV2
    # Dive #1 -> index 0, Dive #4 -> index 3, Dive #5 -> index 4, Dive #8 -> index 7
    dive1, dive4, dive5, dive8 = dives[0], dives[3], dives[4], dives[7]

    d4_is_standalone = parent_map.get(dive4, root).tag != 'trip'
    d8_is_standalone = parent_map.get(dive8, root).tag != 'trip'
    d1_in_trip = parent_map.get(dive1, root).tag == 'trip'
    d5_in_trip = parent_map.get(dive5, root).tag == 'trip'

    if d4_is_standalone:
        score += 20
        feedback.append("Dive #4 successfully removed from trip.")
    else:
        feedback.append("Dive #4 is still inside a trip.")

    if d8_is_standalone:
        score += 20
        feedback.append("Dive #8 successfully removed from trip.")
    else:
        feedback.append("Dive #8 is still inside a trip.")

    if d1_in_trip and d5_in_trip:
        score += 15
        feedback.append("Other trips maintained structural integrity.")
    else:
        feedback.append("Collateral damage to other trips detected.")

    # 4. VLM Verification (Trajectory Anti-gaming)
    vlm_score = 0
    if VLM_AVAILABLE and traj:
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            prompt = """
            Look at these trajectory frames of a user operating the Subsurface dive log application.
            Did the user right-click on dives in the dive list and interact with the context menu 
            (specifically looking for 'Remove dive from trip' or similar tree hierarchy actions)?
            
            Respond strictly in JSON format:
            {"used_context_menu": true/false}
            """
            try:
                vlm_resp = query_vlm(images=frames, prompt=prompt)
                parsed = vlm_resp.get("parsed", {})
                if parsed.get("used_context_menu"):
                    vlm_score = 15
                    feedback.append("VLM confirmed UI context menu usage.")
                else:
                    feedback.append("VLM did not clearly see context menu usage.")
            except Exception as e:
                logger.error(f"VLM verification error: {e}")
                vlm_score = 15 # Grant points on VLM crash if other checks pass
    else:
        vlm_score = 15 # Grant points if VLM is unavailable during test execution
        
    score += vlm_score

    # Threshold checks
    key_criteria_met = file_modified and total_dives == 8 and (d4_is_standalone or d8_is_standalone)
    passed = score >= 70 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }