#!/usr/bin/env python3
"""
Verifier for adr_session_prep task.
Occupation: Sound Engineering Technician / Dialogue Editor (SOC 27-4014)
Industry: Motion Picture & Video Production

Checks that the agent prepared an ADR session with a muted guide track,
a record-armed destination track, a 3-beep cue track, and a 5.0s-15.0s loop range.
"""

import os
import tempfile
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

PASS_THRESHOLD = 75.0
SAMPLE_RATE = 44100

# ---------- Ardour XML helpers ----------

def get_audio_routes(root):
    """Get all audio tracks (excluding Master/Monitor)."""
    routes = []
    for route in root.iter('Route'):
        flags = route.get('flags', '')
        if 'MasterOut' in flags or 'MonitorOut' in flags:
            continue
        if route.get('default-type') == 'audio':
            routes.append(route)
    return routes

def get_route_by_keywords(routes, keywords):
    """Find a route matching any of the given keywords."""
    for route in routes:
        name = route.get('name', '').lower()
        if any(kw in name for kw in keywords):
            return route
    return None

def is_route_muted(route):
    """Check if a route is muted."""
    if not route:
        return False
    # Check Controllable
    for ctrl in route.iter('Controllable'):
        if ctrl.get('name') == 'mute':
            return ctrl.get('value', '0') in ('1', 'yes', 'true')
    # Check Route attribute
    return route.get('muted', '0') in ('1', 'yes', 'true')

def is_route_record_armed(route):
    """Check if a route is record-armed."""
    if not route:
        return False
    # Check Controllable
    for ctrl in route.iter('Controllable'):
        if ctrl.get('name') == 'recenable':
            return ctrl.get('value', '0') in ('1', 'yes', 'true')
    # Check Route attribute
    return route.get('record-enabled', '0') in ('1', 'yes', 'true')

def count_regions_on_route(root, route):
    """Count how many regions exist on the playlist used by this route."""
    if not route:
        return 0
    route_name = route.get('name', '')
    count = 0
    for playlist in root.iter('Playlist'):
        pl_name = playlist.get('name', '')
        base = pl_name.rsplit('.', 1)[0] if '.' in pl_name else pl_name
        if base.lower() == route_name.lower() or pl_name.lower().startswith(route_name.lower()):
            for region in playlist.iter('Region'):
                count += 1
    return count

def get_loop_range(root):
    """Find the start and end samples for the loop range."""
    for loc in root.iter('Location'):
        flags = loc.get('flags', '')
        name = loc.get('name', '').lower()
        if 'isautoloop' in flags.lower() or name == 'loop':
            try:
                start = int(loc.get('start', '0'))
                end = int(loc.get('end', '0'))
                return start, end
            except ValueError:
                return None, None
    return None, None

# ---------- Main verifier ----------

