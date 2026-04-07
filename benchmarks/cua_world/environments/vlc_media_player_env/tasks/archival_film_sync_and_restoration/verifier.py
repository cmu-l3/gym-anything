#!/usr/bin/env python3
"""
Verifier for Archival Film Sync and Restoration task.
Tests multi-modal signal correction using physical audio/visual measurements,
not just checking metadata flags.
"""

import os
import json
import tempfile
import logging
import numpy as np
import cv2
from scipy.io import wavfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# --- VLM Prompts ---
TRAJECTORY_PROMPT = """You are auditing a user operating VLC Media Player.
Look at these chronological screenshots. The user's goal was to transcode an archival video, applying an audio delay, a deinterlace filter, and an aspect ratio override.
1. Did the user open the 'Convert / Save' dialog?
2. Did they navigate into the codec/profile settings (wrench icon)?
3. Is there evidence they navigated into the Audio codec or Video codec settings to adjust filters/sync?

Answer in JSON format:
{
    "convert_save_used": true/false,
    "profile_settings_opened": true/false,
    "confidence": "high/medium/low"
}"""

def _measure_av_sync(video_path, audio_path):
    """
    Finds the exact timestamp of the visual flash and audio peak.
    Returns (visual_time_sec, audio_time_sec).
    """
    visual_time = -1.0
    audio_time = -1.0
    
    # 1. Process Video (find white flash)
    if os.path.exists(video_path):
        cap = cv2.VideoCapture(video_path)
        fps = cap.get(cv2.CAP_PROP_FPS) or 25.0
        max_mean = -1
        flash_frame = -1
        frame_idx = 0
        while True:
            ret, frame = cap.read()
            if not ret: break
            mean_val = np.mean(frame)
            if mean_val > max_mean:
                max_mean = mean_val
                flash_frame = frame_idx
            frame_idx += 1
        cap.release()
        if max_mean > 150: # The flash is pure white (mean near 255), rest of video is test pattern (mean ~100)
            visual_time = flash_frame / fps

    # 2. Process Audio (find 1000Hz beep peak)
    if os.path.exists(audio_path):
        try:
            sr, data = wavfile.read(audio_path)
            # Find index of max absolute amplitude
            peak_idx = np.argmax(np.abs(data))
            audio_time = peak_idx / sr
        except Exception as e:
            logger.error(f"Error reading WAV: {e}")
            
    return visual_time, audio_time

def verify_archival_film_sync_and_restoration(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback = []
    
    temp_files = []
    def _create_temp(ext=".tmp"):
        tf = tempfile.NamedTemporaryFile(delete=False, suffix=ext)
        tf.close()
        temp_files.append(tf.name)
        return tf.name

    try:
        # Load Result Data
        result_json_path = _create_temp(".json")
        try:
            copy_from_env("/tmp/task_result.json", result_json_path)
            with open(result_json_path, 'r') as f:
                res = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to read result metadata: {e}"}

        # Validate existence & generation (10 points)
        if not res.get("output_exists"):
            return {"passed": False, "score": 0, "feedback": "Output video restored_archive.mp4 not found."}
        
        if not res.get("created_during_task"):
            return {"passed": False, "score": 0, "feedback": "Anti-gaming failure: File exists but was not created during the task timeframe."}
            
        score += 10
        feedback.append("Output video generated properly.")

        # --- A/V Sync Verification (30 Points) ---
        vid_path = _create_temp(".mp4")
        aud_path = _create_temp(".wav")
        try:
            copy_from_env("/home/ga/Videos/restored_archive.mp4", vid_path)
            copy_from_env("/tmp/restored_audio.wav", aud_path)
            
            v_time, a_time = _measure_av_sync(vid_path, aud_path)
            
            if v_time > 0 and a_time > 0:
                diff = abs(v_time - a_time)
                if diff <= 0.2:
                    score += 30
                    feedback.append(f"A/V Sync Fixed: Visual flash ({v_time:.2f}s) and audio beep ({a_time:.2f}s) align perfectly (diff {diff:.2f}s)!")
                elif abs(abs(v_time - a_time) - 1.5) <= 0.2:
                    feedback.append(f"A/V Sync Failed: Audio beep ({a_time:.2f}s) is still exactly 1.5s out of sync with flash ({v_time:.2f}s).")
                else:
                    feedback.append(f"A/V Sync Incorrect: Sync difference is {diff:.2f}s (expected < 0.2s).")
            else:
                feedback.append("Could not accurately extract signals to verify A/V sync.")
        except Exception as e:
            feedback.append(f"Error processing A/V sync: {e}")

        # --- Deinterlacing Verification (20 Points) ---
        try:
            prog_f = int(res.get("prog_frames", 0))
            tff_f = int(res.get("tff_frames", 0))
            total_f = prog_f + tff_f
            
            if total_f > 0:
                prog_ratio = prog_f / total_f
                if prog_ratio > 0.8:
                    score += 20
                    feedback.append(f"Deinterlacing Applied: Detected {prog_ratio*100:.1f}% progressive frames.")
                else:
                    feedback.append(f"Deinterlacing Failed: Detected high interlacing ({100-(prog_ratio*100):.1f}% TFF frames).")
            else:
                feedback.append("Deinterlacing Unknown: idet filter returned no frame counts.")
        except ValueError:
            feedback.append("Deinterlacing error parsing IDET values.")

        # --- Aspect Ratio Verification (15 Points) ---
        dar_str = res.get("dar", "").strip()
        w_str = str(res.get("width", "0")).strip()
        h_str = str(res.get("height", "0")).strip()
        
        ar_fixed = False
        if "16:9" in dar_str:
            ar_fixed = True
        elif ":" in dar_str:
            # Maybe evaluating fraction?
            try:
                num, den = map(float, dar_str.split(":"))
                if abs((num/den) - 1.777) < 0.05:
                    ar_fixed = True
            except: pass
        elif w_str != "0" and h_str != "0":
            # If DAR is stripped but output is physically 16:9
            try:
                if abs((float(w_str) / float(h_str)) - 1.777) < 0.05:
                    ar_fixed = True
            except: pass

        if ar_fixed:
            score += 15
            feedback.append("Aspect Ratio Corrected: Confirmed 16:9 representation.")
        else:
            feedback.append(f"Aspect Ratio Incorrect: Found DAR '{dar_str}', Dimensions {w_str}x{h_str}.")

        # --- Report Verification (15 Points) ---
        if res.get("report_exists"):
            log_path = _create_temp(".json")
            try:
                copy_from_env("/tmp/restoration_log.json", log_path)
                with open(log_path, 'r') as f:
                    log_data = json.load(f)
                
                req_keys = ['source_file', 'issues_fixed', 'audio_delay_ms', 'aspect_ratio_target', 'deinterlace_applied']
                if all(k in log_data for k in req_keys):
                    if log_data.get("audio_delay_ms") == 1500 and log_data.get("deinterlace_applied") is True:
                        score += 15
                        feedback.append("Report correct: JSON log contains all required schema keys and valid values.")
                    else:
                        score += 5
                        feedback.append("Report partial: Keys exist but values are incorrect/inaccurate.")
                else:
                    feedback.append("Report invalid: Missing required schema keys.")
            except Exception as e:
                feedback.append("Report invalid: Could not parse JSON log.")
        else:
            feedback.append("Report missing: No restoration_log.json found.")

        # --- VLM Trajectory Process Verification (10 Points) ---
        try:
            frames = sample_trajectory_frames(traj, n=4)
            vlm_response = query_vlm(images=frames, prompt=TRAJECTORY_PROMPT)
            if vlm_response and vlm_response.get("success"):
                v_data = vlm_response.get("parsed", {})
                if v_data.get("convert_save_used") and v_data.get("profile_settings_opened"):
                    score += 10
                    feedback.append("VLM Verified: Trajectory confirms use of VLC Convert/Save pipeline.")
                else:
                    feedback.append("VLM Note: Trajectory does not clearly show VLC workflow configuration.")
        except Exception as e:
            logger.warning(f"VLM process check failed: {e}")

    finally:
        for f in temp_files:
            if os.path.exists(f):
                os.unlink(f)

    # Determine Pass (Threshold = 70 AND Sync must be fixed)
    passed = (score >= 70) and ("A/V Sync Fixed" in " ".join(feedback))
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }