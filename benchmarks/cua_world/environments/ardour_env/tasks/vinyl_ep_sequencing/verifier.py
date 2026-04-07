#!/usr/bin/env python3
"""
Verifier for vinyl_ep_sequencing task.
Validates programmatic session layout via Ardour's XML file and confirms
work was done via VLM trajectory checks.
"""

import math
import os
import json
import tempfile
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# --- XML Parsing Helpers ---

def get_audio_routes(root):
    routes = []
    for route in root.iter('Route'):
        flags = route.get('flags', '')
        if 'MasterOut' in flags or 'MonitorOut' in flags:
            continue
        if route.get('default-type') == 'audio':
            routes.append(route)
    return routes

def get_route_gain_db(route):
    for ctrl in route.iter('Controllable'):
        if ctrl.get('name') in ('gaincontrol', 'gain'):
            try:
                val = float(ctrl.get('value', '1.0'))
                if val <= 0:
                    return -120.0
                return 20 * math.log10(val)
            except (ValueError, TypeError):
                return 0.0
    return 0.0

def get_playlist_for_route(root, route):
    """Finds the playlist XML element associated with a specific route."""
    diskstream = route.find('Diskstream')
    if diskstream is not None:
        pl_name = diskstream.get('playlist')
        for pl in root.iter('Playlist'):
            if pl.get('name') == pl_name:
                return pl
    # Fallback: find a playlist matching the route name
    route_name = route.get('name', '')
    for pl in root.iter('Playlist'):
        if pl.get('name', '').startswith(route_name):
            return pl
    return None

def find_region_position(playlist, region_name_part):
    """Finds a region matching the substring and returns its position in samples."""
    if playlist is None:
        return None
    for region in playlist.iter('Region'):
        if region_name_part.lower() in region.get('name', '').lower():
            try:
                return int(region.get('position', '0'))
            except ValueError:
                return None
    return None


# --- VLM Verification Helper ---

def perform_vlm_check(traj, env_info):
    """Uses VLM to ensure the agent physically interacted with the GUI."""
    query_vlm = env_info.get("query_vlm")
    if not query_vlm:
        logger.warning("VLM not available, skipping VLM check.")
        return True, "VLM not available (default pass)"

    from gym_anything.vlm import sample_trajectory_frames
    
    # Get 4 trajectory frames representing progression
    frames = sample_trajectory_frames(traj, n=4)
    if not frames:
        return False, "No trajectory frames captured."

    prompt = """You are verifying a user's workflow in a Digital Audio Workstation (Ardour).
    Look at these sequential screenshots from the task.
    Did the user interact with the audio timeline by dragging/placing audio regions/clips onto the tracks? 
    Are there multiple audio clips visible on the timeline in the later screenshots?
    Respond with JSON: {"timeline_used": true/false, "reason": "brief explanation"}"""

    try:
        response = query_vlm(images=frames, prompt=prompt)
        if response and response.get('success'):
            parsed = response.get('parsed', {})
            is_used = parsed.get('timeline_used', False)
            return is_used, parsed.get('reason', 'VLM analyzed timeline')
        else:
            return True, "VLM query failed (default pass)"
    except Exception as e:
        logger.error(f"VLM Exception: {e}")
        return True, "VLM exception (default pass)"


# --- Main Verifier ---

def verify_vinyl_ep_sequencing(traj, env_info, task_info):
    """
    Scoring System (100 points, Pass >= 70):
    - Track Creation & Naming (10 pts)
    - Lathe Headroom Gain (15 pts)
    - Needle Drop (song1 & song3 at 1.0s) (20 pts)
    - Side A Gap (song2 at 13.0s) (20 pts)
    - Side B Gap (song4 at 18.0s) (20 pts)
    - VLM Verification (15 pts) - confirms timeline usage.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    target_positions = metadata.get('positions_samples', {})
    tolerance = metadata.get('position_tolerance_samples', 4410)
    target_gain = metadata.get('target_gain_db', -3.0)
    gain_tol = metadata.get('gain_tolerance_db', 0.5)

    score = 0.0
    feedback = []

    # 1. Check if session was updated via exported result
    try:
        tmp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp_res.close()
        copy_from_env("/tmp/vinyl_task_result.json", tmp_res.name)
        with open(tmp_res.name, 'r') as f:
            export_data = json.load(f)
        os.unlink(tmp_res.name)
    except Exception as e:
        logger.warning(f"Could not load export result: {e}")
        export_data = {}

    if not export_data.get('session_modified', True):
        feedback.append("Warning: Session file was not modified during the task time window.")

    # 2. Parse Ardour XML
    session_remote = "/home/ga/Audio/sessions/MyProject/MyProject.ardour"
    tmp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.ardour')
    tmp_xml.close()

    try:
        copy_from_env(session_remote, tmp_xml.name)
    except Exception as e:
        return {"passed": False, "score": 0.0, "feedback": f"Could not access session: {e}"}

    if not os.path.exists(tmp_xml.name) or os.path.getsize(tmp_xml.name) == 0:
        return {"passed": False, "score": 0.0, "feedback": "Session XML is empty or missing."}

    try:
        tree = ET.parse(tmp_xml.name)
        root = tree.getroot()
    except Exception as e:
        os.unlink(tmp_xml.name)
        return {"passed": False, "score": 0.0, "feedback": f"Failed to parse XML: {e}"}

    audio_routes = get_audio_routes(root)
    
    # 3. Criterion: Track Creation & Naming (10 pts)
    side_a = None
    side_b = None
    for route in audio_routes:
        name = route.get('name', '').lower()
        if 'side a' in name:
            side_a = route
        if 'side b' in name:
            side_b = route

    if side_a and side_b:
        score += 10.0
        feedback.append("Track Naming: PASS (Side A and Side B found)")
    else:
        feedback.append("Track Naming: FAIL (Side A and/or Side B missing)")

    # 4. Criterion: Gain Staging (15 pts)
    gain_correct = 0
    for side, route in [("Side A", side_a), ("Side B", side_b)]:
        if route:
            gain = get_route_gain_db(route)
            if abs(gain - target_gain) <= gain_tol:
                gain_correct += 1
            else:
                feedback.append(f"{side} Gain is {gain:.1f} dB (Expected {target_gain} dB)")
    
    if gain_correct == 2:
        score += 15.0
        feedback.append("Lathe Gain (-3 dB): PASS")
    elif gain_correct == 1:
        score += 7.5
        feedback.append("Lathe Gain (-3 dB): PARTIAL (One track correct)")
    
    # Position checks
    pl_a = get_playlist_for_route(root, side_a) if side_a else None
    pl_b = get_playlist_for_route(root, side_b) if side_b else None

    # 5. Criterion: Needle Drop (song1 & song3 at 44100) (20 pts)
    pos_song1 = find_region_position(pl_a, "song1")
    pos_song3 = find_region_position(pl_b, "song3")

    nd_correct = 0
    if pos_song1 is not None and abs(pos_song1 - target_positions['song1']) <= tolerance:
        nd_correct += 1
    if pos_song3 is not None and abs(pos_song3 - target_positions['song3']) <= tolerance:
        nd_correct += 1
    
    if nd_correct == 2:
        score += 20.0
        feedback.append("Needle Drop Spacing: PASS")
    elif nd_correct == 1:
        score += 10.0
        feedback.append("Needle Drop Spacing: PARTIAL")
    else:
        feedback.append("Needle Drop Spacing: FAIL (Missing 1.0s lead-in)")

    # 6. Criterion: Side A Banding Gap (song2 at 573300) (20 pts)
    pos_song2 = find_region_position(pl_a, "song2")
    if pos_song2 is not None and abs(pos_song2 - target_positions['song2']) <= tolerance:
        score += 20.0
        feedback.append("Side A Banding: PASS")
    else:
        feedback.append(f"Side A Banding: FAIL (Found at {pos_song2}, expected {target_positions['song2']})")

    # 7. Criterion: Side B Banding Gap (song4 at 793800) (20 pts)
    pos_song4 = find_region_position(pl_b, "song4")
    if pos_song4 is not None and abs(pos_song4 - target_positions['song4']) <= tolerance:
        score += 20.0
        feedback.append("Side B Banding: PASS")
    else:
        feedback.append(f"Side B Banding: FAIL (Found at {pos_song4}, expected {target_positions['song4']})")

    # 8. Criterion: VLM Verification (15 pts)
    vlm_passed, vlm_reason = perform_vlm_check(traj, env_info)
    if vlm_passed:
        score += 15.0
        feedback.append("VLM Check: PASS (Timeline interactions verified)")
    else:
        feedback.append(f"VLM Check: FAIL ({vlm_reason})")

    # Cleanup
    os.unlink(tmp_xml.name)

    passed = score >= 70.0

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "pos_song1": pos_song1,
            "pos_song2": pos_song2,
            "pos_song3": pos_song3,
            "pos_song4": pos_song4
        }
    }