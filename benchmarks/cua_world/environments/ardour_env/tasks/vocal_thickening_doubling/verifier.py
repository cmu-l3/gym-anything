#!/usr/bin/env python3
"""
Verifier for vocal_thickening_doubling task.
Checks that the agent created two duplicate tracks, configured hard panning,
attenuated the volume to -6 dB, and nudged the audio regions by 20ms and 35ms.
"""

import math
import os
import tempfile
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# ---------- Ardour XML helpers ----------

def get_audio_routes(root):
    """Extract all audio track routes."""
    routes = []
    for route in root.iter('Route'):
        flags = route.get('flags', '')
        if 'MasterOut' in flags or 'MonitorOut' in flags:
            continue
        if route.get('default-type') == 'audio':
            routes.append(route)
    return routes

def get_route_by_name(root, name_pattern):
    """Find an audio route matching a name pattern."""
    for route in get_audio_routes(root):
        if name_pattern.lower() in route.get('name', '').lower():
            return route
    return None

def get_route_pan(route):
    """Extract panning value (0.0 = Left, 1.0 = Right, 0.5 = Center)."""
    for ctrl in route.iter('Controllable'):
        if 'pan' in ctrl.get('name', '').lower():
            try:
                return float(ctrl.get('value', '0.5'))
            except (ValueError, TypeError):
                return 0.5
    return 0.5

def get_route_gain_db(route):
    """Extract gain in decibels."""
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

def get_regions_for_route(root, route_name):
    """Extract regions mapped to a specific route playlist."""
    regions = []
    for playlist in root.iter('Playlist'):
        pl_name = playlist.get('name', '')
        # Handle Ardour's playlist naming scheme (e.g., "Double Left.1")
        base = pl_name.rsplit('.', 1)[0] if '.' in pl_name else pl_name
        if base.lower() == route_name.lower() or pl_name.lower().startswith(route_name.lower()):
            for region in playlist.iter('Region'):
                regions.append({
                    'name': region.get('name', ''),
                    'position': int(region.get('position', '0')),
                    'length': int(region.get('length', '0')),
                })
    return regions


# ---------- Main verifier ----------

def verify_vocal_thickening(traj, env_info, task_info):
    """
    Evaluates the Ardour session XML for vocal thickening configurations.

    Criteria (100 points, Pass >= 60):
      1. Duplicate tracks exist & named properly (20 pts)
      2. Hard panning configured (L < 0.2, R > 0.8) (20 pts)
      3. Double tracks gain staging (-8 to -4 dB) (20 pts)
      4. Left Double nudged (+20ms / 882 samples ± 220) (20 pts)
      5. Right Double nudged (+35ms / 1543 samples ± 220) (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "copy_from_env not available"}

    score = 0.0
    feedback = []

    # Retrieve metadata constraints
    metadata = task_info.get('metadata', {})
    expected_left_samples = metadata.get('left_delay_samples', 882)
    expected_right_samples = metadata.get('right_delay_samples', 1543)
    tolerance = metadata.get('tolerance_samples', 220)
    target_gain = metadata.get('target_gain_db', -6)
    gain_tol = metadata.get('gain_tolerance_db', 2)

    session_remote = "/home/ga/Audio/sessions/MyProject/MyProject.ardour"
    tmp_session = tempfile.NamedTemporaryFile(delete=False, suffix='.ardour')
    tmp_session.close()

    try:
        copy_from_env(session_remote, tmp_session.name)
    except Exception as e:
        return {"passed": False, "score": 0.0, "feedback": f"Session file not accessible: {e}"}

    if not os.path.exists(tmp_session.name) or os.path.getsize(tmp_session.name) == 0:
        return {"passed": False, "score": 0.0, "feedback": "Session file is empty or missing"}

    try:
        tree = ET.parse(tmp_session.name)
        root = tree.getroot()
    except Exception as e:
        os.unlink(tmp_session.name)
        return {"passed": False, "score": 0.0, "feedback": f"Session XML parse error: {e}"}

    # Verify tracks
    route_left = get_route_by_name(root, "double left")
    route_right = get_route_by_name(root, "double right")

    if route_left is not None and route_right is not None:
        score += 20.0
        feedback.append("PASS: Found 'Double Left' and 'Double Right' tracks.")
    else:
        feedback.append("FAIL: Missing one or both double tracks (check track names).")
        # Without the tracks, we can't test the other criteria effectively.
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    # Verify Panning
    pan_l = get_route_pan(route_left)
    pan_r = get_route_pan(route_right)
    if pan_l <= 0.2 and pan_r >= 0.8:
        score += 20.0
        feedback.append(f"PASS: Panning correct (L={pan_l:.2f}, R={pan_r:.2f}).")
    else:
        feedback.append(f"FAIL: Panning incorrect (Expected L<0.2, R>0.8. Got L={pan_l:.2f}, R={pan_r:.2f}).")

    # Verify Gain
    gain_l = get_route_gain_db(route_left)
    gain_r = get_route_gain_db(route_right)
    gain_range = (target_gain - gain_tol, target_gain + gain_tol)

    if gain_range[0] <= gain_l <= gain_range[1] and gain_range[0] <= gain_r <= gain_range[1]:
        score += 20.0
        feedback.append(f"PASS: Gains are within {gain_range} dB (L={gain_l:.1f}, R={gain_r:.1f}).")
    else:
        feedback.append(f"FAIL: Gains not within -8 to -4 dB (L={gain_l:.1f}, R={gain_r:.1f}).")

    # Verify Regions / Micro-delays
    left_regions = get_regions_for_route(root, route_left.get('name'))
    right_regions = get_regions_for_route(root, route_right.get('name'))

    left_start = min([r['position'] for r in left_regions]) if left_regions else -1
    right_start = min([r['position'] for r in right_regions]) if right_regions else -1

    # Check Left Double Nudge (Target: 882 ± 220 samples)
    if left_start >= 0 and abs(left_start - expected_left_samples) <= tolerance:
        score += 20.0
        feedback.append(f"PASS: Left double nudged correctly (Position: {left_start}).")
    else:
        feedback.append(f"FAIL: Left double nudge incorrect (Expected ~{expected_left_samples}, Got {left_start}).")

    # Check Right Double Nudge (Target: 1543 ± 220 samples)
    if right_start >= 0 and abs(right_start - expected_right_samples) <= tolerance:
        score += 20.0
        feedback.append(f"PASS: Right double nudged correctly (Position: {right_start}).")
    else:
        feedback.append(f"FAIL: Right double nudge incorrect (Expected ~{expected_right_samples}, Got {right_start}).")

    # Clean up
    os.unlink(tmp_session.name)

    passed = score >= metadata.get('pass_threshold', 60.0)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "pan_left": pan_l,
            "pan_right": pan_r,
            "gain_left": gain_l,
            "gain_right": gain_r,
            "start_left_samples": left_start,
            "start_right_samples": right_start
        }
    }