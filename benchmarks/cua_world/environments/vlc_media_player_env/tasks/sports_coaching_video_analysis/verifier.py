#!/usr/bin/env python3
"""
Verifier for Sports Coaching Video Analysis task.
Scores 6 distinct sets of deliverables based on the JSON produced by export_result.sh.
"""

import os
import json
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_sports_coaching_video_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_plays = metadata.get('expected_plays', {})
    expected_slowmo = metadata.get('expected_slowmo', {})
    
    score = 0
    max_score = 46
    feedback_parts = []
    
    # 1. Copy the results from the container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            results = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported results: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    files = results.get("files", {})
    
    # helper for file checking
    def check_video(info, expected_dur, tolerance=2.0):
        if not info:
            return 0, "Not found"
        if info.get("size_bytes", 0) < 1000:
            return 0, "File empty/corrupt"
        if "video_codec" not in info:
            return 0, "Not a valid video"
            
        dur = info.get("duration", 0)
        if abs(dur - expected_dur) > tolerance:
            return 0, f"Duration {dur:.1f}s (expected {expected_dur}s)"
        return 2, f"Correct ({dur:.1f}s)"

    # --- 1. Play Clips (12 pts, 2 pts each) ---
    play_scores = []
    for i in range(1, 7):
        fname = f"play_0{i}.mp4"
        expected_dur = expected_plays.get(str(i), {}).get("duration", 20)
        pts, msg = check_video(files.get(fname), expected_dur, tolerance=2.0)
        score += pts
        if pts > 0:
            play_scores.append(f"{fname}: {msg}")
        else:
            feedback_parts.append(f"x {fname}: {msg}")
    
    if len(play_scores) == 6:
        feedback_parts.append("+ All 6 play clips correctly extracted")
    elif play_scores:
        feedback_parts.append(f"~ {len(play_scores)}/6 play clips correct")

    # --- 2. Slow-Motion Clips (12 pts, 4 pts each) ---
    slowmo_scores = []
    for i in [2, 4, 6]:
        fname = f"slowmo_0{i}.mp4"
        expected_dur = expected_slowmo.get(str(i), {}).get("duration", 40)
        # 4 pts each if it matches the 2x duration requirement
        pts, msg = check_video(files.get(fname), expected_dur, tolerance=3.0)
        if pts == 2: pts = 4 # scale to 4 pts
        
        score += pts
        if pts > 0:
            slowmo_scores.append(f"{fname}: {msg}")
        else:
            feedback_parts.append(f"x {fname}: {msg}")
            
    if len(slowmo_scores) == 3:
        feedback_parts.append("+ All 3 slow-motion clips correctly encoded")
    elif slowmo_scores:
        feedback_parts.append(f"~ {len(slowmo_scores)}/3 slow-motion clips correct")

    # --- 3. Tactical Snapshots (6 pts, 1 pt each) ---
    snap_count = 0
    for i in range(1, 7):
        fname = f"formation_0{i}.png"
        info = files.get(fname)
        if info and info.get("size_bytes", 0) >= 10240: # 10KB
            snap_count += 1
            score += 1
    if snap_count == 6:
        feedback_parts.append("+ All 6 formation snapshots valid (>10KB)")
    else:
        feedback_parts.append(f"~ {snap_count}/6 formation snapshots valid")

    # --- 4. Coach Commentary Track (6 pts) ---
    audio_info = files.get("coach_commentary.mp3")
    if audio_info and audio_info.get("size_bytes", 0) > 1000:
        score += 1
        feedback_parts.append("+ Audio file exists")
        
        dur = audio_info.get("duration", 0)
        if abs(dur - 180.0) <= 3.0:
            score += 2
            feedback_parts.append("+ Audio duration correct (~180s)")
        else:
            feedback_parts.append(f"x Audio duration incorrect ({dur:.1f}s)")
            
        channels = audio_info.get("audio_channels", 0)
        if channels == 1:
            score += 2
            feedback_parts.append("+ Audio is Mono (1 channel)")
        else:
            feedback_parts.append(f"x Audio is not Mono (Channels: {channels})")
            
        bitrate = audio_info.get("bitrate", 0)
        if bitrate >= 120000: # generous threshold around 128k
            score += 1
            feedback_parts.append("+ Audio bitrate >= 128kbps")
        else:
            feedback_parts.append(f"x Audio bitrate too low ({bitrate//1000}kbps)")
    else:
        feedback_parts.append("x Coach commentary audio missing or invalid")

    # --- 5. Highlight Playlist (4 pts) ---
    entries = results.get("playlist_entries", [])
    if files.get("highlights.m3u"):
        score += 1
        if len(entries) == 3:
            score += 1
            # Check order
            has_1 = "play_01" in entries[0]
            has_3 = "play_03" in entries[1]
            has_5 = "play_05" in entries[2]
            if has_1 and has_3 and has_5:
                score += 2
                feedback_parts.append("+ Playlist correct (Plays 1, 3, 5 in order)")
            else:
                feedback_parts.append("x Playlist entries incorrect order/content")
        else:
            feedback_parts.append(f"x Playlist has {len(entries)} entries (expected 3)")
    else:
        feedback_parts.append("x Highlight playlist missing")

    # --- 6. Analysis Manifest (6 pts) ---
    manifest = results.get("manifest_content")
    if manifest == "invalid_json":
        feedback_parts.append("x Manifest is invalid JSON")
    elif isinstance(manifest, dict):
        score += 1
        feedback_parts.append("+ Manifest is valid JSON")
        
        if "source" in manifest:
            score += 1
            
        if manifest.get("total_deliverables") == 18:
            score += 1
            
        # Inspect the array of files
        items = manifest.get("files", manifest.get("deliverables", manifest.get("items", [])))
        if not items and len(manifest.keys()) >= 18:
            # Maybe they made keys the filenames
            items = list(manifest.values())
            for k, v in manifest.items():
                if isinstance(v, dict) and "filename" not in v:
                    v["filename"] = k
        elif not items:
            # Fallback if the whole object contains the items directly without a wrapper key
            items = [v for v in manifest.values() if isinstance(v, dict) and "type" in v]
            
        if isinstance(items, list) and len(items) >= 18:
            score += 2
            feedback_parts.append("+ Manifest lists all 18 deliverables")
            
            has_props = True
            for item in items[:3]:
                if not isinstance(item, dict) or ("filename" not in item and "name" not in item) or "type" not in item:
                    has_props = False
            if has_props:
                score += 1
                feedback_parts.append("+ Manifest entries have required fields")
            else:
                feedback_parts.append("x Manifest entries missing required fields")
        else:
            feedback_parts.append("x Manifest does not list all 18 deliverables")
    else:
        feedback_parts.append("x Manifest missing or not a JSON object")

    # Determine pass/fail
    # Threshold: 26 points out of 46
    passed = score >= 26
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }