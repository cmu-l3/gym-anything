#!/usr/bin/env python3
"""
Verifier for dark_ride_audio_sync task.
Occupation: AV Technician / Theatrical Sound Designer
Industry: Amusement & Recreation

Checks that the agent set up a dark ride audio session with proper track naming,
panning, region placement, gain sharing, and exported the reference mix.
"""

import math
import os
import json
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

def find_route_by_keywords(routes, keywords):
    for route in routes:
        rname = route.get('name', '').lower()
        if any(kw.lower() in rname for kw in keywords):
            return route
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

def get_route_pan(route):
    # In Ardour, panning is usually stored in a controllable with 'pan' or 'azimuth' in the name
    for ctrl in route.iter('Controllable'):
        name = ctrl.get('name', '').lower()
        if 'pan' in name or 'azimuth' in name:
            try:
                return float(ctrl.get('value', '0.5'))
            except (ValueError, TypeError):
                pass
    return 0.5

def get_earliest_region_position(root, route_name):
    earliest = None
    for playlist in root.iter('Playlist'):
        pl_name = playlist.get('name', '')
        base = pl_name.rsplit('.', 1)[0] if '.' in pl_name else pl_name
        if base.lower() == route_name.lower() or pl_name.lower().startswith(route_name.lower()):
            for region in playlist.iter('Region'):
                try:
                    pos = int(region.get('position', '0'))
                    if earliest is None or pos < earliest:
                        earliest = pos
                except ValueError:
                    continue
    return earliest

def get_markers(root):
    markers = []
    for loc in root.iter('Location'):
        flags = loc.get('flags', '')
        if any(f in flags for f in ('IsSessionRange', 'IsAutoLoop', 'IsAutoPunch')):
            continue
        markers.append({
            'name': loc.get('name', ''),
            'start': int(loc.get('start', '0'))
        })
    return markers

def get_route_groups(root):
    groups = []
    for group in root.iter('RouteGroup'):
        members = []
        for member in group.iter('RouteGroupMember'):
            members.append(member.get('route-id', ''))
        groups.append({
            'name': group.get('name', ''),
            'gain_shared': group.get('gain', '0') == '1',
            'members': members
        })
    return groups

# ---------- Main verifier ----------

def verify_dark_ride_audio_sync(traj, env_info, task_info):
    """
    Multi-criterion verifier for dark ride audio sync.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    pass_threshold = metadata.get('pass_threshold', 65)

    score = 0.0
    feedback = []

    # 1. Load result JSON from export script
    result_json_path = "/tmp/dark_ride_result.json"
    tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_json.close()

    result_data = {}
    try:
        copy_from_env(result_json_path, tmp_json.name)
        if os.path.exists(tmp_json.name) and os.path.getsize(tmp_json.name) > 0:
            with open(tmp_json.name, 'r') as f:
                result_data = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load result JSON: {e}")
    finally:
        if os.path.exists(tmp_json.name):
            os.unlink(tmp_json.name)

    # 2. Copy and parse Ardour session XML
    session_remote = "/home/ga/Audio/sessions/MyProject/MyProject.ardour"
    tmp_session = tempfile.NamedTemporaryFile(delete=False, suffix='.ardour')
    tmp_session.close()

    try:
        copy_from_env(session_remote, tmp_session.name)
    except Exception as e:
        return {"passed": False, "score": 0.0, "feedback": f"Session file not accessible: {e}"}

    if not os.path.exists(tmp_session.name) or os.path.getsize(tmp_session.name) == 0:
        return {"passed": False, "score": 0.0, "feedback": "Session file empty or missing"}

    try:
        tree = ET.parse(tmp_session.name)
        root = tree.getroot()
    except Exception as e:
        os.unlink(tmp_session.name)
        return {"passed": False, "score": 0.0, "feedback": f"Session XML parse error: {e}"}
    finally:
        if os.path.exists(tmp_session.name):
            os.unlink(tmp_session.name)

    # Extract required info from XML
    audio_routes = get_audio_routes(root)
    
    bgm_route = find_route_by_keywords(audio_routes, ['ambient', 'bgm'])
    left_route = find_route_by_keywords(audio_routes, ['left', 'scare l'])
    right_route = find_route_by_keywords(audio_routes, ['right', 'scare r'])

    # ================================================================
    # CRITERION 1: Track Names (15 pts - 5 pts each)
    # ================================================================
    tracks_found = 0
    if bgm_route is not None:
        tracks_found += 1
    if left_route is not None:
        tracks_found += 1
    if right_route is not None:
        tracks_found += 1
    
    score += (tracks_found * 5.0)
    if tracks_found == 3:
        feedback.append("PASS: All 3 tracks named correctly.")
    else:
        feedback.append(f"PARTIAL: Found {tracks_found}/3 required tracks.")

    # ================================================================
    # CRITERION 2: Region Placement & BGM Gain (25 pts)
    # ================================================================
    placement_score = 0
    bgm_pos = get_earliest_region_position(root, bgm_route.get('name', '')) if bgm_route else None
    if bgm_pos is not None and bgm_pos <= 22050:
        placement_score += 5.0
    
    left_pos = get_earliest_region_position(root, left_route.get('name', '')) if left_route else None
    if left_pos is not None and abs(left_pos - metadata.get('scare_left_position_samples', 441000)) <= metadata.get('position_tolerance_samples', 22050):
        placement_score += 5.0

    right_pos = get_earliest_region_position(root, right_route.get('name', '')) if right_route else None
    if right_pos is not None and abs(right_pos - metadata.get('scare_right_position_samples', 882000)) <= metadata.get('position_tolerance_samples', 22050):
        placement_score += 5.0

    if bgm_route is not None:
        bgm_gain = get_route_gain_db(bgm_route)
        if -9.0 <= bgm_gain <= -3.0:
            placement_score += 10.0
            feedback.append("PASS: BGM gain within target range.")
        else:
            feedback.append(f"FAIL: BGM gain out of range ({bgm_gain:.1f} dB).")
            
    score += placement_score
    feedback.append(f"Region Placement Score: {placement_score}/25")

    # ================================================================
    # CRITERION 3: Spatial Panning (20 pts - 10 per track)
    # ================================================================
    pan_score = 0
    if left_route is not None:
        left_pan = get_route_pan(left_route)
        if left_pan <= metadata.get('scare_left_pan_max', 0.2):
            pan_score += 10.0
            
    if right_route is not None:
        right_pan = get_route_pan(right_route)
        if right_pan >= metadata.get('scare_right_pan_min', 0.8):
            pan_score += 10.0
            
    score += pan_score
    if pan_score == 20:
        feedback.append("PASS: Hard panning applied correctly.")
    else:
        feedback.append(f"PARTIAL: Panning score {pan_score}/20.")

    # ================================================================
    # CRITERION 4: Route Grouping (20 pts)
    # 10 for group with both tracks, 10 for gain sharing
    # ================================================================
    group_score = 0
    if left_route is not None and right_route is not None:
        left_id = left_route.get('id')
        right_id = right_route.get('id')
        
        groups = get_route_groups(root)
        for g in groups:
            if left_id in g['members'] and right_id in g['members']:
                group_score += 10.0
                if g['gain_shared']:
                    group_score += 10.0
                break
                
        # Fallback check for direct attribute assignments in older Ardour
        if group_score == 0:
            l_grp = left_route.get('group-id')
            r_grp = right_route.get('group-id')
            if l_grp and r_grp and l_grp == r_grp:
                group_score += 10.0
                
    score += group_score
    feedback.append(f"Route Grouping Score: {group_score}/20")

    # ================================================================
    # CRITERION 5: Export & Markers (20 pts - 10 each)
    # ================================================================
    export_score = 0
    if result_data.get('export_exists', False) and result_data.get('export_size_bytes', 0) > 102400: # >100KB
        export_score += 10.0
        feedback.append("PASS: Valid reference WAV exported.")
    else:
        feedback.append("FAIL: Exported WAV missing or too small.")

    markers = get_markers(root)
    marker_hits = 0
    for m in markers:
        # Check near 10s or 20s
        if abs(m['start'] - 441000) <= 22050:
            marker_hits += 1
        elif abs(m['start'] - 882000) <= 22050:
            marker_hits += 1
            
    if marker_hits >= 2:
        export_score += 10.0
    elif marker_hits == 1:
        export_score += 5.0
        
    score += export_score

    # Final Evaluation
    passed = score >= pass_threshold
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "tracks_found": tracks_found,
            "region_score": placement_score,
            "pan_score": pan_score,
            "group_score": group_score,
            "export_score": export_score
        }
    }