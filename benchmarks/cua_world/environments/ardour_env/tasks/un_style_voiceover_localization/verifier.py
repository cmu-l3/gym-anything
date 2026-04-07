#!/usr/bin/env python3
"""
Verifier for un_style_voiceover_localization task.
Occupation: Audio and Video Technician (SOC 27-4011)
Industry: Motion Picture and Video Production

This verifier parses the Ardour XML session file to precisely evaluate:
1. Track creation and naming
2. Gain ducking (-15 dB)
3. Spatial separation ( panning )
4. Temporal offset (region shifted by exactly 2.0s)
5. Valid exported output file.
"""

import math
import os
import json
import tempfile
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def get_audio_routes(root):
    """Filter to only include standard audio tracks."""
    routes = []
    for route in root.iter('Route'):
        flags = route.get('flags', '')
        if 'MasterOut' in flags or 'MonitorOut' in flags:
            continue
        if route.get('default-type') == 'audio':
            routes.append(route)
    return routes

def get_route_by_alias(routes, aliases):
    """Find a route by checking if its name contains any of the target aliases."""
    for route in routes:
        name = route.get('name', '').lower()
        if any(alias in name for alias in aliases):
            return route
    return None

def get_route_gain_db(route):
    """Convert linear gain controllable to decibels."""
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
    """Get panning value (0.0 is left, 0.5 is center, 1.0 is right in Ardour azimuth)."""
    for ctrl in route.iter('Controllable'):
        name = ctrl.get('name', '').lower()
        if 'pan' in name or 'azimuth' in name:
            try:
                return float(ctrl.get('value', '0.5'))
            except (ValueError, TypeError):
                return 0.5
    return 0.5

def get_earliest_region_position(root, route):
    """Find the start position (in samples) of the earliest region on the route's playlist."""
    # Find the playlist ID assigned to this route
    playlist_id = None
    for ds in route.iter('Diskstream'):
        playlist_id = ds.get('playlist')
        break
    
    if not playlist_id:
        # Fallback: try matching by name
        route_name = route.get('name', '')
        for pl in root.iter('Playlist'):
            pl_name = pl.get('name', '')
            base = pl_name.rsplit('.', 1)[0] if '.' in pl_name else pl_name
            if base.lower() == route_name.lower():
                playlist_id = pl.get('id')
                break

    if not playlist_id:
        return None

    # Find regions in that playlist
    earliest = None
    for pl in root.iter('Playlist'):
        if pl.get('id') == playlist_id or pl.get('orig_id') == playlist_id:
            for region in pl.iter('Region'):
                try:
                    pos = int(region.get('position', '0'))
                    if earliest is None or pos < earliest:
                        earliest = pos
                except ValueError:
                    continue
    return earliest

def verify_un_style_voiceover_localization(traj, env_info, task_info):
    """
    Evaluates the UN-Style voiceover mix.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    ducking_target = metadata.get('ducking_target_db', -15)
    ducking_tol = metadata.get('ducking_tolerance_db', 3)
    target_samples = metadata.get('offset_target_samples', 88200)  # 2.0s at 44.1kHz
    target_tol = metadata.get('offset_tolerance_samples', 8820)    # 0.2s tolerance

    score = 0
    feedback_parts = []
    
    # 1. Read JSON result from export_result.sh
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_data = {}
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.warning(f"Could not read result JSON: {e}")
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Read Ardour Session XML
    session_remote = "/home/ga/Audio/sessions/MyProject/MyProject.ardour"
    temp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.ardour')
    try:
        copy_from_env(session_remote, temp_xml.name)
        if not os.path.exists(temp_xml.name) or os.path.getsize(temp_xml.name) == 0:
            return {"passed": False, "score": 0, "feedback": "Session file is empty or missing"}
            
        tree = ET.parse(temp_xml.name)
        root = tree.getroot()
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to parse Ardour XML: {e}"}
    finally:
        if os.path.exists(temp_xml.name):
            os.unlink(temp_xml.name)

    routes = get_audio_routes(root)
    
    # Criterion 1: Track Creation (15 pts)
    original_route = get_route_by_alias(routes, ['original', 'interview'])
    dub_route = get_route_by_alias(routes, ['translated', 'dub', 'voiceover'])

    if original_route is not None and dub_route is not None:
        score += 15
        feedback_parts.append("Both tracks found")
    else:
        feedback_parts.append("Failed to find 'Original Audio' or 'Translated Dub' tracks")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Gain Ducking (20 pts)
    # Original should be approx -15 dB. Dub should be near 0 dB.
    orig_gain = get_route_gain_db(original_route)
    dub_gain = get_route_gain_db(dub_route)
    
    if abs(orig_gain - ducking_target) <= ducking_tol:
        score += 20
        feedback_parts.append(f"Original ducked correctly ({orig_gain:.1f} dB)")
    elif orig_gain < -3.0:
        score += 10
        feedback_parts.append(f"Original ducked partially ({orig_gain:.1f} dB)")
    else:
        feedback_parts.append(f"Original NOT ducked ({orig_gain:.1f} dB)")

    # Criterion 3: Spatial Panning (20 pts)
    # Original should be left (< 0.4), Dub should be right (> 0.6)
    orig_pan = get_route_pan(original_route)
    dub_pan = get_route_pan(dub_route)
    
    if orig_pan < 0.45 and dub_pan > 0.55:
        score += 20
        feedback_parts.append(f"Tracks spatially separated (Orig:{orig_pan:.2f}, Dub:{dub_pan:.2f})")
    elif orig_pan != 0.5 or dub_pan != 0.5:
        score += 10
        feedback_parts.append(f"Tracks partially panned (Orig:{orig_pan:.2f}, Dub:{dub_pan:.2f})")
    else:
        feedback_parts.append("Tracks left at center pan")

    # Criterion 4: Temporal Offset (25 pts)
    # Dub should be shifted ~2.0 seconds (88200 samples)
    dub_pos = get_earliest_region_position(root, dub_route)
    orig_pos = get_earliest_region_position(root, original_route)
    
    if dub_pos is not None:
        # Calculate relative offset if original isn't exactly at 0
        effective_offset = dub_pos - (orig_pos if orig_pos else 0)
        
        if abs(effective_offset - target_samples) <= target_tol:
            score += 25
            feedback_parts.append(f"Dub offset correctly (offset: {effective_offset} samples)")
        else:
            feedback_parts.append(f"Dub offset incorrect (offset: {effective_offset} samples)")
    else:
        feedback_parts.append("No regions found on Dub track")

    # Criterion 5: Final Export (20 pts)
    export_exists = result_data.get('export_exists', False)
    export_created = result_data.get('export_created_during_task', False)
    export_size = result_data.get('export_size_bytes', 0)

    if export_exists and export_created and export_size > 10000:
        score += 20
        feedback_parts.append("Valid mix exported")
    elif export_exists and export_size > 10000:
        score += 10
        feedback_parts.append("Mix exported (but timestamp precedes task start)")
    else:
        feedback_parts.append("Final mix not exported successfully")

    passed = score >= metadata.get('pass_threshold', 65)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }