#!/usr/bin/env python3
"""
Verifier for Verify Recording Integrity task
"""

import sys
import os
import logging
import tempfile
import re
import json

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import (
    get_video_info,
    setup_verification_environment,
    cleanup_verification_environment
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_recording_integrity(traj, env_info, task_info):
    """
    Verify recording integrity task completion.
    
    Checks:
    1. Report file exists and has content
    2. Report mentions correct resolution (1920x1080)
    3. Report mentions framerate check (30fps)
    4. Report acknowledges 2 audio tracks
    5. Report identifies low volume issue
    6. Report specifies Track 2 or microphone
    7. Report provides recommendation
    8. Report includes overall assessment
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_met = 0
    total_criteria = 8
    feedback_parts = []
    
    # Stage 1: Copy and check report file
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
    
    try:
        copy_from_env("/tmp/vlc_recording_verification_report.txt", temp_report.name)
        
        with open(temp_report.name, 'r') as f:
            report_content = f.read()
        
        if len(report_content) < 50:
            os.unlink(temp_report.name)
            return {
                "passed": False,
                "score": 0,
                "feedback": "Report file is empty or too short (< 50 chars)"
            }
        
        criteria_met += 1
        feedback_parts.append("✅ Report file created")
        
        # Convert to lowercase for easier matching
        report_lower = report_content.lower()
        
        # Stage 2: Independent verification of recording file
        # Verify the recording actually has the correct properties
        logger.info("Independently verifying recording file...")
        success, file_info, error = setup_verification_environment(
            copy_from_env,
            "/home/ga/Videos/gameplay_recording.mkv",
            file_type='video'
        )
        
        recording_verified = False
        
        if success:
            video_data = file_info.get('data', {})
            logger.info(f"Recording file info: {video_data}")
            
            # Check basic properties
            correct_resolution = (video_data.get('width') == 1920 and 
                                video_data.get('height') == 1080)
            correct_fps = video_data.get('fps', 0) >= 29.5  # Allow slight tolerance
            correct_codec = 'h264' in video_data.get('codec', '').lower()
            
            recording_verified = correct_resolution and correct_fps and correct_codec
            
            cleanup_verification_environment(file_info.get('temp_dir'))
            
            if recording_verified:
                logger.info("✅ Recording file has correct properties")
            else:
                logger.warning(f"⚠️ Recording verification: res={correct_resolution}, fps={correct_fps}, codec={correct_codec}")
        else:
            logger.error(f"❌ Could not verify recording file: {error}")
        
        # Stage 3: Parse report content
        
        # Criterion 2: Resolution mentioned
        if '1920' in report_content and '1080' in report_content:
            criteria_met += 1
            feedback_parts.append("✅ Resolution verified (1920x1080)")
        else:
            feedback_parts.append("❌ Resolution not mentioned")
        
        # Criterion 3: Framerate mentioned
        if re.search(r'30\s*fps|30\s*FPS|framerate|frame rate|frame.*30', report_lower):
            criteria_met += 1
            feedback_parts.append("✅ Framerate verified")
        else:
            feedback_parts.append("❌ Framerate not mentioned")
        
        # Criterion 4: Audio tracks counted
        audio_track_mentioned = False
        # Look for "2" or "two" near audio/track mentions
        if re.search(r'(2|two)\s*(audio|track)', report_lower) or \
           re.search(r'(audio|track)[^\n]{0,30}(2|two)', report_lower):
            criteria_met += 1
            audio_track_mentioned = True
            feedback_parts.append("✅ Audio track count verified")
        
        if not audio_track_mentioned:
            feedback_parts.append("❌ Audio track count not mentioned")
        
        # Criterion 5: Issue detected (general)
        issue_keywords = [
            'low volume', 'quiet', 'muted', 'low audio', 
            'issue', 'problem', 'warning', 'detected',
            'very low', 'no volume', 'inaudible', 'silent',
            'not recording', 'no sound', 'audio problem'
        ]
        issue_detected = any(kw in report_lower for kw in issue_keywords)
        
        if issue_detected:
            criteria_met += 1
            feedback_parts.append("✅ Audio issue identified")
        else:
            feedback_parts.append("❌ Audio issue not identified")
        
        # Criterion 6: Specific track identified
        track_keywords = [
            'track 2', 'track two', 'second track',
            'microphone', 'mic', 'audio 2', 'audio track 2',
            'track two', 'channel 2'
        ]
        
        if any(kw in report_lower for kw in track_keywords):
            criteria_met += 1
            feedback_parts.append("✅ Specific track identified (Track 2/Mic)")
        else:
            feedback_parts.append("❌ Specific track not identified")
        
        # Criterion 7: Recommendation provided
        rec_keywords = [
            're-record', 'rerecord', 're record',
            'fix', 'check', 'adjust', 'increase',
            'recommendation', 'suggest', 'should',
            'need to', 'must', 'correct', 'before',
            'input level', 'settings'
        ]
        
        if any(kw in report_lower for kw in rec_keywords):
            criteria_met += 1
            feedback_parts.append("✅ Recommendation provided")
        else:
            feedback_parts.append("❌ No recommendation")
        
        # Criterion 8: Overall assessment
        status_keywords = [
            'status', 'overall', 'result', 'conclusion',
            'needs attention', 'pass', 'fail', 'failed',
            'acceptable', 'unacceptable', 'ready', 'not ready',
            'verdict', 'assessment'
        ]
        
        if any(kw in report_lower for kw in status_keywords):
            criteria_met += 1
            feedback_parts.append("✅ Overall assessment included")
        else:
            feedback_parts.append("❌ No overall assessment")
        
        os.unlink(temp_report.name)
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        try:
            os.unlink(temp_report.name)
        except:
            pass
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Error reading report: {str(e)}"
        }
    
    # Check completion marker
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_verify_recording_completed.txt", temp_marker.name)
        feedback_parts.append("✅ Task completed marker found")
        os.unlink(temp_marker.name)
    except Exception:
        feedback_parts.append("⚠️ Completion marker missing")
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75  # Need 6/8 criteria
    
    # Add final summary
    feedback_parts.insert(0, f"Score: {criteria_met}/{total_criteria} ({score}%)")
    
    if passed:
        feedback_parts.insert(1, "✅ PASSED")
    else:
        feedback_parts.insert(1, "❌ FAILED")
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }