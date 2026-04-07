#!/usr/bin/env python3
"""
Verifier for live_recording_session_prep task.
Occupation: Audio and Video Technicians (SOC 27-4011)
Industry: Live Events / Entertainment

Checks that the agent set up a live recording session with correct input
tracks, bus tracks, pan positions, gain staging, and set list markers.
"""

import math
import os
import sys
import tempfile
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

PASS_THRESHOLD = 55.0
SAMPLE_RATE = 44100


# ---------- Ardour XML helpers ----------

def get_all_routes(root):
    """Get all routes including buses."""
    routes = []
    for route in root.iter('Route'):
        flags = route.get('flags', '')
        if 'MasterOut' in flags or 'MonitorOut' in flags:
            continue
        routes.append(route)
    return routes


def get_audio_routes(root):
    routes = []
    for route in root.iter('Route'):
        flags = route.get('flags', '')
        if 'MasterOut' in flags or 'MonitorOut' in flags:
            continue
        if route.get('default-type') == 'audio':
            routes.append(route)
    return routes


def get_route_names(root):
    return [r.get('name', '') for r in get_all_routes(root)]


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


def get_route_pan(route):
    for ctrl in route.iter('Controllable'):
        name = ctrl.get('name', '')
        if 'pan' in name.lower():
            try:
                return float(ctrl.get('value', '0.5'))
            except (ValueError, TypeError):
                return 0.5
    return 0.5


def find_route_by_keywords(root, keywords):
    """Find a route whose name contains any of the keywords."""
    for route in get_all_routes(root):
        rname = route.get('name', '').lower()
        for kw in keywords:
            if kw.lower() in rname:
                return route
    return None


# ---------- Main verifier ----------

