#!/usr/bin/env python3
"""
Verifier for Verify Media Specifications task

This verifier checks if the agent successfully:
1. Accessed VLC's Media Information feature
2. Read the video specifications
3. Documented the findings correctly
"""

import sys
import os
import logging
import tempfile
import re

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_media_specifications(traj, env_info, task_info):
    """
    Verify media specifications documentation task completion.
    
    Checks:
    1. Verification document exists
    2. Document contains resolution information (1920x1080)
    3. Document contains video codec information (H.264/AVC)
    4. Document indicates audio presence
    5. Document shows approval/verification status
    
    Returns:
        dict: {passed: bool, score: int, feedback: str}
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_met = 0
    total_criteria = 5
    feedback_parts = []
    
    # Copy verification document from container
    temp_doc = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
    
    try:
        # Try to copy verification document
        try:
            copy_from_env("/tmp/vlc_verification_document.txt", temp_doc.name)
        except Exception as e:
            logger.error(f"Error copying verification document: {e}")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ Verification document not found or not accessible: {str(e)}"
            }
        
        # Read document content
        with open(temp_doc.name, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
        
        # Check if file is empty
        if not content or len(content.strip()) < 10:
            os.unlink(temp_doc.name)
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ Verification document is empty or too short. Did you document your findings?"
            }
        
        criteria_met += 1
        feedback_parts.append("✅ Verification document exists and has content")
        
        # Convert to lowercase for easier matching
        content_lower = content.lower()
        
        # Criterion 2: Check for resolution (1920x1080)
        # Match patterns like: 1920x1080, 1920×1080, 1920 x 1080, 1920*1080
        resolution_patterns = [
            r'1920\s*[x×*]\s*1080',
            r'1080p',
            r'resolution.*1920.*1080',
            r'1920.*1080'
        ]
        
        resolution_found = False
        for pattern in resolution_patterns:
            if re.search(pattern, content_lower):
                resolution_found = True
                break
        
        if resolution_found:
            criteria_met += 1
            feedback_parts.append("✅ Resolution (1920x1080) documented correctly")
        else:
            feedback_parts.append("❌ Resolution (1920x1080) not found in verification document")
        
        # Criterion 3: Check for video codec (H.264/AVC)
        # Match patterns like: h.264, h264, avc, x264
        codec_patterns = [
            r'h\.264',
            r'h264',
            r'\bavc\b',
            r'x264',
            r'codec.*h\.?264',
            r'video.*h\.?264'
        ]
        
        codec_found = False
        for pattern in codec_patterns:
            if re.search(pattern, content_lower):
                codec_found = True
                break
        
        if codec_found:
            criteria_met += 1
            feedback_parts.append("✅ Video codec (H.264) documented correctly")
        else:
            feedback_parts.append("❌ Video codec (H.264) not found in verification document")
        
        # Criterion 4: Check for audio presence documentation
        # Match patterns indicating audio is present
        audio_patterns = [
            r'audio.*present',
            r'audio.*yes',
            r'audio.*✓',
            r'audio.*√',
            r'audio.*found',
            r'audio.*detected',
            r'audio.*ok',
            r'audio.*available',
            r'aac',
            r'audio.*track',
            r'has audio'
        ]
        
        audio_found = False
        for pattern in audio_patterns:
            if re.search(pattern, content_lower):
                audio_found = True
                break
        
        if audio_found:
            criteria_met += 1
            feedback_parts.append("✅ Audio presence documented")
        else:
            feedback_parts.append("❌ Audio presence not documented clearly")
        
        # Criterion 5: Check for approval/verification status
        # Match patterns indicating approval or completion
        approval_patterns = [
            r'approved',
            r'accepted',
            r'verified',
            r'passed',
            r'✓',
            r'√',
            r'success',
            r'meets.*requirement',
            r'status.*ok',
            r'compliant'
        ]
        
        approval_found = False
        for pattern in approval_patterns:
            if re.search(pattern, content_lower):
                approval_found = True
                break
        
        if approval_found:
            criteria_met += 1
            feedback_parts.append("✅ Approval/verification status indicated")
        else:
            feedback_parts.append("❌ Approval status not clearly indicated")
        
        # Clean up temp file
        os.unlink(temp_doc.name)
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        if os.path.exists(temp_doc.name):
            os.unlink(temp_doc.name)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Error during verification: {str(e)}"
        }
    
    # Check for completion marker (optional, for additional context)
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_mediainfo_completed.txt", temp_marker.name)
        # Don't add to criteria, just informational
        logger.info("Task completion marker found")
        os.unlink(temp_marker.name)
    except Exception:
        logger.info("Completion marker not found (non-critical)")
    
    # Calculate score as percentage
    score = int((criteria_met / total_criteria) * 100)
    
    # Task passes if score >= 75% (at least 4 out of 5 criteria met)
    passed = score >= 75
    
    # Construct final feedback message
    feedback_header = f"{'✅ Task completed successfully!' if passed else '❌ Task incomplete'} (Score: {score}%)"
    feedback = f"{feedback_header}\n" + "\n".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }