#!/usr/bin/env python3
"""
Verifier for Radio Drama Stereo Mix task.
Parses the Ardour session XML and checks track names, pan positions,
gain levels, mute states, markers, and exported audio.
"""

import os
import math
import json
import tempfile
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Track name matching aliases
TRACK_ALIASES = {
    "narrator": [
        "narrator", "narr", "narrator_intro", "narrator intro",
        "narration", "narrator track"
    ],
    "alice": [
        "alice", "character alice", "character_alice", "char_alice",
        "char alice", "alice track"
    ],
    "bob": [
        "bob", "character bob", "character_bob", "char_bob",
        "char bob", "bob track"
    ],
    "room_tone": [
        "room tone", "room_tone", "roomtone", "ambience",
        "ambience_room", "amb", "room", "room ambience",
        "room tone track", "ambient"
    ],
}

def parse_routes(root):
    """Extract audio routes (not Master/Monitor) from session XML."""
    routes = []
    for route in root.iter("Route"):
        name = route.get("name", "")
        # Skip master and monitor buses
        if name.lower() in ("master", "monitor"):
            continue
        # We want audio tracks
        if route.get("default-type") == "audio":
            routes.append(route)
    return routes

def get_controllable_value(route, controllable_name):
    """Get the value of a named Controllable within a Route."""
    for ctrl in route.iter("Controllable"):
        if ctrl.get("name", "") == controllable_name:
            try:
                return float(ctrl.get("value", "0"))
            except (ValueError, TypeError):
                return None
    return None

def get_pan_azimuth(route):
    """Get the pan-azimuth value for a route."""
    for pannable in route.iter("Pannable"):
        for ctrl in pannable.iter("Controllable"):
            if ctrl.get("name", "") == "pan-azimuth":
                try:
                    return float(ctrl.get("value", "0.5"))
                except (ValueError, TypeError):
                    return 0.5
    # If no Pannable found, check directly in route
    return get_controllable_value(route, "pan-azimuth")

def linear_to_db(linear):
    """Convert linear gain to dB."""
    if linear is None or linear <= 0:
        return -float("inf")
    return 20.0 * math.log10(linear)

def has_regions(route, root):
    """Check if a route's playlist contains any regions."""
    route_name = route.get("name", "")
    for playlist in root.iter("Playlist"):
        pname = playlist.get("name", "")
        if pname.lower() == route_name.lower() or pname.lower().startswith(route_name.lower()):
            for _ in playlist.iter("Region"):
                return True
    for playlist in route.iter("Playlist"):
        for _ in playlist.iter("Region"):
            return True
    return False

def match_track(route_name, track_key):
    """Check if a route name matches a required track key."""
    name_lower = route_name.lower().strip()
    for alias in TRACK_ALIASES[track_key]:
        if alias == name_lower or alias.replace(" ", "_") == name_lower:
            return True
        # Substring match for longer names
        if len(alias) >= 4 and alias in name_lower:
            return True
    return False

def verify_radio_drama_stereo_mix(traj, env_info, task_info):
    """Main verification function."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_tracks = metadata.get('expected_tracks', ["narrator", "alice", "bob", "room_tone"])
    pan_specs = metadata.get('pan_specs', {})
    gain_specs = metadata.get('gain_specs', {})
    pass_threshold = metadata.get('pass_threshold', 60)

    total_score = 0
    feedback_parts = []

    # ================================================================
    # Read Export Result JSON
    # ================================================================
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # ================================================================
    # Read Ardour Session XML
    # ================================================================
    session_file_path = result.get('session_file_path', '/home/ga/Audio/sessions/MyProject/MyProject.ardour')
    temp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.ardour')
    try:
        copy_from_env(session_file_path, temp_xml.name)
        tree = ET.parse(temp_xml.name)
        root = tree.getroot()
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to parse session XML: {e}"}
    finally:
        if os.path.exists(temp_xml.name):
            os.unlink(temp_xml.name)

    routes = parse_routes(root)
    feedback_parts.append(f"Found {len(routes)} audio routes")

    # ============================================================
    # 1. Track names (20 pts — 5 per track)
    # ============================================================
    track_score = 0
    matched_routes = {} 

    for track_key in expected_tracks:
        found = False
        for route in routes:
            rname = route.get("name", "")
            if match_track(rname, track_key):
                matched_routes[track_key] = route
                track_score += 5
                found = True
                break
        if not found:
            non_default = [r for r in routes if r.get("name", "").lower() not in ("audio 1", "audio 2", "audio 3") and r not in matched_routes.values()]
            if non_default:
                matched_routes[track_key] = non_default[0]
                track_score += 2  # Partial
                feedback_parts.append(f"Track '{track_key}' missing (partial credit via unmatched track)")
            else:
                feedback_parts.append(f"Track '{track_key}' missing")

    total_score += track_score

    # ============================================================
    # 2. Pan positions (25 pts)
    # ============================================================
    pan_score = 0
    for track_key, (pan_min, pan_max) in pan_specs.items():
        route = matched_routes.get(track_key)
        if route is None: continue
        
        pan_val = get_pan_azimuth(route)
        if pan_val is None: continue

        if pan_min <= pan_val <= pan_max:
            pan_score += 6.25
        elif abs(pan_val - 0.5) > 0.05 and track_key in ("alice", "bob"):
            pan_score += 3.0 # Partial: moved but not fully

    pan_score = min(25, int(pan_score))
    total_score += pan_score

    # ============================================================
    # 3. Gain levels (20 pts — 5 per track)
    # ============================================================
    gain_score = 0
    for track_key, (db_min, db_max) in gain_specs.items():
        route = matched_routes.get(track_key)
        if route is None: continue

        gain_linear = get_controllable_value(route, "gaincontrol")
        if gain_linear is None:
            gain_linear = get_controllable_value(route, "gain")
        if gain_linear is None: continue

        gain_db = linear_to_db(gain_linear)

        if db_min <= gain_db <= db_max:
            gain_score += 5
        elif abs(gain_db - 0.0) > 0.5:
            gain_score += 2 # Partial for changing it from 0

    total_score += gain_score

    # ============================================================
    # 4. Mute state (10 pts)
    # ============================================================
    mute_score = 0
    room_route = matched_routes.get("room_tone")
    if room_route is not None:
        mute_val = get_controllable_value(room_route, "mute")
        room_muted = (mute_val is not None and mute_val > 0)
        
        others_muted = False
        for tk in ["narrator", "alice", "bob"]:
            other_r = matched_routes.get(tk)
            if other_r is not None:
                om = get_controllable_value(other_r, "mute")
                if om is not None and om > 0:
                    others_muted = True

        if room_muted and not others_muted:
            mute_score = 10
        elif room_muted:
            mute_score = 5 # Others were muted too

    total_score += mute_score

    # ============================================================
    # 5. Scene markers (10 pts)
    # ============================================================
    marker_score = 0
    marker_count = 0
    locations = root.find("Locations")
    if locations is not None:
        for loc in locations.iter("Location"):
            flags = loc.get("flags", "")
            if any(f in flags for f in ["IsSessionRange", "IsAutoLoop", "IsAutoPunch"]):
                continue
            name = loc.get("name", "")
            if len(name.strip()) > 1:
                marker_count += 1
                
    if marker_count >= 3:
        marker_score = 10
    elif marker_count == 2:
        marker_score = 5
    elif marker_count == 1:
        marker_score = 3
        
    total_score += marker_score

    # ============================================================
    # 6. Exported WAV (15 pts) & Anti-gaming checks
    # ============================================================
    export_score = 0
    wav_found = result.get('wav_found', False)
    wav_size = result.get('wav_size_bytes', 0)
    created_during = result.get('file_created_during_task', False)
    wav_path = result.get('wav_path', '')

    if wav_found and wav_size >= 1024:
        if "radio_drama_mix" in wav_path:
            export_score = 15
        else:
            export_score = 10 # Fallback dir

        if not created_during:
            feedback_parts.append("WARNING: WAV file predates task start")
            export_score = max(0, export_score - 5)

    total_score += export_score

    # Region presence check (anti-gaming to make sure tracks have audio)
    routes_with_regions = 0
    for route in matched_routes.values():
        if has_regions(route, root):
            routes_with_regions += 1

    if routes_with_regions < 2 and total_score > 20:
        penalty = 10
        feedback_parts.append(f"PENALTY: Only {routes_with_regions} tracks have audio regions (-{penalty})")
        total_score = max(0, total_score - penalty)

    # ============================================================
    # Final Eval
    # ============================================================
    passed = total_score >= pass_threshold
    feedback_str = " | ".join(feedback_parts)
    if not feedback_str:
        feedback_str = f"Completed with score {total_score}"

    return {
        "passed": passed,
        "score": total_score,
        "feedback": feedback_str,
        "details": {
            "track_score": track_score,
            "pan_score": pan_score,
            "gain_score": gain_score,
            "mute_score": mute_score,
            "marker_score": marker_score,
            "export_score": export_score
        }
    }