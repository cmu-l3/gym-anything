#!/usr/bin/env python3
"""
Verifier for vinyl_album_sequencing task.
Occupation: Mastering Engineer (SOC 27-4014)
Industry: Sound Recording Industries

Checks that the agent correctly sequenced two audio files on a single track,
implemented a mathematically precise gap of silence between them, placed
start markers, applied a fade-out, and exported the continuous file.
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
    """Get all audio track routes."""
    routes = []
    for route in root.iter('Route'):
        flags = route.get('flags', '')
        if 'MasterOut' in flags or 'MonitorOut' in flags:
            continue
        if route.get('default-type') == 'audio':
            routes.append(route)
    return routes


def get_route_names(root):
    """Return list of audio route names."""
    return [r.get('name', '') for r in get_audio_routes(root)]


def get_regions_for_route(root, route_name):
    """Get region metadata from the playlist associated with a route."""
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
                    'fade_out_length': int(region.get('fade-out-length', '0')),
                    'fade_out_active': region.get('fade-out-active', '0') == '1'
                })
    # Sort regions temporally
    regions.sort(key=lambda x: x['position'])
    return regions


def get_markers(root):
    """Get user-placed markers."""
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

def verify_vinyl_album_sequencing(traj, env_info, task_info):
    """
    Multi-criterion verifier for vinyl album sequencing.

    Criteria (100 pts total, pass >= 70):
      1. Track Name & Usage: Single track named "Vinyl Pre-Master" holding both regions (10 pts)
      2. Region Sequencing: Both files chronologically ordered (moonlight -> narration) (20 pts)
      3. Precise Gap: Gap between regions is exactly 3.0 seconds (30 pts)
      4. Location Markers: "Side A1" and "Side A2" at region starts (15 pts)
      5. Fade-Out: Final region has a 2.0 second fade out applied (10 pts)
      6. Export: Valid WAV file exported (15 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    sample_rate = metadata.get('sample_rate', 44100)
    gap_samples = int(metadata.get('required_gap_seconds', 3.0) * sample_rate)
    gap_tol = metadata.get('gap_tolerance_samples', 8820)
    fade_samples = int(metadata.get('required_fade_seconds', 2.0) * sample_rate)
    fade_tol = metadata.get('fade_tolerance_samples', 22050)
    marker_tol = metadata.get('marker_tolerance_samples', 4410)

    score = 0.0
    feedback = []

    # ---- Check Export JSON ----
    export_json_path = "/tmp/vinyl_sequencing_result.json"
    tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_json.close()
    
    export_data = {}
    try:
        copy_from_env(export_json_path, tmp_json.name)
        with open(tmp_json.name, 'r') as f:
            export_data = json.load(f)
    except Exception as e:
        logger.warning(f"Could not load export JSON: {e}")
    finally:
        if os.path.exists(tmp_json.name):
            os.unlink(tmp_json.name)

    # ---- Copy session XML ----
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

    # ================================================================
    # Find the track holding the sequenced regions
    # ================================================================
    route_names = get_route_names(root)
    target_route = None
    target_regions = []

    # First look for appropriately named track
    for rn in route_names:
        if 'vinyl' in rn.lower() or 'pre-master' in rn.lower() or 'master' in rn.lower():
            regs = get_regions_for_route(root, rn)
            if len(regs) >= 2:
                target_route = rn
                target_regions = regs
                break
    
    # Fallback: look for ANY track holding >= 2 regions
    if not target_route:
        for rn in route_names:
            regs = get_regions_for_route(root, rn)
            if len(regs) >= 2:
                target_route = rn
                target_regions = regs
                break

    if not target_route or len(target_regions) < 2:
        feedback.append("FAIL: Could not find a track containing two sequenced regions.")
        return {"passed": False, "score": 0.0, "feedback": " | ".join(feedback)}

    # ================================================================
    # CRITERION 1: Track Name (10 pts)
    # ================================================================
    if 'vinyl' in target_route.lower() or 'pre-master' in target_route.lower():
        score += 10.0
        feedback.append("PASS: Correctly named track ('Vinyl Pre-Master')")
    else:
        score += 5.0
        feedback.append(f"PARTIAL: Used incorrectly named track '{target_route}'")

    # ================================================================
    # CRITERION 2: Region Sequencing (20 pts)
    # R1 should be moonlight, R2 should be narration
    # ================================================================
    r1 = target_regions[0]
    r2 = target_regions[1]

    if 'moonlight' in r1['name'].lower() and 'narration' in r2['name'].lower():
        score += 20.0
        feedback.append("PASS: Files sequenced in correct chronological order")
    elif 'narration' in r1['name'].lower() and 'moonlight' in r2['name'].lower():
        feedback.append("FAIL: Regions sequenced in the wrong order")
    else:
        score += 10.0
        feedback.append("PARTIAL: Unrecognized source files, but sequential arrangement found")

    # ================================================================
    # CRITERION 3: Precise Gap (30 pts)
    # Gap = R2.pos - (R1.pos + R1.length) == 132300 samples (+/- 8820)
    # ================================================================
    r1_end = r1['position'] + r1['length']
    actual_gap = r2['position'] - r1_end

    if abs(actual_gap - gap_samples) <= gap_tol:
        score += 30.0
        feedback.append(f"PASS: Perfect 3.0s gap calculated (delta {abs(actual_gap - gap_samples)} samples)")
    elif abs(actual_gap - gap_samples) <= (gap_tol * 3):
        score += 15.0
        feedback.append(f"PARTIAL: Gap is approximately 3.0s but outside strict tolerance")
    else:
        actual_gap_sec = actual_gap / sample_rate
        feedback.append(f"FAIL: Gap is incorrect ({actual_gap_sec:.2f}s instead of 3.0s)")

    # ================================================================
    # CRITERION 4: Location Markers (15 pts)
    # ================================================================
    markers = get_markers(root)
    m1_found = False
    m2_found = False

    for m in markers:
        name = m['name'].lower()
        if 'a1' in name and abs(m['start'] - r1['position']) <= marker_tol:
            m1_found = True
        if 'a2' in name and abs(m['start'] - r2['position']) <= marker_tol:
            m2_found = True

    if m1_found and m2_found:
        score += 15.0
        feedback.append("PASS: Both track markers placed accurately")
    elif m1_found or m2_found:
        score += 7.0
        feedback.append("PARTIAL: Only one track marker correctly placed")
    else:
        feedback.append("FAIL: Track markers missing or improperly placed")

    # ================================================================
    # CRITERION 5: Fade-Out (10 pts)
    # ================================================================
    # Check if the final region has a ~2.0s fade out
    final_region = target_regions[-1]
    
    has_fade = final_region['fade_out_active'] and final_region['fade_out_length'] > 0
    fade_len = final_region['fade_out_length']

    if has_fade and abs(fade_len - fade_samples) <= fade_tol:
        score += 10.0
        feedback.append("PASS: Correct 2.0s fade-out applied to ending")
    elif has_fade and fade_len > 44100: # at least 1 second
        score += 5.0
        feedback.append("PARTIAL: Fade-out applied, but incorrect length")
    else:
        feedback.append("FAIL: Required fade-out is missing on final region")

    # ================================================================
    # CRITERION 6: Export (15 pts)
    # ================================================================
    exported_file = export_data.get('exported_file', '')
    exported_size = export_data.get('exported_file_size', 0)
    exported_mtime = export_data.get('exported_file_mtime', 0)
    task_start = export_data.get('task_start_timestamp', 0)

    if exported_file and exported_size > 1048576: # > 1MB
        # Anti-gaming: Ensure file was made after task started
        if exported_mtime > task_start:
            score += 15.0
            feedback.append("PASS: Continuous WAV file exported successfully")
        else:
            feedback.append("FAIL: Exported file is older than the task start (stale/cheated file)")
    else:
        feedback.append("FAIL: Exported file missing or too small")

    pass_threshold = metadata.get('pass_threshold', 70)
    passed = score >= pass_threshold

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }