#!/usr/bin/env python3
"""
Verifier for KTV Backing Track Pipeline task.

Verification Strategy:
1. Container & Streams (20 pts): Output files must be MKV format with >= 1 Video, 1 Audio, 1 Subtitle stream.
2. Audio Phase Cancellation (30 pts): FFT analysis of extracted audio to verify center-panned frequency (vocals) is reduced by >75% compared to side-panned frequencies (instruments).
3. Visual Watermark (25 pts): VLM checks extracted video frames for the "STAR KTV" logo in the bottom-right corner.
4. JSON Catalog (15 pts): Evaluates catalog.json structure.
5. File Existence (10 pts): Tracks presence.

Pass threshold: 75%
"""

import os
import json
import tarfile
import tempfile
import logging
import base64
import numpy as np
from scipy.io import wavfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Frequencies used in the generated tracks
TRACK_FREQS = {
    1: {"center": 1000, "side1": 400, "side2": 800},
    2: {"center": 1500, "side1": 500, "side2": 900},
    3: {"center": 1200, "side1": 300, "side2": 700}
}

def check_vocal_removal(wav_path, center_freq, side_freqs):
    """
    Checks if the center-panned frequency was successfully removed/reduced
    via phase cancellation (L-R) while side frequencies remain intact.
    """
    try:
        sr, data = wavfile.read(wav_path)
        
        # Convert stereo to mono for analysis by averaging channels
        # If agent just passed the original audio through, mono will still contain the center frequency.
        # If agent did proper karaoke (L-R) and output mono, we just FFT it.
        # If agent did L-R and output dual-mono, averaging gives the same result.
        if len(data.shape) > 1:
            mono = np.mean(data, axis=1)
        else:
            mono = data
            
        # Check if audio is completely silent
        if np.max(np.abs(mono)) < 10:
            return False, "Audio is completely silent."
            
        fft_out = np.abs(np.fft.rfft(mono))
        freqs = np.fft.rfftfreq(len(mono), 1/sr)
        
        def get_mag(f_target):
            idx = np.argmin(np.abs(freqs - f_target))
            # Search a small window around the target bin
            return np.max(fft_out[max(0, idx-5):min(len(fft_out), idx+6)])
            
        mag_c = get_mag(center_freq)
        mag_s1 = get_mag(side_freqs[0])
        mag_s2 = get_mag(side_freqs[1])
        
        # In the original audio, mag_c is approx equal to (mag_s1 + mag_s2).
        # In a successful vocal removal (L-R), mag_c should be near 0,
        # while mag_s1 and mag_s2 should remain strong.
        max_side_mag = max(mag_s1, mag_s2)
        if max_side_mag == 0:
            return False, "Side instrument frequencies missing."
            
        ratio = mag_c / max_side_mag
        # If center is reduced to less than 25% of the side instruments, it's successful
        if ratio < 0.25:
            return True, f"Vocal isolated (Center ratio: {ratio:.2f})"
        else:
            return False, f"Vocal intact (Center ratio: {ratio:.2f})"
            
    except Exception as e:
        logger.error(f"FFT error: {e}")
        return False, f"Audio analysis failed: {str(e)}"

def verify_ktv_backing_track_pipeline(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0.0
    feedback_parts = []
    
    temp_dir = tempfile.mkdtemp(prefix='ktv_verify_')
    tar_path = os.path.join(temp_dir, 'ktv_export.tar.gz')
    extract_dir = os.path.join(temp_dir, 'extracted')
    
    try:
        copy_from_env("/tmp/ktv_export.tar.gz", tar_path)
        with tarfile.open(tar_path, "r:gz") as tar:
            tar.extractall(path=extract_dir)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve exports: {e}"}

    export_root = os.path.join(extract_dir, "ktv_export")
    
    # 1. Verify File Existence & Container/Streams (10 + 20 pts)
    # 2. Verify Audio Phase Cancellation (30 pts)
    # 3. Verify Visual Watermark via VLM (25 pts)
    processed_count = 0
    successful_audio = 0
    successful_watermark = 0
    successful_streams = 0

    for i in [1, 2, 3]:
        probe_file = os.path.join(export_root, f"track{i}_probe.json")
        audio_file = os.path.join(export_root, f"track{i}_audio.wav")
        frame_file = os.path.join(export_root, f"track{i}_frame.png")
        
        if not os.path.exists(probe_file):
            feedback_parts.append(f"Track {i}: Missing")
            continue
            
        processed_count += 1
        score += 3.33  # File existence points
        
        # Check container & streams
        with open(probe_file, 'r') as f:
            probe_data = json.load(f)
            
        fmt = probe_data.get('format', {}).get('format_name', '')
        streams = probe_data.get('streams', [])
        
        has_video = any(s.get('codec_type') == 'video' for s in streams)
        has_audio = any(s.get('codec_type') == 'audio' for s in streams)
        has_subtitle = any(s.get('codec_type') == 'subtitle' for s in streams)
        
        if ('matroska' in fmt or 'webm' in fmt) and has_video and has_audio and has_subtitle:
            successful_streams += 1
            score += 6.66
            feedback_parts.append(f"Track {i}: MKV container & streams OK")
        else:
            feedback_parts.append(f"Track {i}: Stream/Container mismatch")

        # Check Audio Vocal Removal
        if os.path.exists(audio_file):
            freqs = TRACK_FREQS[i]
            is_removed, msg = check_vocal_removal(audio_file, freqs["center"], [freqs["side1"], freqs["side2"]])
            if is_removed:
                successful_audio += 1
                score += 10.0
                feedback_parts.append(f"Track {i}: Audio phase cancel OK")
            else:
                feedback_parts.append(f"Track {i}: Audio fail ({msg})")
        
        # Check Watermark via VLM
        if os.path.exists(frame_file) and query_vlm:
            try:
                vlm_prompt = (
                    "Look at this video frame. "
                    "Is there a transparent watermark logo that says 'STAR KTV' located specifically in the bottom-right area? "
                    "Reply in JSON format strictly matching: {\"watermark_present\": true/false}"
                )
                vlm_response = query_vlm(prompt=vlm_prompt, image=frame_file)
                if vlm_response.get("success"):
                    parsed = vlm_response.get("parsed", {})
                    if parsed.get("watermark_present") is True:
                        successful_watermark += 1
                        score += 8.33
                        feedback_parts.append(f"Track {i}: Watermark verified")
                    else:
                        feedback_parts.append(f"Track {i}: Watermark missing/incorrect")
            except Exception as e:
                logger.error(f"VLM error on Track {i}: {e}")

    # 4. Verify Catalog Manifest (15 pts)
    catalog_file = os.path.join(export_root, "catalog.json")
    if os.path.exists(catalog_file):
        try:
            with open(catalog_file, 'r') as f:
                catalog = json.load(f)
            if catalog.get("venue") == "Star KTV" and "processed_tracks" in catalog:
                tracks = catalog["processed_tracks"]
                if len(tracks) >= 3 and all(t.get("output_file", "").endswith(".mkv") for t in tracks):
                    score += 15.0
                    feedback_parts.append("Catalog JSON: Valid schema")
                else:
                    feedback_parts.append("Catalog JSON: Incomplete tracks data")
            else:
                feedback_parts.append("Catalog JSON: Schema mismatch")
        except Exception:
            feedback_parts.append("Catalog JSON: Invalid format")
    else:
        feedback_parts.append("Catalog JSON: Missing")

    # Final logic
    passed = score >= 75.0 and successful_audio >= 2 and successful_streams >= 2
    
    # Cleanup
    try:
        import shutil
        shutil.rmtree(temp_dir)
    except:
        pass

    return {
        "passed": passed,
        "score": min(100.0, score),
        "feedback": " | ".join(feedback_parts)
    }