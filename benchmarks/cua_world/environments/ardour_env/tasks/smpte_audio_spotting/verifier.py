#!/usr/bin/env python3
"""
Verifier for smpte_audio_spotting task.
Evaluates Ardour configuration, track naming, precise audio placement (spotting), 
and region safety locks based on raw session XML data.
"""

import json
import os
import tempfile
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_smpte_audio_spotting(traj, env_info, task_info):
    """
    Scoring Breakdown (100 pts total, passing threshold 70):
    1. Session saved after start    (10 pts)
    2. Timecode set to 24 fps       (15 pts)
    3. 'Voiceover' track created    (15 pts)
    4. Region is locked             (20 pts)
    5. Exact Placement (3991050)    (40 pts exact / 20 pts partial)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    target_samples = metadata.get('target_samples', 3991050)
    exact_tol = metadata.get('tolerance_exact_samples', 500)
    partial_tol = metadata.get('tolerance_partial_samples', 44100)
    session_remote = metadata.get('session_file', "/home/ga/Audio/sessions/MyProject/MyProject.ardour")

    score = 0
    feedback_parts = []
    
    # ================================================================
    # Read Exported JSON for Timestamps
    # ================================================================
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    session_mtime = result.get('session_mtime', 0)
    task_start = result.get('task_start_time', 0)

    # Criterion 1: Session saved
    if session_mtime > task_start and result.get('session_file_exists'):
        score += 10
        feedback_parts.append("Session saved")
    else:
        feedback_parts.append("Session not saved during task window")

    # ================================================================
    # Copy & Parse Session XML
    # ================================================================
    temp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.ardour')
    try:
        copy_from_env(session_remote, temp_xml.name)
        if not os.path.exists(temp_xml.name) or os.path.getsize(temp_xml.name) == 0:
            return {"passed": False, "score": score, "feedback": "Session XML missing or empty"}
            
        tree = ET.parse(temp_xml.name)
        root = tree.getroot()
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"XML parse error: {e}"}
    finally:
        if os.path.exists(temp_xml.name):
            os.unlink(temp_xml.name)

    # ================================================================
    # Criterion 2: Timecode 24 FPS
    # ================================================================
    fps_24 = False
    
    # Check config options
    for opt in root.findall('.//Option'):
        if opt.get('name') == 'timecode-format' and '24' in opt.get('value', ''):
            fps_24 = True
            
    # Fallback to Config attributes
    for cfg in root.findall('.//Config'):
        if '24' in cfg.get('timecode-format', ''):
            fps_24 = True

    if fps_24:
        score += 15
        feedback_parts.append("Timecode set to 24 fps")
    else:
        feedback_parts.append("Timecode not set to 24 fps")

    # ================================================================
    # Criterion 3: Voiceover Track
    # ================================================================
    target_route = None
    for route in root.findall('.//Route'):
        if route.get('default-type') == 'audio':
            r_name = route.get('name', '').lower()
            if 'voiceover' in r_name or 'narration' in r_name:
                target_route = route
                break

    if target_route is not None:
        score += 15
        feedback_parts.append("Voiceover track found")
    else:
        feedback_parts.append("Voiceover track missing")

    # ================================================================
    # Criteria 4 & 5: Region Lock and Placement
    # ================================================================
    closest_diff = float('inf')
    is_locked = False
    region_found = False

    if target_route is not None:
        # Find the playlist ID assigned to this route's diskstream to be highly precise
        playlist_id = None
        for ds in target_route.findall('.//Diskstream'):
            playlist_id = ds.get('playlist')
            if playlist_id: break

        # Find regions inside that playlist
        regions = []
        if playlist_id:
            for pl in root.findall('.//Playlist'):
                if pl.get('id') == playlist_id:
                    regions.extend(pl.findall('.//Region'))
        
        # Calculate distances to target timecode
        for reg in regions:
            region_found = True
            pos = int(reg.get('position', '0'))
            diff = abs(pos - target_samples)
            if diff < closest_diff:
                closest_diff = diff
                # Ardour flags boolean locked as '1' or 'true' or 'yes'
                is_locked = reg.get('locked') in ['1', 'true', 'yes']

    if region_found:
        if is_locked:
            score += 20
            feedback_parts.append("Region is locked")
        else:
            feedback_parts.append("Region is NOT locked")

        if closest_diff <= exact_tol:
            score += 40
            feedback_parts.append("Spotting exact (100% accurate)")
        elif closest_diff <= partial_tol:
            score += 20
            feedback_parts.append("Spotting partial (within 1 second)")
        else:
            feedback_parts.append(f"Spotting missed (Off by {closest_diff} samples)")
    else:
        feedback_parts.append("No audio region found on target track")

    # Final pass conditions
    passed = score >= 70 and region_found and closest_diff <= partial_tol

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }