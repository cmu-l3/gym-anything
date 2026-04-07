#!/usr/bin/env python3
"""
Verifier for call_and_response_assembly task.
Occupation: Instructional Designer / Audio Editor
Industry: Ed-Tech

Checks that the agent imported the files, sliced the voice track, spaced the phrases,
ducked the music bed, added pedagogical markers, and exported the exercise.
"""

import math
import os
import json
import tempfile
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

PASS_THRESHOLD = 65.0
SAMPLE_RATE = 44100

# Tolerance for region and marker placement: 0.5 seconds
TOLERANCE_SAMPLES = int(SAMPLE_RATE * 0.5) 


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

def get_regions_for_route(root, route_name):
    """Find all regions on the playlist corresponding to a route."""
    regions = []
    for playlist in root.iter('Playlist'):
        pl_name = playlist.get('name', '')
        # Ardour typically names playlists matching the track, e.g., "Voice.1"
        base = pl_name.rsplit('.', 1)[0] if '.' in pl_name else pl_name
        if base.lower() == route_name.lower() or pl_name.lower().startswith(route_name.lower()):
            for region in playlist.iter('Region'):
                regions.append({
                    'name': region.get('name', ''),
                    'position': int(region.get('position', '0')),
                    'length': int(region.get('length', '0')),
                })
    return regions

def get_route_gain_db(route):
    """Get the gain parameter of a route in decibels."""
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

def get_markers(root):
    markers = []
    for loc in root.iter('Location'):
        flags = loc.get('flags', '')
        # Ignore system loop/punch ranges
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

def verify_call_and_response_assembly(traj, env_info, task_info):
    """
    Multi-criterion verifier for the listen-and-repeat assembly task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "copy_from_env not available"}

    score = 0.0
    feedback = []
    max_score = 100.0

    # 1. Parse JSON Result from export_result.sh
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0.0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Parse Ardour XML Session
    session_remote = "/home/ga/Audio/sessions/MyProject/MyProject.ardour"
    tmp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.ardour')
    tmp_xml.close()

    try:
        copy_from_env(session_remote, tmp_xml.name)
    except Exception as e:
        return {"passed": False, "score": 0.0, "feedback": f"Session XML not accessible: {e}"}

    if not os.path.exists(tmp_xml.name) or os.path.getsize(tmp_xml.name) == 0:
        return {"passed": False, "score": 0.0, "feedback": "Session XML is empty or missing"}

    try:
        tree = ET.parse(tmp_xml.name)
        root = tree.getroot()
    except Exception as e:
        os.unlink(tmp_xml.name)
        return {"passed": False, "score": 0.0, "feedback": f"Session XML parse error: {e}"}

    # ================================================================
    # Track Identification
    # ================================================================
    audio_routes = get_audio_routes(root)
    voice_route = None
    music_route = None

    for r in audio_routes:
        rname = r.get('name', '').lower()
        if 'voice' in rname or 'speech' in rname or 'narration' in rname:
            voice_route = r
        elif 'music' in rname or 'bed' in rname:
            music_route = r

    # Fallback to checking region counts if renaming failed
    if not voice_route or not music_route:
        for r in audio_routes:
            regs = get_regions_for_route(root, r.get('name', ''))
            if len(regs) >= 2 and not voice_route:
                voice_route = r
            elif len(regs) == 1 and not music_route:
                music_route = r

    # CRITERION 1: Track Renaming (10 points)
    if voice_route and 'voice' in voice_route.get('name', '').lower():
        score += 5.0
        feedback.append("Voice track named correctly")
    if music_route and 'music' in music_route.get('name', '').lower():
        score += 5.0
        feedback.append("MusicBed track named correctly")

    # ================================================================
    # Voice Region Slicing and Spacing
    # ================================================================
    if voice_route:
        voice_regions = get_regions_for_route(root, voice_route.get('name', ''))
        # Sort chronologically
        voice_regions.sort(key=lambda x: x['position'])
        
        # CRITERION 2: Phrase 1 & Cut (10 points)
        # Expecting at least 1 region starting near 0s
        if len(voice_regions) > 0 and abs(voice_regions[0]['position'] - 0) <= TOLERANCE_SAMPLES:
            score += 10.0
            feedback.append("Phrase 1 placed correctly near 0s")
        
        # CRITERION 3: Phrase 2 Spacing (20 points)
        # Expecting a region starting near 10.0s (441000 samples)
        if len(voice_regions) >= 2 and abs(voice_regions[1]['position'] - 441000) <= TOLERANCE_SAMPLES:
            score += 20.0
            feedback.append("Phrase 2 spaced correctly near 10s")
            
        # CRITERION 4: Phrase 3 Spacing (20 points)
        # Expecting a region starting near 20.0s (882000 samples)
        if len(voice_regions) >= 3 and abs(voice_regions[2]['position'] - 882000) <= TOLERANCE_SAMPLES:
            score += 20.0
            feedback.append("Phrase 3 spaced correctly near 20s")
        
        if len(voice_regions) < 3:
            feedback.append(f"Expected 3 voice phrases, found {len(voice_regions)}. Spacing may be incomplete.")
    else:
        feedback.append("Voice track not found, skipping spacing verification.")

    # ================================================================
    # CRITERION 5: Music Gain Attenuation (15 points)
    # Target: -15 dB (Range: -18 to -10)
    # ================================================================
    if music_route:
        music_gain = get_route_gain_db(music_route)
        if -18.5 <= music_gain <= -9.5:
            score += 15.0
            feedback.append(f"Music gain correctly attenuated to ~{music_gain:.1f} dB")
        elif -24.0 <= music_gain <= -4.0:
            score += 8.0
            feedback.append(f"Music gain adjusted to {music_gain:.1f} dB, but outside ideal -18 to -10 range")
        else:
            feedback.append(f"Music gain not properly attenuated ({music_gain:.1f} dB)")
    else:
        feedback.append("Music track not found, skipping gain check")

    # ================================================================
    # CRITERION 6: Pedagogical Markers (10 points)
    # ================================================================
    markers = get_markers(root)
    m1_found = False
    m2_found = False

    for m in markers:
        # Check near 5s (220500)
        if abs(m['start'] - 220500) <= TOLERANCE_SAMPLES and 'repeat' in m['name'].lower():
            m1_found = True
        # Check near 15s (661500)
        elif abs(m['start'] - 661500) <= TOLERANCE_SAMPLES and 'repeat' in m['name'].lower():
            m2_found = True

    if m1_found and m2_found:
        score += 10.0
        feedback.append("Both repetition markers placed correctly")
    elif m1_found or m2_found:
        score += 5.0
        feedback.append("Only one repetition marker placed correctly")
    else:
        feedback.append("Repetition markers missing or misplaced")

    # ================================================================
    # CRITERION 7: Exported Exercise (15 points)
    # ================================================================
    export_exists = result.get('export_exists', False)
    export_size = result.get('export_size_bytes', 0)
    file_created_during_task = result.get('file_created_during_task', False)

    if export_exists and export_size > 1000 and file_created_during_task:
        score += 15.0
        feedback.append("Exercise exported successfully")
    elif export_exists and export_size > 1000:
        # Existed before? Suspicious, but possible timing issue in bash script
        score += 8.0
        feedback.append("Exercise export found, but timestamp check failed")
    else:
        feedback.append("Exercise WAV file not exported or invalid")

    # ================================================================
    # VLM Trajectory Verification (Anti-Gaming Check)
    # ================================================================
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        query_vlm = env_info.get('query_vlm')
        
        if query_vlm:
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            prompt = (
                "You are reviewing screenshots of a user assembling an audio exercise in Ardour DAW. "
                "Did the user actively use the interface to interact with the audio regions on the timeline? "
                "Look for evidence of splitting clips, dragging clips apart to create gaps, or adjusting track levels. "
                "Reply with a JSON containing a boolean 'interacted' and a brief 'reason'."
            )
            
            vlm_res = query_vlm(prompt=prompt, images=images)
            if vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if not parsed.get("interacted", True):
                    feedback.append("VLM FLAG: Trajectory does not show active editing.")
                    # Penalty for non-interaction but don't automatically fail if XML is perfect
                    score = max(0, score - 20)
    except Exception as e:
        logger.warning(f"VLM verification skipped/failed: {e}")

    # Determine final pass/fail
    passed = score >= PASS_THRESHOLD

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }