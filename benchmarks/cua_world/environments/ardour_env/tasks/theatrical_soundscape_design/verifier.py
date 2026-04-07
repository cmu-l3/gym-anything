#!/usr/bin/env python3
"""
Verifier for theatrical_soundscape_design task.
Occupation: Sound Designer
Industry: Performing Arts Companies

Checks that the agent created tracks with correct names, imported/positioned regions,
set panning and gain staging properly, added a region fade, and placed markers.
"""

import math
import os
import sys
import tempfile
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Hard tolerances
POSITION_TOLERANCE_SAMPLES = int(44100 * 0.5)  # +/- 0.5 seconds
GAIN_TOLERANCE_DB = 2.0
PAN_TOLERANCE = 0.15


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


def get_route_by_name(root, name):
    for route in get_audio_routes(root):
        if route.get('name', '').lower() == name.lower():
            return route
    return None


def get_markers(root):
    markers = []
    for loc in root.iter('Location'):
        flags = loc.get('flags', '')
        if any(f in flags for f in ('IsSessionRange', 'IsAutoLoop', 'IsAutoPunch')):
            continue
        markers.append({
            'name': loc.get('name', ''),
            'start': int(loc.get('start', '0')),
        })
    return markers


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


def get_route_pan_azimuth(route):
    for ctrl in route.iter('Controllable'):
        if 'azimuth' in ctrl.get('name', '').lower():
            try:
                return float(ctrl.get('value', '0.5'))
            except (ValueError, TypeError):
                return 0.5
    return 0.5


def get_earliest_region(root, route_name):
    earliest = None
    min_pos = float('inf')
    for playlist in root.iter('Playlist'):
        pl_name = playlist.get('name', '')
        base = pl_name.rsplit('.', 1)[0] if '.' in pl_name else pl_name
        if base.lower() == route_name.lower() or pl_name.lower().startswith(route_name.lower()):
            for region in playlist.iter('Region'):
                pos = int(region.get('position', '0'))
                if pos < min_pos:
                    min_pos = pos
                    earliest = {
                        'position': pos,
                        'fade_in_active': region.get('fade-in-active', '0') == '1',
                        'fade_in_length': int(region.get('fade-in-length', '0'))
                    }
    return earliest


# ---------- Main verifier ----------

def verify_theatrical_soundscape(traj, env_info, task_info):
    """
    Multi-criterion verifier for theatrical soundscape design.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "copy_from_env not available"}

    score = 0.0
    feedback = []

    # Check anti-gaming stats
    try:
        tmp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp_res.close()
        copy_from_env("/tmp/theatrical_soundscape_result.json", tmp_res.name)
        import json
        with open(tmp_res.name, 'r') as f:
            res_data = json.load(f)
        os.unlink(tmp_res.name)
        
        start_ts = int(res_data.get("task_start_timestamp", 0))
        mod_ts = int(res_data.get("session_modified_timestamp", 0))
        if mod_ts > 0 and mod_ts < start_ts:
            return {"passed": False, "score": 0.0, "feedback": "Session was not modified during the task."}
    except Exception as e:
        logger.warning(f"Could not verify timestamps: {e}")

    # Parse Session XML
    session_remote = "/home/ga/Audio/sessions/MyProject/MyProject.ardour"
    tmp_sess = tempfile.NamedTemporaryFile(delete=False, suffix='.ardour')
    tmp_sess.close()

    try:
        copy_from_env(session_remote, tmp_sess.name)
    except Exception as e:
        return {"passed": False, "score": 0.0, "feedback": f"Session file not accessible: {e}"}

    try:
        tree = ET.parse(tmp_sess.name)
        root = tree.getroot()
    except Exception as e:
        os.unlink(tmp_sess.name)
        return {"passed": False, "score": 0.0, "feedback": f"Session XML parse error: {e}"}
    finally:
        if os.path.exists(tmp_sess.name):
            os.unlink(tmp_sess.name)

    # ================================================================
    # CRITERION 1: Track Setup & Naming (15 pts)
    # ================================================================
    expected_tracks = ["Piano_Atmos", "Left_Monologue", "Right_Interruption"]
    found_tracks = {}
    for t in expected_tracks:
        route = get_route_by_name(root, t)
        if route is not None:
            found_tracks[t] = route
            score += 5.0
            feedback.append(f"PASS: Track '{t}' exists.")
        else:
            feedback.append(f"FAIL: Track '{t}' missing.")

    if not found_tracks:
        return {"passed": False, "score": 0.0, "feedback": "No expected tracks found. " + " | ".join(feedback)}

    # ================================================================
    # CRITERION 2: Temporal Arrangement (25 pts)
    # Piano (0s), Left (2.0s), Right (5.0s)
    # ================================================================
    expected_pos = {
        "Piano_Atmos": 0,
        "Left_Monologue": 44100 * 2,
        "Right_Interruption": 44100 * 5
    }
    
    pos_score = 0.0
    for t, expected_samples in expected_pos.items():
        if t in found_tracks:
            region = get_earliest_region(root, t)
            if region:
                diff = abs(region['position'] - expected_samples)
                if diff <= POSITION_TOLERANCE_SAMPLES:
                    pos_score += (25.0 / 3.0)
                    feedback.append(f"PASS: '{t}' region placed correctly (~{expected_samples/44100:.1f}s).")
                else:
                    feedback.append(f"FAIL: '{t}' region at {region['position']/44100:.1f}s, expected {expected_samples/44100:.1f}s.")
            else:
                feedback.append(f"FAIL: No region found on '{t}'.")
    score += pos_score

    # ================================================================
    # CRITERION 3: Spatial Panning (20 pts)
    # Left_Monologue (0.0), Right_Interruption (1.0), Piano (0.5)
    # ================================================================
    expected_pan = {
        "Piano_Atmos": 0.5,
        "Left_Monologue": 0.0,
        "Right_Interruption": 1.0
    }
    
    pan_score = 0.0
    for t, expected_azimuth in expected_pan.items():
        if t in found_tracks:
            azimuth = get_route_pan_azimuth(found_tracks[t])
            if abs(azimuth - expected_azimuth) <= PAN_TOLERANCE:
                pan_score += (20.0 / 3.0)
                feedback.append(f"PASS: '{t}' panned correctly (azimuth {azimuth:.2f}).")
            else:
                feedback.append(f"FAIL: '{t}' pan incorrect (azimuth {azimuth:.2f}, expected {expected_azimuth:.2f}).")
    score += pan_score

    # ================================================================
    # CRITERION 4: Gain Staging (20 pts)
    # Piano (-12dB), Left (-6dB), Right (0dB)
    # ================================================================
    expected_gain = {
        "Piano_Atmos": -12.0,
        "Left_Monologue": -6.0,
        "Right_Interruption": 0.0
    }
    
    gain_score = 0.0
    for t, expected_db in expected_gain.items():
        if t in found_tracks:
            db = get_route_gain_db(found_tracks[t])
            if abs(db - expected_db) <= GAIN_TOLERANCE_DB:
                gain_score += (20.0 / 3.0)
                feedback.append(f"PASS: '{t}' gain correct ({db:.1f} dB).")
            else:
                feedback.append(f"FAIL: '{t}' gain incorrect ({db:.1f} dB, expected {expected_db} dB).")
    score += gain_score

    # ================================================================
    # CRITERION 5: Fade-in & Markers (20 pts)
    # ================================================================
    fade_markers_score = 0.0
    
    # Check Fade
    if "Piano_Atmos" in found_tracks:
        piano_reg = get_earliest_region(root, "Piano_Atmos")
        if piano_reg:
            # Check length >= 1.9s to be safe
            if piano_reg['fade_in_active'] and piano_reg['fade_in_length'] >= (44100 * 1.9):
                fade_markers_score += 10.0
                feedback.append("PASS: Piano region has >= 2.0s fade-in.")
            else:
                feedback.append(f"FAIL: Piano region fade-in missing or too short ({piano_reg['fade_in_length']} samples).")

    # Check Markers
    expected_marker_pos = [0, 44100 * 2, 44100 * 5]
    markers = get_markers(root)
    matched_markers = 0
    for emp in expected_marker_pos:
        for m in markers:
            if abs(m['start'] - emp) <= POSITION_TOLERANCE_SAMPLES:
                matched_markers += 1
                break
                
    if matched_markers >= 3:
        fade_markers_score += 10.0
        feedback.append("PASS: 3 cue markers placed at correct locations.")
    elif matched_markers > 0:
        fade_markers_score += (matched_markers * 3.0)
        feedback.append(f"PARTIAL: {matched_markers}/3 cue markers found.")
    else:
        feedback.append("FAIL: No matching cue markers found.")
        
    score += fade_markers_score

    # Final evaluation
    passed = score >= 60.0 and pos_score >= 8.0 and pan_score >= 6.0
    
    return {
        "passed": bool(passed),
        "score": float(score),
        "feedback": " | ".join(feedback)
    }