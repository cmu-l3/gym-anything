#!/usr/bin/env python3
"""
Verifier for film_scoring_session_setup task.
Occupation: Music Director / Composer (SOC 27-2041)
Industry: Motion Picture & Video Production

Checks that the agent configured a film scoring session template with
correct tracks, markers, pan positions, reference audio, and mute state.
"""

import math
import os
import sys
import tempfile
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

PASS_THRESHOLD = 60.0
SAMPLE_RATE = 44100


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


def get_route_by_name(root, name_pattern):
    """Find a route whose name contains the pattern (case-insensitive)."""
    for route in root.iter('Route'):
        rname = route.get('name', '').lower()
        if name_pattern.lower() in rname:
            return route
    return None


def get_route_names(root):
    return [r.get('name', '') for r in get_audio_routes(root)]


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


def get_route_muted(route):
    for ctrl in route.iter('Controllable'):
        if ctrl.get('name') == 'mute':
            return ctrl.get('value', '0') in ('1', 'yes', 'true')
    # Also check route attribute
    return route.get('muted', '0') in ('1', 'yes', 'true')


def get_route_pan(route):
    for ctrl in route.iter('Controllable'):
        name = ctrl.get('name', '')
        if 'pan' in name.lower():
            try:
                return float(ctrl.get('value', '0.5'))
            except (ValueError, TypeError):
                return 0.5
    return 0.5


def get_regions_for_route(root, route_name):
    regions = []
    for playlist in root.iter('Playlist'):
        pl_name = playlist.get('name', '')
        base = pl_name.rsplit('.', 1)[0] if '.' in pl_name else pl_name
        if base.lower() == route_name.lower() or pl_name.lower().startswith(route_name.lower()):
            for region in playlist.iter('Region'):
                regions.append({
                    'name': region.get('name', ''),
                    'position': int(region.get('position', '0')),
                    'length': int(region.get('length', '0')),
                })
    return regions


# ---------- Main verifier ----------

def verify_film_scoring_session_setup(traj, env_info, task_info):
    """
    Multi-criterion verifier for film scoring session setup.

    Criteria (100 pts total, pass >= 60):
      1. Five required tracks exist with correct names  (20 pts)
      2. Scene markers at correct positions (±10%)      (20 pts)
      3. Pan positions approximately correct             (20 pts)
      4. Audio on Dialogue Ref at Interview 1 position   (20 pts)
      5. Dialogue Ref track is muted                     (20 pts)
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
        return {"passed": False, "score": 0.0, "feedback": "Session file empty or missing"}

    try:
        tree = ET.parse(tmp.name)
        root = tree.getroot()
    except Exception as e:
        os.unlink(tmp.name)
        return {"passed": False, "score": 0.0, "feedback": f"XML parse error: {e}"}

    # ================================================================
    # CRITERION 1: Five tracks with correct names (20 pts)
    # Required: Strings, Piano, Ambient Synth, Percussion, Dialogue Ref
    # ================================================================
    route_names = get_route_names(root)
    route_names_lower = [n.lower() for n in route_names]

    required = {
        'strings': ['strings', 'string'],
        'piano': ['piano'],
        'ambient_synth': ['ambient synth', 'ambient_synth', 'synth', 'ambient'],
        'percussion': ['percussion', 'perc', 'drums'],
        'dialogue_ref': ['dialogue ref', 'dialogue_ref', 'dialog ref', 'dialogue reference', 'dial ref'],
    }

    found_tracks = {}
    for key, aliases in required.items():
        for rn in route_names_lower:
            for alias in aliases:
                if alias in rn or rn in alias:
                    found_tracks[key] = rn
                    break
            if key in found_tracks:
                break

    n_found = len(found_tracks)
    if n_found >= 5:
        score += 20.0
        feedback.append(f"PASS: All 5 scoring tracks created")
    elif n_found >= 3:
        score += 12.0
        feedback.append(f"PARTIAL: {n_found}/5 tracks found ({', '.join(found_tracks.keys())})")
    elif n_found >= 1:
        score += 5.0
        feedback.append(f"PARTIAL: {n_found}/5 tracks found")
    else:
        if len(route_names) > 1:
            score += 2.0
            feedback.append(f"PARTIAL: {len(route_names)} tracks exist but names don't match")
        else:
            feedback.append("FAIL: No scoring tracks created")

    # ================================================================
    # CRITERION 2: Scene markers at correct positions (20 pts)
    # Expected: Opening(0), Interview1(1323000), B-Roll(3307500),
    #           Interview2(5292000), Closing(7938000), EndCredits(9261000)
    # ================================================================
    expected_markers = {
        'opening': 0,
        'interview 1': 1323000,
        'b-roll': 3307500,
        'interview 2': 5292000,
        'closing': 7938000,
        'end credits': 9261000,
    }

    markers = get_markers(root)
    markers_matched = 0
    tolerance = 0.10  # 10% tolerance

    for marker in markers:
        mname = marker['name'].lower().strip()
        mstart = marker['start']
        for ename, epos in expected_markers.items():
            if any(kw in mname for kw in ename.split()):
                if epos == 0:
                    if mstart <= SAMPLE_RATE:  # Within 1 second of start
                        markers_matched += 1
                        break
                else:
                    if abs(mstart - epos) / epos <= tolerance:
                        markers_matched += 1
                        break

    if markers_matched >= 5:
        score += 20.0
        feedback.append(f"PASS: {markers_matched}/6 scene markers at correct positions")
    elif markers_matched >= 3:
        score += 12.0
        feedback.append(f"PARTIAL: {markers_matched}/6 scene markers correct")
    elif markers_matched >= 1:
        score += 5.0
        feedback.append(f"PARTIAL: {markers_matched}/6 scene markers correct")
    else:
        total_markers = len(markers)
        if total_markers > 0:
            score += 3.0
            feedback.append(f"PARTIAL: {total_markers} markers exist but positions don't match")
        else:
            feedback.append("FAIL: No scene markers placed")

    # ================================================================
    # CRITERION 3: Pan positions (20 pts)
    # Strings: 30% left (pan ≈ 0.20), Piano: center (0.5),
    # Ambient Synth: 20% right (pan ≈ 0.70), Percussion: center (0.5),
    # Dialogue Ref: center (0.5)
    # ================================================================
    expected_pans = {
        'strings': 0.20,       # 30% left
        'piano': 0.50,         # center
        'ambient_synth': 0.70, # 20% right
        'percussion': 0.50,    # center
        'dialogue_ref': 0.50,  # center
    }

    pan_correct = 0
    pan_total = 0
    pan_tolerance = 0.15

    for key, expected_pan in expected_pans.items():
        if key in found_tracks:
            route = get_route_by_name(root, found_tracks[key])
            if route is not None:
                actual_pan = get_route_pan(route)
                pan_total += 1
                if abs(actual_pan - expected_pan) <= pan_tolerance:
                    pan_correct += 1

    if pan_total >= 3 and pan_correct >= 3:
        score += 20.0
        feedback.append(f"PASS: {pan_correct}/{pan_total} pan positions correct")
    elif pan_correct >= 2:
        score += 12.0
        feedback.append(f"PARTIAL: {pan_correct}/{pan_total} pan positions correct")
    elif pan_correct >= 1:
        score += 5.0
        feedback.append(f"PARTIAL: {pan_correct}/{pan_total} pan positions correct")
    else:
        # Check if any pans were changed from default center
        any_changed = False
        for route in get_audio_routes(root):
            if abs(get_route_pan(route) - 0.5) > 0.05:
                any_changed = True
                break
        if any_changed:
            score += 3.0
            feedback.append("PARTIAL: Some pan positions changed but not to spec")
        else:
            feedback.append("FAIL: Pan positions not configured")

    # ================================================================
    # CRITERION 4: Audio on Dialogue Ref at Interview 1 position (20 pts)
    # ================================================================
    interview1_pos = 1323000
    ref_has_audio = False
    ref_position_correct = False

    for key_name in ['dialogue_ref', 'dialogue ref']:
        if key_name.replace(' ', '_') in found_tracks or key_name in found_tracks:
            tk = found_tracks.get(key_name.replace(' ', '_'), found_tracks.get(key_name, ''))
            # Find the actual route name
            for route in get_audio_routes(root):
                rn = route.get('name', '').lower()
                if tk in rn or rn in tk:
                    regions = get_regions_for_route(root, route.get('name', ''))
                    if regions:
                        ref_has_audio = True
                        for r in regions:
                            if abs(r['position'] - interview1_pos) / max(interview1_pos, 1) <= 0.15:
                                ref_position_correct = True
                    break

    if ref_has_audio and ref_position_correct:
        score += 20.0
        feedback.append("PASS: Reference audio placed on Dialogue Ref at Interview 1 position")
    elif ref_has_audio:
        score += 10.0
        feedback.append("PARTIAL: Audio on Dialogue Ref but not at correct position")
    else:
        # Check if any audio was imported on any new track
        total_regions = sum(1 for _ in root.iter('Region'))
        if total_regions > 1:
            score += 3.0
            feedback.append("PARTIAL: Audio imported but not on Dialogue Ref track")
        else:
            feedback.append("FAIL: No reference audio imported onto Dialogue Ref")

    # ================================================================
    # CRITERION 5: Dialogue Ref track is muted (20 pts)
    # ================================================================
    dialogue_muted = False
    dialogue_found = False

    for route in get_audio_routes(root):
        rname = route.get('name', '').lower()
        if any(kw in rname for kw in ['dialogue', 'dialog', 'ref']):
            dialogue_found = True
            if get_route_muted(route):
                dialogue_muted = True
            break

    if dialogue_found and dialogue_muted:
        score += 20.0
        feedback.append("PASS: Dialogue Ref track is muted")
    elif dialogue_found:
        feedback.append("FAIL: Dialogue Ref track exists but is not muted")
    else:
        feedback.append("FAIL: Dialogue Ref track not found")

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


verify_task = verify_film_scoring_session_setup


# ---------- Offline mock tests ----------

if __name__ == "__main__":
    import shutil

    def make_session(tracks=None, markers=None, regions=None):
        xml = '<?xml version="1.0" encoding="UTF-8"?>\n<Session name="MyProject">\n'
        xml += '<Routes>\n'
        xml += '<Route name="Master" default-type="audio" flags="MasterOut">'
        xml += '<Controllable name="gaincontrol" value="1.0"/></Route>\n'
        if tracks:
            for t in tracks:
                gain = 10 ** (t.get('gain_db', 0) / 20.0)
                muted = '1' if t.get('muted', False) else '0'
                pan = t.get('pan', 0.5)
                xml += f'<Route name="{t["name"]}" default-type="audio" muted="{muted}">'
                xml += f'<Controllable name="gaincontrol" value="{gain}"/>'
                xml += f'<Controllable name="mute" value="{muted}"/>'
                xml += f'<Controllable name="pan-azimuth" value="{pan}"/>'
                xml += '</Route>\n'
        xml += '</Routes>\n'
        xml += '<Playlists>\n'
        if tracks and regions:
            for t in tracks:
                tname = t['name']
                xml += f'<Playlist name="{tname}.1">\n'
                for r in regions:
                    if r.get('track', '').lower() == tname.lower():
                        xml += f'<Region name="{r.get("rname","audio")}" '
                        xml += f'position="{r["position"]}" length="{r.get("length", 44100)}"/>\n'
                xml += '</Playlist>\n'
        xml += '</Playlists>\n'
        xml += '<Locations>\n'
        xml += '<Location name="session" start="0" end="10000000" flags="IsSessionRange"/>\n'
        if markers:
            for m in markers:
                xml += f'<Location name="{m["name"]}" start="{m["start"]}" end="{m["start"]}" flags="IsMark"/>\n'
        xml += '</Locations>\n'
        xml += '</Session>'
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

        result = verify_film_scoring_session_setup([], {'copy_from_env': mock_copy}, {})
        shutil.rmtree(tmpdir, ignore_errors=True)
        print(f"\nTEST: {name} -> passed={result['passed']}, score={result['score']}")
        print(f"  {result['feedback']}")
        return result

    # Do-nothing
    r1 = run_test("Do-nothing", make_session(
        tracks=[{'name': 'Audio 1'}]))
    assert not r1['passed'], "Do-nothing must fail"

    # Full completion
    r2 = run_test("Full completion", make_session(
        tracks=[
            {'name': 'Strings', 'pan': 0.20},
            {'name': 'Piano', 'pan': 0.50},
            {'name': 'Ambient Synth', 'pan': 0.70},
            {'name': 'Percussion', 'pan': 0.50},
            {'name': 'Dialogue Ref', 'pan': 0.50, 'muted': True},
        ],
        markers=[
            {'name': 'Opening Titles', 'start': 0},
            {'name': 'Interview 1', 'start': 1323000},
            {'name': 'B-Roll Montage', 'start': 3307500},
            {'name': 'Interview 2', 'start': 5292000},
            {'name': 'Closing', 'start': 7938000},
            {'name': 'End Credits', 'start': 9261000},
        ],
        regions=[
            {'track': 'Dialogue Ref', 'rname': 'moonlight', 'position': 1323000, 'length': 1323000},
        ]))
    assert r2['passed'], f"Full completion must pass, got {r2['score']}"

    print("\n\nAll offline mock tests passed!")
