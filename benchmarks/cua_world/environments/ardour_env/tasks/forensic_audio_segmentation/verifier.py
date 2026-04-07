#!/usr/bin/env python3
"""
Verifier for forensic_audio_segmentation task.
Occupation: Forensic Science Technician (SOC 19-4092)
Industry: Legal / Criminal Justice

Checks that the agent prepared audio evidence with proper track labeling,
segment markers, exported segment files, chain of custody documentation,
and preservation of original recording.
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
CASE_NUMBER = "2024-CR-0847"


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


def count_regions(root):
    """Count total audio regions in all playlists."""
    return sum(1 for _ in root.iter('Region'))


# ---------- Main verifier ----------

def verify_forensic_audio_segmentation(traj, env_info, task_info):
    """
    Multi-criterion verifier for forensic audio segmentation.

    Criteria (100 pts total, pass >= 60):
      1. Track renamed with case number reference          (20 pts)
      2. Segment markers/ranges at correct positions       (20 pts)
      3. 5 segment WAV files exported                      (25 pts)
      4. Chain of custody text file with required fields   (20 pts)
      5. Original audio region preserved (not deleted)     (15 pts)
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
    # CRITERION 1: Track renamed with case number (20 pts)
    # Must contain "Exhibit A" or "2024-CR-0847" or "case"
    # ================================================================
    route_names = get_route_names(root)
    case_keywords = ['exhibit', '2024-cr-0847', '0847', 'case', 'evidence']
    renamed_correctly = False

    for rn in route_names:
        rn_lower = rn.lower()
        if rn_lower != 'audio 1':
            for kw in case_keywords:
                if kw in rn_lower:
                    renamed_correctly = True
                    break
        if renamed_correctly:
            break

    if renamed_correctly:
        score += 20.0
        feedback.append("PASS: Track labeled with case/exhibit reference")
    else:
        non_default = [rn for rn in route_names if rn.lower() != 'audio 1']
        if non_default:
            score += 8.0
            feedback.append(f"PARTIAL: Track renamed to '{non_default[0]}' but missing case reference")
        else:
            feedback.append("FAIL: Track not relabeled for evidence")

    # ================================================================
    # CRITERION 2: Segment markers at correct positions (20 pts)
    # Expected boundaries: 0, 220500, 661500, 793800, 1102500, 1323000
    # ================================================================
    expected_boundaries = [0, 220500, 661500, 793800, 1102500, 1323000]
    markers = get_markers(root)
    tolerance = int(SAMPLE_RATE * 1.5)  # 1.5 second tolerance

    boundaries_matched = 0
    for eb in expected_boundaries:
        for m in markers:
            # Check start or end of marker/range
            if abs(m['start'] - eb) <= tolerance or abs(m['end'] - eb) <= tolerance:
                boundaries_matched += 1
                break

    if boundaries_matched >= 5:
        score += 20.0
        feedback.append(f"PASS: {boundaries_matched}/6 segment boundaries marked correctly")
    elif boundaries_matched >= 3:
        score += 12.0
        feedback.append(f"PARTIAL: {boundaries_matched}/6 segment boundaries correct")
    elif boundaries_matched >= 1:
        score += 5.0
        feedback.append(f"PARTIAL: {boundaries_matched}/6 segment boundaries correct")
    else:
        if len(markers) > 0:
            score += 3.0
            feedback.append(f"PARTIAL: {len(markers)} markers exist but positions don't match segments")
        else:
            feedback.append("FAIL: No segment markers placed")

    # ================================================================
    # CRITERION 3: 5 segment WAV files exported (25 pts)
    # ================================================================
    export_dir = "/home/ga/Audio/evidence_output"
    expected_segments = [
        'segment_01_background.wav',
        'segment_02_speaker1_defendant.wav',
        'segment_03_crosstalk.wav',
        'segment_04_speaker2_complainant.wav',
        'segment_05_ambient_tail.wav',
    ]
    alt_keywords = [
        ['segment_01', 'seg_01', 'background', 'seg1', 'segment1'],
        ['segment_02', 'seg_02', 'speaker1', 'defendant', 'seg2', 'segment2'],
        ['segment_03', 'seg_03', 'crosstalk', 'unintelligible', 'seg3', 'segment3'],
        ['segment_04', 'seg_04', 'speaker2', 'complainant', 'seg4', 'segment4'],
        ['segment_05', 'seg_05', 'ambient', 'tail', 'seg5', 'segment5'],
    ]

    tmp_export = tempfile.mkdtemp()
    segments_found = 0

    # Try expected names
    for fname in expected_segments:
        try:
            remote = f"{export_dir}/{fname}"
            local = os.path.join(tmp_export, fname)
            copy_from_env(remote, local)
            if os.path.exists(local) and os.path.getsize(local) > 100:
                segments_found += 1
        except Exception:
            pass

    # Try alternatives if needed
    if segments_found < 5:
        for kw_list in alt_keywords:
            already_found = segments_found >= 5
            if already_found:
                break
            for kw in kw_list:
                fname = f"{kw}.wav"
                try:
                    remote = f"{export_dir}/{fname}"
                    local = os.path.join(tmp_export, fname)
                    copy_from_env(remote, local)
                    if os.path.exists(local) and os.path.getsize(local) > 100:
                        segments_found += 1
                        break
                except Exception:
                    continue

    if segments_found >= 5:
        score += 25.0
        feedback.append(f"PASS: All {segments_found} evidence segments exported")
    elif segments_found >= 3:
        score += 15.0
        feedback.append(f"PARTIAL: {segments_found}/5 segments exported")
    elif segments_found >= 1:
        score += 7.0
        feedback.append(f"PARTIAL: {segments_found}/5 segments exported")
    else:
        feedback.append("FAIL: No segment files exported")

    # ================================================================
    # CRITERION 4: Chain of custody log (20 pts)
    # Must contain: case number, exhibit ID, lab file #,
    #               examiner reference, date, segment descriptions
    # ================================================================
    coc_path = f"{export_dir}/chain_of_custody.txt"
    tmp_coc = os.path.join(tmp_export, "chain_of_custody.txt")
    coc_found = False
    coc_content = ""

    try:
        copy_from_env(coc_path, tmp_coc)
        if os.path.exists(tmp_coc) and os.path.getsize(tmp_coc) > 10:
            coc_found = True
            with open(tmp_coc, 'r', errors='replace') as f:
                coc_content = f.read().lower()
    except Exception:
        pass

    if coc_found:
        required_fields = {
            'case_number': any(x in coc_content for x in ['2024-cr-0847', '0847']),
            'exhibit_id': any(x in coc_content for x in ['exhibit a', 'exhibit-a']),
            'lab_file': any(x in coc_content for x in ['ae-2024-1547', '1547']),
            'segments': any(x in coc_content for x in ['segment', 'speaker', 'background', 'crosstalk']),
            'preservation': any(x in coc_content for x in ['original', 'not altered', 'unaltered',
                                                            'preserved', 'intact', 'not modified']),
        }
        fields_present = sum(required_fields.values())

        if fields_present >= 4:
            score += 20.0
            feedback.append(f"PASS: Chain of custody log has {fields_present}/5 required fields")
        elif fields_present >= 2:
            score += 12.0
            feedback.append(f"PARTIAL: Chain of custody has {fields_present}/5 required fields")
        elif fields_present >= 1:
            score += 5.0
            feedback.append(f"PARTIAL: Chain of custody has {fields_present}/5 required fields")
        else:
            score += 3.0
            feedback.append("PARTIAL: Chain of custody file exists but missing key fields")
    else:
        feedback.append("FAIL: No chain of custody log found")

    # ================================================================
    # CRITERION 5: Original audio region preserved (15 pts)
    # There should still be at least 1 audio region in the session
    # ================================================================
    region_count = count_regions(root)
    if region_count >= 1:
        score += 15.0
        feedback.append(f"PASS: Original recording preserved ({region_count} region(s) in session)")
    else:
        feedback.append("FAIL: Original audio region appears to have been deleted")

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


verify_task = verify_forensic_audio_segmentation


# ---------- Offline mock tests ----------

if __name__ == "__main__":
    import shutil

    def make_session(tracks=None, markers=None, has_region=True):
        xml = '<?xml version="1.0" encoding="UTF-8"?>\n<Session name="MyProject">\n'
        xml += '<Routes>\n'
        xml += '<Route name="Master" default-type="audio" flags="MasterOut">'
        xml += '<Controllable name="gaincontrol" value="1.0"/></Route>\n'
        if tracks:
            for t in tracks:
                xml += f'<Route name="{t["name"]}" default-type="audio">'
                xml += '<Controllable name="gaincontrol" value="1.0"/></Route>\n'
        xml += '</Routes>\n<Playlists>\n'
        if has_region and tracks:
            tname = tracks[0]['name']
            xml += f'<Playlist name="{tname}.1">'
            xml += '<Region name="evidence" position="0" length="1323000"/>'
            xml += '</Playlist>\n'
        xml += '</Playlists>\n<Locations>\n'
        xml += '<Location name="session" start="0" end="1323000" flags="IsSessionRange"/>\n'
        if markers:
            for m in markers:
                xml += f'<Location name="{m["name"]}" start="{m["start"]}" end="{m.get("end", m["start"])}" flags="{m.get("flags","IsMark")}"/>\n'
        xml += '</Locations>\n</Session>'
        return xml

    def run_test(name, xml_str, export_files=None, coc_content=None):
        tmpdir = tempfile.mkdtemp()
        sp = os.path.join(tmpdir, "MyProject.ardour")
        with open(sp, 'w') as f:
            f.write(xml_str)

        export_d = os.path.join(tmpdir, "evidence_output")
        os.makedirs(export_d, exist_ok=True)
        if export_files:
            for fname in export_files:
                with open(os.path.join(export_d, fname), 'wb') as f:
                    f.write(b'\x00' * 5000)
        if coc_content:
            with open(os.path.join(export_d, "chain_of_custody.txt"), 'w') as f:
                f.write(coc_content)

        def mock_copy(remote, local):
            if 'MyProject.ardour' in remote:
                shutil.copy2(sp, local)
            elif 'evidence_output' in remote:
                fname = os.path.basename(remote)
                src = os.path.join(export_d, fname)
                if os.path.exists(src):
                    shutil.copy2(src, local)
                else:
                    raise FileNotFoundError(remote)
            else:
                raise FileNotFoundError(remote)

        result = verify_forensic_audio_segmentation([], {'copy_from_env': mock_copy}, {})
        shutil.rmtree(tmpdir, ignore_errors=True)
        print(f"\nTEST: {name} -> passed={result['passed']}, score={result['score']}")
        print(f"  {result['feedback']}")
        return result

    # Do-nothing
    r1 = run_test("Do-nothing", make_session(tracks=[{'name': 'Audio 1'}]))
    assert not r1['passed'], "Do-nothing must fail"

    # Full completion
    coc = """CHAIN OF CUSTODY LOG
Case Number: 2024-CR-0847
Exhibit: Exhibit A
Lab File: AE-2024-1547
Examiner: Audio Lab Tech
Date: 2024-11-16
Segments: Background, Speaker 1, Crosstalk, Speaker 2, Ambient
The original recording was not altered during this analysis."""

    r2 = run_test("Full completion",
        make_session(
            tracks=[{'name': 'Exhibit A - Case 2024-CR-0847'}],
            markers=[
                {'name': 'Background Start', 'start': 0},
                {'name': 'Speaker 1', 'start': 220500},
                {'name': 'Crosstalk', 'start': 661500},
                {'name': 'Speaker 2', 'start': 793800},
                {'name': 'Ambient Tail', 'start': 1102500},
                {'name': 'End', 'start': 1323000},
            ]),
        export_files=[
            'segment_01_background.wav',
            'segment_02_speaker1_defendant.wav',
            'segment_03_crosstalk.wav',
            'segment_04_speaker2_complainant.wav',
            'segment_05_ambient_tail.wav',
        ],
        coc_content=coc)
    assert r2['passed'], f"Full completion must pass, got {r2['score']}"

    print("\n\nAll offline mock tests passed!")
