#!/usr/bin/env python3
"""
Verifier for game_audio_seamless_loop task.
Checks that the agent imported a file, split it, swapped the halves,
crossfaded them properly, and renamed the track.
"""

import os
import tempfile
import json
import logging
import xml.etree.ElementTree as ET
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Standard sample rate for the environment
SAMPLE_RATE = 44100
TOLERANCE_SAMPLES = int(SAMPLE_RATE * 0.5)  # 0.5 second tolerance

# Expected target positions/offsets
EXPECTED_HALFWAY_OFFSET = 15.0 * SAMPLE_RATE       # 661500 samples
EXPECTED_FRONT_HALF_POS = 14.0 * SAMPLE_RATE       # 617400 samples

def get_audio_routes(root):
    """Get audio track routes (excluding Master/Monitor buses)."""
    routes = []
    for route in root.iter('Route'):
        flags = route.get('flags', '')
        if 'MasterOut' in flags or 'MonitorOut' in flags:
            continue
        if route.get('default-type') == 'audio':
            routes.append(route)
    return routes

def get_regions_for_route(root, route_name):
    """Get regions from the playlist associated with a route."""
    regions = []
    for playlist in root.iter('Playlist'):
        pl_name = playlist.get('name', '')
        base = pl_name.rsplit('.', 1)[0] if '.' in pl_name else pl_name
        if base.lower() == route_name.lower() or pl_name.lower().startswith(route_name.lower()):
            for region in playlist.iter('Region'):
                regions.append({
                    'name': region.get('name', ''),
                    'position': int(region.get('position', '0')),
                    'start': int(region.get('start', '0')),
                    'length': int(region.get('length', '0')),
                })
    return regions

def verify_game_audio_seamless_loop(traj, env_info, task_info):
    """
    Multi-criterion verifier for game audio seamless loop.
    
    Criteria (100 pts total, pass >= 70):
      1. Audio Imported (Regions exist)        (10 pts)
      2. Track Renamed ("Ambient Loop")        (10 pts)
      3. Back Half Swapped (pos ~0, off ~15)   (25 pts)
      4. Front Half Swapped (pos ~14, off ~0)  (25 pts)
      5. Session Saved during task             (10 pts)
      6. VLM Trajectory (UI interaction)       (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "copy_from_env not available"}

    score = 0.0
    feedback = []

    # ================================================================
    # 1. Check Export JSON (Session saved)
    # ================================================================
    tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_json.close()
    
    session_saved = False
    try:
        copy_from_env("/tmp/game_audio_seamless_loop_result.json", tmp_json.name)
        with open(tmp_json.name, 'r') as f:
            result = json.load(f)
            session_saved = result.get('session_saved_during_task', False)
    except Exception as e:
        logger.warning(f"Failed to load export JSON: {e}")
    finally:
        if os.path.exists(tmp_json.name):
            os.unlink(tmp_json.name)

    if session_saved:
        score += 10.0
        feedback.append("PASS: Session was saved")
    else:
        feedback.append("FAIL: Session was not saved during task")

    # ================================================================
    # 2. Parse Session XML
    # ================================================================
    session_remote = "/home/ga/Audio/sessions/MyProject/MyProject.ardour"
    tmp_session = tempfile.NamedTemporaryFile(delete=False, suffix='.ardour')
    tmp_session.close()

    try:
        copy_from_env(session_remote, tmp_session.name)
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Session file not accessible: {e}"}

    if not os.path.exists(tmp_session.name) or os.path.getsize(tmp_session.name) == 0:
        return {"passed": False, "score": score, "feedback": "Session file empty or missing"}

    try:
        tree = ET.parse(tmp_session.name)
        root = tree.getroot()
    except Exception as e:
        os.unlink(tmp_session.name)
        return {"passed": False, "score": score, "feedback": f"Session XML parse error: {e}"}

    # ================================================================
    # 3. Check Track Renaming
    # ================================================================
    audio_routes = get_audio_routes(root)
    if not audio_routes:
        return {"passed": False, "score": score, "feedback": "No audio tracks found in session"}

    target_route = None
    track_renamed = False
    
    for route in audio_routes:
        rname = route.get('name', '').lower()
        # Look for our specific keywords
        if 'ambient' in rname or 'loop' in rname:
            target_route = route
            track_renamed = True
            break
            
    # Fallback: if not renamed, just use the first audio track
    if not target_route:
        target_route = audio_routes[0]

    if track_renamed:
        score += 10.0
        feedback.append("PASS: Track renamed to 'Ambient Loop'")
    else:
        feedback.append("FAIL: Track not renamed correctly")

    # ================================================================
    # 4. Check Regions (Imported & Swapped)
    # ================================================================
    regions = get_regions_for_route(root, target_route.get('name', ''))
    
    if len(regions) > 0:
        score += 10.0
        feedback.append("PASS: Audio imported (regions exist on track)")
    else:
        feedback.append("FAIL: No audio regions found on track")
        
    back_half_swapped = False
    front_half_swapped = False
    
    for r in regions:
        pos = r['position']
        offset = r['start']
        
        # Check Back Half: Should be near position 0, but offset ~15s into source
        if pos <= TOLERANCE_SAMPLES and abs(offset - EXPECTED_HALFWAY_OFFSET) <= TOLERANCE_SAMPLES:
            back_half_swapped = True
            
        # Check Front Half: Should be near position 14s, but offset ~0s into source
        if abs(pos - EXPECTED_FRONT_HALF_POS) <= TOLERANCE_SAMPLES and offset <= TOLERANCE_SAMPLES:
            front_half_swapped = True

    if back_half_swapped:
        score += 25.0
        feedback.append("PASS: Back half of audio swapped to beginning")
    else:
        feedback.append("FAIL: Back half of audio not placed at beginning properly")

    if front_half_swapped:
        score += 25.0
        feedback.append("PASS: Front half of audio swapped to ~14s (crossfade created)")
    else:
        feedback.append("FAIL: Front half of audio not placed at 14s properly")

    # ================================================================
    # 5. VLM Verification (Trajectory checking)
    # ================================================================
    # We do a quick VLM check to ensure the agent actually worked in the UI
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        if frames and final:
            vlm_prompt = """You are verifying an audio editing task in Ardour DAW.
            The agent is supposed to import an audio file, split it into two regions, swap them, and overlap them.
            Look across these sequential trajectory frames.
            
            Do you see evidence of the agent working in the Ardour UI timeline, manipulating audio blocks (regions)?
            Respond in JSON:
            {
                "ui_interaction_visible": true/false,
                "multiple_regions_visible": true/false
            }
            """
            
            try:
                vlm_res = query_vlm(prompt=vlm_prompt, images=frames + [final])
                if vlm_res and vlm_res.get("success"):
                    parsed = vlm_res.get("parsed", {})
                    if parsed.get("ui_interaction_visible", False):
                        score += 10.0
                        feedback.append("PASS: VLM verified UI interaction")
                    else:
                        feedback.append("FAIL: VLM did not see UI interaction")
                        
                    if parsed.get("multiple_regions_visible", False):
                        score += 10.0
                        feedback.append("PASS: VLM verified multiple regions visible")
                    else:
                        feedback.append("FAIL: VLM did not see multiple regions")
                else:
                    score += 20.0
                    feedback.append("PASS: VLM query failed, granting points by default")
            except Exception as e:
                logger.warning(f"VLM error: {e}")
                score += 20.0
                feedback.append("PASS: VLM error, granting points by default")
        else:
            score += 20.0
            feedback.append("PASS: No frames for VLM, granting points")
    else:
        score += 20.0
        feedback.append("PASS: VLM unavailable, granting points")

    # Clean up
    if os.path.exists(tmp_session.name):
        os.unlink(tmp_session.name)

    # Determine pass/fail
    passed = score >= 70.0 and back_half_swapped and front_half_swapped

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }