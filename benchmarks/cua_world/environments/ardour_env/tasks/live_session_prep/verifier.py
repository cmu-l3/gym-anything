#!/usr/bin/env python3
"""
Verifier for live_session_prep task.
Occupation: Audio and Video Technician (SOC 27-4011)
Industry: Performing Arts / Live Entertainment

Checks that the agent set up an Ardour session for a live recording
rehearsal, configuring track names, panning, gains, mutes, markers,
and importing a test audio file onto the Room Mic track.
"""

import math
import os
import tempfile
import logging
import json
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# ---------- Ardour XML helpers ----------

def get_audio_routes(root):
    """Return all audio tracks (excluding master/monitor buses)."""
    routes = []
    for route in root.iter('Route'):
        flags = route.get('flags', '')
        if 'MasterOut' in flags or 'MonitorOut' in flags:
            continue
        if route.get('default-type') == 'audio':
            routes.append(route)
    return routes

def get_route_gain_db(route):
    """Calculate gain in dB for a given route."""
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
    """Extract pan azimuth value (0.0=L, 0.5=C, 1.0=R)."""
    for ctrl in route.iter('Controllable'):
        name = ctrl.get('name', '')
        if 'pan' in name.lower() and 'azimuth' in name.lower():
            try:
                return float(ctrl.get('value', '0.5'))
            except (ValueError, TypeError):
                return 0.5
    return 0.5

def get_route_muted(route):
    """Check if the route is muted."""
    # Check controllable
    for ctrl in route.iter('Controllable'):
        if ctrl.get('name') == 'mute':
            return ctrl.get('value', '0') in ('1', 'yes', 'true')
    # Check mute master element
    mute_master = route.find('MuteMaster')
    if mute_master is not None:
        return mute_master.get('muted', '0') in ('1', 'yes', 'true')
    # Check attribute directly
    return route.get('muted', '0') in ('1', 'yes', 'true')

def get_markers(root):
    """Extract user-placed location markers."""
    markers = []
    for loc in root.iter('Location'):
        flags = loc.get('flags', '')
        if any(f in flags for f in ('IsSessionRange', 'IsAutoLoop', 'IsAutoPunch')):
            continue
        markers.append({
            'name': loc.get('name', ''),
            'start': int(loc.get('start', '0')),
        })
    return markers

def has_regions(root, route_name):
    """Check if the given route's playlist contains any audio regions."""
    for playlist in root.iter('Playlist'):
        pl_name = playlist.get('name', '')
        base = pl_name.rsplit('.', 1)[0] if '.' in pl_name else pl_name
        if base.lower() == route_name.lower() or pl_name.lower().startswith(route_name.lower()):
            if playlist.find('Region') is not None:
                return True
    return False

def find_route_by_aliases(routes, aliases):
    """Find the first route matching any of the aliases."""
    for route in routes:
        name = route.get('name', '').lower()
        for alias in aliases:
            if alias in name:
                return route
    return None

# ---------- Main Verifier ----------

def verify_live_session_prep(traj, env_info, task_info):
    """
    Multi-criterion verifier for live_session_prep.
    
    Criteria (100 pts total, pass >= 55):
      1. Track Names (24 pts) - 4 pts per track (6 tracks)
      2. Pan Positions (24 pts) - 4 pts per track (6 tracks)
      3. Gain Levels (24 pts) - 4 pts per track (6 tracks)
      4. Mute States (12 pts) - 6 pts for Room Mic muted, 6 pts for all others unmuted
      5. Markers (8 pts) - 4 pts per marker (Soundcheck, Take 1) with correct temporal ordering
      6. Audio Imported (8 pts) - Audio region exists on Room Mic track
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "copy_from_env not available"}

    score = 0.0
    feedback = []

    # Verify basic JSON export output for do-nothing detection
    result_tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_tmp.close()
    try:
        copy_from_env("/tmp/live_session_prep_result.json", result_tmp.name)
        with open(result_tmp.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0.0, "feedback": f"Failed to read result metadata: {e}"}
    finally:
        if os.path.exists(result_tmp.name):
            os.unlink(result_tmp.name)

    task_start = result_data.get('task_start_timestamp', 0)
    session_mtime = result_data.get('session_mtime', 0)
    
    # Anti-gaming: Do Nothing Check
    if session_mtime > 0 and session_mtime <= task_start:
        feedback.append("WARNING: Session file was not modified after task started (Do nothing detected).")

    # ---- Copy and parse Ardour session XML ----
    session_remote = "/home/ga/Audio/sessions/MyProject/MyProject.ardour"
    tmp_session = tempfile.NamedTemporaryFile(delete=False, suffix='.ardour')
    tmp_session.close()

    try:
        copy_from_env(session_remote, tmp_session.name)
    except Exception as e:
        return {"passed": False, "score": 0.0, "feedback": f"Session XML not accessible: {e}"}

    if not os.path.exists(tmp_session.name) or os.path.getsize(tmp_session.name) == 0:
        return {"passed": False, "score": 0.0, "feedback": "Session XML file empty or missing"}

    try:
        tree = ET.parse(tmp_session.name)
        root = tree.getroot()
    except Exception as e:
        os.unlink(tmp_session.name)
        return {"passed": False, "score": 0.0, "feedback": f"Session XML parse error: {e}"}

    audio_routes = get_audio_routes(root)
    
    # Define track aliases mapping
    track_aliases = {
        'kick': ['kick'],
        'snare': ['snare'],
        'bass': ['bass'],
        'guitar': ['guitar', 'elec', 'eg'],
        'vocal': ['vocal', 'vox', 'lead'],
        'room': ['room', 'mic']
    }
    
    found_routes = {}
    for key, aliases in track_aliases.items():
        matched = find_route_by_aliases(audio_routes, aliases)
        if matched is not None:
            found_routes[key] = matched

    # 1. Track Names (24 pts: 4 pts per track)
    track_names_score = len(found_routes) * 4.0
    score += track_names_score
    feedback.append(f"Track names: Found {len(found_routes)}/6 expected tracks ({track_names_score} pts)")

    # 2. Pan Positions (24 pts: 4 pts per track)
    # Target pans: Kick=0.5, Snare=0.6, Bass=0.5, Guitar=0.0, Vocal=0.5, Room=0.5
    expected_pans = {
        'kick': (0.45, 0.55),
        'snare': (0.55, 0.70),
        'bass': (0.45, 0.55),
        'guitar': (0.00, 0.15),
        'vocal': (0.45, 0.55),
        'room': (0.45, 0.55)
    }
    
    pan_score = 0.0
    for key, route in found_routes.items():
        pan_val = get_route_pan(route)
        min_p, max_p = expected_pans[key]
        if min_p <= pan_val <= max_p:
            pan_score += 4.0
        else:
            feedback.append(f"  - Pan off target for {key} (Value: {pan_val:.2f})")
    
    score += pan_score
    feedback.append(f"Pan positions: {int(pan_score/4.0)}/6 correct ({pan_score} pts)")

    # 3. Gain Levels (24 pts: 4 pts per track)
    # Targets: Kick=-3, Snare=-3, Bass=-6, Guitar=-6, Vocal=0, Room=-12
    # Tolerance: +/- 2 dB
    expected_gains = {
        'kick': (-5.0, -1.0),
        'snare': (-5.0, -1.0),
        'bass': (-8.0, -4.0),
        'guitar': (-8.0, -4.0),
        'vocal': (-2.0, 2.0),
        'room': (-14.0, -10.0)
    }
    
    gain_score = 0.0
    for key, route in found_routes.items():
        gain_val = get_route_gain_db(route)
        min_g, max_g = expected_gains[key]
        if min_g <= gain_val <= max_g:
            gain_score += 4.0
        else:
            feedback.append(f"  - Gain off target for {key} (Value: {gain_val:.1f} dB)")
            
    score += gain_score
    feedback.append(f"Gain levels: {int(gain_score/4.0)}/6 correct ({gain_score} pts)")

    # 4. Mute States (12 pts)
    # Room Mic Muted (6 pts), All others Unmuted (6 pts)
    mute_score = 0.0
    room_route = found_routes.get('room')
    if room_route is not None:
        if get_route_muted(room_route):
            mute_score += 6.0
            feedback.append("Mute state: Room Mic is muted (6 pts)")
        else:
            feedback.append("Mute state: Room Mic is NOT muted (0 pts)")
            
    others_unmuted = True
    for key, route in found_routes.items():
        if key == 'room':
            continue
        if get_route_muted(route):
            others_unmuted = False
            feedback.append(f"  - Track '{key}' is incorrectly muted")
            
    if others_unmuted and len(found_routes) > 1:
        mute_score += 6.0
        feedback.append("Mute state: Other tracks are correctly unmuted (6 pts)")
        
    score += mute_score

    # 5. Location Markers (8 pts)
    markers = get_markers(root)
    soundcheck_pos = None
    take_pos = None
    
    for m in markers:
        name_lower = m['name'].lower()
        if 'soundcheck' in name_lower:
            soundcheck_pos = m['start']
        elif 'take' in name_lower:
            take_pos = m['start']
            
    marker_score = 0.0
    if soundcheck_pos is not None:
        marker_score += 4.0
    if take_pos is not None:
        if soundcheck_pos is not None and take_pos > soundcheck_pos:
            marker_score += 4.0
        elif soundcheck_pos is None:
            marker_score += 4.0
            
    score += marker_score
    feedback.append(f"Markers: Detected {'Soundcheck ' if soundcheck_pos is not None else ''}{'Take 1' if take_pos is not None else ''} ({marker_score} pts)")
    
    if soundcheck_pos is not None and take_pos is not None and take_pos <= soundcheck_pos:
        feedback.append("  - Marker temporal ordering is incorrect ('Take 1' before 'Soundcheck')")

    # 6. Audio Imported (8 pts)
    import_score = 0.0
    if room_route is not None:
        r_name = room_route.get('name', '')
        if has_regions(root, r_name):
            import_score = 8.0
            feedback.append("Audio Import: Region found on Room Mic track (8 pts)")
        else:
            feedback.append("Audio Import: No regions found on Room Mic track (0 pts)")
            
    score += import_score

    # Final cleanup & pass condition
    try:
        os.unlink(tmp_session.name)
    except:
        pass

    passed = score >= 55.0

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "track_names_score": track_names_score,
            "pan_score": pan_score,
            "gain_score": gain_score,
            "mute_score": mute_score,
            "marker_score": marker_score,
            "import_score": import_score
        }
    }