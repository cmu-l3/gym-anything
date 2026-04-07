#!/usr/bin/env python3
"""
Verifier for theater_cue_assembly task.
Occupation: Sound Engineering Technician
Industry: Theater / Live Events

Checks that the agent set up the theatrical playback session with correct cues, fades, levels, and warning markers.
"""

import math
import os
import sys
import tempfile
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

PASS_THRESHOLD = 65.0
SAMPLE_RATE = 44100

def get_audio_routes(root):
    routes = []
    for route in root.iter('Route'):
        flags = route.get('flags', '')
        if 'MasterOut' in flags or 'MonitorOut' in flags:
            continue
        if route.get('default-type') == 'audio':
            routes.append(route)
    return routes

def get_route_by_name(root, name_pattern):
    for route in get_audio_routes(root):
        rname = route.get('name', '').lower()
        if name_pattern.lower() in rname:
            return route
    return None

def get_regions_for_route(root, route_name):
    regions = []
    for playlist in root.iter('Playlist'):
        pl_name = playlist.get('name', '')
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

def verify_theater_cue_assembly(traj, env_info, task_info):
    """
    Multi-criterion verifier for theater cue assembly.
    1. Track Setup (15)
    2. Region Spotting (30)
    3. Cue 1 Fade-out (15)
    4. Cue 3 Gain (20)
    5. Markers (20)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "copy_from_env not available"}

    score = 0.0
    feedback = []

    # Get JSON output from export_result.sh
    tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_json.close()
    session_modified = False
    try:
        copy_from_env("/tmp/theater_cue_assembly_result.json", tmp_json.name)
        import json
        with open(tmp_json.name, 'r') as f:
            res = json.load(f)
            session_modified = res.get('session_modified', False)
    except Exception:
        pass
    finally:
        if os.path.exists(tmp_json.name):
            os.unlink(tmp_json.name)
            
    if not session_modified:
        feedback.append("WARNING: Session file was not saved/modified during task.")

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

    # CRITERION 1: Track Setup (15 pts)
    # Cue 1 Preshow, Cue 2 Prologue, Cue 3 Intermission
    track1 = get_route_by_name(root, "Cue 1") or get_route_by_name(root, "Preshow")
    track2 = get_route_by_name(root, "Cue 2") or get_route_by_name(root, "Prologue")
    track3 = get_route_by_name(root, "Cue 3") or get_route_by_name(root, "Intermission")

    tracks_found = sum([1 for t in [track1, track2, track3] if t is not None])
    score += tracks_found * 5.0
    if tracks_found == 3:
        feedback.append("PASS: All 3 cue tracks found.")
    else:
        feedback.append(f"PARTIAL: Found {tracks_found}/3 required tracks.")

    # Get route names to find regions
    r1_name = track1.get('name') if track1 else "Cue 1 Preshow"
    r2_name = track2.get('name') if track2 else "Cue 2 Prologue"
    r3_name = track3.get('name') if track3 else "Cue 3 Intermission"

    # CRITERION 2: Region Spotting (30 pts, 10 each)
    tolerance = 88200 # 2 seconds
    r1_regions = get_regions_for_route(root, r1_name)
    r2_regions = get_regions_for_route(root, r2_name)
    r3_regions = get_regions_for_route(root, r3_name)
    
    # We will also search all playlists if we couldn't match the track exactly
    if not r1_regions or not r2_regions or not r3_regions:
        all_regions = []
        for playlist in root.iter('Playlist'):
            for region in playlist.iter('Region'):
                all_regions.append(region)
    else:
        all_regions = []

    cue1_ok = False
    cue2_ok = False
    cue3_ok = False

    def check_region_pos(regions, expected_pos, tol):
        for r in regions:
            pos = int(r.get('position', '0'))
            if abs(pos - expected_pos) <= tol:
                return r
        return None

    c1_expected = 0
    c2_expected = 5292000
    c3_expected = 13230000

    r1_found = check_region_pos(r1_regions, c1_expected, tolerance)
    if not r1_found and all_regions:
        r1_found = check_region_pos(all_regions, c1_expected, tolerance)
    if r1_found is not None:
        cue1_ok = True
        score += 10.0

    r2_found = check_region_pos(r2_regions, c2_expected, tolerance)
    if not r2_found and all_regions:
        r2_found = check_region_pos(all_regions, c2_expected, tolerance)
    if r2_found is not None:
        cue2_ok = True
        score += 10.0

    r3_found = check_region_pos(r3_regions, c3_expected, tolerance)
    if not r3_found and all_regions:
        r3_found = check_region_pos(all_regions, c3_expected, tolerance)
    if r3_found is not None:
        cue3_ok = True
        score += 10.0

    if cue1_ok and cue2_ok and cue3_ok:
        feedback.append("PASS: All regions spotted correctly.")
    else:
        cues_spotted = sum([1 for c in [cue1_ok, cue2_ok, cue3_ok] if c])
        feedback.append(f"PARTIAL: {cues_spotted}/3 regions spotted correctly.")

    # CRITERION 3: Cue 1 Fade-out (15 pts)
    fade_ok = False
    if r1_found is not None:
        fade_out = r1_found.find('FadeOut')
        if fade_out is not None:
            active = fade_out.get('active', '0')
            if active == '1' or active.lower() in ['yes', 'true']:
                fade_ok = True

                if fade_ok:
                    score += 15.0
                    feedback.append("PASS: Cue 1 fade-out applied.")
                else:
                    score += 5.0
                    feedback.append("PARTIAL: FadeOut element found but active state unclear.")
            else:
                feedback.append("FAIL: Cue 1 fade-out present but not active.")
        else:
            feedback.append("FAIL: Cue 1 fade-out not found.")
    else:
        feedback.append("FAIL: Cue 1 region not found to check fade-out.")

    # CRITERION 4: Cue 3 Gain (20 pts)
    # Should be between -15 dB and -5 dB
    gain_ok = False
    if track3 is not None:
        gain_db = get_route_gain_db(track3)
        if -16.0 <= gain_db <= -4.0:
            score += 20.0
            gain_ok = True
            feedback.append(f"PASS: Cue 3 gain adjusted to {gain_db:.1f} dB.")
        else:
            if gain_db < -0.5:
                # Give partial credit if they reduced gain but not enough or too much
                score += 10.0
                feedback.append(f"PARTIAL: Cue 3 gain reduced to {gain_db:.1f} dB, but outside target range.")
            else:
                feedback.append(f"FAIL: Cue 3 gain not properly reduced (currently {gain_db:.1f} dB).")
    else:
        feedback.append("FAIL: Cue 3 track not found to check gain.")

    # CRITERION 5: Markers (20 pts)
    # House Lights Down near 5071500 (115s)
    # Act 1 End near 13009500 (295s)
    m1_expected = 5071500
    m2_expected = 13009500
    
    markers = get_markers(root)
    m1_found = False
    m2_found = False

    for m in markers:
        name = m['name'].lower()
        start = m['start']
        if 'house' in name or 'lights' in name:
            if abs(start - m1_expected) <= tolerance:
                m1_found = True
        if 'act' in name or 'end' in name:
            if abs(start - m2_expected) <= tolerance:
                m2_found = True
                
        # Also just check positions in case they misspelled
        if abs(start - m1_expected) <= tolerance:
            m1_found = True
        if abs(start - m2_expected) <= tolerance:
            m2_found = True

    if m1_found:
        score += 10.0
    if m2_found:
        score += 10.0

    if m1_found and m2_found:
        feedback.append("PASS: Both warning markers placed correctly.")
    else:
        markers_spotted = sum([1 for m in [m1_found, m2_found] if m])
        feedback.append(f"PARTIAL: {markers_spotted}/2 markers placed correctly.")

    passed = score >= PASS_THRESHOLD and session_modified

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }