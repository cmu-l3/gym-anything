#!/usr/bin/env python3
"""
Verifier for hiit_workout_assembly task.
Occupation: Audio and Video Technician / Podcast Editor
Industry: Fitness / Media Production

Checks that the agent assembled an audio interval mix with strict timeline
gaps, correct voice cue placements, appropriate gain staging, and session markers.
"""

import math
import os
import tempfile
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

SAMPLE_RATE = 44100


# ---------- Ardour XML helpers ----------

def get_audio_routes(root):
    """Return all audio track routes excluding master/monitor."""
    routes = []
    for route in root.iter('Route'):
        flags = route.get('flags', '')
        if 'MasterOut' in flags or 'MonitorOut' in flags:
            continue
        if route.get('default-type') == 'audio':
            routes.append(route)
    return routes


def get_route_gain_db(route):
    """Read the gain control value and convert to dB."""
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


def get_regions_for_route(root, route_name):
    """Find the playlist matching the route name and extract its regions."""
    regions = []
    # Find matching playlist (Ardour playlists often named TrackName or TrackName.1)
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


def get_markers(root):
    """Extract all user-placed Location markers."""
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


# ---------- Main verifier ----------

def verify_hiit_workout_assembly(traj, env_info, task_info):
    """
    Multi-criterion verifier for HIIT workout assembly.

    Criteria (100 pts total, pass >= 70):
      1. Tracks Named "Music" and "Voice Cues"              (15 pts)
      2. Music covers the 10s and 40s points                (20 pts)
      3. Strict rest gap verified on Music track (21s-29s)  (20 pts)
      4. Voice cues placed at 18s and 28s                   (20 pts)
      5. Gain staging (Music -6dB, Voice +3dB)              (15 pts)
      6. Markers placed correctly                           (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "copy_from_env not available"}

    score = 0.0
    feedback = []

    # Get metadata configuration
    metadata = task_info.get('metadata', {})
    music_cov_points = metadata.get('music_coverage_points_samples', [441000, 1764000])  # 10s, 40s
    gap_start, gap_end = metadata.get('strict_gap_range_samples', [926100, 1278900])     # 21s, 29s
    voice_targets = metadata.get('voice_cue_targets_samples', [793800, 1234800])         # 18s, 28s
    voice_tol = metadata.get('voice_cue_tolerance_samples', 44100)                       # 1s
    music_gain_target = metadata.get('music_gain_target_db', -6)
    voice_gain_target = metadata.get('voice_gain_target_db', 3)
    gain_tol = metadata.get('gain_tolerance_db', 1.5)

    # Validate output exported from the container
    try:
        import json
        tmp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp_res.close()
        copy_from_env("/tmp/hiit_workout_assembly_result.json", tmp_res.name)
        with open(tmp_res.name, 'r') as f:
            result = json.load(f)
        os.unlink(tmp_res.name)

        if not result.get("session_modified_during_task", False):
            return {"passed": False, "score": 0.0, "feedback": "Session was not modified during the task."}
    except Exception as e:
        logger.warning(f"Could not read export results: {e}")

    # Copy session XML
    session_remote = "/home/ga/Audio/sessions/MyProject/MyProject.ardour"
    tmp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.ardour')
    tmp_xml.close()

    try:
        copy_from_env(session_remote, tmp_xml.name)
        tree = ET.parse(tmp_xml.name)
        root = tree.getroot()
        os.unlink(tmp_xml.name)
    except Exception as e:
        if os.path.exists(tmp_xml.name):
            os.unlink(tmp_xml.name)
        return {"passed": False, "score": 0.0, "feedback": f"Failed to access or parse Ardour session: {e}"}

    # Extract all data needed
    audio_routes = get_audio_routes(root)
    
    music_route = None
    voice_route = None

    for r in audio_routes:
        name_lower = r.get('name', '').lower()
        if 'music' in name_lower:
            music_route = r
        elif 'voice' in name_lower or 'cue' in name_lower:
            voice_route = r

    # CRITERION 1: Track Naming (15 pts)
    if music_route and voice_route:
        score += 15.0
        feedback.append("PASS: Found 'Music' and 'Voice Cues' tracks.")
    elif music_route or voice_route:
        score += 7.0
        feedback.append("PARTIAL: Found only one of the required tracks.")
    else:
        feedback.append("FAIL: Required track names not found.")
        # Proceed assuming the first track is music, second is voice (if they exist)
        if len(audio_routes) >= 2:
            music_route = audio_routes[0]
            voice_route = audio_routes[1]
        elif len(audio_routes) == 1:
            music_route = audio_routes[0]

    # Stop early if no tracks at all
    if not music_route and not voice_route:
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    # Get regions
    music_regions = get_regions_for_route(root, music_route.get('name')) if music_route else []
    voice_regions = get_regions_for_route(root, voice_route.get('name')) if voice_route else []

    # CRITERION 2: Music Timeline Coverage (20 pts)
    # Check if music plays at 10s and 40s
    cov_1 = any(r['position'] <= music_cov_points[0] and (r['position'] + r['length']) >= music_cov_points[0] for r in music_regions)
    cov_2 = any(r['position'] <= music_cov_points[1] and (r['position'] + r['length']) >= music_cov_points[1] for r in music_regions)

    if cov_1 and cov_2:
        score += 20.0
        feedback.append("PASS: Music regions cover work blocks correctly.")
    elif cov_1 or cov_2:
        score += 10.0
        feedback.append("PARTIAL: Music regions only cover one work block.")
    else:
        feedback.append("FAIL: Music regions do not cover the 10s and 40s work intervals.")

    # CRITERION 3: Strict Rest Gap (20 pts)
    # Check that NO music region intersects the 21s to 29s gap.
    gap_violated = False
    for r in music_regions:
        r_start = r['position']
        r_end = r_start + r['length']
        # Region intersects gap if its start is before gap_end AND its end is after gap_start
        if r_start < gap_end and r_end > gap_start:
            gap_violated = True
            break

    strict_gap_passed = False
    if not gap_violated and len(music_regions) > 0:
        strict_gap_passed = True
        score += 20.0
        feedback.append("PASS: Strict silence gap observed during Rest interval.")
    else:
        feedback.append("FAIL: Music continues playing through the designated Rest interval gap.")

    # CRITERION 4: Voice Cues Timeline (20 pts)
    # Expect regions near 18s and 28s
    cue1_found = any(abs(r['position'] - voice_targets[0]) <= voice_tol for r in voice_regions)
    cue2_found = any(abs(r['position'] - voice_targets[1]) <= voice_tol for r in voice_regions)

    cues_passed = 0
    if cue1_found and cue2_found:
        cues_passed = 2
        score += 20.0
        feedback.append("PASS: Both voice cues placed at correct times.")
    elif cue1_found or cue2_found:
        cues_passed = 1
        score += 10.0
        feedback.append("PARTIAL: Only one voice cue placed correctly.")
    else:
        feedback.append("FAIL: Voice cues not placed near 18s and 28s targets.")

    # CRITERION 5: Gain Staging (15 pts)
    music_gain = get_route_gain_db(music_route) if music_route else 0.0
    voice_gain = get_route_gain_db(voice_route) if voice_route else 0.0

    music_gain_ok = abs(music_gain - music_gain_target) <= gain_tol
    voice_gain_ok = abs(voice_gain - voice_gain_target) <= gain_tol

    if music_gain_ok and voice_gain_ok:
        score += 15.0
        feedback.append(f"PASS: Gain staged perfectly (Music: {music_gain:.1f}dB, Voice: {voice_gain:.1f}dB).")
    elif music_gain_ok or voice_gain_ok:
        score += 7.0
        feedback.append(f"PARTIAL: Partial gain staging (Music: {music_gain:.1f}dB, Voice: {voice_gain:.1f}dB).")
    else:
        feedback.append(f"FAIL: Incorrect gain levels (Music: {music_gain:.1f}dB, Voice: {voice_gain:.1f}dB).")

    # CRITERION 6: Markers (10 pts)
    # Expected: "Work 1" ~ 0s, "Rest" ~ 20s, "Work 2" ~ 30s
    expected_markers = metadata.get('expected_markers', {'work': 0, 'rest': 882000})
    marker_tol = metadata.get('marker_tolerance_samples', 44100)
    actual_markers = get_markers(root)
    
    matched_markers = 0
    for expected_name, expected_pos in expected_markers.items():
        for am in actual_markers:
            # Match by name loosely AND position
            if expected_name.lower().split()[0] in am['name'].lower() and abs(am['start'] - expected_pos) <= marker_tol:
                matched_markers += 1
                break

    if matched_markers == 3:
        score += 10.0
        feedback.append("PASS: All 3 session markers correctly placed.")
    elif matched_markers > 0:
        score += (matched_markers * 3.0)
        feedback.append(f"PARTIAL: {matched_markers}/3 markers placed correctly.")
    else:
        feedback.append("FAIL: Missing expected session markers.")

    # Final pass conditions: Must have a score >= 70, AND must have verified the gap, AND at least one cue.
    passed = (score >= 70.0) and strict_gap_passed and (cues_passed > 0)

    if not passed and score >= 70.0:
        feedback.append("FAIL: Score is >= 70, but missing critical requirements (Strict Rest Gap or Voice Cues).")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }