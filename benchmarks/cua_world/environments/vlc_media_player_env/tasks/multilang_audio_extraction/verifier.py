#!/usr/bin/env python3
"""
Verifier for multilang_audio_extraction task.

Verifies:
1. Audio Tracks (MP3 format, ~60s duration, specific frequency footprint).
2. Video Copies (correct stream counts and properties).
3. JSON Inventory contents.
4. Anti-gaming (Timestamps, distinct frequency separation).
5. VLM Trajectory (Process verification).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_multilang_audio_extraction(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback = []
    score = 0.0

    # Task properties
    EXPECTED_DUR = 60.0
    DUR_TOL = 4.0
    FREQ_ENG = 440
    FREQ_SPA = 660
    FREQ_FRA = 880
    FREQ_TOL = 40

    # 1. Read main verification JSON
    temp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_res.name)
        with open(temp_res.name, 'r') as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve results: {e}"}
    finally:
        if os.path.exists(temp_res.name):
            os.unlink(temp_res.name)

    start_time = data.get("task_start_time", 0.0)

    # Helper function to process audio file scoring (13 pts max per file)
    def grade_audio_file(filename, expected_freq, name_label):
        sub_score = 0
        file_data = data.get(filename, {})
        
        if not file_data.get('exists', False):
            feedback.append(f"x {name_label}: File {filename} not found.")
            return sub_score, 0

        # Check Format & Existence (4 pts)
        fmt_name = file_data.get('format', {}).get('format_name', '')
        if 'mp3' in fmt_name.lower():
            sub_score += 4
            feedback.append(f"+ {name_label}: File exists and is MP3.")
        else:
            sub_score += 2
            feedback.append(f"~ {name_label}: File exists but format is {fmt_name} (expected MP3).")

        # Check Duration (4 pts)
        dur = float(file_data.get('format', {}).get('duration', 0))
        if abs(dur - EXPECTED_DUR) <= DUR_TOL:
            sub_score += 4
            feedback.append(f"+ {name_label}: Duration correct ({dur:.1f}s).")
        else:
            feedback.append(f"x {name_label}: Duration incorrect ({dur:.1f}s).")

        # Check Frequency (5 pts)
        peak_freq = file_data.get('peak_freq', 0)
        if abs(peak_freq - expected_freq) <= FREQ_TOL:
            sub_score += 5
            feedback.append(f"+ {name_label}: Correct audio track verified via FFT ({peak_freq:.0f}Hz).")
        else:
            feedback.append(f"x {name_label}: Incorrect audio track. Peak freq {peak_freq:.0f}Hz (Expected ~{expected_freq}Hz).")

        return sub_score, peak_freq

    # Grade Audio Tracks
    score_eng, freq_eng = grade_audio_file("audio_english.mp3", FREQ_ENG, "English MP3")
    score_spa, freq_spa = grade_audio_file("audio_spanish.mp3", FREQ_SPA, "Spanish MP3")
    score_fra, freq_fra = grade_audio_file("audio_french.mp3", FREQ_FRA, "French MP3")
    score += (score_eng + score_spa + score_fra)

    # Distinct Frequencies Anti-Gaming Check (5 pts)
    # Prevents extracting the default track 3 times and renaming.
    if freq_eng > 0 and freq_spa > 0 and freq_fra > 0:
        if abs(freq_eng - freq_spa) > 100 and abs(freq_spa - freq_fra) > 100 and abs(freq_eng - freq_fra) > 100:
            score += 5
            feedback.append("+ Anti-Gaming: All 3 audio files have distinctly separate frequency signatures.")
        else:
            feedback.append("x Anti-Gaming: Audio files appear to contain duplicate tracks.")

    # Grade video_only.mp4 (11 pts)
    vo_data = data.get("video_only.mp4", {})
    if vo_data.get('exists', False):
        score += 3
        feedback.append("+ Video Only: File exists.")
        
        streams = vo_data.get('streams', [])
        v_streams = [s for s in streams if s.get('codec_type') == 'video']
        a_streams = [s for s in streams if s.get('codec_type') == 'audio']
        
        if len(v_streams) >= 1 and len(a_streams) == 0:
            score += 6
            feedback.append(f"+ Video Only: Correct streams (1 Video, 0 Audio).")
        else:
            feedback.append(f"x Video Only: Incorrect streams ({len(v_streams)} Video, {len(a_streams)} Audio).")

        dur = float(vo_data.get('format', {}).get('duration', 0))
        if abs(dur - EXPECTED_DUR) <= DUR_TOL:
            score += 2
            feedback.append(f"+ Video Only: Duration correct ({dur:.1f}s).")
    else:
        feedback.append("x Video Only: File not found.")

    # Grade english_reference.mp4 (11 pts)
    er_data = data.get("english_reference.mp4", {})
    if er_data.get('exists', False):
        score += 3
        feedback.append("+ English Ref: File exists.")
        
        streams = er_data.get('streams', [])
        v_streams = [s for s in streams if s.get('codec_type') == 'video']
        a_streams = [s for s in streams if s.get('codec_type') == 'audio']
        
        if len(v_streams) == 1 and len(a_streams) == 1:
            score += 4
            feedback.append(f"+ English Ref: Correct streams (1 Video, 1 Audio).")
        else:
            feedback.append(f"x English Ref: Incorrect streams ({len(v_streams)} Video, {len(a_streams)} Audio).")
            
        peak_freq = er_data.get('peak_freq', 0)
        if abs(peak_freq - FREQ_ENG) <= FREQ_TOL:
            score += 4
            feedback.append(f"+ English Ref: Audio is the English track ({peak_freq:.0f}Hz).")
        else:
            feedback.append(f"x English Ref: Incorrect audio track mixed in.")
    else:
        feedback.append("x English Ref: File not found.")

    # Grade stream_inventory.json (18 pts)
    temp_inv = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    inventory = None
    try:
        copy_from_env("/home/ga/Videos/dubbing_deliverables/stream_inventory.json", temp_inv.name)
        with open(temp_inv.name, 'r') as f:
            inventory = json.load(f)
    except Exception:
        feedback.append("x Inventory: stream_inventory.json not found or invalid JSON.")
    finally:
        if os.path.exists(temp_inv.name):
            os.unlink(temp_inv.name)

    if inventory:
        score += 4
        feedback.append("+ Inventory: Valid JSON file provided.")
        
        total_streams = inventory.get("total_streams", 0)
        if total_streams == 4:
            score += 3
            feedback.append("+ Inventory: Correct total_streams (4).")
            
        v_inv = inventory.get("video_streams", [])
        if len(v_inv) == 1 and "h264" in str(v_inv[0].get("codec", "")).lower():
            score += 3
            feedback.append("+ Inventory: Correct video stream details.")
            
        a_inv = inventory.get("audio_streams", [])
        if len(a_inv) == 3:
            langs = [str(a.get("language", "")).lower() for a in a_inv]
            if "english" in langs and "spanish" in langs and "french" in langs:
                score += 5
                feedback.append("+ Inventory: Successfully identified all 3 audio languages.")
            
            # Spot check details
            valid_details = all("sample_rate" in a and "channels" in a for a in a_inv)
            if valid_details:
                score += 3
                feedback.append("+ Inventory: Audio objects contain channel and sample rate details.")

    # Timestamps Anti-Gaming (10 pts)
    files_created = sum(1 for f in data.keys() if isinstance(data[f], dict) and data[f].get('mtime', 0) > start_time)
    if files_created >= 5:
        score += 10
        feedback.append("+ Timestamps: Deliverables were created during the active session.")
    else:
        feedback.append(f"x Timestamps: Only {files_created} deliverables created during the session.")

    # VLM Trajectory Verification (6 pts)
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        
        if frames and final:
            prompt = (
                "You are reviewing screenshots of an agent using VLC Media Player to analyze and transcode media. "
                "Did the agent utilize VLC's features (such as 'Convert / Save', 'Media Information', or codec adjustment dialogs) "
                "to perform stream extractions or transcodings?\n"
                "Respond in JSON format: {\"used_vlc_features\": true/false}"
            )
            query_vlm = env_info.get("query_vlm")
            if query_vlm:
                vlm_res = query_vlm(images=frames + [final], prompt=prompt)
                if vlm_res and vlm_res.get("success"):
                    parsed = vlm_res.get("parsed", {})
                    if parsed.get("used_vlc_features", False):
                        score += 6
                        feedback.append("+ VLM: Visual confirmation of VLC feature usage.")
                    else:
                        feedback.append("- VLM: Could not visually confirm VLC conversion workflows.")
    except Exception as e:
        logger.warning(f"VLM verification skipped or failed: {e}")

    # Determine passing (Threshold 65%)
    # To pass, they must have successfully extracted the audio and avoided pure 0-point failures on core mechanics.
    passed = score >= 65.0

    return {
        "passed": passed,
        "score": min(100, int(score)),
        "feedback": "\n".join(feedback)
    }