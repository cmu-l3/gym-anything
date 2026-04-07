#!/usr/bin/env python3
"""
Verifier for broadcast_censor_edit task.
Occupation: Broadcast Technician (SOC 27-4012)
Industry: Radio Broadcasting / Media

Checks that the agent created Interview and Censor tracks, removed the audio
from the Interview track between 14.5s and 15.5s, placed the beep accurately
on the Censor track covering that gap, and exported the result.
"""

import os
import tempfile
import logging
import json
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# ---------- Ardour XML helpers ----------

def get_audio_routes(root):
    """Return all audio track routes (excluding Master/Monitor)."""
    routes = []
    for route in root.iter('Route'):
        flags = route.get('flags', '')
        if 'MasterOut' in flags or 'MonitorOut' in flags:
            continue
        if route.get('default-type') == 'audio':
            routes.append(route)
    return routes

def get_playlist_name_for_route(route):
    """Reliably find the playlist name mapped to a specific route."""
    for ds in route.iter('Diskstream'):
        return ds.get('playlist', '')
    return ''

def get_regions_for_playlist(root, playlist_name):
    """Get all active regions for a specific playlist."""
    regions = []
    for playlist in root.iter('Playlist'):
        if playlist.get('name', '') == playlist_name:
            for region in playlist.iter('Region'):
                muted = region.get('muted', '0') in ('1', 'yes', 'true')
                if not muted:
                    regions.append({
                        'name': region.get('name', ''),
                        'position': int(region.get('position', '0')),
                        'length': int(region.get('length', '0')),
                    })
    return regions

def is_route_muted(route):
    """Check if the entire track/route is muted."""
    if route.get('muted', '0') in ('1', 'yes', 'true'):
        return True
    for ctrl in route.iter('Controllable'):
        if ctrl.get('name') == 'mute' and ctrl.get('value', '0') in ('1', 'yes', 'true'):
            return True
    return False


# ---------- Main verifier ----------

