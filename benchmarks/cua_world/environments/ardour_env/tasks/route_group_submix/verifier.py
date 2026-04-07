#!/usr/bin/env python3
"""
Verifier for route_group_submix task.
Occupation: Sound Engineering Technician (SOC 27-4014)

Checks that the agent created specific tracks, assigned them to route groups
with exact sharing properties, configured initial gain stages, and set mute states.
"""

import math
import os
import tempfile
import json
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Track name aliases to allow slight variations in agent output
TRACK_ALIASES = {
    'kick': ['kick', 'bd', 'bass drum', 'kick drum'],
    'snare': ['snare', 'sd', 'snare drum'],
    'overhead': ['overhead', 'oh', 'overheads', 'drum oh'],
    'lead_vocal': ['lead vocal', 'lead vox', 'vocal 1', 'main vocal', 'leadvocal'],
    'harmony_vocal': ['harmony vocal', 'harmony', 'bgv', 'backing vocal', 'harmonyvocal']
}

GROUP_ALIASES = {
    'drums': ['drum', 'drums', 'drum group', 'drum bus'],
    'vocals': ['vocal', 'vocals', 'vox', 'vocal group']
}

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

def get_route_groups(root):
    """Get all RouteGroups defined in the session."""
    groups = []
    for rg in root.iter('RouteGroup'):
        groups.append(rg)
    return groups

def get_route_group_id(route, root):
    """Determine the RouteGroup ID a given route belongs to."""
    # Method 1: PresentationInfo group attribute (most common in Ardour 6/7/8)
    pinfo = route.find('PresentationInfo')
    if pinfo is not None and pinfo.get('group'):
        return pinfo.get('group')
    
    # Method 2: Check RouteGroup elements for RouteGroupMember children
    route_id = route.get('id')
    for rg in root.iter('RouteGroup'):
        for member in rg.iter('RouteGroupMember'):
            if member.get('route-id') == route_id:
                return rg.get('id')
    return None

def get_route_gain_db(route):
    """Return gain of a route in dB."""
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

def is_route_muted(route):
    """Return True if the route is muted."""
    for ctrl in route.iter('Controllable'):
        if ctrl.get('name') == 'mute':
            return ctrl.get('value', '0') in ('1', '1.0000000', '1.0', 'yes', 'true')
    for mm in route.iter('MuteMaster'):
        if mm.get('muted', '0') in ('1', 'true', 'yes'):
            return True
    return False

def verify_route_group_submix(traj, env_info, task_info):
    """
    Multi-criterion verifier for route group organization task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "copy_from_env not available"}

    score = 0.0
    feedback = []

    # Verify session and load JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_json.close()
    
    try:
        copy_from_env("/tmp/route_group_submix_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0.0, "feedback": f"Failed to load export result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    if not result_data.get('session_file_exists', False):
        return {"passed": False, "score": 0.0, "feedback": "Session file missing."}

    # Anti-gaming: Ensure work was done
    initial_tracks = result_data.get('initial_track_count', 0)
    current_tracks = result_data.get('current_track_count', 0)
    if current_tracks <= initial_tracks:
        feedback.append(f"FAIL: No new tracks created (initial: {initial_tracks}, current: {current_tracks}).")
        return {"passed": False, "score": 0.0, "feedback": " ".join(feedback)}

    # Read the XML file
    session_remote = "/home/ga/Audio/sessions/MyProject/MyProject.ardour"
    tmp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.ardour')
    tmp_xml.close()

    try:
        copy_from_env(session_remote, tmp_xml.name)
        tree = ET.parse(tmp_xml.name)
        root = tree.getroot()
    except Exception as e:
        if os.path.exists(tmp_xml.name): os.unlink(tmp_xml.name)
        return {"passed": False, "score": 0.0, "feedback": f"XML parse error: {e}"}

    metadata = task_info.get('metadata', {})
    track_targets = metadata.get('track_targets', {})
    group_targets = metadata.get('group_targets', {})
    tolerance_db = metadata.get('tolerance_db', 2.0)

    # 1. Identify routes by aliases
    routes = get_audio_routes(root)
    found_routes = {}
    for r in routes:
        name = r.get('name', '').lower()
        for t_key, aliases in TRACK_ALIASES.items():
            if t_key not in found_routes and any(a in name for a in aliases):
                found_routes[t_key] = r
                break

    # Criterion 1: Track Names (20 pts)
    tracks_found_count = len(found_routes)
    if tracks_found_count == 5:
        score += 20.0
        feedback.append("PASS: All 5 expected tracks found.")
    else:
        pts = tracks_found_count * 4.0
        score += pts
        feedback.append(f"PARTIAL: Found {tracks_found_count}/5 tracks.")

    # 2. Identify groups by aliases
    xml_groups = get_route_groups(root)
    found_groups = {}
    for g in xml_groups:
        gname = g.get('name', '').lower()
        for g_key, aliases in GROUP_ALIASES.items():
            if g_key not in found_groups and any(a in gname for a in aliases):
                found_groups[g_key] = g
                break

    # Criterion 2: Route Groups Exist (15 pts)
    groups_found_count = len(found_groups)
    if groups_found_count == 2:
        score += 15.0
        feedback.append("PASS: Both 'Drums' and 'Vocals' groups created.")
    elif groups_found_count == 1:
        score += 7.0
        feedback.append("PARTIAL: Only 1 route group created.")
    else:
        feedback.append("FAIL: Route groups not found.")

    # Criterion 3: Group Membership (20 pts)
    # Criterion 5: Gain Levels (20 pts)
    # Criterion 6: Mute States (10 pts)
    membership_correct = 0
    gain_correct = 0
    mute_correct = 0

    for t_key, target in track_targets.items():
        route = found_routes.get(t_key)
        if not route:
            continue

        # Check membership
        gid = get_route_group_id(route, root)
        expected_g_key = target['group_alias']
        expected_group = found_groups.get(expected_g_key)
        
        if expected_group is not None and gid == expected_group.get('id'):
            membership_correct += 1

        # Check gain
        actual_gain = get_route_gain_db(route)
        expected_gain = target['gain_db']
        if abs(actual_gain - expected_gain) <= tolerance_db:
            gain_correct += 1

        # Check mute
        actual_mute = is_route_muted(route)
        expected_mute = target['muted']
        if actual_mute == expected_mute:
            mute_correct += 1

    # Apply points for C3, C5, C6
    mem_pts = (membership_correct / 5.0) * 20.0
    gain_pts = (gain_correct / 5.0) * 20.0
    mute_pts = (mute_correct / 5.0) * 10.0

    score += mem_pts
    score += gain_pts
    score += mute_pts

    feedback.append(f"Membership: {membership_correct}/5 tracks correct.")
    feedback.append(f"Gain levels: {gain_correct}/5 tracks correct.")
    feedback.append(f"Mute states: {mute_correct}/5 tracks correct.")

    # Criterion 4: Group Sharing Properties (15 pts)
    flags_correct = 0
    for g_key, expected_cfg in group_targets.items():
        group_el = found_groups.get(g_key)
        if group_el is not None:
            actual_flags = group_el.get('flags', '')
            expected_flags = expected_cfg['flags']
            
            all_present = all(f in actual_flags for f in expected_flags)
            # Make sure SoloControl is NOT in Drums if not specified
            if g_key == 'drums' and 'SoloControl' in actual_flags:
                all_present = False
                
            if all_present:
                flags_correct += 1
                
    if flags_correct == 2:
        score += 15.0
        feedback.append("PASS: Both groups have correct sharing flags.")
    elif flags_correct == 1:
        score += 7.0
        feedback.append("PARTIAL: One group has correct sharing flags.")
    else:
        feedback.append("FAIL: Group sharing flags incorrect or missing.")

    # Clean up
    if os.path.exists(tmp_xml.name):
        os.unlink(tmp_xml.name)

    passed = score >= 55.0 and tracks_found_count >= 3 and groups_found_count >= 1

    return {
        "passed": passed,
        "score": round(score, 1),
        "feedback": " | ".join(feedback)
    }