def verify_live_recording_session_prep(traj, env_info, task_info):
    """
    Multi-criterion verifier for live recording session prep.

    Criteria (100 pts total, pass >= 55):
      1. 7 input tracks with correct names            (25 pts)
      2. 2 bus tracks (Drum Sub, Piano Sub)            (15 pts)
      3. Pan positions correct (Piano L/R, Sax)        (20 pts)
      4. Set list markers (at least 5 of 7)            (20 pts)
      5. Bus gain at -6 dB                             (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "copy_from_env not available"}

    score = 0.0
    feedback = []

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

    # ================================================================
    # CRITERION 1: 7 input tracks with correct names (25 pts)
    # Required: Kick Drum, Drum Overheads, Upright Bass DI,
    #           Piano Left, Piano Right, Tenor Sax, Room Mics
    # ================================================================
    required_inputs = {
        'kick': ['kick drum', 'kick', 'bass drum', 'bd'],
        'overheads': ['drum overhead', 'overhead', 'oh', 'drum oh'],
        'bass': ['upright bass', 'bass di', 'bass', 'upright'],
        'piano_l': ['piano left', 'piano l', 'piano_left', 'piano_l'],
        'piano_r': ['piano right', 'piano r', 'piano_right', 'piano_r'],
        'sax': ['tenor sax', 'sax', 'saxophone', 'tenor'],
        'room': ['room mic', 'room', 'ambien'],
    }

    route_names = get_route_names(root)
    route_names_lower = [n.lower() for n in route_names]

    found_inputs = {}
    for key, aliases in required_inputs.items():
        for rn in route_names_lower:
            for alias in aliases:
                if alias in rn or rn in alias:
                    found_inputs[key] = rn
                    break
            if key in found_inputs:
                break

    n_inputs = len(found_inputs)
    if n_inputs >= 7:
        score += 25.0
        feedback.append(f"PASS: All 7 input tracks created")
    elif n_inputs >= 5:
        score += 18.0
        feedback.append(f"PARTIAL: {n_inputs}/7 input tracks found")
    elif n_inputs >= 3:
        score += 10.0
        feedback.append(f"PARTIAL: {n_inputs}/7 input tracks found")
    elif n_inputs >= 1:
        score += 5.0
        feedback.append(f"PARTIAL: {n_inputs}/7 input tracks found")
    else:
        total_routes = len(route_names)
        if total_routes > 1:
            score += 3.0
            feedback.append(f"PARTIAL: {total_routes} tracks exist but names don't match rider")
        else:
            feedback.append("FAIL: No input tracks created")

    # ================================================================
    # CRITERION 2: Bus tracks - Drum Sub and Piano Sub (15 pts)
    # ================================================================
    bus_keywords = {
        'drum_sub': ['drum sub', 'drum_sub', 'drum bus', 'drum group', 'drums sub'],
        'piano_sub': ['piano sub', 'piano_sub', 'piano bus', 'piano group', 'keys sub'],
    }

    found_buses = {}
    for key, aliases in bus_keywords.items():
        for rn in route_names_lower:
            for alias in aliases:
                if alias in rn or rn in alias:
                    found_buses[key] = rn
                    break
            if key in found_buses:
                break

    if len(found_buses) >= 2:
        score += 15.0
        feedback.append("PASS: Both bus tracks (Drum Sub, Piano Sub) created")
    elif len(found_buses) >= 1:
        score += 8.0
        feedback.append(f"PARTIAL: {len(found_buses)}/2 bus tracks found")
    else:
        # Check if any buses exist at all
        bus_found = any('bus' in rn or 'sub' in rn or 'group' in rn for rn in route_names_lower)
        if bus_found:
            score += 3.0
            feedback.append("PARTIAL: Bus tracks exist but don't match rider names")
        else:
            feedback.append("FAIL: No bus tracks created")

    # ================================================================
    # CRITERION 3: Pan positions (20 pts)
    # Piano Left: ~0.15 (35% left), Piano Right: ~0.85 (35% right),
    # Tenor Sax: ~0.65 (15% right)
    # Others: center (0.5)
    # ================================================================
    expected_pans = {
        'piano_l': 0.15,   # 35% left
        'piano_r': 0.85,   # 35% right
        'sax': 0.65,       # 15% right
    }
    pan_tolerance = 0.15

    pan_correct = 0
    pan_total = 0

    for key, expected in expected_pans.items():
        if key in found_inputs:
            route = find_route_by_keywords(root, [found_inputs[key]])
            if route is not None:
                actual = get_route_pan(route)
                pan_total += 1
                if abs(actual - expected) <= pan_tolerance:
                    pan_correct += 1

    if pan_correct >= 3:
        score += 20.0
        feedback.append("PASS: Pan positions correct (Piano L/R stereo, Sax right)")
    elif pan_correct >= 2:
        score += 12.0
        feedback.append(f"PARTIAL: {pan_correct}/3 key pan positions correct")
    elif pan_correct >= 1:
        score += 6.0
        feedback.append(f"PARTIAL: {pan_correct}/3 key pan positions correct")
    else:
        # Check if any pan was moved from center
        any_panned = False
        for route in get_all_routes(root):
            p = get_route_pan(route)
            if abs(p - 0.5) > 0.05:
                any_panned = True
                break
        if any_panned:
            score += 3.0
            feedback.append("PARTIAL: Some tracks panned but not matching rider")
        else:
            feedback.append("FAIL: No pan positions configured")

    # ================================================================
    # CRITERION 4: Set list markers (20 pts)
    # At least 5 of 7 expected
    # ================================================================
    expected_marker_data = {
        'autumn': 0,
        'blue in green': 13230000,
        'all blues': 26460000,
        'break': 39690000,
        'favorite': 52920000,
        'giant': 66150000,
        'take five': 79380000,
    }

    markers = get_markers(root)
    markers_matched = 0
    tolerance_samples = SAMPLE_RATE * 30  # 30 second tolerance for song markers

    for marker in markers:
        mname = marker['name'].lower()
        mstart = marker['start']
        for ename, epos in expected_marker_data.items():
            if ename in mname:
                if epos == 0:
                    if mstart <= SAMPLE_RATE * 5:
                        markers_matched += 1
                        break
                else:
                    if abs(mstart - epos) <= tolerance_samples:
                        markers_matched += 1
                        break

    # Also match generic "Set 1", "Set 2", "Set Break" etc.
    if markers_matched < 5:
        set_keywords = ['set 1', 'set 2', 'set break', 'encore']
        for marker in markers:
            mname = marker['name'].lower()
            for kw in set_keywords:
                if kw in mname:
                    markers_matched += 1
                    set_keywords.remove(kw)
                    break

    markers_matched = min(markers_matched, 7)  # Cap at max expected

    if markers_matched >= 5:
        score += 20.0
        feedback.append(f"PASS: {markers_matched}/7 set list markers placed")
    elif markers_matched >= 3:
        score += 12.0
        feedback.append(f"PARTIAL: {markers_matched}/7 set list markers placed")
    elif markers_matched >= 1:
        score += 5.0
        feedback.append(f"PARTIAL: {markers_matched}/7 set list markers")
    else:
        total = len(markers)
        if total > 0:
            score += 3.0
            feedback.append(f"PARTIAL: {total} markers exist but don't match set list")
        else:
            feedback.append("FAIL: No set list markers placed")

    # ================================================================
    # CRITERION 5: Bus tracks at -6 dB gain (20 pts)
    # ================================================================
    bus_gain_correct = 0
    bus_gain_total = 0

    for key, rname in found_buses.items():
        route = find_route_by_keywords(root, [rname])
        if route is not None:
            gain_db = get_route_gain_db(route)
            bus_gain_total += 1
            if -9.0 <= gain_db <= -3.0:  # Accept -9 to -3 dB range
                bus_gain_correct += 1

    if bus_gain_total >= 2 and bus_gain_correct >= 2:
        score += 20.0
        feedback.append("PASS: Bus tracks gain set to approximately -6 dB")
    elif bus_gain_correct >= 1:
        score += 10.0
        feedback.append(f"PARTIAL: {bus_gain_correct}/{bus_gain_total} bus gains correct")
    elif bus_gain_total > 0:
        # Check if gain was changed at all
        any_changed = False
        for key, rname in found_buses.items():
            route = find_route_by_keywords(root, [rname])
            if route and abs(get_route_gain_db(route)) > 0.5:
                any_changed = True
                break
        if any_changed:
            score += 5.0
            feedback.append("PARTIAL: Bus gain changed but not to -6 dB")
        else:
            feedback.append("FAIL: Bus gain not configured")
    else:
        feedback.append("FAIL: No bus tracks to check gain on")

    # Cleanup
    try:
        os.unlink(tmp.name)
    except Exception:
        pass

    passed = score >= PASS_THRESHOLD
    return {
        "passed": passed,
        "score": round(score, 1),
        "feedback": " | ".join(feedback)
    }


verify_task = verify_live_recording_session_prep


# ---------- Offline mock tests ----------

if __name__ == "__main__":
    import shutil

    def make_session(tracks=None, markers=None):
        xml = '<?xml version="1.0" encoding="UTF-8"?>\n<Session name="MyProject">\n'
        xml += '<Routes>\n'
        xml += '<Route name="Master" default-type="audio" flags="MasterOut">'
        xml += '<Controllable name="gaincontrol" value="1.0"/></Route>\n'
        if tracks:
            for t in tracks:
                gain = 10 ** (t.get('gain_db', 0) / 20.0) if t.get('gain_db', 0) > -120 else 0
                pan = t.get('pan', 0.5)
                xml += f'<Route name="{t["name"]}" default-type="audio">'
                xml += f'<Controllable name="gaincontrol" value="{gain}"/>'
                xml += f'<Controllable name="pan-azimuth" value="{pan}"/>'
                xml += '</Route>\n'
        xml += '</Routes>\n<Playlists/>\n<Locations>\n'
        xml += '<Location name="session" start="0" end="100000000" flags="IsSessionRange"/>\n'
        if markers:
            for m in markers:
                xml += f'<Location name="{m["name"]}" start="{m["start"]}" end="{m["start"]}" flags="IsMark"/>\n'
        xml += '</Locations>\n</Session>'
        return xml

    def run_test(name, xml_str):
        tmpdir = tempfile.mkdtemp()
        sp = os.path.join(tmpdir, "MyProject.ardour")
        with open(sp, 'w') as f:
            f.write(xml_str)

        def mock_copy(remote, local):
            if 'MyProject.ardour' in remote:
                shutil.copy2(sp, local)
            else:
                raise FileNotFoundError(remote)

        result = verify_live_recording_session_prep([], {'copy_from_env': mock_copy}, {})
        shutil.rmtree(tmpdir, ignore_errors=True)
        print(f"\nTEST: {name} -> passed={result['passed']}, score={result['score']}")
        print(f"  {result['feedback']}")
        return result

    # Do-nothing
    r1 = run_test("Do-nothing", make_session(tracks=[{'name': 'Audio 1'}]))
    assert not r1['passed'], "Do-nothing must fail"

    # Full completion
    r2 = run_test("Full completion", make_session(
        tracks=[
            {'name': 'Kick Drum', 'pan': 0.5},
            {'name': 'Drum Overheads', 'pan': 0.5},
            {'name': 'Upright Bass DI', 'pan': 0.5},
            {'name': 'Piano Left', 'pan': 0.15},
            {'name': 'Piano Right', 'pan': 0.85},
            {'name': 'Tenor Sax', 'pan': 0.65},
            {'name': 'Room Mics', 'pan': 0.5},
            {'name': 'Drum Sub', 'gain_db': -6},
            {'name': 'Piano Sub', 'gain_db': -6},
        ],
        markers=[
            {'name': 'Set 1 - Autumn Leaves', 'start': 0},
            {'name': 'Blue in Green', 'start': 13230000},
            {'name': 'All Blues', 'start': 26460000},
            {'name': 'Set Break', 'start': 39690000},
            {'name': 'Set 2 - My Favorite Things', 'start': 52920000},
            {'name': 'Giant Steps', 'start': 66150000},
            {'name': 'Encore - Take Five', 'start': 79380000},
        ]))
    assert r2['passed'], f"Full completion must pass, got {r2['score']}"

    # Partial - some tracks but no buses or markers
    r3 = run_test("Partial (tracks only)", make_session(
        tracks=[
            {'name': 'Kick Drum', 'pan': 0.5},
            {'name': 'Drum Overheads', 'pan': 0.5},
            {'name': 'Upright Bass DI', 'pan': 0.5},
            {'name': 'Piano Left', 'pan': 0.15},
            {'name': 'Piano Right', 'pan': 0.85},
            {'name': 'Tenor Sax', 'pan': 0.65},
            {'name': 'Room Mics', 'pan': 0.5},
        ]))
    assert not r3['passed'], "Partial should not pass (no buses/markers)"
    assert r3['score'] > 0, "Partial should get credit"

    print("\n\nAll offline mock tests passed!")
