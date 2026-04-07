#!/usr/bin/env python3
"""
Verifier for escape_room_audio_puzzle task.

Checks that the agent created a dual-channel puzzle:
1. Tracks named correctly (Hidden Message, Gramophone).
2. Extreme panning (Hard L / Hard R).
3. Temporal offset (Message starts at 5s) and trimmed to ~10s.
4. Reversed processing applied to the clue.
5. Marker placed at 5s.
6. Exported valid WAV.
"""

import math
import os
import json
import tempfile
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

SAMPLE_RATE = 44100
TARGET_OFFSET_SEC = 5.0
TARGET_TRIM_SEC = 10.0


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

def get_route_pan(route):
    for ctrl in route.iter('Controllable'):
        name = ctrl.get('name', '')
        if 'pan' in name.lower():
            try:
                # Ardour 6/7/8 use values typically 0.0 (Left) to 1.0 (Right), 0.5 (Center)
                return float(ctrl.get('value', '0.5'))
            except (ValueError, TypeError):
                pass
    return 0.5

def get_regions_for_route(root, route_name):
    regions = []
    for playlist in root.iter('Playlist'):
        pl_name = playlist.get('name', '')
        # Handle playlist names like "TrackName.1"
        base = pl_name.rsplit('.', 1)[0] if '.' in pl_name else pl_name
        if base.lower() == route_name.lower() or pl_name.lower().startswith(route_name.lower()):
            for region in playlist.iter('Region'):
                regions.append(region)
    return regions

def get_markers(root):
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


# ---------- Main verifier ----------

def verify_escape_room_audio_puzzle(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "copy_from_env not available"}

    score = 0.0
    feedback = []

    # 1. Fetch export JSON
    tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_json.close()
    try:
        copy_from_env("/tmp/escape_room_result.json", tmp_json.name)
        with open(tmp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0.0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(tmp_json.name):
            os.unlink(tmp_json.name)

    # 2. Fetch Session XML
    session_remote = "/home/ga/Audio/sessions/MyProject/MyProject.ardour"
    tmp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.ardour')
    tmp_xml.close()

    try:
        copy_from_env(session_remote, tmp_xml.name)
        tree = ET.parse(tmp_xml.name)
        root = tree.getroot()
    except Exception as e:
        return {"passed": False, "score": 0.0, "feedback": f"Failed to read/parse session XML: {e}"}
    finally:
        if os.path.exists(tmp_xml.name):
            os.unlink(tmp_xml.name)

    routes = get_audio_routes(root)
    
    # Track identifiers
    msg_route = None
    gram_route = None
    
    for route in routes:
        name = route.get('name', '').lower()
        if 'hidden' in name or 'message' in name or 'clue' in name:
            msg_route = route
        elif 'gramophone' in name or 'music' in name or 'piano' in name:
            gram_route = route

    # ================================================================
    # CRITERION 1: Track Names (15 pts)
    # ================================================================
    if msg_route is not None and gram_route is not None:
        score += 15.0
        feedback.append("PASS: Required tracks 'Hidden Message' and 'Gramophone' found.")
    else:
        if msg_route is not None:
            score += 7.5
            feedback.append("PARTIAL: Only 'Hidden Message' track found.")
        elif gram_route is not None:
            score += 7.5
            feedback.append("PARTIAL: Only 'Gramophone' track found.")
        else:
            feedback.append("FAIL: Neither required track was found.")

    # ================================================================
    # CRITERION 2: Extreme Panning (20 pts)
    # ================================================================
    pan_passed = False
    if msg_route and gram_route:
        msg_pan = get_route_pan(msg_route)
        gram_pan = get_route_pan(gram_route)
        
        # Hard Left usually <= 0.1, Hard Right >= 0.9
        if msg_pan <= 0.1 and gram_pan >= 0.9:
            score += 20.0
            pan_passed = True
            feedback.append("PASS: Hard Left/Right panning successfully applied.")
        else:
            feedback.append(f"FAIL: Panning incorrect. Hidden: {msg_pan:.2f} (expected <0.1), Gramophone: {gram_pan:.2f} (expected >0.9).")
    else:
        feedback.append("FAIL: Cannot check panning due to missing tracks.")

    # ================================================================
    # CRITERION 3: Temporal Offset & Trim (20 pts)
    # ================================================================
    offset_passed = False
    if msg_route:
        regions = get_regions_for_route(root, msg_route.get('name', ''))
        if regions:
            # Check the primary region
            r = regions[0]
            pos_samples = int(r.get('position', '0'))
            len_samples = int(r.get('length', '0'))
            
            target_pos = int(TARGET_OFFSET_SEC * SAMPLE_RATE)
            target_len = int(TARGET_TRIM_SEC * SAMPLE_RATE)
            
            pos_diff_sec = abs(pos_samples - target_pos) / SAMPLE_RATE
            len_diff_sec = abs(len_samples - target_len) / SAMPLE_RATE
            
            if pos_diff_sec <= 0.5:
                score += 10.0
                offset_passed = True
                feedback.append("PASS: Hidden message starts at correct offset (~5s).")
            else:
                feedback.append(f"FAIL: Hidden message starts at {pos_samples/SAMPLE_RATE:.2f}s (expected 5.0s).")
                
            if len_diff_sec <= 2.0:  # 2 seconds tolerance for "approx 10s"
                score += 10.0
                feedback.append("PASS: Hidden message trimmed to correct duration (~10s).")
            else:
                feedback.append(f"FAIL: Hidden message length is {len_samples/SAMPLE_RATE:.2f}s (expected ~10.0s).")
        else:
            feedback.append("FAIL: No regions found on Hidden Message track.")

    # ================================================================
    # CRITERION 4: Reverse Processing (15 pts)
    # ================================================================
    if msg_route:
        regions = get_regions_for_route(root, msg_route.get('name', ''))
        reversed_found = False
        for r in regions:
            # In Ardour, reversing often appends "reversed" to the source file or region name
            name = r.get('name', '').lower()
            if 'revers' in name or 'backwards' in name:
                reversed_found = True
                break
            # Also check if there's a property flag
            for prop in r.iter('Property'):
                if prop.get('name') == 'reverse-audio' and prop.get('value') == '1':
                    reversed_found = True
                    break
                    
        if reversed_found:
            score += 15.0
            feedback.append("PASS: Hidden message region is reversed.")
        else:
            feedback.append("FAIL: No evidence of reverse processing on Hidden Message region.")
    
    # ================================================================
    # CRITERION 5: Marker Placement (10 pts)
    # ================================================================
    markers = get_markers(root)
    marker_found = False
    target_pos = int(TARGET_OFFSET_SEC * SAMPLE_RATE)
    
    for m in markers:
        if 'clue' in m['name'].lower():
            diff_sec = abs(m['start'] - target_pos) / SAMPLE_RATE
            if diff_sec <= 1.0:
                marker_found = True
                break
                
    if marker_found:
        score += 10.0
        feedback.append("PASS: 'Clue Start' marker found at ~5s.")
    else:
        feedback.append("FAIL: 'Clue Start' marker not found at ~5s.")

    # ================================================================
    # CRITERION 6: Exported WAV (20 pts)
    # ================================================================
    export_exists = result_data.get('export_exists', False)
    file_created = result_data.get('file_created_during_task', False)
    size_bytes = result_data.get('export_size_bytes', 0)
    
    if export_exists and size_bytes > 102400: # > 100KB
        if file_created:
            score += 20.0
            feedback.append("PASS: Valid WAV file exported during task.")
        else:
            score += 10.0
            feedback.append("PARTIAL: WAV file exists but may not have been created during this session.")
    else:
        feedback.append("FAIL: Required WAV file not exported or too small.")

    # Evaluate final passing status
    passed = score >= task_info.get('metadata', {}).get('pass_threshold', 65.0) and pan_passed and offset_passed
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " | ".join(feedback)
    }