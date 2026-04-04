#!/usr/bin/env python3
"""
Verifier for Verify Audio Description Track task

This verifier checks if the agent successfully:
1. Opened the test video in VLC
2. Identified the audio description track
3. Selected the audio description track (Track 2)
4. Left VLC in a state where AD track is active
"""

import sys
import os
import logging
import tempfile
import json

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_audio_description_track(traj, env_info, task_info):
    """
    Verify audio description track selection task completion.
    
    Checks:
    1. VLC was running with correct video (from result data)
    2. Audio track was explicitly selected (not default)
    3. Track 2 (AD track) was selected
    4. Completion marker exists
    
    Args:
        traj: Trajectory data (not used directly)
        env_info: Environment info with copy_from_env function
        task_info: Task metadata (not used directly)
        
    Returns:
        Dict with:
            - passed (bool): Whether task passed
            - score (int): Score 0-100
            - feedback (str): Human-readable feedback
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available - cannot verify task"
        }
    
    criteria_met = 0
    total_criteria = 4
    feedback_parts = []
    
    # Copy audio description track result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    
    try:
        try:
            copy_from_env("/tmp/vlc_ad_track_result.json", temp_result.name)
        except Exception as e:
            logger.error(f"Error copying AD track result: {e}", exc_info=True)
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Result file not found - task may not have run: {str(e)}"
            }
        
        # Parse JSON result
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        
        logger.info(f"AD track result: {result}")
        
        # Extract data from result
        audio_track = result.get('audio_track', '')
        track_changed = result.get('track_changed', False)
        runtime_captured = result.get('runtime_captured', False)
        video_exists = result.get('video_exists', False)
        audio_track_count = result.get('audio_track_count', 0)
        source = result.get('source', 'unknown')
        
        # Criterion 1: Video was opened (video exists with multiple tracks)
        if video_exists and audio_track_count >= 2:
            criteria_met += 1
            feedback_parts.append(f"✅ Video file valid ({audio_track_count} audio tracks)")
        else:
            feedback_parts.append("❌ Video file not found or invalid")
        
        # Criterion 2: Audio track data was captured
        if audio_track and audio_track != '':
            feedback_parts.append(f"Audio track: {audio_track} [source: {source}]")
        else:
            feedback_parts.append("⚠️ Audio track data not captured")
        
        # Criterion 3: Track was explicitly changed (not default -1)
        if track_changed:
            criteria_met += 1
            feedback_parts.append("✅ Audio track explicitly selected (not default)")
        else:
            feedback_parts.append("❌ Audio track not changed from default")
        
        # Criterion 4: Correct track selected (Track 2 for AD)
        # VLC may number tracks as 0,1 (0-indexed) or 1,2 (1-indexed)
        # Track 2 could be represented as "1" (0-indexed) or "2" (1-indexed)
        # We accept either "1" or "2" as valid AD track selection
        if audio_track in ['1', '2']:
            criteria_met += 1
            feedback_parts.append(f"✅ Audio Description track selected (Track {audio_track})")
            
            # If track is "2", it's definitely correct (1-indexed Track 2)
            # If track is "1", it could be 0-indexed Track 2, which is also correct
            if audio_track == '2':
                # Bonus: definitely the AD track in 1-indexed system
                feedback_parts.append("✅ Confirmed: Track 2 (Audio Description)")
            elif audio_track == '1':
                # Could be 0-indexed Track 2 or 1-indexed Track 1
                # Given the task setup, Track 1 in 0-indexed = Track 2 = AD track
                feedback_parts.append("✅ Track 1 selected (likely 0-indexed Track 2 = AD)")
        elif audio_track == '0':
            # Track 0 is the main audio, not AD
            feedback_parts.append(f"❌ Wrong track selected: Track {audio_track} (Main Audio, not AD)")
        elif audio_track == '-1' or audio_track == '':
            feedback_parts.append("❌ No audio track selected (still at default)")
        else:
            feedback_parts.append(f"⚠️ Unexpected track value: {audio_track}")
        
        os.unlink(temp_result.name)
        
    except json.JSONDecodeError as e:
        logger.error(f"JSON parse error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Error parsing result JSON: {str(e)}"
        }
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    
    # Criterion 5: Check completion marker
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_ad_track_completed.txt", temp_marker.name)
        
        with open(temp_marker.name, 'r') as f:
            marker_content = f.read()
        
        if marker_content and len(marker_content) > 10:
            criteria_met += 1
            feedback_parts.append("✅ Task completed")
        else:
            feedback_parts.append("⚠️ Completion marker invalid")
        
        os.unlink(temp_marker.name)
        
    except Exception as e:
        logger.warning(f"Completion marker not found: {e}")
        feedback_parts.append("⚠️ Completion marker not found")
    
    # Calculate score
    # Weight the criteria appropriately:
    # - Video valid: 25%
    # - Track changed: 25%
    # - Correct track: 30%
    # - Completion: 20%
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 70
    
    # Build final feedback message
    feedback = " | ".join(feedback_parts)
    
    logger.info(f"Verification result: passed={passed}, score={score}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }