#!/usr/bin/env python3
"""
Verifier for drivein_fm_broadcast_mastering task.

Verification Strategy:
1. File Existence & Creation (10 pts)
2. Format & Container: MP3 codec, 0 video streams (15 pts)
3. Audio Properties: Mono (1 channel), 44.1kHz (25 pts)
4. DSP Verification: Acoustic volume analysis proves compressor was applied (30 pts)
5. Metadata: JSON spec file exists and is correct (20 pts)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fm_broadcast_mastering(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    output_exists = result.get('output_exists', False)
    created_during_task = result.get('created_during_task', False)
    
    # 1. Existence and timestamp
    if not output_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Output audio file /home/ga/Music/fm_broadcast_audio.mp3 was not found."
        }
    
    if created_during_task:
        score += 10
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("File existed before task started (gaming attempt?)")

    # 2. Format & Container
    has_video = result.get('has_video', True)
    codec = result.get('codec', '').lower()
    
    if not has_video:
        score += 7.5
        feedback_parts.append("Video stream stripped")
    else:
        feedback_parts.append("Video stream still present")
        
    if codec in ['mp3']:
        score += 7.5
        feedback_parts.append("Correct codec (MP3)")
    else:
        feedback_parts.append(f"Wrong codec: {codec}")

    # 3. Audio Properties
    channels = result.get('channels', 0)
    sample_rate = result.get('sample_rate', 0)
    
    if channels == 1:
        score += 12.5
        feedback_parts.append("Downmixed to Mono")
    else:
        feedback_parts.append(f"Wrong channel count: {channels} (expected 1)")
        
    if sample_rate == 44100:
        score += 12.5
        feedback_parts.append("Sample rate 44.1kHz")
    else:
        feedback_parts.append(f"Wrong sample rate: {sample_rate} (expected 44100)")

    # 4. DSP Verification (Dynamic Range Compressor)
    # With a highly dynamic track, a standard extraction yields a very low mean volume (e.g., -26 dB)
    # The VLC Dynamic Range Compressor applies makeup gain, significantly raising the mean volume 
    # (e.g., to -15 dB) and shrinking the crest factor (max - mean).
    agent_mean = float(result.get('mean_volume_db', 0))
    base_mean = float(result.get('base_mean_volume_db', 0))
    
    # Check if makeup gain was applied (mean volume raised by at least 3dB)
    if agent_mean > (base_mean + 3.0):
        score += 30
        feedback_parts.append(f"Compressor verified (Mean Vol raised from {base_mean:.1f}dB to {agent_mean:.1f}dB)")
        dsp_passed = True
    else:
        feedback_parts.append(f"Compressor missing/inactive (Mean Vol {agent_mean:.1f}dB vs Base {base_mean:.1f}dB)")
        dsp_passed = False

    # 5. Metadata JSON Specification
    spec_exists = result.get('spec_exists', False)
    spec_content = result.get('spec_content', {})
    
    if spec_exists and isinstance(spec_content, dict) and not "error" in spec_content:
        spec_score = 0
        
        # Check keys
        if str(spec_content.get('channels')) == "1":
            spec_score += 5
        if str(spec_content.get('sample_rate')) == "44100":
            spec_score += 5
        if spec_content.get('compression_applied') is True:
            spec_score += 5
        if "fm_broadcast_audio.mp3" in str(spec_content.get('filename', '')):
            spec_score += 5
            
        score += spec_score
        feedback_parts.append(f"JSON spec score: {spec_score}/20")
    else:
        feedback_parts.append("JSON spec missing or invalid")

    # Determine pass/fail
    # Must achieve at least 70/100, downmix to mono, and successfully apply the compressor
    key_criteria_met = (channels == 1) and dsp_passed and created_during_task
    passed = (score >= 70) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }