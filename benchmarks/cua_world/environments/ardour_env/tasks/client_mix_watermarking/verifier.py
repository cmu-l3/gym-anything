#!/usr/bin/env python3
"""
Verifier for client_mix_watermarking task.

Checks that the agent assembled a watermarked client preview mix with proper
track names, region placements at regular timestamps, correct gain staging,
and exported the final audio mix.
"""

import math
import os
import json
import tempfile
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

PASS_THRESHOLD = 65.0
SAMPLE_RATE = 44100

def get_audio_routes(root):
    """Retrieve all audio tracks (excluding Master/Monitor buses)."""
    routes = []
    for route in root.iter('Route'):
        flags = route.get('flags', '')
        if 'MasterOut' in flags or 'MonitorOut' in flags:
            continue
        if route.get('default-type') == 'audio':
            routes.append(route)
    return routes

def get_route_gain_db(route):
    """Calculate the gain setting of an Ardour track in decibels."""
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
    """Get the start positions and lengths of all audio regions in a track."""
    regions = []
    for playlist in root.iter('Playlist'):
        pl_name = playlist.get('name', '')
        # Ardour links playlists to routes loosely, match base names
        base = pl_name.rsplit('.', 1)[0] if '.' in pl_name else pl_name
        if base.lower() == route_name.lower() or pl_name.lower().startswith(route_name.lower()):
            for region in playlist.iter('Region'):
                regions.append({
                    'name': region.get('name', ''),
                    'position': int(region.get('position', '0')),
                    'length': int(region.get('length', '0')),
                })
    return regions

def verify_client_mix_watermarking(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "copy_from_env not available"}

    score = 0.0
    feedback = []

    # 1. Retrieve the exported JSON from bash script
    tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_json.close()
    try:
        copy_from_env("/tmp/task_result.json", tmp_json.name)
        with open(tmp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0.0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(tmp_json.name):
            os.unlink(tmp_json.name)

    # 2. Retrieve and parse Ardour session XML
    session_remote = "/home/ga/Audio/sessions/MyProject/MyProject.ardour"
    tmp_session = tempfile.NamedTemporaryFile(delete=False, suffix='.ardour')
    tmp_session.close()

    try:
        copy_from_env(session_remote, tmp_session.name)
        tree = ET.parse(tmp_session.name)
        root = tree.getroot()
    except Exception as e:
        return {"passed": False, "score": 0.0, "feedback": f"Failed to parse Ardour XML: {e}"}
    finally:
        if os.path.exists(tmp_session.name):
            os.unlink(tmp_session.name)

    routes = get_audio_routes(root)
    
    # Identify specific tracks
    piano_track = None
    watermark_track = None
    
    for r in routes:
        name = r.get('name', '').lower()
        if 'piano' in name or ('mix' in name and 'watermark' not in name):
            piano_track = r
        if 'watermark' in name or 'voice' in name:
            watermark_track = r

    # CRITERION 1: Track Setup & Naming (15 pts)
    if piano_track is not None and watermark_track is not None:
        score += 15
        feedback.append("PASS: Found 'Piano Mix' and 'Watermark' tracks.")
    else:
        feedback.append("FAIL: Did not find both tracks with expected names.")
        if piano_track: feedback.append("PARTIAL: Found 'Piano Mix' track.")
        if watermark_track: feedback.append("PARTIAL: Found 'Watermark' track.")

    # CRITERION 2: Gain Staging (20 pts)
    # Piano Mix ~ -4dB (-5.5 to -2.5)
    # Watermark ~ +2dB (+0.5 to +3.5)
    if piano_track is not None:
        p_gain = get_route_gain_db(piano_track)
        if -5.5 <= p_gain <= -2.5:
            score += 10
            feedback.append(f"PASS: Piano Mix gain is {p_gain:.1f} dB (within target).")
        else:
            feedback.append(f"FAIL: Piano Mix gain is {p_gain:.1f} dB (expected ~-4 dB).")

    if watermark_track is not None:
        w_gain = get_route_gain_db(watermark_track)
        if 0.5 <= w_gain <= 3.5:
            score += 10
            feedback.append(f"PASS: Watermark gain is {w_gain:.1f} dB (within target).")
        else:
            feedback.append(f"FAIL: Watermark gain is {w_gain:.1f} dB (expected ~+2 dB).")

    # CRITERION 3: Watermark Placement (30 pts, 10 per region)
    # Target positions: 5s, 15s, 25s. Tolerance: +/- 0.5 seconds (22050 samples)
    matched_targets = set()
    if watermark_track is not None:
        w_name = watermark_track.get('name', '')
        w_regions = get_regions_for_route(root, w_name)
        
        target_positions = [5 * SAMPLE_RATE, 15 * SAMPLE_RATE, 25 * SAMPLE_RATE]
        tolerance = int(0.5 * SAMPLE_RATE)
        
        for reg in w_regions:
            pos = reg['position']
            for i, target in enumerate(target_positions):
                if i not in matched_targets and abs(pos - target) <= tolerance:
                    matched_targets.add(i)
                    score += 10
                    break
                    
        feedback.append(f"Watermark placements found: {len(matched_targets)}/3.")
    else:
        feedback.append("FAIL: Cannot check watermark placements (track missing).")

    # CRITERION 4: Session Saved (10 pts)
    if piano_track is not None or watermark_track is not None:
        score += 10
        feedback.append("PASS: Session changes were successfully saved.")

    # CRITERION 5: Exported Preview (25 pts)
    export_exists = result.get('export_exists', False)
    export_size = result.get('export_size_bytes', 0)
    created_during = result.get('file_created_during_task', False)

    if export_exists and created_during and export_size > 100000:
        score += 25
        feedback.append("PASS: Preview mix successfully exported.")
    elif export_exists and created_during:
        score += 10
        feedback.append(f"PARTIAL: Exported file found but size is suspiciously small ({export_size} bytes).")
    elif export_exists:
        feedback.append("FAIL: Exported file exists but was not created/modified during the task.")
    else:
        feedback.append("FAIL: Preview mix not found at expected path.")

    # VLM Trajectory checking for anti-gaming (Does not strictly alter score here)
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        frames = sample_trajectory_frames(traj, n=3)
        final = get_final_screenshot(traj)
        if frames and final:
            # Trajectory check functionality confirms images exist
            pass
    except Exception as e:
        logger.warning(f"VLM dependencies unavailable or error: {e}")

    # Final Pass Condition
    key_work_done = (len(matched_targets) >= 2) and export_exists
    passed = (score >= PASS_THRESHOLD) and key_work_done

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }