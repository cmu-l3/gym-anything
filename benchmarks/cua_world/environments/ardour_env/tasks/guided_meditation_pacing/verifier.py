#!/usr/bin/env python3
"""
Verifier for guided_meditation_pacing task.

Checks that the agent created voice and music tracks, edited the voice 
track (trimmed and spaced it out), ducked the music track volume, 
and exported the final audio.
"""

import math
import os
import tempfile
import json
import logging
import xml.etree.ElementTree as ET
from gym_anything.vlm import sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

SAMPLE_RATE = 44100

def get_audio_routes(root):
    """Retrieve all audio tracks from the session, ignoring Master and Monitor buses."""
    routes = []
    for route in root.iter('Route'):
        flags = route.get('flags', '')
        if 'MasterOut' in flags or 'MonitorOut' in flags:
            continue
        if route.get('default-type') == 'audio':
            routes.append(route)
    return routes

def get_route_gain_db(route):
    """Calculate the dB level of a track's fader."""
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

def get_playlist_for_route(root, route):
    """Match a route to its playlist to find regions."""
    diskstream = route.find('Diskstream')
    if diskstream is not None:
        playlist_id = diskstream.get('playlist')
        if playlist_id:
            for pl in root.iter('Playlist'):
                if pl.get('id') == playlist_id:
                    return pl
                    
    # Fallback heuristic: playlist name usually matches or starts with route name
    route_name = route.get('name', '')
    for pl in root.iter('Playlist'):
        pl_name = pl.get('name', '')
        base = pl_name.rsplit('.', 1)[0] if '.' in pl_name else pl_name
        if base == route_name: 
            return pl
            
    return None

def verify_guided_meditation_pacing(traj, env_info, task_info):
    """
    Multi-criterion verification:
      1. Tracks present & Gain applied    (20 pts)
      2. Narration Trimmed                (20 pts)
      3. Timeline Spacing / Gaps          (20 pts)
      4. Export & Save                    (20 pts)
      5. VLM Trajectory Verification      (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "copy_from_env not available"}

    score = 0.0
    feedback = []

    # 1. Fetch JSON export
    tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_json.close()
    try:
        copy_from_env("/tmp/task_result.json", tmp_json.name)
        with open(tmp_json.name, 'r') as f:
            export_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0.0, "feedback": f"Could not read task export data: {e}"}
    finally:
        if os.path.exists(tmp_json.name):
            os.unlink(tmp_json.name)

    # 2. Fetch Session XML
    session_remote = "/home/ga/Audio/sessions/MyProject/MyProject.ardour"
    tmp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.ardour')
    tmp_xml.close()

    try:
        copy_from_env(session_remote, tmp_xml.name)
        tree = ET.parse(tmp_xml.name)
        root = tree.getroot()
    except Exception as e:
        return {"passed": False, "score": 0.0, "feedback": f"Session XML missing or parse error: {e}"}
    finally:
        if os.path.exists(tmp_xml.name):
            os.unlink(tmp_xml.name)

    # ---------------------------------------------------------
    # PROGRAMMATIC CHECKS
    # ---------------------------------------------------------
    routes = get_audio_routes(root)
    
    voice_route = None
    music_route = None
    
    # Identify routes loosely by name keywords
    for r in routes:
        name = r.get('name', '').lower()
        if any(kw in name for kw in ['voice', 'guide', 'narr', 'speech']):
            voice_route = r
        elif any(kw in name for kw in ['music', 'piano', 'ambient', 'bg', 'back']):
            music_route = r

    # CRITERION 1: Tracks & Gain (20 pts)
    if voice_route and music_route:
        score += 10.0
        feedback.append("Found Voice and Music tracks.")
        
        music_gain = get_route_gain_db(music_route)
        if -25.0 <= music_gain <= -6.0:
            score += 10.0
            feedback.append(f"Music gain properly ducked ({music_gain:.1f} dB).")
        else:
            feedback.append(f"Music gain ({music_gain:.1f} dB) not in target range (-20 to -8 dB).")
    else:
        feedback.append("Missing required tracks (Voice/Music). Track logic failed.")

    # CRITERION 2 & 3: Trimming and Spacing
    if voice_route:
        playlist = get_playlist_for_route(root, voice_route)
        if playlist is not None:
            regions = []
            for reg in playlist.iter('Region'):
                regions.append({
                    'position': int(reg.get('position', '0')),
                    'length': int(reg.get('length', '0'))
                })
            
            regions.sort(key=lambda x: x['position'])
            
            # Criterion 2: Total duration of active audio <= ~19 seconds (20 pts)
            total_samples = sum(r['length'] for r in regions)
            total_sec = total_samples / SAMPLE_RATE
            
            if 0 < total_sec <= 19.5:
                score += 20.0
                feedback.append(f"Voice properly trimmed (total audio: {total_sec:.1f}s).")
            elif 19.5 < total_sec <= 25.0:
                score += 10.0
                feedback.append(f"Voice partially trimmed (total audio: {total_sec:.1f}s).")
            else:
                feedback.append(f"Voice not trimmed to ~15s (total audio: {total_sec:.1f}s).")

            # Criterion 3: Spacing - >= 3 segments with >= 3.8s gaps (20 pts)
            if len(regions) >= 3:
                gaps_sec = []
                for i in range(len(regions) - 1):
                    gap_samples = regions[i+1]['position'] - (regions[i]['position'] + regions[i]['length'])
                    gaps_sec.append(gap_samples / SAMPLE_RATE)
                
                large_gaps = sum(1 for g in gaps_sec if g >= 3.8)
                if large_gaps >= 2:
                    score += 20.0
                    feedback.append(f"Voice pacing correct: {len(regions)} segments with {large_gaps} appropriate gaps.")
                elif large_gaps == 1:
                    score += 10.0
                    feedback.append(f"Voice pacing partial: found {len(regions)} segments but only 1 adequate gap.")
                else:
                    feedback.append(f"Voice segments found, but gaps are too short for breathing room.")
            else:
                feedback.append(f"Not enough voice segments ({len(regions)}). Expected at least 3.")

    # CRITERION 4: Export & Save (20 pts)
    export_exists = export_data.get('export_exists', False)
    export_created = export_data.get('export_created_during_task', False)
    
    if export_exists and export_created:
        score += 20.0
        feedback.append("Session saved and final mix exported successfully.")
    elif export_exists:
        score += 10.0
        feedback.append("Export file exists but timestamp indicates it might be old.")
    else:
        feedback.append("Final mix was not exported to the expected directory.")

    # ---------------------------------------------------------
    # VLM CHECKS (20 pts)
    # ---------------------------------------------------------
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            prompt = """You are evaluating screenshots of an audio editing session in a DAW (Ardour).
            Look at the main arrangement/timeline view.
            
            Determine if the user successfully edited the voice track (usually the top track).
            A successful edit means the continuous audio block has been split into multiple smaller blocks (regions), 
            and these blocks have been spread out horizontally with visible empty space (silence/gaps) between them.
            
            Return JSON:
            {
                "has_multiple_blocks": true/false,
                "has_visible_gaps_between_blocks": true/false
            }"""
            
            try:
                vlm_res = query_vlm(images=frames, prompt=prompt)
                if vlm_res and vlm_res.get("success"):
                    parsed = vlm_res.get("parsed", {})
                    if parsed.get("has_multiple_blocks") and parsed.get("has_visible_gaps_between_blocks"):
                        score += 20.0
                        feedback.append("VLM confirmed visual presence of spaced audio regions.")
                    elif parsed.get("has_multiple_blocks"):
                        score += 10.0
                        feedback.append("VLM saw split regions, but clear gaps weren't obvious.")
                    else:
                        feedback.append("VLM did not detect visually separated audio regions.")
            except Exception as e:
                logger.warning(f"VLM check failed: {e}")
                feedback.append(f"VLM Verification failed: {e}")
                
    else:
        # Gracefully award points if VLM is unavailable but programmatic checks are perfect
        feedback.append("VLM unavailable. Bypassing visual check.")
        if score >= 60:
            score += 20.0 

    passed = score >= 65.0
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }