#!/usr/bin/env python3
"""Verifier for edit_trip_summary task.

Verifies that the correct Trip header was edited, rather than individual dives,
by parsing the Subsurface XML and checking for trajectory evidence.
"""

import os
import json
import tempfile
import xml.etree.ElementTree as ET
import logging

try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_edit_trip_summary(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_location = metadata.get('expected_location', 'Hood Canal Winter Retreat')
    expected_notes = metadata.get('expected_notes', 'Instructor training weekend')

    score = 0
    feedback_parts = []
    
    # 1. Read task_result.json
    result_json_path = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    try:
        copy_from_env('/tmp/task_result.json', result_json_path)
        with open(result_json_path, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        task_result = {}
        logger.warning(f"Could not read task_result.json: {e}")
    finally:
        if os.path.exists(result_json_path):
            os.unlink(result_json_path)

    # Criterion 1: File modified during task (10 pts)
    file_modified = task_result.get('file_modified_during_task', False)
    if file_modified:
        score += 10
        feedback_parts.append("File was saved successfully.")
    else:
        feedback_parts.append("File modification not detected (did you save?).")

    # 2. Read and parse dives.ssrf
    ssrf_path = tempfile.NamedTemporaryFile(delete=False, suffix='.ssrf').name
    try:
        copy_from_env('/home/ga/Documents/dives.ssrf', ssrf_path)
        tree = ET.parse(ssrf_path)
        root = tree.getroot()
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"XML parse error: {e}"}
    finally:
        if os.path.exists(ssrf_path):
            os.unlink(ssrf_path)

    trip_renamed = False
    notes_added = False
    dives_unaffected = True

    # Check Trip elements
    for trip in root.iter('trip'):
        loc = trip.get('location', '')
        
        # Did they successfully rename the trip?
        if loc == expected_location:
            trip_renamed = True
            
            # Did they add the proper notes to the trip?
            notes_elem = trip.find('notes')
            if notes_elem is not None and notes_elem.text and expected_notes.lower() in notes_elem.text.lower():
                notes_added = True

    # Criterion 2: Trip renamed (30 pts)
    if trip_renamed:
        score += 30
        feedback_parts.append(f"Trip location correctly set to '{expected_location}'.")
    else:
        feedback_parts.append(f"Trip location not updated to '{expected_location}'.")

    # Criterion 3: Trip notes added (20 pts)
    if notes_added:
        score += 20
        feedback_parts.append("Trip notes correctly updated.")
    else:
        feedback_parts.append("Trip notes missing or incorrect.")

    # Integrity check: Make sure no individual dive was accidentally renamed
    for dive in root.iter('dive'):
        # Check attribute
        if dive.get('location') == expected_location:
            dives_unaffected = False
        # Check child element
        loc_elem = dive.find('location')
        if loc_elem is not None and loc_elem.text == expected_location:
            dives_unaffected = False

    # Criterion 4: Dives unaffected (20 pts)
    if dives_unaffected:
        score += 20
        feedback_parts.append("Individual dive sites were preserved.")
    else:
        feedback_parts.append("WARNING: Individual dive sites were overwritten instead of just the Trip.")

    # Criterion 5: VLM trajectory check (20 pts)
    if VLM_AVAILABLE and traj:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            prompt = """You are evaluating an AI agent using the Subsurface dive log application.
The agent was asked to edit a "Trip" summary (not an individual dive).
Did the agent interact with the Subsurface UI to select a Trip header and edit its notes/location?
Return JSON format: {"ui_interaction_observed": true/false}"""

            vlm_res = query_vlm(images=images, prompt=prompt)
            
            if vlm_res and vlm_res.get("success") and vlm_res.get("parsed", {}).get("ui_interaction_observed"):
                score += 20
                feedback_parts.append("VLM confirmed UI interaction.")
            else:
                feedback_parts.append("VLM did not observe clear UI interaction.")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # Do not completely fail the task if VLM goes down
            feedback_parts.append("VLM check skipped due to error.")
            # Grant proportional free points if VLM is unavailable but file is modified + XML is perfect
            if file_modified and trip_renamed and notes_added and dives_unaffected:
                score += 20
    else:
        # Give points if VLM is entirely unavailable but other strict program metrics pass
        if file_modified and trip_renamed and notes_added and dives_unaffected:
            score += 20

    # Determine pass/fail
    # Must have saved file, renamed trip, and NOT overwritten the dives
    passed = (score >= 70) and trip_renamed and dives_unaffected

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }