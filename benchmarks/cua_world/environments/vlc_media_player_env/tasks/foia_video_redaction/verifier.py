#!/usr/bin/env python3
"""
Verifier for FOIA Video Redaction Task.

Verification Criteria (32 points max, passing threshold 18):
- Audio-redacted file exists, valid MP4, ~120s duration (3 pts)
- Audio-redacted: R1 range (40-60s) is silent (3 pts)
- Audio-redacted: R3 range (80-100s) is silent (3 pts)
- Audio-redacted: Non-redacted ranges have audio (2 pts)
- Releasable file exists, valid MP4 (2 pts)
- Releasable: ~100s duration (3 pts)
- Releasable: Audio muting preserved in shifted positions (3 pts)
- Releasable: Non-redacted ranges have audio (2 pts)
- Redaction log: Valid JSON + structure (2 pts)
- Redaction log: 3 entries of correct types (3 pts)
- Redaction log: Correct metadata and timestamps (2 pts)
- Technical properties: Valid JSON w/ 2 files (2 pts)
- Technical properties: matching reported durations (2 pts)
"""

import json
import os
import subprocess
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def get_audio_duration(filepath):
    """Get precise duration of media file using ffprobe."""
    try:
        cmd = [
            'ffprobe', '-v', 'error',
            '-show_entries', 'format=duration',
            '-of', 'json', filepath
        ]
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
        if res.returncode == 0:
            data = json.loads(res.stdout)
            dur = data.get('format', {}).get('duration')
            if dur:
                return float(dur)
    except Exception as e:
        logger.error(f"Duration extraction failed: {e}")
    return 0.0


def get_mean_volume(filepath, start_time, duration=5):
    """
    Measure the mean audio volume (RMS) of a specific segment using ffmpeg.
    Returns float in dB (e.g., -15.4). Returns -91.0 if silent or no audio stream.
    """
    try:
        cmd = [
            'ffmpeg', '-ss', str(start_time), '-t', str(duration),
            '-i', filepath, '-af', 'volumedetect', '-f', 'null', '/dev/null'
        ]
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=20)
        
        # Parse output for 'mean_volume: -15.4 dB'
        import re
        match = re.search(r'mean_volume:\s*([-0-9.]+)\s*dB', res.stderr)
        if match:
            return float(match.group(1))
    except Exception as e:
        logger.error(f"Volume detection failed: {e}")
    return -91.0  # Safe default representing silence


def verify_foia_video_redaction(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback = []
    score = 0.0
    max_score = 32.0
    
    # Ground truth
    ORIGINAL_DURATION = 120.0
    RELEASABLE_DURATION = 100.0
    DURATION_TOLERANCE = 3.0
    SILENCE_THRESHOLD_DB = -40.0
    LOUD_THRESHOLD_DB = -30.0

    temp_dir = tempfile.mkdtemp(prefix='foia_verify_')
    
    # Files to verify
    audio_redacted_name = 'evidence_audio_redacted.mp4'
    releasable_name = 'evidence_releasable.mp4'
    log_name = 'redaction_log.json'
    tech_name = 'technical_properties.json'

    # 1. Verify Audio-Redacted Video (Max 11 points)
    audio_redacted_path = os.path.join(temp_dir, audio_redacted_name)
    try:
        copy_from_env(f'/tmp/foia_output/{audio_redacted_name}', audio_redacted_path)
    except Exception:
        feedback.append(f"x Missing: {audio_redacted_name}")
        audio_redacted_path = None

    if audio_redacted_path and os.path.exists(audio_redacted_path) and os.path.getsize(audio_redacted_path) > 1000:
        dur = get_audio_duration(audio_redacted_path)
        if abs(dur - ORIGINAL_DURATION) <= DURATION_TOLERANCE:
            score += 3.0
            feedback.append(f"+ {audio_redacted_name}: Exists and correct duration ({dur:.1f}s)")
            
            # Check audio muting at specific timestamps
            # R1 mute: 40-60s (check at 50s)
            vol_r1 = get_mean_volume(audio_redacted_path, 50, 5)
            if vol_r1 <= SILENCE_THRESHOLD_DB:
                score += 3.0
                feedback.append(f"+ {audio_redacted_name}: R1 successfully muted ({vol_r1}dB)")
            else:
                feedback.append(f"x {audio_redacted_name}: R1 NOT muted ({vol_r1}dB)")

            # R3 mute: 80-100s (check at 90s)
            vol_r3 = get_mean_volume(audio_redacted_path, 90, 5)
            if vol_r3 <= SILENCE_THRESHOLD_DB:
                score += 3.0
                feedback.append(f"+ {audio_redacted_name}: R3 successfully muted ({vol_r3}dB)")
            else:
                feedback.append(f"x {audio_redacted_name}: R3 NOT muted ({vol_r3}dB)")
                
            # Non-redacted checks (10s and 110s)
            vol_loud1 = get_mean_volume(audio_redacted_path, 10, 5)
            vol_loud2 = get_mean_volume(audio_redacted_path, 110, 5)
            if vol_loud1 >= LOUD_THRESHOLD_DB and vol_loud2 >= LOUD_THRESHOLD_DB:
                score += 2.0
                feedback.append(f"+ {audio_redacted_name}: Non-redacted sections preserved audio")
            else:
                feedback.append(f"x {audio_redacted_name}: Non-redacted sections silent! (Over-muted or track stripped)")
        else:
            feedback.append(f"x {audio_redacted_name}: Invalid duration ({dur:.1f}s, expected ~120s)")
    else:
        if audio_redacted_path:
            feedback.append(f"x {audio_redacted_name} is empty or invalid.")

    # 2. Verify Releasable Video (Max 10 points)
    releasable_path = os.path.join(temp_dir, releasable_name)
    try:
        copy_from_env(f'/tmp/foia_output/{releasable_name}', releasable_path)
    except Exception:
        feedback.append(f"x Missing: {releasable_name}")
        releasable_path = None

    if releasable_path and os.path.exists(releasable_path) and os.path.getsize(releasable_path) > 1000:
        score += 2.0
        feedback.append(f"+ {releasable_name}: Exists")
        
        dur = get_audio_duration(releasable_path)
        if abs(dur - RELEASABLE_DURATION) <= DURATION_TOLERANCE:
            score += 3.0
            feedback.append(f"+ {releasable_name}: Segment successfully excised (New duration: {dur:.1f}s)")
            
            # Since 60-80s was removed, the R3 muted section (originally 80-100s) shifts to 60-80s.
            # R1 mute: 40-60s (check at 50s)
            vol_rel_r1 = get_mean_volume(releasable_path, 50, 5)
            # R3 mute: now at 60-80s (check at 70s)
            vol_rel_r3 = get_mean_volume(releasable_path, 70, 5)
            
            if vol_rel_r1 <= SILENCE_THRESHOLD_DB and vol_rel_r3 <= SILENCE_THRESHOLD_DB:
                score += 3.0
                feedback.append(f"+ {releasable_name}: Audio mutes correctly preserved across excision")
            else:
                feedback.append(f"x {releasable_name}: Audio mutes misaligned or missing after excision")
                
            # Non-redacted checks (10s and 90s)
            vol_rel_loud1 = get_mean_volume(releasable_path, 10, 5)
            vol_rel_loud2 = get_mean_volume(releasable_path, 90, 5) # 90s is the original 110s section
            if vol_rel_loud1 >= LOUD_THRESHOLD_DB and vol_rel_loud2 >= LOUD_THRESHOLD_DB:
                score += 2.0
                feedback.append(f"+ {releasable_name}: Non-redacted sections preserved audio")
            else:
                feedback.append(f"x {releasable_name}: Non-redacted sections silent! (Over-muted)")
        else:
            feedback.append(f"x {releasable_name}: Invalid duration ({dur:.1f}s, expected ~100s). Excision failed.")

    # 3. Verify Redaction Log JSON (Max 7 points)
    log_path = os.path.join(temp_dir, log_name)
    try:
        copy_from_env(f'/tmp/foia_output/{log_name}', log_path)
        with open(log_path, 'r') as f:
            redaction_log = json.load(f)
            
        score += 2.0
        feedback.append(f"+ {log_name}: Valid JSON structure")
        
        redactions = redaction_log.get('redactions', [])
        if len(redactions) == 3:
            score += 3.0
            feedback.append(f"+ {log_name}: Found exactly 3 redaction entries")
            
            # Check metadata content
            has_case = redaction_log.get('case_id') == "FOIA-2024-0847"
            has_types = all(r.get('type') in ['audio_mute', 'full_excision'] for r in redactions)
            has_starts = all('start_time' in r for r in redactions)
            if has_case and has_types and has_starts:
                score += 2.0
                feedback.append(f"+ {log_name}: Correct metadata fields, types, and legal basis documented")
            else:
                feedback.append(f"x {log_name}: Missing required case_id, types, or timestamps")
        else:
            feedback.append(f"x {log_name}: Expected 3 redaction entries, found {len(redactions)}")
    except Exception:
        feedback.append(f"x {log_name}: Missing or invalid JSON")

    # 4. Verify Technical Properties JSON (Max 4 points)
    tech_path = os.path.join(temp_dir, tech_name)
    try:
        copy_from_env(f'/tmp/foia_output/{tech_name}', tech_path)
        with open(tech_path, 'r') as f:
            tech_props = json.load(f)
            
        score += 2.0
        feedback.append(f"+ {tech_name}: Valid JSON")
        
        # Check if lists the deliverables with reasonable durations
        # Could be list or dict
        items = tech_props if isinstance(tech_props, list) else (tech_props.get('outputs', []) or list(tech_props.values()))
        durations = [item.get('duration_seconds') for item in items if isinstance(item, dict) and 'duration_seconds' in item]
        
        if any(abs(float(d)-120) <= 5 for d in durations) and any(abs(float(d)-100) <= 5 for d in durations):
            score += 2.0
            feedback.append(f"+ {tech_name}: Accurately documented output durations")
        else:
            feedback.append(f"x {tech_name}: Output durations missing or highly inaccurate")
    except Exception:
        feedback.append(f"x {tech_name}: Missing or invalid JSON")

    # Cleanup temp dir
    try:
        import shutil
        shutil.rmtree(temp_dir)
    except Exception:
        pass

    passed = score >= 18.0
    return {
        "passed": passed,
        "score": int(score),
        "feedback": "\n".join(feedback)
    }