#!/usr/bin/env python3
"""
Verifier for oral_history_tape_assembly task.
Occupation: Archivist / Audio Preservationist
Industry: Museum / Historical Society

Checks that the agent assembled two tape sides onto a continuous timeline
with a precise 2-second overlap, marked the splice, renamed the track,
and exported the restored master file.
"""

import os
import tempfile
import json
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


def get_route_names(root):
    return [r.get('name', '') for r in get_audio_routes(root)]


def get_playlists(root):
    """Returns a dict mapping playlist names to a list of regions."""
    playlists = {}
    for pl in root.iter('Playlist'):
        pl_name = pl.get('name', '')
        regions = []
        for r in pl.iter('Region'):
            regions.append({
                'name': r.get('name', '').lower(),
                'position': int(r.get('position', '0')),
                'length': int(r.get('length', '0'))
            })
        playlists[pl_name] = regions
    return playlists


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


# ---------- Main verifier ----------

def verify_oral_history_tape_assembly(traj, env_info, task_info):
    """
    Multi-criterion verifier for oral history tape assembly.

    Criteria (100 pts total, pass >= 60):
      1. Track renamed ("tape 042" / "archive")             (15 pts)
      2. Side A position ~0s                                (20 pts)
      3. Side B position ~13s (2s overlap)                  (25 pts)
      4. Marker "Tape Flip" ~13s                            (15 pts)
      5. Exported WAV file created during task (> 100KB)    (25 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "copy_from_env not available"}

    score = 0.0
    feedback = []

    # Expected values
    expected_sideA_pos = 0
    expected_sideB_pos = 573300  # 13 seconds @ 44.1kHz
    tolerance = 22050            # 0.5 seconds

    # ---- Check Export JSON ----
    tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_json.close()
    try:
        copy_from_env("/tmp/oral_history_result.json", tmp_json.name)
        with open(tmp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0.0, "feedback": f"Could not read result JSON: {e}"}
    finally:
        if os.path.exists(tmp_json.name):
            os.unlink(tmp_json.name)

    # ---- Copy session XML ----
    session_remote = "/home/ga/Audio/sessions/MyProject/MyProject.ardour"
    tmp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.ardour')
    tmp_xml.close()

    try:
        copy_from_env(session_remote, tmp_xml.name)
        tree = ET.parse(tmp_xml.name)
        root = tree.getroot()
    except Exception as e:
        if os.path.exists(tmp_xml.name):
            os.unlink(tmp_xml.name)
        return {"passed": False, "score": 0.0, "feedback": f"XML parse error or session missing: {e}"}
    finally:
        if os.path.exists(tmp_xml.name):
            os.unlink(tmp_xml.name)

    # ================================================================
    # CRITERION 1: Track renamed (15 pts)
    # ================================================================
    route_names = get_route_names(root)
    valid_keywords = ['tape 042', 'oral history', 'archive', '042', 'history']
    renamed = False

    for rn in route_names:
        rn_lower = rn.lower()
        if rn_lower != 'audio 1' and any(kw in rn_lower for kw in valid_keywords):
            renamed = True
            break

    if renamed:
        score += 15.0
        feedback.append("PASS: Track renamed correctly")
    else:
        non_default = [rn for rn in route_names if rn.lower() != 'audio 1']
        if non_default:
            score += 5.0
            feedback.append(f"PARTIAL: Track renamed to '{non_default[0]}' but missing keywords")
        else:
            feedback.append("FAIL: Track not renamed")

    # ================================================================
    # CRITERION 2 & 3: Region Positions and Overlap (45 pts total)
    # ================================================================
    playlists = get_playlists(root)
    
    sidea_found = False
    sideb_found = False
    sidea_pos = -1
    sideb_pos = -1
    same_track = False

    for pl_name, regions in playlists.items():
        has_a = False
        has_b = False
        local_a_pos = -1
        local_b_pos = -1
        for r in regions:
            if 'sidea' in r['name']:
                local_a_pos = r['position']
                has_a = True
            if 'sideb' in r['name']:
                local_b_pos = r['position']
                has_b = True
                
        if has_a:
            sidea_found = True
            sidea_pos = local_a_pos
        if has_b:
            sideb_found = True
            sideb_pos = local_b_pos
            
        if has_a and has_b:
            same_track = True

    if sidea_found and abs(sidea_pos - expected_sideA_pos) <= tolerance:
        score += 20.0
        feedback.append("PASS: Side A positioned at start (0:00)")
    elif sidea_found:
        score += 10.0
        feedback.append(f"PARTIAL: Side A found but position off ({sidea_pos})")
    else:
        feedback.append("FAIL: Side A region not found in session")

    if sideb_found and abs(sideb_pos - expected_sideB_pos) <= tolerance:
        score += 25.0
        feedback.append("PASS: Side B positioned at 0:13 (correct 2s overlap)")
    elif sideb_found:
        score += 10.0
        feedback.append(f"PARTIAL: Side B found but position off ({sideb_pos})")
    else:
        feedback.append("FAIL: Side B region not found in session")
        
    if sidea_found and sideb_found and not same_track:
        score -= 10.0
        feedback.append("PENALTY: Regions placed on different tracks (instructions requested single track)")

    # ================================================================
    # CRITERION 4: Marker "Tape Flip" (15 pts)
    # ================================================================
    markers = get_markers(root)
    flip_marker_found = False

    for m in markers:
        if 'flip' in m['name'].lower():
            if abs(m['start'] - expected_sideB_pos) <= tolerance:
                flip_marker_found = True
                break

    if flip_marker_found:
        score += 15.0
        feedback.append("PASS: 'Tape Flip' marker correctly placed")
    else:
        # Check if they placed a marker at the right spot but named it wrong
        unnamed_marker_at_spot = any(abs(m['start'] - expected_sideB_pos) <= tolerance for m in markers)
        if unnamed_marker_at_spot:
            score += 7.0
            feedback.append("PARTIAL: Marker placed at correct position but incorrectly named")
        else:
            feedback.append("FAIL: 'Tape Flip' marker not found at correct position")

    # ================================================================
    # CRITERION 5: Exported WAV File (25 pts)
    # ================================================================
    export_exists = result.get('export_exists', False)
    export_size = result.get('export_size', 0)
    export_mtime = result.get('export_mtime', 0)
    task_start = result.get('task_start_timestamp', 0)

    if export_exists and export_size > 100000:  # > 100 KB
        if export_mtime >= task_start:
            score += 25.0
            feedback.append("PASS: Continuous master file exported successfully")
        else:
            feedback.append("FAIL: Export file is older than task start (anti-gaming)")
    elif export_exists:
        score += 10.0
        feedback.append(f"PARTIAL: Export file exists but is unexpectedly small ({export_size} bytes)")
    else:
        feedback.append("FAIL: Master WAV file not exported")

    # ================================================================
    # FINAL EVALUATION
    # ================================================================
    passed = score >= PASS_THRESHOLD

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }