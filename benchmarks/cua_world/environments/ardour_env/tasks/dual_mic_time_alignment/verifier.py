#!/usr/bin/env python3
"""
Verifier for dual_mic_time_alignment task.
Occupation: Dialogue Editor / Re-recording Mixer
Industry: Motion Picture / Post-Production

Checks that the agent imported a file to two specific tracks, aligned the lavalier
exactly 220 samples later than the boom, applied correct gain staging, and grouped
the tracks with edit sharing enabled.
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
    routes = []
    for route in root.iter('Route'):
        flags = route.get('flags', '')
        if 'MasterOut' in flags or 'MonitorOut' in flags:
            continue
        if route.get('default-type') == 'audio':
            routes.append(route)
    return routes


def get_route_by_alias(routes, aliases):
    for route in routes:
        rname = route.get('name', '').lower()
        if any(alias in rname for alias in aliases):
            return route
    return None


def get_first_region_position(root, route_name):
    """Find the first region in the playlist associated with the route."""
    for playlist in root.iter('Playlist'):
        pl_name = playlist.get('name', '')
        base = pl_name.rsplit('.', 1)[0] if '.' in pl_name else pl_name
        if base.lower() == route_name.lower() or pl_name.lower().startswith(route_name.lower()):
            for region in playlist.iter('Region'):
                return int(region.get('position', '0'))
    return None


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


def is_edit_grouped(root, route1, route2):
    """Check if both routes share an active RouteGroup with edit='1'."""
    group1 = route1.get('group')
    group2 = route2.get('group')
    
    # Must share the same group ID
    if not group1 or not group2 or group1 != group2:
        return False
        
    for rg in root.iter('RouteGroup'):
        if rg.get('id') == group1:
            if rg.get('edit', '0') == '1':
                return True
    return False


# ---------- Main verifier ----------

def verify_dual_mic_time_alignment(traj, env_info, task_info):
    """
    Multi-criterion verifier for dual mic time alignment.

    Criteria (100 pts total, pass >= 70):
      1. Tracks setup & import (Lav and Boom exist + regions) (20 pts)
      2. Boom mic position (at 0)                             (15 pts)
      3. Lav mic time alignment (220 samples offset)          (30 pts) -> Required
      4. Gain staging (Boom ~-6dB, Lav ~0dB)                  (20 pts)
      5. Route grouping (Edit enabled on same group)          (15 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "copy_from_env not available"}

    score = 0.0
    feedback = []
    metadata = task_info.get('metadata', {})

    session_remote = "/home/ga/Audio/sessions/MyProject/MyProject.ardour"
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.ardour')
    tmp.close()

    try:
        copy_from_env(session_remote, tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0.0, "feedback": f"Session not accessible: {e}"}

    if not os.path.exists(tmp.name) or os.path.getsize(tmp.name) == 0:
        return {"passed": False, "score": 0.0, "feedback": "Session empty or missing"}

    try:
        tree = ET.parse(tmp.name)
        root = tree.getroot()
    except Exception as e:
        os.unlink(tmp.name)
        return {"passed": False, "score": 0.0, "feedback": f"XML parse error: {e}"}

    routes = get_audio_routes(root)
    
    # ================================================================
    # CRITERION 1: Track Setup & Import (20 pts)
    # ================================================================
    lav_route = get_route_by_alias(routes, ['lav'])
    boom_route = get_route_by_alias(routes, ['boom'])
    
    lav_pos = get_first_region_position(root, lav_route.get('name', '')) if lav_route else None
    boom_pos = get_first_region_position(root, boom_route.get('name', '')) if boom_route else None
    
    tracks_ok = 0
    if lav_route and lav_pos is not None:
        tracks_ok += 10
        feedback.append("Found Lav track with audio")
    if boom_route and boom_pos is not None:
        tracks_ok += 10
        feedback.append("Found Boom track with audio")
        
    score += tracks_ok
    if tracks_ok < 20:
        feedback.append("Missing required tracks or imported audio")

    # ================================================================
    # CRITERION 2: Boom Mic Position (15 pts)
    # ================================================================
    boom_target = metadata.get('boom_target_sample', 0)
    boom_tol = metadata.get('boom_sample_tolerance', 10)
    
    if boom_pos is not None:
        if abs(boom_pos - boom_target) <= boom_tol:
            score += 15.0
            feedback.append(f"Boom placed at start (pos: {boom_pos})")
        else:
            feedback.append(f"Boom not at start (pos: {boom_pos})")

    # ================================================================
    # CRITERION 3: Lav Mic Time Alignment (30 pts)
    # ================================================================
    lav_target = metadata.get('lav_target_sample', 220)
    lav_tol = metadata.get('lav_sample_tolerance', 20)
    time_aligned = False
    
    if lav_pos is not None:
        if abs(lav_pos - lav_target) <= lav_tol:
            score += 30.0
            time_aligned = True
            feedback.append(f"Lav precisely time-aligned (pos: {lav_pos})")
        else:
            feedback.append(f"Lav time alignment incorrect (expected ~{lav_target}, got {lav_pos})")

    # ================================================================
    # CRITERION 4: Gain Staging (20 pts)
    # ================================================================
    boom_target_db = metadata.get('boom_target_gain_db', -6.0)
    lav_target_db = metadata.get('lav_target_gain_db', 0.0)
    gain_tol = metadata.get('gain_tolerance_db', 1.5)
    
    gains_ok = 0
    if boom_route:
        boom_db = get_route_gain_db(boom_route)
        if abs(boom_db - boom_target_db) <= gain_tol:
            gains_ok += 10
            feedback.append(f"Boom gain correct ({boom_db:.1f} dB)")
        else:
            feedback.append(f"Boom gain incorrect ({boom_db:.1f} dB)")
            
    if lav_route:
        lav_db = get_route_gain_db(lav_route)
        if abs(lav_db - lav_target_db) <= gain_tol:
            gains_ok += 10
            feedback.append(f"Lav gain correct ({lav_db:.1f} dB)")
        else:
            feedback.append(f"Lav gain incorrect ({lav_db:.1f} dB)")
            
    score += gains_ok

    # ================================================================
    # CRITERION 5: Route Grouping (15 pts)
    # ================================================================
    if boom_route and lav_route:
        if is_edit_grouped(root, boom_route, lav_route):
            score += 15.0
            feedback.append("Tracks grouped with Edit sharing enabled")
        else:
            feedback.append("Tracks not grouped or Edit sharing disabled")

    # Clean up
    os.unlink(tmp.name)
    
    # Calculate final result
    pass_threshold = metadata.get('pass_threshold', 70)
    # Fail automatically if time-alignment wasn't achieved (it's the core skill being tested)
    passed = score >= pass_threshold and time_aligned

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }