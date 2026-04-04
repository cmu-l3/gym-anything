#!/usr/bin/env python3
"""
Verifier for Create Notification Sound task

Checks if agent correctly extracted and optimized a notification sound
with appropriate duration, format, file size, and audio parameters.
"""

import sys
import os
import logging
import tempfile
import json
from typing import Tuple, Dict, Any

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import (
    get_audio_info,
    setup_verification_environment,
    cleanup_verification_environment
)

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)


def verify_create_notification_sound(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Verify that agent created a valid notification sound with correct properties.
    
    Scoring breakdown (total 100 points):
    - File exists and valid: 15 points
    - Duration correct (4s ±0.5s): 20 points
    - File size ≤ 500 KB: 20 points
    - Format is MP3: 15 points
    - Channels (mono=10, stereo=5): 10 points
    - Sample rate appropriate: 10 points
    - Bitrate in range: 10 points
    
    Pass threshold: 70 points
    
    Args:
        traj: Trajectory information
        env_info: Environment info including copy_from_env function
        task_info: Task information
    
    Returns:
        Dict with 'passed', 'score', and 'feedback' keys
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Copy function not available"
        }
    
    score = 0.0
    max_score = 100.0
    feedback_parts = []
    temp_dir = None
    
    try:
        # Load task parameters
        task_params = {
            'duration': 4.0,
            'max_size_kb': 500,
            'start_time': '00:00:17.0'
        }
        
        try:
            temp_params = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
            copy_from_env("/tmp/vlc_notification_params.json", temp_params.name)
            with open(temp_params.name, 'r') as f:
                task_params = json.load(f)
            os.unlink(temp_params.name)
            logger.info("Loaded task parameters")
        except Exception as e:
            logger.warning(f"Could not load task parameters, using defaults: {e}")
            feedback_parts.append("⚠️ Using default task parameters")
        
        expected_duration = task_params.get('duration', 4.0)
        max_size_kb = task_params.get('max_file_size_kb', 500)
        
        # === CRITERION 1: Output file exists and is valid audio (15 points) ===
        output_path = "/tmp/vlc_notification_output.mp3"
        success, file_info, error = setup_verification_environment(
            copy_from_env,
            output_path,
            file_type='audio'
        )
        
        if not success:
            feedback_parts.append(f"❌ Output file not found or invalid: {error}")
            return {
                "passed": False,
                "score": 0,
                "feedback": "\n".join(feedback_parts)
            }
        
        temp_dir = file_info.get('temp_dir')
        audio_data = file_info.get('data', {})
        
        if 'error' in audio_data:
            feedback_parts.append(f"❌ Invalid audio file: {audio_data['error']}")
            cleanup_verification_environment(temp_dir)
            return {
                "passed": False,
                "score": 0,
                "feedback": "\n".join(feedback_parts)
            }
        
        score += 15
        feedback_parts.append("✅ Notification file exists and is valid audio (15/15)")
        
        # === CRITERION 2: Duration correct - 4 seconds ±0.5s (20 points) ===
        duration = audio_data.get('duration', 0)
        duration_tolerance = 0.5
        
        if duration > 0:
            duration_diff = abs(duration - expected_duration)
            
            if duration_diff <= duration_tolerance:
                score += 20
                feedback_parts.append(f"✅ Duration perfect: {duration:.2f}s (target: {expected_duration}s) (20/20)")
            elif duration_diff <= 1.0:
                # Partial credit if within 1 second
                partial_score = 10
                score += partial_score
                feedback_parts.append(f"⚠️ Duration acceptable: {duration:.2f}s (target: {expected_duration}s ±{duration_tolerance}s) ({partial_score}/20)")
            else:
                feedback_parts.append(f"❌ Duration incorrect: {duration:.2f}s (expected: {expected_duration}s ±{duration_tolerance}s) (0/20)")
        else:
            feedback_parts.append("❌ Duration not detected (0/20)")
        
        # === CRITERION 3: File size < 500 KB (20 points) ===
        file_size_bytes = audio_data.get('size_bytes', 0)
        file_size_kb = file_size_bytes / 1024
        
        if file_size_kb > 0:
            if file_size_kb <= max_size_kb:
                score += 20
                feedback_parts.append(f"✅ File size optimal: {file_size_kb:.1f} KB (max: {max_size_kb} KB) (20/20)")
            elif file_size_kb <= max_size_kb * 1.2:
                # Partial credit if within 20% over limit
                partial_score = 10
                score += partial_score
                feedback_parts.append(f"⚠️ File size slightly over: {file_size_kb:.1f} KB (max: {max_size_kb} KB) ({partial_score}/20)")
            else:
                feedback_parts.append(f"❌ File size too large: {file_size_kb:.1f} KB (max: {max_size_kb} KB) (0/20)")
        else:
            feedback_parts.append("❌ File size not detected (0/20)")
        
        # === CRITERION 4: Format is MP3 (15 points) ===
        codec = audio_data.get('codec', '').lower()
        audio_format = audio_data.get('format', '').lower()
        
        if 'mp3' in codec or 'mp3' in audio_format or 'mpeg' in codec:
            score += 15
            feedback_parts.append(f"✅ Format is MP3 (codec: {codec}) (15/15)")
        else:
            feedback_parts.append(f"❌ Format is not MP3 (codec: {codec}, format: {audio_format}) (0/15)")
        
        # === CRITERION 5: Mono audio preferred (10 points) ===
        channels = audio_data.get('channels', 0)
        
        if channels == 1:
            score += 10
            feedback_parts.append("✅ Mono audio (1 channel) - optimal for notifications (10/10)")
        elif channels == 2:
            score += 5
            feedback_parts.append("△ Stereo audio (2 channels) - works but not optimal (5/10)")
        else:
            feedback_parts.append(f"❌ Unexpected channel count: {channels} (0/10)")
        
        # === CRITERION 6: Sample rate 44.1kHz or 22.05kHz (10 points) ===
        sample_rate = audio_data.get('sample_rate', 0)
        
        if sample_rate in [44100, 22050]:
            score += 10
            feedback_parts.append(f"✅ Sample rate optimal: {sample_rate} Hz (10/10)")
        elif 8000 <= sample_rate <= 48000:
            score += 5
            feedback_parts.append(f"△ Sample rate acceptable: {sample_rate} Hz (5/10)")
        else:
            feedback_parts.append(f"❌ Unusual sample rate: {sample_rate} Hz (0/10)")
        
        # === CRITERION 7: Bitrate 64-128 kbps (10 points) ===
        bitrate = audio_data.get('bitrate', 0)
        bitrate_kbps = bitrate / 1000 if bitrate > 0 else 0
        
        if 64 <= bitrate_kbps <= 128:
            score += 10
            feedback_parts.append(f"✅ Bitrate optimal: {bitrate_kbps:.0f} kbps (10/10)")
        elif 32 <= bitrate_kbps <= 192:
            score += 5
            feedback_parts.append(f"△ Bitrate acceptable: {bitrate_kbps:.0f} kbps (5/10)")
        elif bitrate_kbps > 0:
            feedback_parts.append(f"⚠️ Bitrate: {bitrate_kbps:.0f} kbps (not optimal) (0/10)")
        else:
            feedback_parts.append("❌ Bitrate not detected (0/10)")
        
        # Calculate final score (normalize to 0-100)
        final_score = int(score)
        passed = final_score >= 70
        
        # Build final feedback
        if passed:
            result_msg = f"🎉 SUCCESS: Notification sound created correctly! ({final_score}/100)"
        else:
            result_msg = f"❌ INCOMPLETE: Score {final_score}/100 (need 70 to pass)"
        
        feedback_parts.insert(0, result_msg)
        feedback_parts.append(f"\n{'='*60}")
        feedback_parts.append(f"Final Score: {final_score}/100 {'✅ PASSED' if passed else '❌ FAILED'}")
        
        return {
            "passed": passed,
            "score": final_score,
            "feedback": "\n".join(feedback_parts)
        }
    
    except Exception as e:
        logger.exception("Verification error")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification error: {str(e)}"
        }
    
    finally:
        if temp_dir:
            cleanup_verification_environment(temp_dir)
