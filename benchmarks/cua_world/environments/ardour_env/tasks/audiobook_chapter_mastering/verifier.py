#!/usr/bin/env python3
"""
Verifier for audiobook_chapter_mastering task.
Occupation: Sound Engineering Technician (SOC 27-4014)
Industry: Publishing

Checks that the agent prepared an audiobook session with proper chapter
segmentation, track naming, gain levels, and exported chapter files.
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


# ---------- Main verifier ----------

def verify_audiobook_chapter_mastering(traj, env_info, task_info):
    """
    Multi-criterion verifier for audiobook chapter mastering.

    Criteria (100 pts total, pass >= 60):
      1. Track renamed (contains 'narration' or 'strategic')  (15 pts)
      2. Chapter markers at correct positions                  (25 pts)
      3. Track gain in ACX range (-6 to -3 dB)                (15 pts)
      4. 3 chapter WAV files exported to audiobook_export/     (30 pts)
      5. Exported files are valid (non-zero size)              (15 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "copy_from_env not available"}

    score = 0.0
    feedback = []

    # ---- Copy session XML ----
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
    # CRITERION 1: Track renamed appropriately (15 pts)
    # Should contain 'narration', 'strategic', 'chapter', or 'audiobook'
    # Must NOT be the default 'Audio 1'
    # ================================================================
    route_names = get_route_names(root)
    renamed = False
    narration_keywords = ['narration', 'strategic', 'chapter', 'audiobook', 'narrator']

    for rn in route_names:
        rn_lower = rn.lower()
        if rn_lower != 'audio 1' and any(kw in rn_lower for kw in narration_keywords):
            renamed = True
            break

    if renamed:
        score += 15.0
        feedback.append("PASS: Track renamed with audiobook reference")
    else:
        # Partial credit if renamed to anything other than default
        non_default = [rn for rn in route_names if rn.lower() != 'audio 1']
        if non_default:
            score += 7.0
            feedback.append(f"PARTIAL: Track renamed to '{non_default[0]}' but doesn't match spec")
        else:
            feedback.append("FAIL: Track not renamed from 'Audio 1'")

    # ================================================================
    # CRITERION 2: Chapter markers at correct positions (25 pts)
    # Expected: Ch1 start (0), Ch2 start (441000), Ch3 start (882000),
    #           End (1323000)
    # ================================================================
    expected_positions = {
        'ch1_start': 0,
        'ch2_start': 441000,   # 10 seconds
        'ch3_start': 882000,   # 20 seconds
        'end': 1323000,        # 30 seconds
    }

    markers = get_markers(root)
    chapter_keywords = ['ch', 'chapter', 'intro', 'first', 'strategic', 'framework', 'end']
    markers_matched = 0
    tolerance_samples = int(SAMPLE_RATE * 1.5)  # 1.5 second tolerance

    for marker in markers:
        mname = marker['name'].lower()
        mstart = marker['start']
        for ename, epos in expected_positions.items():
            if abs(mstart - epos) <= tolerance_samples:
                markers_matched += 1
                break

    if markers_matched >= 4:
        score += 25.0
        feedback.append(f"PASS: {markers_matched} chapter markers at correct positions")
    elif markers_matched >= 3:
        score += 18.0
        feedback.append(f"PARTIAL: {markers_matched}/4 chapter markers correct")
    elif markers_matched >= 2:
        score += 12.0
        feedback.append(f"PARTIAL: {markers_matched}/4 chapter markers correct")
    elif markers_matched >= 1:
        score += 5.0
        feedback.append(f"PARTIAL: {markers_matched}/4 chapter markers correct")
    else:
        if len(markers) > 0:
            score += 3.0
            feedback.append(f"PARTIAL: {len(markers)} markers exist but positions wrong")
        else:
            feedback.append("FAIL: No chapter markers placed")

    # ================================================================
    # CRITERION 3: Track gain in ACX range (15 pts)
    # Target: peak between -6 dB and -3 dB
    # Accept wider range for partial credit: -9 dB to 0 dB
    # ================================================================
    routes = get_audio_routes(root)
    gain_ok = False
    gain_partial = False

    for route in routes:
        gain_db = get_route_gain_db(route)
        if -6.0 <= gain_db <= -3.0:
            gain_ok = True
            break
        elif -9.0 <= gain_db <= 0.0 and gain_db != 0.0:
            gain_partial = True

    if gain_ok:
        score += 15.0
        feedback.append("PASS: Track gain within ACX range (-6 to -3 dB)")
    elif gain_partial:
        score += 8.0
        feedback.append("PARTIAL: Track gain adjusted but outside ideal ACX range")
    else:
        # Check if gain changed at all from default (0 dB)
        any_changed = any(abs(get_route_gain_db(r)) > 0.5 for r in routes)
        if any_changed:
            score += 3.0
            feedback.append("PARTIAL: Gain changed but not to ACX spec")
        else:
            feedback.append("FAIL: Track gain not adjusted for ACX compliance")

    # ================================================================
    # CRITERION 4: 3 chapter WAV files exported (30 pts)
    # Expected: ch01_introduction.wav, ch02_first_principles.wav,
    #           ch03_strategic_framework.wav
    # ================================================================
    export_dir = "/home/ga/Audio/audiobook_export"
    expected_files = [
        'ch01_introduction.wav',
        'ch02_first_principles.wav',
        'ch03_strategic_framework.wav',
    ]
    # Also accept common variations
    alt_patterns = [
        ['ch01', 'chapter_1', 'chapter1', 'introduction', 'ch_01'],
        ['ch02', 'chapter_2', 'chapter2', 'first_principles', 'ch_02'],
        ['ch03', 'chapter_3', 'chapter3', 'strategic_framework', 'ch_03'],
    ]

    tmp_export = tempfile.mkdtemp()
    files_found = 0
    files_valid = 0

    # Try expected filenames first
    for fname in expected_files:
        try:
            remote = f"{export_dir}/{fname}"
            local = os.path.join(tmp_export, fname)
            copy_from_env(remote, local)
            if os.path.exists(local) and os.path.getsize(local) > 100:
                files_found += 1
                if os.path.getsize(local) > 1000:
                    files_valid += 1
        except Exception:
            pass

    # If not found with expected names, try alternatives
    if files_found < 3:
        for ch_patterns in alt_patterns:
            if files_found >= 3:
                break
            for pat in ch_patterns:
                fname = f"{pat}.wav"
                try:
                    remote = f"{export_dir}/{fname}"
                    local = os.path.join(tmp_export, fname)
                    copy_from_env(remote, local)
                    if os.path.exists(local) and os.path.getsize(local) > 100:
                        files_found += 1
                        if os.path.getsize(local) > 1000:
                            files_valid += 1
                        break
                except Exception:
                    continue

    # Also check default Ardour export location
    if files_found == 0:
        default_export = "/home/ga/Audio/sessions/MyProject/export"
        for fname in ['MyProject.wav', 'ch01.wav', 'ch02.wav', 'ch03.wav']:
            try:
                remote = f"{default_export}/{fname}"
                local = os.path.join(tmp_export, fname)
                copy_from_env(remote, local)
                if os.path.exists(local) and os.path.getsize(local) > 100:
                    files_found += 1
                    if os.path.getsize(local) > 1000:
                        files_valid += 1
            except Exception:
                continue

    if files_found >= 3:
        score += 30.0
        feedback.append(f"PASS: {files_found} chapter files exported")
    elif files_found >= 2:
        score += 20.0
        feedback.append(f"PARTIAL: {files_found}/3 chapter files exported")
    elif files_found >= 1:
        score += 10.0
        feedback.append(f"PARTIAL: {files_found}/3 chapter files exported")
    else:
        feedback.append("FAIL: No chapter files exported")

    # ================================================================
    # CRITERION 5: Exported files are valid WAVs (15 pts)
    # ================================================================
    if files_valid >= 3:
        score += 15.0
        feedback.append(f"PASS: All {files_valid} exported files are valid WAV")
    elif files_valid >= 2:
        score += 10.0
        feedback.append(f"PARTIAL: {files_valid}/3 files are valid WAV")
    elif files_valid >= 1:
        score += 5.0
        feedback.append(f"PARTIAL: {files_valid}/3 files are valid WAV")
    elif files_found > 0:
        feedback.append("FAIL: Exported files exist but appear corrupted/empty")
    else:
        feedback.append("FAIL: No valid WAV files to check")

    # Cleanup
    try:
        os.unlink(tmp.name)
        import shutil
        shutil.rmtree(tmp_export, ignore_errors=True)
    except Exception:
        pass

    passed = score >= PASS_THRESHOLD
    return {
        "passed": passed,
        "score": round(score, 1),
        "feedback": " | ".join(feedback)
    }


verify_task = verify_audiobook_chapter_mastering


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
                gain = 10 ** (t.get('gain_db', 0) / 20.0)
                xml += f'<Route name="{t["name"]}" default-type="audio">'
                xml += f'<Controllable name="gaincontrol" value="{gain}"/>'
                xml += '</Route>\n'
        xml += '</Routes>\n<Playlists/>\n<Locations>\n'
        xml += '<Location name="session" start="0" end="1323000" flags="IsSessionRange"/>\n'
        if markers:
            for m in markers:
                xml += f'<Location name="{m["name"]}" start="{m["start"]}" end="{m["start"]}" flags="IsMark"/>\n'
        xml += '</Locations>\n</Session>'
        return xml

    def run_test(name, xml_str, export_files=None):
        tmpdir = tempfile.mkdtemp()
        sp = os.path.join(tmpdir, "MyProject.ardour")
        with open(sp, 'w') as f:
            f.write(xml_str)

        export_d = os.path.join(tmpdir, "export")
        os.makedirs(export_d, exist_ok=True)
        if export_files:
            for fname in export_files:
                with open(os.path.join(export_d, fname), 'wb') as f:
                    f.write(b'\x00' * 5000)

        def mock_copy(remote, local):
            if 'MyProject.ardour' in remote:
                shutil.copy2(sp, local)
            elif 'audiobook_export' in remote:
                fname = os.path.basename(remote)
                src = os.path.join(export_d, fname)
                if os.path.exists(src):
                    shutil.copy2(src, local)
                else:
                    raise FileNotFoundError(remote)
            else:
                raise FileNotFoundError(remote)

        result = verify_audiobook_chapter_mastering([], {'copy_from_env': mock_copy}, {})
        shutil.rmtree(tmpdir, ignore_errors=True)
        print(f"\nTEST: {name} -> passed={result['passed']}, score={result['score']}")
        print(f"  {result['feedback']}")
        return result

    # Do-nothing
    r1 = run_test("Do-nothing", make_session(tracks=[{'name': 'Audio 1'}]))
    assert not r1['passed'], "Do-nothing must fail"

    # Full completion
    r2 = run_test("Full completion", make_session(
        tracks=[{'name': 'Narration - Strategic Thinking', 'gain_db': -4.5}],
        markers=[
            {'name': 'Chapter 1 Start', 'start': 0},
            {'name': 'Chapter 2 Start', 'start': 441000},
            {'name': 'Chapter 3 Start', 'start': 882000},
            {'name': 'End', 'start': 1323000},
        ]),
        export_files=['ch01_introduction.wav', 'ch02_first_principles.wav', 'ch03_strategic_framework.wav'])
    assert r2['passed'], f"Full completion must pass, got {r2['score']}"

    # Partial - track renamed and markers but no export
    r3 = run_test("Partial (no export)", make_session(
        tracks=[{'name': 'Narration - Strategic Thinking', 'gain_db': -4.5}],
        markers=[
            {'name': 'Ch1', 'start': 0},
            {'name': 'Ch2', 'start': 441000},
            {'name': 'Ch3', 'start': 882000},
            {'name': 'End', 'start': 1323000},
        ]))
    assert not r3['passed'], "Partial should not pass (missing export)"
    assert r3['score'] > 0, "Partial should get credit"

    print("\n\nAll offline mock tests passed!")
