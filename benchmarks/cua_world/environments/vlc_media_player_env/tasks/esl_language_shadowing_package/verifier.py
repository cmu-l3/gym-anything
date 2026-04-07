#!/usr/bin/env python3
"""
Verifier for ESL Language Shadowing Package task.

VERIFICATION STRATEGY:
1. File Existence & Format (10 points): Checks if the 5 MP3 files exist and are audio-only MP3s.
2. Time-Stretching Accuracy (50 points): Evaluates the duration of each output file to confirm 
   it exactly matches the 80% speed expansion factor:
   - Phrase 1 (4s -> 5.0s) = 10 pts
   - Phrase 2 (5s -> 6.25s) = 10 pts
   - Phrase 3 (6s -> 7.5s) = 10 pts
   - Phrase 4 (8s -> 10.0s) = 10 pts
   - Phrase 5 (3s -> 3.75s) = 10 pts
3. Playlist Existence (10 points): Checks if the shadowing_practice.m3u file was created.
4. Playlist Interleaving (30 points): Parses the M3U to ensure exact alternating sequence 
   between the phrases and the 3-second silence track.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_esl_language_shadowing_package(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_files = metadata.get('expected_files', [])
    expected_durations = metadata.get('expected_durations', {})
    tolerance = metadata.get('duration_tolerance', 0.4)
    silence_track_name = metadata.get('silence_track_name', "silence_3s.mp3")

    feedback_parts = []
    score = 0
    
    # 1. Retrieve the exported JSON from the environment
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    files_data = result.get('files', {})
    
    # 2. Evaluate File Existence & Formats (10 points, 2 pts per file)
    valid_files_count = 0
    for fname in expected_files:
        fdata = files_data.get(fname, {})
        if fdata.get('exists', False):
            codec = fdata.get('codec', '').lower()
            if codec == 'mp3' or codec == 'mp3float':
                valid_files_count += 1
            else:
                feedback_parts.append(f"{fname} uses wrong codec ({codec})")
        else:
            feedback_parts.append(f"{fname} missing")
            
    format_score = (valid_files_count / len(expected_files)) * 10
    score += format_score
    if valid_files_count == len(expected_files):
        feedback_parts.append("All 5 audio files created as MP3s (+10)")

    # 3. Evaluate Time-Stretching (50 points, 10 pts per file)
    correct_durations_count = 0
    for fname, expected_dur in expected_durations.items():
        fdata = files_data.get(fname, {})
        if fdata.get('exists', False):
            actual_dur = fdata.get('duration', 0)
            diff = abs(actual_dur - expected_dur)
            if diff <= tolerance:
                score += 10
                correct_durations_count += 1
                feedback_parts.append(f"{fname} duration {actual_dur:.2f}s matches expected {expected_dur}s (+10)")
            else:
                feedback_parts.append(f"{fname} duration {actual_dur:.2f}s incorrect (expected {expected_dur}s)")
                
    if correct_durations_count == 0 and valid_files_count > 0:
        feedback_parts.append("Warning: Audio extracted but speed not adjusted to 80%")

    # 4. Evaluate Playlist Existence (10 points)
    playlist_exists = result.get('playlist_exists', False)
    if playlist_exists:
        score += 10
        feedback_parts.append("Playlist shadowing_practice.m3u exists (+10)")
    else:
        feedback_parts.append("Playlist missing")

    # 5. Evaluate Playlist Interleaving (30 points)
    playlist_content = result.get('playlist_content', [])
    if playlist_exists and playlist_content:
        # We expect exactly 10 media entries in the playlist
        if len(playlist_content) == 10:
            phrases = playlist_content[0::2]   # Items 0, 2, 4, 6, 8
            silences = playlist_content[1::2]  # Items 1, 3, 5, 7, 9
            
            # Check phrases sequence
            phrases_correct = 0
            for i, p in enumerate(phrases):
                expected_phrase = f"phrase_0{i+1}.mp3"
                if expected_phrase.lower() in p.lower():
                    phrases_correct += 1
                    
            # Check silences
            silences_correct = 0
            for s in silences:
                if silence_track_name.lower() in s.lower():
                    silences_correct += 1
            
            # Award points proportionally
            phrases_score = (phrases_correct / 5) * 15
            silences_score = (silences_correct / 5) * 15
            score += phrases_score + silences_score
            
            if phrases_correct == 5 and silences_correct == 5:
                feedback_parts.append("Playlist interleaving is perfect (+30)")
            else:
                feedback_parts.append(f"Playlist interleaving partial (phrases {phrases_correct}/5, silences {silences_correct}/5)")
        else:
            feedback_parts.append(f"Playlist has {len(playlist_content)} items (expected 10)")
            # Partial credit if they just dumped everything
            if any(silence_track_name.lower() in l.lower() for l in playlist_content):
                score += 5
                feedback_parts.append("Playlist contains silence track but lacks proper alternating structure (+5)")

    # 6. Final Evaluation
    # Pass requires completing the core objective: extracting audio, adjusting speed for at least some, and attempting playlist
    passed = score >= 70

    return {
        "passed": passed,
        "score": round(score, 1),
        "feedback": " | ".join(feedback_parts)
    }