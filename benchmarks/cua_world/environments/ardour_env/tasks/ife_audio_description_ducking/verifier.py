#!/usr/bin/env python3
"""
Verifier for ife_audio_description_ducking task.
Occupation: Audio and Video Technician (SOC 27-4011)

Checks that the agent created a narration track, placed it correctly,
ducked the program track temporally, added a marker, and exported the result.
"""

import math
import os
import tempfile
import json
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

SAMPLE_RATE = 44100

# ---------- XML Parsing & Math Helpers ----------

def parse_events(events_str):
    """Parses Ardour automation events 'time value, time value' into a sorted list of tuples."""
    pts = []
    if not events_str: return pts
    for pt in events_str.strip().split(','):
        parts = pt.strip().split()
        if len(parts) >= 2:
            pts.append((int(parts[0]), float(parts[1])))
    return sorted(pts)

def interpolate(pts, time):
    """Linearly interpolate value at given time from event points."""
    if not pts: return 1.0
    if time <= pts[0][0]: return pts[0][1]
    if time >= pts[-1][0]: return pts[-1][1]
    for i in range(len(pts)-1):
        t1, v1 = pts[i]
        t2, v2 = pts[i+1]
        if t1 <= time <= t2:
            if t1 == t2: return v1
            fraction = (time - t1) / (t2 - t1)
            return v1 + fraction * (v2 - v1)
    return 1.0

def get_audio_routes(root):
    routes = []
    for route in root.iter('Route'):
        flags = route.get('flags', '')
        if 'MasterOut' in flags or 'MonitorOut' in flags:
            continue
        if route.get('default-type') == 'audio':
            routes.append(route)
    return routes

def find_route_by_name(root, name):
    for route in get_audio_routes(root):
        if route.get('name', '').lower() == name.lower():
            return route
    return None

def get_route_gain_linear(route, time):
    """Gets the automated or static track gain at a given time sample."""
    ctrl = route.find(".//Controllable[@name='gaincontrol']")
    if ctrl is None: return 1.0
    
    auto = ctrl.find(".//AutomationList/events")
    if auto is not None and auto.text:
        pts = parse_events(auto.text)
        return interpolate(pts, time)
    return float(ctrl.get('value', '1.0'))

def get_playlist_regions(root, route):
    """Locates the regions for a specific route."""
    regions = []
    # Check inside the route's diskstream first
    for pl in route.findall('.//Playlist'):
        regions.extend(pl.findall('.//Region'))
    if not regions:
        # Check global playlists matching route name
        rname = route.get('name', '')
        for pl in root.findall('./Playlists/Playlist') + root.findall('./Playlist'):
            pl_name = pl.get('name', '')
            base = pl_name.rsplit('.', 1)[0] if '.' in pl_name else pl_name
            if base.lower() == rname.lower() or pl_name.lower().startswith(rname.lower()):
                regions.extend(pl.findall('.//Region'))
    return regions

def get_region_gain_linear(root, route, time):
    """Calculates the maximum region gain (scale-amplitude * envelope) at a specific time."""
    regions = get_playlist_regions(root, route)
    max_gain = 0.0
    overlapping_regions = 0
    
    for r in regions:
        pos = int(r.get('position', '0'))
        length = int(r.get('length', '0'))
        
        if pos <= time < pos + length:
            overlapping_regions += 1
            scale = float(r.get('scale-amplitude', '1.0'))
            
            # Envelope Automation
            env_gain = 1.0
            env = r.find('.//Envelope/AutomationList/events')
            if env is not None and env.text:
                pts = parse_events(env.text)
                rel_time = time - pos
                env_gain = interpolate(pts, rel_time)
                
            gain = scale * env_gain
            if gain > max_gain:
                max_gain = gain
                
    if max_gain == 0.0 and overlapping_regions > 0:
        return 0.0 # True silence (region gain pulled to 0)
    if max_gain == 0.0:
        return 1.0 # No regions found, fallback logic prevents math errors
    return max_gain

def get_effective_gain_db(root, route, time):
    """Combined gain of Track Fader + Region properties converted to dB."""
    track_gain = get_route_gain_linear(route, time)
    region_gain = get_region_gain_linear(root, route, time)
    
    total_linear = track_gain * region_gain
    if total_linear <= 0.000001: 
        return -120.0
    return 20 * math.log10(total_linear)

def get_markers(root):
    markers = []
    for loc in root.iter('Location'):
        flags = loc.get('flags', '')
        if 'IsMark' in flags and 'IsSessionRange' not in flags:
            markers.append({
                'name': loc.get('name', ''),
                'start': int(loc.get('start', '0'))
            })
    return markers

# ---------- Main Verifier ----------

def verify_ife_audio_description_ducking(traj, env_info, task_info):
    """
    1. Track Creation & Naming (15 pts)
    2. Narration Position @ 10s (20 pts)
    3. Ducking Execution (30 pts) -> Program gain at 15s >= 6dB lower than at 5s
    4. Marker Placement (15 pts) -> "AD Start" at 10s
    5. Audio Export (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    target_sample = metadata.get('narration_start_sample', 441000)
    tolerance = metadata.get('tolerance_samples', 22050)
    ducking_req_db = metadata.get('ducking_min_db_reduction', 6.0)
    
    score = 0.0
    feedback = []

    # 1. READ EXPORT RESULT JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_data = {}
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to read result json: {e}")
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. READ ARDOUR XML
    session_remote = "/home/ga/Audio/sessions/MyProject/MyProject.ardour"
    tmp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.ardour')
    
    try:
        copy_from_env(session_remote, tmp_xml.name)
        tree = ET.parse(tmp_xml.name)
        root = tree.getroot()
    except Exception as e:
        if os.path.exists(tmp_xml.name): os.unlink(tmp_xml.name)
        return {"passed": False, "score": 0, "feedback": f"Session parse error: {e}"}
    finally:
        if os.path.exists(tmp_xml.name):
            os.unlink(tmp_xml.name)

    # --- CRITERION 1: Track Creation & Naming (15 pts) ---
    program_route = find_route_by_name(root, "Program")
    narration_route = find_route_by_name(root, "Narration")
    
    if program_route is not None and narration_route is not None:
        score += 15.0
        feedback.append("PASS: Both Program and Narration tracks found.")
    else:
        # Fallback to general tracking logic for partial credit
        routes = get_audio_routes(root)
        if len(routes) >= 2:
            score += 7.0
            feedback.append("PARTIAL: 2 tracks found, but missing exact names 'Program' / 'Narration'.")
            # Assign first track as program, second as narration just to allow further testing
            program_route = routes[0]
            narration_route = routes[1]
        else:
            feedback.append("FAIL: Required tracks not found.")

    # --- CRITERION 2: Narration Position (20 pts) ---
    if narration_route is not None:
        regions = get_playlist_regions(root, narration_route)
        positioned_correctly = False
        
        for r in regions:
            pos = int(r.get('position', '0'))
            if abs(pos - target_sample) <= tolerance:
                positioned_correctly = True
                break
                
        if positioned_correctly:
            score += 20.0
            feedback.append("PASS: Narration region placed at 10.0s.")
        else:
            feedback.append("FAIL: Narration region not found at 10.0s.")
    else:
        feedback.append("FAIL: Could not check Narration position (track missing).")

    # --- CRITERION 3: Ducking Execution (30 pts) ---
    ducking_success = False
    if program_route is not None:
        gain_5s = get_effective_gain_db(root, program_route, int(5.0 * SAMPLE_RATE))
        gain_15s = get_effective_gain_db(root, program_route, int(15.0 * SAMPLE_RATE))
        
        reduction = gain_5s - gain_15s
        
        if reduction >= ducking_req_db:
            score += 30.0
            ducking_success = True
            feedback.append(f"PASS: Ducking successful (Gain drops by {reduction:.1f} dB at 15s).")
        elif reduction > 2.0:
            score += 15.0
            feedback.append(f"PARTIAL: Mild ducking detected (Gain drops by {reduction:.1f} dB).")
        else:
            feedback.append(f"FAIL: No ducking detected. Gain delta: {reduction:.1f} dB.")
    else:
        feedback.append("FAIL: Could not check ducking (Program track missing).")

    # --- CRITERION 4: Marker Placement (15 pts) ---
    markers = get_markers(root)
    marker_found = False
    for m in markers:
        if 'ad' in m['name'].lower() and abs(m['start'] - target_sample) <= tolerance:
            marker_found = True
            break
            
    if marker_found:
        score += 15.0
        feedback.append("PASS: 'AD Start' marker placed correctly.")
    else:
        # Partial credit if they just placed a marker at 10s without the correct name
        if any(abs(m['start'] - target_sample) <= tolerance for m in markers):
            score += 7.0
            feedback.append("PARTIAL: Marker placed at 10s, but not named 'AD Start'.")
        else:
            feedback.append("FAIL: 'AD Start' marker not found at 10s.")

    # --- CRITERION 5: Audio Export (20 pts) ---
    export_exists = result_data.get('export_exists', False)
    file_created = result_data.get('file_created_during_task', False)
    size_bytes = result_data.get('export_size_bytes', 0)
    
    if export_exists and file_created and size_bytes > 50000:
        score += 20.0
        feedback.append("PASS: Final mix exported correctly.")
    elif export_exists and size_bytes > 1000:
        score += 10.0
        feedback.append("PARTIAL: File exported but may have existed before task or is too small.")
    else:
        feedback.append("FAIL: Final mix WAV file not exported properly.")

    # --- Pass Threshold logic ---
    key_work_done = ducking_success or (export_exists and file_created)
    passed = (score >= 70.0) and key_work_done

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "ducking_success": ducking_success,
            "export_found": export_exists
        }
    }