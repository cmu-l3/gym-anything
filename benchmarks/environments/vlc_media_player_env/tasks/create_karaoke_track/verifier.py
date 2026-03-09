#!/usr/bin/env python3
"""
Verifier for Create Karaoke Track task

Checks if vocal reduction was successfully applied by:
1. Verifying output file exists
2. Validating audio properties
3. Checking duration matches input
4. Ensuring stereo format is maintained
"""

import sys
import os
import logging
import tempfile
from pathlib import Path

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import (
    get_audio_info,
    setup_verification_environment,
    cleanup_verification_environment
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_create_karaoke_track(traj, env_info, task_info):
    """
    Verify the karaoke track creation task.
    
    Checks:
    1. Output file exists (30 points)
    2. Output file is valid audio with correct codec (30 points)
    3. Duration matches input within tolerance (20 points)
    4. Stereo format maintained (20 points)
    
    Pass threshold: 80%
    """
    
    logger.info("=" * 60)
    logger.info("Verifying create_karaoke_track@1")
    logger.info("=" * 60)
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Copy function not available"
        }
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # Check if "not created" flag exists
    temp_flag = tempfile.NamedTemporaryFile(delete=False, suffix='.flag')
    try:
        copy_from_env("/tmp/vlc_karaoke_not_created.flag", temp_flag.name)
        os.unlink(temp_flag.name)
        logger.error("Karaoke version was not created")
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Karaoke version file was not created"
        }
    except Exception:
        # Flag doesn't exist, which is good - continue verification
        pass
    
    # Criterion 1: Check if karaoke output exists (30 points)
    temp_karaoke = tempfile.NamedTemporaryFile(delete=False, suffix='.mp3')
    try:
        copy_from_env("/tmp/vlc_karaoke_output.mp3", temp_karaoke.name)
        
        # Check file size
        file_size = os.path.getsize(temp_karaoke.name)
        file_size_kb = file_size / 1024
        
        if file_size < 1024:  # Less than 1 KB
            logger.error(f"Karaoke file too small: {file_size_kb:.1f} KB")
            feedback_parts.append(f"❌ Output file too small ({file_size_kb:.1f} KB)")
            os.unlink(temp_karaoke.name)
            return {
                "passed": False,
                "score": 10,
                "feedback": " | ".join(feedback_parts)
            }
        
        score += 30
        logger.info(f"✅ Karaoke file exists ({file_size_kb:.1f} KB)")
        feedback_parts.append(f"✅ File exists ({file_size_kb:.1f} KB)")
        
    except Exception as e:
        logger.error(f"Karaoke output file not found: {e}")
        feedback_parts.append("❌ Karaoke output file not found")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts)
        }
    
    # Criterion 2: Validate audio properties (30 points)
    karaoke_info = get_audio_info(temp_karaoke.name)
    
    if 'error' in karaoke_info:
        logger.error(f"Karaoke file is not valid audio: {karaoke_info['error']}")
        feedback_parts.append(f"❌ Invalid audio file: {karaoke_info['error']}")
        os.unlink(temp_karaoke.name)
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
    
    # Check codec
    codec = karaoke_info.get('codec', 'unknown')
    if codec in ['mp3', 'mp3float', 'aac', 'vorbis']:
        score += 15
        logger.info(f"✅ Valid audio codec: {codec}")
        feedback_parts.append(f"✅ Codec: {codec}")
    else:
        logger.warning(f"Unexpected codec: {codec}")
        feedback_parts.append(f"⚠️ Codec: {codec}")
        score += 5
    
    # Check sample rate
    sample_rate = karaoke_info.get('sample_rate', 0)
    if sample_rate >= 44100:
        score += 15
        logger.info(f"✅ Sample rate: {sample_rate} Hz")
        feedback_parts.append(f"✅ Sample rate: {sample_rate} Hz")
    elif sample_rate > 0:
        logger.warning(f"Low sample rate: {sample_rate} Hz")
        feedback_parts.append(f"⚠️ Low sample rate: {sample_rate} Hz")
        score += 8
    else:
        logger.error("Sample rate not detected")
        feedback_parts.append("❌ Sample rate not detected")
    
    # Criterion 3: Check duration matches input (20 points)
    karaoke_duration = karaoke_info.get('duration', 0)
    
    if karaoke_duration <= 0:
        logger.error("Duration not detected")
        feedback_parts.append("❌ Duration not detected")
    else:
        logger.info(f"Karaoke duration: {karaoke_duration:.1f}s")
        
        # Get original file duration for comparison
        temp_original = tempfile.NamedTemporaryFile(delete=False, suffix='.mp3')
        try:
            copy_from_env("/tmp/vlc_karaoke_original.mp3", temp_original.name)
            original_info = get_audio_info(temp_original.name)
            original_duration = original_info.get('duration', 30.0)  # Default to 30s
            
            duration_diff = abs(karaoke_duration - original_duration)
            
            if duration_diff < 2.0:
                score += 20
                logger.info(f"✅ Duration matches original (diff: {duration_diff:.2f}s)")
                feedback_parts.append(f"✅ Duration: {karaoke_duration:.1f}s (matches original)")
            elif duration_diff < 5.0:
                score += 10
                logger.warning(f"Duration slightly off (diff: {duration_diff:.2f}s)")
                feedback_parts.append(f"⚠️ Duration: {karaoke_duration:.1f}s (diff: {duration_diff:.2f}s)")
            else:
                logger.warning(f"Duration differs significantly (diff: {duration_diff:.2f}s)")
                feedback_parts.append(f"⚠️ Duration differs from original ({duration_diff:.2f}s diff)")
            
            os.unlink(temp_original.name)
            
        except Exception as e:
            logger.warning(f"Could not compare with original: {e}")
            # Still give partial credit if duration is reasonable (25-35 seconds)
            if 25 <= karaoke_duration <= 35:
                score += 10
                feedback_parts.append(f"⚠️ Duration: {karaoke_duration:.1f}s (original not available)")
            else:
                feedback_parts.append(f"❌ Duration: {karaoke_duration:.1f}s (seems wrong)")
    
    # Criterion 4: Check stereo format (20 points)
    channels = karaoke_info.get('channels', 0)
    
    if channels == 2:
        score += 20
        logger.info("✅ Stereo format maintained (2 channels)")
        feedback_parts.append("✅ Stereo (2ch)")
    elif channels == 1:
        score += 5
        logger.warning("Audio is mono instead of stereo")
        feedback_parts.append("⚠️ Mono (should be stereo)")
    else:
        logger.error(f"Unexpected channel count: {channels}")
        feedback_parts.append(f"❌ Channels: {channels}")
    
    # Clean up
    os.unlink(temp_karaoke.name)
    
    # Check completion marker (bonus, doesn't affect score)
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_karaoke_completed.txt", temp_marker.name)
        logger.info("✅ Task completion marker found")
        os.unlink(temp_marker.name)
    except Exception:
        logger.warning("⚠️ Completion marker not found")
    
    # Final assessment
    passed = score >= 80
    
    # Create final feedback
    if passed:
        final_feedback = f"✅ Karaoke track successfully created! Score: {score}/{max_score}"
    else:
        final_feedback = f"❌ Karaoke track incomplete or incorrect. Score: {score}/{max_score}"
    
    feedback_with_details = final_feedback + " | " + " | ".join(feedback_parts)
    
    logger.info("=" * 60)
    logger.info(f"Final Score: {score}/{max_score}")
    logger.info(f"Passed: {passed}")
    logger.info("=" * 60)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback_with_details
    }