def verify_adr_session_prep(traj, env_info, task_info):
    """
    Multi-criterion verifier for ADR session prep.

    Criteria (100 pts total, pass >= 75):
      1. Three required tracks exist (Guide, ADR Record, Beep)  (20 pts)
      2. Guide track is muted                                   (15 pts)
      3. ADR Record track is record-armed                       (15 pts)
      4. Beep track has exactly 3 regions                       (25 pts)
      5. Loop range is set to 5.0s - 15.0s                      (25 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "copy_from_env not available"}

    score = 0.0
    feedback = []

    # Get metadata
    metadata = task_info.get('metadata', {})
    expected_start = metadata.get('loop_start_samples', 220500)
    expected_end = metadata.get('loop_end_samples', 661500)
    tolerance = metadata.get('loop_tolerance_samples', 44100)

    # Validate export json
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_json.close()
    try:
        copy_from_env("/tmp/adr_session_prep_result.json", temp_json.name)
        import json
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0.0, "feedback": f"Failed to read result metadata: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    task_start = result_data.get('task_start_timestamp', 0)
    session_mtime = result_data.get('session_mtime', 0)

    # Check anti-gaming
    if session_mtime < task_start:
        return {
            "passed": False, 
            "score": 0.0, 
            "feedback": "FAIL: Session file was not saved during the task execution."
        }

    # ---- Copy session XML ----
    session_remote = "/home/ga/Audio/sessions/MyProject/MyProject.ardour"
    tmp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.ardour')
    tmp_xml.close()

    try:
        copy_from_env(session_remote, tmp_xml.name)
    except Exception as e:
        return {"passed": False, "score": 0.0, "feedback": f"Session not accessible: {e}"}

    if not os.path.exists(tmp_xml.name) or os.path.getsize(tmp_xml.name) == 0:
        return {"passed": False, "score": 0.0, "feedback": "Session file empty or missing"}

    try:
        tree = ET.parse(tmp_xml.name)
        root = tree.getroot()
    except Exception as e:
        os.unlink(tmp_xml.name)
        return {"passed": False, "score": 0.0, "feedback": f"XML parse error: {e}"}

    audio_routes = get_audio_routes(root)

    # Find the tracks
    guide_track = get_route_by_keywords(audio_routes, ['guide'])
    record_track = get_route_by_keywords(audio_routes, ['record', 'adr'])
    beep_track = get_route_by_keywords(audio_routes, ['beep'])

    # ================================================================
    # CRITERION 1: Track Names (20 pts)
    # ================================================================
    tracks_found = sum(1 for t in [guide_track, record_track, beep_track] if t is not None)
    if tracks_found == 3:
        score += 20.0
        feedback.append("PASS: All 3 required tracks (Guide, Record, Beep) found")
    elif tracks_found > 0:
        pts = tracks_found * 6.0
        score += pts
        feedback.append(f"PARTIAL: Found {tracks_found}/3 required tracks")
    else:
        feedback.append("FAIL: Required tracks not found")

    # ================================================================
    # CRITERION 2: Guide Track Muted (15 pts)
    # ================================================================
    if guide_track and is_route_muted(guide_track):
        score += 15.0
        feedback.append("PASS: Guide Track is muted")
    else:
        feedback.append("FAIL: Guide Track is missing or not muted")

    # ================================================================
    # CRITERION 3: ADR Record Track Record-Armed (15 pts)
    # ================================================================
    if record_track and is_route_record_armed(record_track):
        score += 15.0
        feedback.append("PASS: ADR Record Track is record-armed")
    else:
        feedback.append("FAIL: ADR Record Track is missing or not record-armed")

    # ================================================================
    # CRITERION 4: Beep Track has 3 regions (25 pts)
    # ================================================================
    beep_regions = count_regions_on_route(root, beep_track)
    if beep_regions == 3:
        score += 25.0
        feedback.append("PASS: Beep Track contains exactly 3 regions")
    elif beep_regions > 0:
        # Partial credit for putting something on the track
        score += 10.0
        feedback.append(f"PARTIAL: Beep Track contains {beep_regions} regions (expected 3)")
    else:
        feedback.append("FAIL: Beep Track has no regions")

    # ================================================================
    # CRITERION 5: Loop Range 5.0s - 15.0s (25 pts)
    # ================================================================
    loop_start, loop_end = get_loop_range(root)
    if loop_start is not None and loop_end is not None:
        start_ok = abs(loop_start - expected_start) <= tolerance
        end_ok = abs(loop_end - expected_end) <= tolerance
        
        if start_ok and end_ok:
            score += 25.0
            feedback.append(f"PASS: Loop range correctly set around {expected_start}-{expected_end} samples")
        else:
            feedback.append(f"FAIL: Loop range incorrect. Found {loop_start}-{loop_end}, expected {expected_start}-{expected_end}")
    else:
        feedback.append("FAIL: Loop range not found in session")

    passed = score >= PASS_THRESHOLD

    # Clean up
    if os.path.exists(tmp_xml.name):
        os.unlink(tmp_xml.name)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }