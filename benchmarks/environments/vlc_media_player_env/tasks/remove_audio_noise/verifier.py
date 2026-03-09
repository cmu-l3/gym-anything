#!/usr/bin/env python3
"""
Verifier for remove_audio_noise@1 task
Checks if the agent successfully applied audio filters to clean up the noisy recording
"""

import json
import logging
import os
import sys
import tempfile
from pathlib import Path
from typing import Dict, Tuple

# Add utils to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_remove_audio_noise(traj, env_info, task_info):
    """
    Verify the remove_audio_noise task.
    
    Args:
        traj: Trajectory information (not used directly here)
        env_info: Environment info containing copy_from_env function
        task_info: Task information (not used directly here)
        
    Returns:
        Dict with passed, score, and feedback
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Copy function not available"
        }

    criteria_met = 0
    total_criteria = 4
    feedback_parts = []
    
    # Criterion 1: Cleaned audio file exists
    cleaned_audio_path = tempfile.NamedTemporaryFile(delete=False, suffix='.mp3')
    cleaned_exists = False
    
    try:
        copy_from_env("/tmp/vlc_cleaned_audio.mp3", cleaned_audio_path.name)
        cleaned_exists = True
        criteria_met += 1
        feedback_parts.append("✅ Cleaned audio file exists")
        logger.info("✓ Cleaned audio file found")
    except Exception as e:
        feedback_parts.append("❌ Cleaned audio file not found")
        logger.error(f"Cleaned audio not found: {e}")
        
        # Early return if file doesn't exist
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Cleaned audio file not found at /home/ga/Music/cleaned_meeting.mp3. Did you save the filtered output?"
        }
    
    # Criterion 2: File is not empty and has reasonable size
    try:
        file_size_kb = os.path.getsize(cleaned_audio_path.name) / 1024
        
        if file_size_kb < 50:
            feedback_parts.append(f"❌ File too small ({file_size_kb:.1f} KB)")
            logger.error(f"File too small: {file_size_kb:.1f} KB")
            os.unlink(cleaned_audio_path.name)
            return {
                "passed": False,
                "score": 25,
                "feedback": f"❌ Cleaned audio file is too small ({file_size_kb:.1f} KB). It may be empty or corrupted."
            }
        
        if file_size_kb > 20000:  # > 20MB for 3 min audio is excessive
            feedback_parts.append(f"❌ File too large ({file_size_kb:.1f} KB)")
            logger.error(f"File too large: {file_size_kb:.1f} KB")
            os.unlink(cleaned_audio_path.name)
            return {
                "passed": False,
                "score": 25,
                "feedback": f"❌ Cleaned audio file is too large ({file_size_kb:.1f} KB). Something went wrong."
            }
        
        criteria_met += 1
        feedback_parts.append(f"✅ File size reasonable ({file_size_kb:.1f} KB)")
        logger.info(f"✓ File size is reasonable: {file_size_kb:.1f} KB")
    except Exception as e:
        feedback_parts.append(f"❌ Cannot check file size: {e}")
        logger.error(f"File size check failed: {e}")
    
    # Criterion 3: Audio file is valid and playable
    cleaned_info_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    
    try:
        copy_from_env("/tmp/cleaned_audio_info.json", cleaned_info_file.name)
        
        with open(cleaned_info_file.name, 'r') as f:
            cleaned_info = json.load(f)
        
        if 'streams' not in cleaned_info or len(cleaned_info['streams']) == 0:
            feedback_parts.append("❌ Audio file invalid (no streams)")
            logger.error("No audio streams found")
            os.unlink(cleaned_audio_path.name)
            os.unlink(cleaned_info_file.name)
            return {
                "passed": False,
                "score": 50,
                "feedback": "❌ Cleaned audio file is not valid - no audio streams found."
            }
        
        criteria_met += 1
        feedback_parts.append("✅ Audio file valid and playable")
        logger.info("✓ Cleaned audio is valid")
        
        # Check duration (should be ~180 seconds)
        if 'format' in cleaned_info and 'duration' in cleaned_info['format']:
            duration = float(cleaned_info['format']['duration'])
            logger.info(f"Cleaned audio duration: {duration:.1f}s")
            
            if duration < 170 or duration > 190:
                feedback_parts.append(f"❌ Duration mismatch ({duration:.1f}s, expected ~180s)")
                logger.error(f"Duration mismatch: {duration:.1f}s")
                os.unlink(cleaned_audio_path.name)
                os.unlink(cleaned_info_file.name)
                return {
                    "passed": False,
                    "score": 50,
                    "feedback": f"❌ Duration mismatch: expected ~180s, got {duration:.1f}s. Did you process the entire file?"
                }
            else:
                criteria_met += 1
                feedback_parts.append(f"✅ Duration preserved ({duration:.1f}s)")
                logger.info("✓ Duration preserved")
        else:
            feedback_parts.append("⚠️ Cannot verify duration")
            logger.warning("Duration not found in audio info")
        
        os.unlink(cleaned_info_file.name)
        
    except Exception as e:
        feedback_parts.append(f"⚠️ Cannot analyze audio: {e}")
        logger.error(f"Audio analysis failed: {e}")
    
    # Clean up
    if os.path.exists(cleaned_audio_path.name):
        os.unlink(cleaned_audio_path.name)
    
    # Calculate final score
    score = int((criteria_met / total_criteria) * 100)
    
    # Success criteria: all criteria must be met
    success = (criteria_met == total_criteria)
    
    if success:
        message = "✅ SUCCESS! Audio file cleaned and saved. The cleaned audio should have reduced 60Hz hum and background noise while preserving speech clarity."
        score = 100
    else:
        message = "❌ Task incomplete. " + " | ".join(feedback_parts)
    
    logger.info(f"Verification result: passed={success}, score={score}")
    logger.info(f"Criteria met: {criteria_met}/{total_criteria}")
    
    return {
        "passed": success,
        "score": score,
        "feedback": message
    }