def verify_broadcast_censor_edit(traj, env_info, task_info):
    """
    Multi-criterion verifier for broadcast profanity censor edit.

    Criteria (100 pts total, pass >= 75):
      1. Track Setup (Interview & Censor tracks exist)            (15 pts)
      2. Profanity Removed (No active audio 14.5s-15.5s)          (30 pts)
      3. Beep Aligned (Active audio on Censor 14.5s-15.5s)        (30 pts)
      4. Mix Exported (fcc_compliant_mix.wav exists and valid)    (25 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    score = 0
    feedback = []

    metadata = task_info.get('metadata', {})
    target_start = metadata.get('censor_start_samples', 639450)
    target_end = metadata.get('censor_end_samples', 683550)
    tolerance = metadata.get('tolerance_samples', 4410)  # 0.1s

    # 1. Retrieve the exported JSON result
    result_json_remote = "/tmp/broadcast_censor_edit_result.json"
    tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_json.close()

    result = {}
    try:
        copy_from_env(result_json_remote, tmp_json.name)
        if os.path.exists(tmp_json.name) and os.path.getsize(tmp_json.name) > 0:
            with open(tmp_json.name, 'r') as f:
                result = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load result JSON: {e}")
    finally:
        if os.path.exists(tmp_json.name):
            os.unlink(tmp_json.name)

    # 2. Retrieve Ardour session XML
    session_remote = "/home/ga/Audio/sessions/MyProject/MyProject.ardour"
    tmp_session = tempfile.NamedTemporaryFile(delete=False, suffix='.ardour')
    tmp_session.close()

    try:
        copy_from_env(session_remote, tmp_session.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Session file not accessible: {e}"}

    if not os.path.exists(tmp_session.name) or os.path.getsize(tmp_session.name) == 0:
        return {"passed": False, "score": 0, "feedback": "Session file empty or missing"}

    try:
        tree = ET.parse(tmp_session.name)
        root = tree.getroot()
    except Exception as e:
        os.unlink(tmp_session.name)
        return {"passed": False, "score": 0, "feedback": f"Session XML parse error: {e}"}
    finally:
        if os.path.exists(tmp_session.name):
            os.unlink(tmp_session.name)

    routes = get_audio_routes(root)
    
    # ================================================================
    # CRITERION 1: Track Setup (15 pts)
    # Find the "Interview" and "Censor" tracks
    # ================================================================
    interview_route = None
    censor_route = None

    for r in routes:
        name = r.get('name', '').lower()
        if 'interview' in name:
            interview_route = r
        elif 'censor' in name or 'beep' in name:
            censor_route = r

    if interview_route and censor_route:
        score += 15
        feedback.append("PASS: Both 'Interview' and 'Censor' tracks found")
    else:
        if interview_route:
            score += 7
            feedback.append("PARTIAL: 'Interview' track found, but missing 'Censor' track")
        elif censor_route:
            score += 7
            feedback.append("PARTIAL: 'Censor' track found, but missing 'Interview' track")
        else:
            feedback.append("FAIL: Required tracks not found")
            return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    # ================================================================
    # CRITERION 2: Profanity Removed (30 pts)
    # The interview track must NOT have active audio between 14.5s and 15.5s
    # ================================================================
    if interview_route:
        if is_route_muted(interview_route):
            # If the entire track is muted, technically profanity is removed, but they ruined the interview
            feedback.append("FAIL: Entire Interview track is muted")
        else:
            playlist_name = get_playlist_name_for_route(interview_route)
            interview_regions = get_regions_for_playlist(root, playlist_name)
            
            overlap_found = False
            for reg in interview_regions:
                reg_start = reg['position']
                reg_end = reg['position'] + reg['length']
                
                # Check intersection logic: overlaps if region start < target end AND region end > target start
                # Use a small tolerance so exactly abutting edges don't trigger false positive
                if reg_start < (target_end - 100) and reg_end > (target_start + 100):
                    overlap_found = True
                    break
            
            if not overlap_found:
                score += 30
                feedback.append("PASS: Profanity successfully removed/muted from Interview track")
            else:
                feedback.append("FAIL: Active audio still exists in the restricted 14.5s-15.5s window")

    # ================================================================
    # CRITERION 3: Beep Aligned (30 pts)
    # The censor track MUST have active audio starting ~14.5s and ending ~15.5s
    # ================================================================
    if censor_route:
        if is_route_muted(censor_route):
            feedback.append("FAIL: Entire Censor track is muted")
        else:
            playlist_name = get_playlist_name_for_route(censor_route)
            censor_regions = get_regions_for_playlist(root, playlist_name)
            
            aligned_beep_found = False
            for reg in censor_regions:
                reg_start = reg['position']
                reg_end = reg['position'] + reg['length']
                
                start_ok = abs(reg_start - target_start) <= tolerance
                end_ok = abs(reg_end - target_end) <= tolerance
                
                if start_ok and end_ok:
                    aligned_beep_found = True
                    break
            
            if aligned_beep_found:
                score += 30
                feedback.append("PASS: Censor beep perfectly aligned to the gap")
            else:
                feedback.append("FAIL: Censor beep not accurately aligned to 14.5s-15.5s")

    # ================================================================
    # CRITERION 4: Mix Exported (25 pts)
    # Check if fcc_compliant_mix.wav exists and has size > 1KB
    # ================================================================
    export_exists = result.get('export_file_exists', False)
    export_size = result.get('export_file_size', 0)
    export_path = result.get('export_file_path', '')

    if export_exists and export_size > 1024:
        score += 25
        if "fcc_compliant" in export_path:
            feedback.append(f"PASS: Mix correctly exported to {os.path.basename(export_path)}")
        else:
            feedback.append(f"PARTIAL: Mix exported, but named {os.path.basename(export_path)}")
    elif export_exists:
        feedback.append("FAIL: Exported file exists but is empty/corrupt")
    else:
        feedback.append("FAIL: Compliant mix was not exported")

    # Final pass determination
    threshold = metadata.get('pass_threshold', 75)
    passed = score >= threshold
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " | ".join(feedback)
    }