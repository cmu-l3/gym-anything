#!/usr/bin/env python3
"""
Verifier for Live Stage Cue Playback Configuration task.

Checks both programmatic evidence (vlcrc edits, XSPF playlist validity) 
and VLM trajectory evidence.
"""

import json
import os
import tempfile
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_vlcrc(filepath):
    """Parse vlcrc file into a dictionary of active settings."""
    settings = {}
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith('#') or line.startswith('['):
                    continue
                if '=' in line:
                    key, val = line.split('=', 1)
                    settings[key.strip()] = val.strip()
    except Exception as e:
        logger.error(f"Failed to parse vlcrc: {e}")
    return settings

def strip_namespaces(elem):
    """Strip XML namespaces for easier node finding."""
    if '}' in elem.tag:
        elem.tag = elem.tag.split('}', 1)[1]
    for child in elem:
        strip_namespaces(child)
    return elem

def parse_xspf(filepath):
    """Parse XSPF playlist and extract tracks and options."""
    tracks_info = []
    try:
        tree = ET.parse(filepath)
        root = tree.getroot()
        root = strip_namespaces(root)
        
        track_nodes = root.findall('.//track')
        for t in track_nodes:
            track = {'location': '', 'options': []}
            loc = t.find('location')
            if loc is not None and loc.text:
                track['location'] = loc.text
            
            ext = t.find('extension')
            if ext is not None:
                opts = ext.findall('.//option')
                for opt in opts:
                    if opt.text:
                        track['options'].append(opt.text.strip())
            
            tracks_info.append(track)
    except Exception as e:
        logger.error(f"Failed to parse XSPF: {e}")
    return tracks_info

def is_truthy(val):
    return str(val).lower() in ('1', 'true', 'yes')

def is_falsy(val):
    return str(val).lower() in ('0', 'false', 'no')

def verify_live_stage_cue_playback_configuration(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    
    # -------------------------------------------------------------------------
    # 1. Retrieve the Task Export JSON
    # -------------------------------------------------------------------------
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    task_start = result.get('task_start', 0)
    
    # -------------------------------------------------------------------------
    # 2. Evaluate VLCRC configuration
    # -------------------------------------------------------------------------
    vlcrc_settings = {}
    if result.get('vlcrc_exists', False):
        temp_vlcrc = tempfile.NamedTemporaryFile(delete=False, suffix='.conf')
        try:
            copy_from_env("/tmp/vlcrc_export", temp_vlcrc.name)
            vlcrc_settings = parse_vlcrc(temp_vlcrc.name)
        except Exception:
            feedback_parts.append("Warning: Could not extract vlcrc.")
        finally:
            if os.path.exists(temp_vlcrc.name):
                os.unlink(temp_vlcrc.name)

    # Check preferences
    if is_truthy(vlcrc_settings.get('fullscreen')):
        score += 10
        feedback_parts.append("Fullscreen enabled (+10)")
    else:
        feedback_parts.append("Fullscreen not enforced")

    title_suppressed = False
    if is_falsy(vlcrc_settings.get('video-title-show')):
        score += 15
        title_suppressed = True
        feedback_parts.append("Video Title suppressed (+15)")
    else:
        feedback_parts.append("Video Title NOT suppressed (CRITICAL)")

    if is_falsy(vlcrc_settings.get('osd')):
        score += 10
        feedback_parts.append("OSD disabled (+10)")
    else:
        feedback_parts.append("OSD not disabled")

    play_and_stop_global = is_truthy(vlcrc_settings.get('play-and-stop'))

    # -------------------------------------------------------------------------
    # 3. Evaluate XSPF Playlist
    # -------------------------------------------------------------------------
    tracks = []
    playlist_valid = False
    if result.get('playlist_exists', False):
        if result.get('playlist_mtime', 0) > task_start:
            temp_xspf = tempfile.NamedTemporaryFile(delete=False, suffix='.xspf')
            try:
                copy_from_env("/tmp/show_cues_export.xspf", temp_xspf.name)
                tracks = parse_xspf(temp_xspf.name)
                if len(tracks) > 0:
                    playlist_valid = True
                    score += 10
                    feedback_parts.append("Valid XSPF playlist created (+10)")
            except Exception:
                feedback_parts.append("Warning: Could not extract XSPF.")
            finally:
                if os.path.exists(temp_xspf.name):
                    os.unlink(temp_xspf.name)
        else:
            feedback_parts.append("Playlist file is older than task start (Invalid).")
    else:
        feedback_parts.append("Playlist file not found (CRITICAL)")

    # Check Playlist Order
    order_correct = False
    if playlist_valid and len(tracks) == 4:
        # Check order: storm -> thunder -> ariel -> ambient
        t1 = 'cue_01' in tracks[0]['location']
        t2 = 'cue_02' in tracks[1]['location']
        t3 = 'cue_03' in tracks[2]['location']
        t4 = 'cue_04' in tracks[3]['location']
        
        if t1 and t2 and t3 and t4:
            score += 10
            order_correct = True
            feedback_parts.append("Playlist track order correct (+10)")
        else:
            feedback_parts.append("Playlist track order incorrect")
    elif playlist_valid:
        feedback_parts.append(f"Playlist has {len(tracks)} tracks, expected exactly 4.")

    # Check Cue 3 Start Time
    if playlist_valid and len(tracks) >= 3:
        # If order is wrong, find cue_03. If order is right, it's index 2.
        t3 = tracks[2] if order_correct else next((t for t in tracks if 'cue_03' in t['location']), None)
        
        if t3:
            has_start_time = any('start-time=15' in opt.replace(' ', '') for opt in t3['options'])
            if has_start_time:
                score += 15
                feedback_parts.append("Cue 03 start-time correctly applied (+15)")
            else:
                feedback_parts.append("Cue 03 start-time option missing")

    # Evaluate Play-and-Stop Behavior (Global or Local)
    play_and_stop_local = False
    if playlist_valid:
        # See if every track has play-and-stop applied locally
        all_tracks_have_it = True
        for t in tracks:
            if not any('play-and-stop' in opt for opt in t['options']):
                all_tracks_have_it = False
                break
        play_and_stop_local = len(tracks) > 0 and all_tracks_have_it

    if play_and_stop_global or play_and_stop_local:
        score += 10
        feedback_parts.append("Play-and-stop behavior enabled (+10)")
    else:
        feedback_parts.append("Play-and-stop behavior missing")

    # -------------------------------------------------------------------------
    # 4. VLM Trajectory Verification
    # -------------------------------------------------------------------------
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        prompt = """You are analyzing a sequence of screenshots of an agent configuring VLC Media Player.
        For a live show configuration task, the agent should:
        1. Open VLC's Advanced Preferences window OR a text editor (to edit vlcrc).
        2. Interact with playlist or media save dialogs.
        
        Assess the frames and answer:
        1. CONFIGURATION_UI_SEEN: Is the VLC Preferences window (especially Advanced preferences) or a text editor showing VLC config visible in any frame?
        2. PLAYLIST_UI_SEEN: Is the Playlist interface or a "Save Playlist" dialog visible in any frame?
        
        Respond ONLY with a valid JSON:
        {
            "configuration_ui_seen": true/false,
            "playlist_ui_seen": true/false
        }
        """
        try:
            vlm_res = query_vlm(prompt=prompt, images=frames)
            if vlm_res and vlm_res.get("success"):
                vlm_data = vlm_res.get("parsed", {})
                
                if vlm_data.get("configuration_ui_seen", False):
                    score += 10
                    feedback_parts.append("VLM verified config interaction (+10)")
                if vlm_data.get("playlist_ui_seen", False):
                    score += 10
                    feedback_parts.append("VLM verified playlist interaction (+10)")
        except Exception as e:
            logger.warning(f"VLM verification error: {e}")
            feedback_parts.append("VLM evaluation failed (No penalty)")
            # Grace score if VLM completely fails but programmatic is perfect
            if score == 80: 
                score += 20
    else:
        feedback_parts.append("No trajectory frames for VLM")

    # -------------------------------------------------------------------------
    # 5. Final Scoring
    # -------------------------------------------------------------------------
    # Critical pass criteria
    key_criteria_met = title_suppressed and playlist_valid
    passed = (score >= 70) and key_criteria_met
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }