#!/usr/bin/env python3
"""
Verifier for ATC Radio Communications Preprocessing task.

Evaluates:
1. File existence and strict MP3 formatting (Mono, 16kHz).
2. Channel separation (Tower vs Ground duration mismatch proves true split).
3. Silence removal (Significant duration reduction from 900s).
4. Waveform generation.
5. VLC XSPF Playlist authoring.
6. JSON report generation.
"""

import json
import os
import tempfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_atc_preprocessing(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0.0
    max_score = 100.0
    feedback = []
    
    # Ground truth approximations based on setup generation
    ORIGINAL_DURATION = 900.0
    EXPECTED_TOWER_DUR = 180.0
    EXPECTED_GROUND_DUR = 100.0
    DURATION_TOLERANCE = 15.0 # Give padding for silence removal thresholds
    
    temp_dir = tempfile.mkdtemp(prefix='atc_verify_')
    
    # Files to copy
    files_to_check = {
        'tower_info': 'tower_clean.mp3_info.json',
        'ground_info': 'ground_clean.mp3_info.json',
        'tower_png': 'tower_waveform.png',
        'ground_png': 'ground_waveform.png',
        'playlist': 'atc_review_playlist.xspf',
        'report': 'processing_report.json'
    }
    
    local_paths = {}
    for key, filename in files_to_check.items():
        local_path = os.path.join(temp_dir, filename)
        try:
            copy_from_env(f"/tmp/atc_export/{filename}", local_path)
            if os.path.exists(local_path) and os.path.getsize(local_path) > 0:
                local_paths[key] = local_path
        except Exception as e:
            logger.warning(f"Failed to copy {filename}: {e}")

    # ================================================================
    # 1. Format Compliance (20 points: 10 per file)
    # ================================================================
    tower_dur, ground_dur = 0.0, 0.0
    
    for prefix, info_key in [("Tower", "tower_info"), ("Ground", "ground_info")]:
        if info_key in local_paths:
            try:
                with open(local_paths[info_key], 'r') as f:
                    data = json.load(f)
                
                # Check stream info
                streams = data.get('streams', [])
                if streams:
                    s = streams[0]
                    codec = s.get('codec_name', '')
                    channels = s.get('channels', 0)
                    sr = s.get('sample_rate', '0')
                    
                    # Duration from format
                    fmt = data.get('format', {})
                    dur = float(fmt.get('duration', 0.0))
                    
                    if prefix == "Tower":
                        tower_dur = dur
                    else:
                        ground_dur = dur
                    
                    # Score format
                    if codec == 'mp3' and channels == 1 and int(sr) == 16000:
                        score += 10.0
                        feedback.append(f"+ {prefix} audio: Correct format (MP3, Mono, 16kHz)")
                    else:
                        feedback.append(f"x {prefix} audio: Incorrect format (Codec:{codec}, Channels:{channels}, SR:{sr})")
            except Exception as e:
                feedback.append(f"x {prefix} audio info parsing failed.")
        else:
            feedback.append(f"x {prefix} audio: MP3 not found.")

    # ================================================================
    # 2. Channel Separation (15 points)
    # If the agent just downmixed stereo->mono without splitting L/R,
    # the durations would be identical (and likely match the max active time).
    # True splitting yields ~180s for Tower and ~100s for Ground.
    # ================================================================
    if tower_dur > 0 and ground_dur > 0:
        duration_diff = abs(tower_dur - ground_dur)
        if duration_diff > 30.0:
            score += 15.0
            feedback.append(f"+ Channel Separation: Valid (Tower {tower_dur:.1f}s, Ground {ground_dur:.1f}s)")
        else:
            feedback.append(f"x Channel Separation: Failed. Durations too similar (diff: {duration_diff:.1f}s), suggests downmix rather than L/R split.")
    else:
        feedback.append("x Channel Separation: Cannot verify (missing/invalid audio).")

    # ================================================================
    # 3. Silence Removal (25 points)
    # Both files must be significantly shorter than 900s.
    # We expect roughly 180s and 100s.
    # ================================================================
    silence_removed = False
    if 30 < tower_dur < 300 and 30 < ground_dur < 300:
        score += 25.0
        silence_removed = True
        feedback.append("+ Silence Removal: Both files successfully condensed (< 300s).")
    elif tower_dur > 0 or ground_dur > 0:
        feedback.append(f"x Silence Removal: Failed or incomplete. (Tower {tower_dur:.1f}s, Ground {ground_dur:.1f}s)")
    
    # ================================================================
    # 4. Waveform Generation (15 points: 7.5 per image)
    # ================================================================
    for prefix, png_key in [("Tower", "tower_png"), ("Ground", "ground_png")]:
        if png_key in local_paths:
            size_kb = os.path.getsize(local_paths[png_key]) / 1024.0
            if size_kb > 10.0:
                score += 7.5
                feedback.append(f"+ {prefix} Waveform: Valid image generated ({size_kb:.1f}KB)")
            else:
                feedback.append(f"x {prefix} Waveform: Image too small ({size_kb:.1f}KB)")
        else:
            feedback.append(f"x {prefix} Waveform: PNG not found.")

    # ================================================================
    # 5. Review Playlist XSPF (15 points)
    # ================================================================
    if 'playlist' in local_paths:
        try:
            tree = ET.parse(local_paths['playlist'])
            root = tree.getroot()
            
            # XSPF uses namespaces
            ns = {'xspf': 'http://xspf.org/ns/0/'}
            # Fallback if no namespace is used (improper but possible)
            ns_empty = {'xspf': ''} 
            
            tracks = root.findall('.//xspf:track', ns)
            if not tracks:
                tracks = root.findall('.//track') # Try without namespace
                
            if len(tracks) >= 2:
                titles = []
                for t in tracks:
                    title_elem = t.find('xspf:title', ns)
                    if title_elem is None:
                        title_elem = t.find('title')
                    if title_elem is not None and title_elem.text:
                        titles.append(title_elem.text.strip())
                
                if "Tower Comms (Cleaned)" in titles and "Ground Comms (Cleaned)" in titles:
                    score += 15.0
                    feedback.append("+ XSPF Playlist: Valid with correct display titles.")
                else:
                    score += 7.5
                    feedback.append(f"~ XSPF Playlist: Found 2+ tracks but missing required titles (Found: {titles}).")
            else:
                feedback.append(f"x XSPF Playlist: Contains fewer than 2 tracks.")
        except Exception as e:
            feedback.append(f"x XSPF Playlist: Invalid XML format ({e}).")
    else:
        feedback.append("x XSPF Playlist: File not found.")

    # ================================================================
    # 6. Processing Report (10 points)
    # ================================================================
    if 'report' in local_paths:
        try:
            with open(local_paths['report'], 'r') as f:
                report = json.load(f)
            
            req_keys = ["original_duration_sec", "tower_final_duration_sec", "ground_final_duration_sec"]
            if all(k in report for k in req_keys):
                score += 10.0
                feedback.append("+ Processing Report: Valid JSON with required keys.")
            else:
                score += 5.0
                feedback.append("~ Processing Report: Missing some required keys.")
        except Exception as e:
            feedback.append("x Processing Report: Invalid JSON format.")
    else:
        feedback.append("x Processing Report: File not found.")

    # ================================================================
    # Final Result
    # ================================================================
    # Key criteria: Must have separated the channels and removed silence
    key_criteria_met = (tower_dur > 0 and ground_dur > 0 and 
                        abs(tower_dur - ground_dur) > 30 and 
                        silence_removed)
    
    passed = (score >= 75.0) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }