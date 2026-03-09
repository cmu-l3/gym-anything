#!/usr/bin/env python3
"""
Verifier for Apply Audio Fadeout task

Verifies that audio fade-out effect was properly applied to video file.
Checks audio levels at different time points to confirm gradual volume decrease.
"""

import sys
import os
import logging
import tempfile
import subprocess
import re

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import (
    get_video_info,
    setup_verification_environment,
    cleanup_verification_environment
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def measure_audio_volume(filepath: str, start: float, duration: float) -> float:
    """
    Measure average audio volume (mean) for a time segment using ffmpeg.
    
    Args:
        filepath: Path to video/audio file
        start: Start time in seconds
        duration: Duration to analyze in seconds
        
    Returns:
        Volume in dB (negative values, closer to 0 = louder)
        Returns -100.0 if measurement fails (indicates silence or error)
    """
    try:
        cmd = [
            'ffmpeg',
            '-ss', str(start),
            '-t', str(duration),
            '-i', filepath,
            '-af', 'volumedetect',
            '-f', 'null',
            '/dev/null'
        ]
        
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=30
        )
        
        # Parse output for mean_volume
        # Example: "[Parsed_volumedetect_0 @ 0x...] mean_volume: -16.5 dB"
        for line in result.stderr.split('\n'):
            if 'mean_volume:' in line:
                match = re.search(r'mean_volume:\s*([-\d.]+)\s*dB', line)
                if match:
                    volume_db = float(match.group(1))
                    logger.info(f"Measured volume at {start}s: {volume_db:.1f} dB")
                    return volume_db
        
        logger.warning(f"Could not parse volume from ffmpeg output at {start}s")
        return -100.0
        
    except subprocess.TimeoutExpired:
        logger.error(f"Timeout measuring volume at {start}s")
        return -100.0
    except Exception as e:
        logger.error(f"Error measuring volume at {start}s: {e}")
        return -100.0


def verify_audio_fadeout(traj, env_info, task_info):
    """
    Verify apply audio fadeout task completion.
    
    Checks:
    1. Output file exists and is valid
    2. Audio fadeout is present (volume decreases)
    3. Fadeout quality (final volume near silence)
    
    Scoring:
    - 100: Perfect fadeout (≥80% volume reduction at end)
    - 75: Good fadeout (50-80% reduction)
    - 50: Partial fadeout (20-50% reduction)
    - 25: File exists but minimal fadeout (<20%)
    - 0: File not found or invalid
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_met = 0
    total_criteria = 4
    feedback_parts = []
    
    # Criterion 1: Check if output file exists
    success, file_info, error = setup_verification_environment(
        copy_from_env,
        "/tmp/vlc_fadeout_output.mp4",
        file_type='video'
    )
    
    if not success:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Output file not found: {error}"
        }
    
    criteria_met += 1
    feedback_parts.append("✅ Output file exists")
    
    try:
        filepath = file_info['filepath']
        temp_dir = file_info['temp_dir']
        
        # Get video info
        video_data = file_info.get('data', {})
        
        if 'error' in video_data:
            cleanup_verification_environment(temp_dir)
            return {
                "passed": False,
                "score": 25,
                "feedback": f"Output file invalid: {video_data['error']}"
            }
        
        # Check duration is reasonable (should be ~60 seconds)
        duration = video_data.get('duration', 0)
        if not (55 <= duration <= 65):
            feedback_parts.append(f"⚠️ Duration mismatch: {duration:.1f}s (expected ~60s)")
        else:
            criteria_met += 1
            feedback_parts.append(f"✅ Duration correct: {duration:.1f}s")
        
        logger.info(f"Analyzing audio levels in output file (duration: {duration:.1f}s)")
        
        # Measure audio volume in multiple regions
        # Region 1: Beginning (5-15s) - should be full volume
        vol_start = measure_audio_volume(filepath, start=5, duration=10)
        
        # Region 2: Before fade (30-40s) - should still be full volume
        vol_before_fade = measure_audio_volume(filepath, start=30, duration=10)
        
        # Region 3: During fade (47-52s) - should be decreasing
        vol_during_fade = measure_audio_volume(filepath, start=47, duration=5)
        
        # Region 4: End of fade (55-58s) - should be very quiet
        vol_end = measure_audio_volume(filepath, start=55, duration=3)
        
        # Check if measurements were successful
        if vol_start == -100.0 or vol_before_fade == -100.0:
            cleanup_verification_environment(temp_dir)
            return {
                "passed": False,
                "score": 50,
                "feedback": "Output file exists but audio analysis failed"
            }
        
        # Calculate baseline volume (average of start and before-fade)
        baseline = max(vol_start, vol_before_fade)
        
        logger.info(f"Audio levels - Start: {vol_start:.1f} dB, "
                   f"Before: {vol_before_fade:.1f} dB, "
                   f"During: {vol_during_fade:.1f} dB, "
                   f"End: {vol_end:.1f} dB")
        
        # Calculate volume reductions (in dB)
        # Lower (more negative) dB = quieter, so reduction = baseline - measured
        during_fade_reduction_db = baseline - vol_during_fade
        end_reduction_db = baseline - vol_end
        
        # Convert dB difference to percentage reduction
        # A 20 dB reduction ≈ 90% power reduction
        # A 10 dB reduction ≈ 68% power reduction
        # A 6 dB reduction ≈ 50% power reduction
        
        # For scoring, we use dB differences directly
        # Good fadeout should show:
        # - During fade: at least -3 dB reduction (30% power)
        # - At end: at least -10 dB reduction (70% power)
        
        feedback_parts.append(
            f"Volume: start={vol_start:.1f}dB, during={vol_during_fade:.1f}dB, "
            f"end={vol_end:.1f}dB"
        )
        
        # Criterion 3: Check volume decreases during fade
        if during_fade_reduction_db >= 3.0:
            criteria_met += 1
            feedback_parts.append(
                f"✅ Fadeout detected (-{during_fade_reduction_db:.1f}dB during fade)"
            )
        elif during_fade_reduction_db >= 1.0:
            criteria_met += 0.5
            feedback_parts.append(
                f"⚠️ Slight fadeout (-{during_fade_reduction_db:.1f}dB, expected ≥3dB)"
            )
        else:
            feedback_parts.append(
                f"❌ No significant fadeout (-{during_fade_reduction_db:.1f}dB)"
            )
        
        # Criterion 4: Check end volume is quiet (main criterion)
        if end_reduction_db >= 15.0:
            # Excellent fadeout (≥15dB = ~94% power reduction)
            criteria_met += 1
            score = 100
            feedback_parts.append(
                f"✅ Excellent fadeout to silence (-{end_reduction_db:.1f}dB at end)"
            )
        elif end_reduction_db >= 10.0:
            # Good fadeout (10-15dB = 70-90% power reduction)
            criteria_met += 1
            score = 85
            feedback_parts.append(
                f"✅ Good fadeout (-{end_reduction_db:.1f}dB at end)"
            )
        elif end_reduction_db >= 6.0:
            # Acceptable fadeout (6-10dB = 50-70% power reduction)
            criteria_met += 0.75
            score = 75
            feedback_parts.append(
                f"✅ Acceptable fadeout (-{end_reduction_db:.1f}dB at end)"
            )
        elif end_reduction_db >= 3.0:
            # Minimal fadeout (3-6dB = 30-50% power reduction)
            criteria_met += 0.5
            score = 50
            feedback_parts.append(
                f"⚠️ Minimal fadeout (-{end_reduction_db:.1f}dB, expected ≥10dB)"
            )
        else:
            # No significant fadeout (<3dB)
            score = 25
            feedback_parts.append(
                f"❌ No significant fadeout (-{end_reduction_db:.1f}dB at end)"
            )
        
        cleanup_verification_environment(temp_dir)
        
        # Use explicit score based on fadeout quality rather than criteria ratio
        passed = score >= 75
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        if 'temp_dir' in locals():
            cleanup_verification_environment(temp_dir)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }