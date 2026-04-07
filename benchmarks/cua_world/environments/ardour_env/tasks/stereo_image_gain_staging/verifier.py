#!/usr/bin/env python3
"""
Verifier for stereo_image_gain_staging task.
Occupation: Sound Engineering Technician (SOC 27-4014)
Industry: Music Recording / Studio Production

Checks that the agent created 5 specified tracks, applied correct pan,
gain staging, and mute states, and placed a session marker.
"""

import math
import os
import sys
import tempfile
import logging
import json
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# ---------- Ardour XML helpers ----------

def get_audio_routes(root):
    """Retrieve all audio routes, excluding master and monitor buses."""
    routes = []
    for route in root.iter('Route'):
        flags = route.get('flags', '')
        if 'MasterOut' in flags or 'MonitorOut' in flags:
            continue
        if route.get('default-type') == 'audio':
            routes.append(route)
    return routes


def get_markers(root):
    """Retrieve user-created location markers."""
    markers = []
    for loc in root.iter('Location'):
        flags = loc.get('flags', '')
        if any(f in flags for f in ('IsSessionRange', 'IsAutoLoop', 'IsAutoPunch')):
            continue
        markers.append({
            'name': loc.get('name', ''),
            'start': int(loc.get('start', '0')),
            'end': int(loc.get('end', '0')),
            'flags': flags,
        })
    return markers


def get_route_gain_db(route):
    """Calculate gain in dB from linear gain factor."""
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


def get_route_pan(route):
    """Retrieve pan-azimuth value (0.0=left, 0.5=center, 1.0=right)."""
    for ctrl in route.iter('Controllable'):
        name = ctrl.get('name', '')
        if 'pan' in name.lower():
            try:
                return float(ctrl.get('value', '0.5'))
            except (ValueError, TypeError):
                return 0.5
    return 0.5


def get_route_muted(route):
    """Determine if a track is muted."""
    for ctrl in route.iter('Controllable'):
        if ctrl.get('name') == 'mute':
            try:
                val = float(ctrl.get('value', '0'))
                return val > 0
            except (ValueError, TypeError):
                return False
    # Fallback to route attribute
    return route.get('muted', '0') in ('1', 'yes', 'true')


# ---------- Main verifier ----------

def verify_stereo_image_gain_staging(traj, env_info, task_info):
    """
    Multi-criterion verifier for stereo image and gain staging.
    
    Criteria (100 pts total, pass >= 60):
      1. Track Names (25 pts): 5 points per correctly named track
      2. Pan Positions (25 pts): 5 points per correct pan position
      3. Gain Levels (25 pts): 5 points per correctly staged gain
      4. Mute States (15 pts): 3 points per correct mute state
      5. Marker (10 pts): Presence of "Verse 1" marker
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    score = 0.0
    feedback = []

    # Read the exported task results (contains anti-gaming metrics)
    result_json_remote = "/tmp/stereo_image_result.json"
    tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_json.close()

    task_result = {}
    try:
        copy_from_env(result_json_remote, tmp_json.name)
        with open(tmp_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        logger.warning(f"Could not read task result JSON: {e}")
    finally:
        if os.path.exists(tmp_json.name):
            os.unlink(tmp_json.name)

    # Read Ardour session file
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

    # Extract all audio routes
    audio_routes = get_audio_routes(root)
    
    # Check for "do nothing" state
    if len(audio_routes) <= 1:
        return {"passed": False, "score": 0, "feedback": "FAIL: Did not create required tracks (found 1 or 0 tracks)."}

    # Define acceptable track aliases for matching
    expected_tracks = {
        'kick': {
            'aliases': ['kick drum', 'kick', 'bass drum', 'bd'],
            'target_pan': 0.5, 'target_gain': -3.0, 'target_mute': False
        },
        'bass': {
            'aliases': ['bass guitar', 'bass', 'upright'],
            'target_pan': 0.5, 'target_gain': -6.0, 'target_mute': False
        },
        'guitar_l': {
            'aliases': ['electric guitar l', 'guitar l', 'gtr l', 'electric l', 'eg l'],
            'target_pan': 0.0, 'target_gain': -9.0, 'target_mute': True
        },
        'guitar_r': {
            'aliases': ['electric guitar r', 'guitar r', 'gtr r', 'electric r', 'eg r'],
            'target_pan': 1.0, 'target_gain': -9.0, 'target_mute': True
        },
        'vocal': {
            'aliases': ['lead vocal', 'vocal', 'vox', 'lead vox', 'singer'],
            'target_pan': 0.5, 'target_gain': 0.0, 'target_mute': False
        }
    }

    # Map found routes to expected slots
    matched_routes = {}
    for route in audio_routes:
        rname = route.get('name', '').lower()
        if rname == 'audio 1':  # Ignore default empty track
            continue
            
        for key, config in expected_tracks.items():
            if key in matched_routes:
                continue
            if any(alias in rname for alias in config['aliases']):
                matched_routes[key] = route
                break

    # 1. Evaluate Track Names (5 pts per track)
    names_score = len(matched_routes) * 5.0
    score += names_score
    feedback.append(f"Track Names: {len(matched_routes)}/5 matched ({names_score} pts)")

    # Initialize sub-scores
    pan_score = 0.0
    gain_score = 0.0
    mute_score = 0.0

    # 2, 3, 4. Evaluate Pan, Gain, and Mute for each matched track
    for key, route in matched_routes.items():
        config = expected_tracks[key]
        
        # Pan (±0.08 tolerance)
        pan_val = get_route_pan(route)
        if abs(pan_val - config['target_pan']) <= 0.08:
            pan_score += 5.0
            
        # Gain (±1.5 dB tolerance)
        gain_db = get_route_gain_db(route)
        if abs(gain_db - config['target_gain']) <= 1.5:
            gain_score += 5.0
            
        # Mute (boolean exact match)
        is_muted = get_route_muted(route)
        if is_muted == config['target_mute']:
            mute_score += 3.0

    score += pan_score
    score += gain_score
    score += mute_score

    feedback.append(f"Pan Positions: {int(pan_score)}/25 pts")
    feedback.append(f"Gain Levels: {int(gain_score)}/25 pts")
    feedback.append(f"Mute States: {int(mute_score)}/15 pts")

    # 5. Evaluate Marker (10 pts)
    markers = get_markers(root)
    verse_marker_found = False
    for m in markers:
        if 'verse' in m['name'].lower():
            verse_marker_found = True
            break
            
    if verse_marker_found:
        score += 10.0
        feedback.append("Marker: 'Verse 1' found (10 pts)")
    else:
        feedback.append("Marker: 'Verse 1' not found (0 pts)")

    # Cleanup
    os.unlink(tmp_session.name)

    # Final verdict
    passed = score >= 60.0
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " | ".join(feedback),
        "details": {
            "tracks_matched": len(matched_routes),
            "verse_marker_found": verse_marker_found
        }
    }