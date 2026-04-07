#!/usr/bin/env python3
"""
Verifier for asmr_haas_stereo_widening task.

Parses the Ardour session XML to verify:
1. Two tracks exist and are named correctly (Left/Right Whisper)
2. Both tracks contain an audio region
3. Tracks are hard-panned
4. The Haas micro-delay is applied (one track's region is offset by 200-8800 samples)
5. Gain is reduced to ASMR levels (-24 to -12 dB)
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

def get_audio_routes(root):
    """Get all audio tracks, excluding Master and Monitor buses."""
    routes = []
    for route in root.iter('Route'):
        flags = route.get('flags', '')
        if 'MasterOut' in flags or 'MonitorOut' in flags:
            continue
        if route.get('default-type') == 'audio':
            routes.append(route)
    return routes

def get_route_pan(route):
    """Extract pan azimuth value. 0.0 is Left, 0.5 is Center, 1.0 is Right."""
    for ctrl in route.iter('Controllable'):
        if 'pan' in ctrl.get('name', '').lower():
            try:
                return float(ctrl.get('value', '0.5'))
            except (ValueError, TypeError):
                pass
    return 0.5

def get_route_gain_db(route):
    """Extract gain in dB."""
    for ctrl in route.iter('Controllable'):
        if ctrl.get('name', '') in ('gaincontrol', 'gain'):
            try:
                val = float(ctrl.get('value', '1.0'))
                if val <= 0: return -120.0
                return 20 * math.log10(val)
            except (ValueError, TypeError):
                pass
    return 0.0

def get_first_region_position(root, track_name):
    """Find the start position (in samples) of the earliest region on the given track."""
    for pl in root.iter('Playlist'):
        pl_name = pl.get('name', '')
        # Ardour playlists are often named "TrackName", "TrackName.1", etc.
        base_name = pl_name.rsplit('.', 1)[0] if '.' in pl_name else pl_name
        
        if base_name.lower() == track_name.lower() or pl_name.lower().startswith(track_name.lower()):
            regions = list(pl.iter('Region'))
            if regions:
                positions = []
                for r in regions:
                    try:
                        positions.append(int(r.get('position', '0')))
                    except ValueError:
                        pass
                if positions:
                    return min(positions)
    return None

def verify_asmr_haas(traj, env_info, task_info):
    """
    Verification logic. Max score 100. Pass threshold 65.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_pan_left_max = metadata.get('expected_pan_left_max', 0.20)
    expected_pan_right_min = metadata.get('expected_pan_right_min', 0.80)
    haas_delay_samples_min = metadata.get('haas_delay_samples_min', 200)
    haas_delay_samples_max = metadata.get('haas_delay_samples_max', 8800)
    gain_db_min = metadata.get('gain_db_min', -25.0)
    gain_db_max = metadata.get('gain_db_max', -11.0)
    pass_threshold = metadata.get('pass_threshold', 65)

    score = 0
    feedback_parts = []

    # 1. Anti-gaming check: Did the agent do anything?
    tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/asmr_haas_result.json", tmp_json.name)
        with open(tmp_json.name, 'r') as f:
            export_result = json.load(f)
            
        if not export_result.get('session_modified', False):
            return {"passed": False, "score": 0, "feedback": "Session file was not modified. No work detected."}
    except Exception as e:
        logger.warning(f"Could not read export json: {e}")
    finally:
        if os.path.exists(tmp_json.name):
            os.unlink(tmp_json.name)

    # 2. Parse Ardour XML
    session_remote = "/home/ga/Audio/sessions/MyProject/MyProject.ardour"
    tmp_ardour = tempfile.NamedTemporaryFile(delete=False, suffix='.ardour')
    tmp_ardour.close()

    try:
        copy_from_env(session_remote, tmp_ardour.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not copy session XML: {e}"}

    try:
        tree = ET.parse(tmp_ardour.name)
        root = tree.getroot()
    except Exception as e:
        os.unlink(tmp_ardour.name)
        return {"passed": False, "score": 0, "feedback": f"XML parse error: {e}"}

    audio_routes = get_audio_routes(root)
    
    # Identify Left and Right tracks
    left_track = None
    right_track = None
    
    for route in audio_routes:
        name = route.get('name', '').lower()
        if 'left' in name or ' L' in name or name.endswith(' l'):
            if not left_track: left_track = route
        if 'right' in name or ' R' in name or name.endswith(' r'):
            if not right_track: right_track = route

    # Criterion 1: Track Names (15 pts)
    if left_track and right_track:
        score += 15
        feedback_parts.append("Found Left and Right tracks")
    else:
        feedback_parts.append("Did not find distinctly named Left and Right tracks")
        # Fallback: if there are exactly 2 tracks, assign them arbitrarily to continue grading
        if len(audio_routes) >= 2 and not left_track and not right_track:
            left_track = audio_routes[0]
            right_track = audio_routes[1]
            feedback_parts.append("Proceeding with two available tracks for grading")
        else:
            return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    left_name = left_track.get('name', '')
    right_name = right_track.get('name', '')

    # Criterion 2: Audio Import (15 pts)
    left_pos = get_first_region_position(root, left_name)
    right_pos = get_first_region_position(root, right_name)
    
    if left_pos is not None and right_pos is not None:
        score += 15
        feedback_parts.append("Regions found on both tracks")
    else:
        feedback_parts.append("Missing audio regions on one or both tracks")
        # Can't check Haas without regions
        left_pos = left_pos or 0
        right_pos = right_pos or 0

    # Criterion 3: Stereo Panning (20 pts)
    l_pan = get_route_pan(left_track)
    r_pan = get_route_pan(right_track)
    
    pan_score = 0
    if l_pan <= expected_pan_left_max:
        pan_score += 10
    if r_pan >= expected_pan_right_min:
        pan_score += 10
        
    score += pan_score
    if pan_score == 20:
        feedback_parts.append("Tracks correctly hard-panned")
    else:
        feedback_parts.append(f"Panning incorrect (L:{l_pan:.2f}, R:{r_pan:.2f})")

    # Criterion 4: Haas Micro-Delay (30 pts)
    # The absolute difference between region start times must be between min and max samples
    if left_pos is not None and right_pos is not None:
        offset = abs(right_pos - left_pos)
        if haas_delay_samples_min <= offset <= haas_delay_samples_max:
            score += 30
            feedback_parts.append(f"Haas delay applied ({offset} samples)")
        else:
            feedback_parts.append(f"Haas delay incorrect or missing (offset = {offset} samples)")

    # Criterion 5: ASMR Gain Level (20 pts)
    l_gain = get_route_gain_db(left_track)
    r_gain = get_route_gain_db(right_track)
    
    gain_score = 0
    if gain_db_min <= l_gain <= gain_db_max:
        gain_score += 10
    if gain_db_min <= r_gain <= gain_db_max:
        gain_score += 10
        
    score += gain_score
    if gain_score == 20:
        feedback_parts.append(f"Gain levels in ASMR range (L:{l_gain:.1f}dB, R:{r_gain:.1f}dB)")
    else:
        feedback_parts.append(f"Gain levels outside expected range (L:{l_gain:.1f}dB, R:{r_gain:.1f}dB)")

    os.unlink(tmp_ardour.name)

    passed = score >= pass_threshold
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }