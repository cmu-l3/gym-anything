#!/usr/bin/env python3
"""
Verifier for Diagnose Compatibility Issue task

Checks if user successfully extracted video codec/format information
and documented it in a diagnostic report.
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


def verify_diagnose_compatibility(traj, env_info, task_info):
    """
    Verify diagnostic report was created with correct technical information.
    
    Checks:
    1. Report file exists and has reasonable content
    2. Report contains video codec (HEVC/H.265)
    3. Report contains resolution (1920x1080)
    4. Report contains audio codec (AAC)
    5. Report contains sample rate (48 kHz)
    
    Pass threshold: 3/4 technical details (75%)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_met = 0
    total_criteria = 4  # 4 main technical checks
    feedback_parts = []
    
    report_path_in_container = "/tmp/vlc_diagnostic_report.txt"
    
    # Copy report file from container
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+b')
    
    try:
        copy_from_env(report_path_in_container, temp_report.name)
    except Exception as e:
        logger.error(f"Error copying report file: {e}", exc_info=True)
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"❌ Report file not found at {report_path_in_container}. Did you save the diagnostic information to /home/ga/Documents/video_diagnostic_report.txt?"
        }
    
    # Check file exists and has content
    try:
        file_size = os.path.getsize(temp_report.name)
    except Exception as e:
        os.unlink(temp_report.name)
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "❌ Report file was not created or is inaccessible"
        }
    
    if file_size < 50:
        os.unlink(temp_report.name)
        return {
            "passed": False, 
            "score": 10, 
            "feedback": f"❌ Report file is too small ({file_size} bytes). It should contain detailed codec information. Minimum expected: ~100 bytes."
        }
    
    feedback_parts.append(f"✅ Report file exists ({file_size} bytes)")
    
    # Read report content
    try:
        with open(temp_report.name, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
    except Exception as e:
        os.unlink(temp_report.name)
        return {
            "passed": False, 
            "score": 10, 
            "feedback": f"❌ Could not read report file: {e}"
        }
    
    # Convert to lowercase for case-insensitive matching
    content_lower = content.lower()
    
    # Log content for debugging
    logger.info(f"Report content ({len(content)} chars):\n{content[:500]}")
    
    # Check for required information
    
    # Check 1: Video codec (HEVC/H.265/H265)
    video_codec_patterns = [
        r'hevc',
        r'h\.?265',
        r'h265',
        r'codec.*265',
        r'video.*hevc'
    ]
    
    video_codec_found = False
    for pattern in video_codec_patterns:
        if re.search(pattern, content_lower):
            video_codec_found = True
            criteria_met += 1
            feedback_parts.append("✅ Video codec identified (HEVC/H.265)")
            break
    
    if not video_codec_found:
        feedback_parts.append("❌ Video codec not found - should mention HEVC or H.265")
    
    # Check 2: Resolution (1920x1080 or 1920*1080 or "1920" and "1080" nearby)
    resolution_patterns = [
        r'1920\s*[x×*]\s*1080',
        r'1080\s*[x×*]\s*1920',
        r'1920.*1080',
        r'1080.*1920',
        r'width.*1920',
        r'height.*1080'
    ]
    
    resolution_found = False
    for pattern in resolution_patterns:
        if re.search(pattern, content_lower):
            resolution_found = True
            criteria_met += 1
            feedback_parts.append("✅ Video resolution documented (1920x1080)")
            break
    
    if not resolution_found:
        feedback_parts.append("❌ Resolution not found - should mention 1920x1080")
    
    # Check 3: Audio codec (AAC/MP4A/MPEG-4 Audio)
    audio_codec_patterns = [
        r'aac',
        r'mp4a',
        r'mpeg-?4\s+audio',
        r'audio.*aac',
        r'codec.*aac'
    ]
    
    audio_codec_found = False
    for pattern in audio_codec_patterns:
        if re.search(pattern, content_lower):
            audio_codec_found = True
            criteria_met += 1
            feedback_parts.append("✅ Audio codec identified (AAC)")
            break
    
    if not audio_codec_found:
        feedback_parts.append("❌ Audio codec not found - should mention AAC")
    
    # Check 4: Sample rate (48000/48.0/48 kHz/48000 Hz)
    sample_rate_patterns = [
        r'48000',
        r'48\.0',
        r'48\s*khz',
        r'48\s*000',
        r'sample.*48',
        r'rate.*48'
    ]
    
    sample_rate_found = False
    for pattern in sample_rate_patterns:
        if re.search(pattern, content_lower):
            sample_rate_found = True
            criteria_met += 1
            feedback_parts.append("✅ Audio sample rate documented (48 kHz)")
            break
    
    if not sample_rate_found:
        feedback_parts.append("❌ Audio sample rate not found - should mention 48000 Hz or 48 kHz")
    
    # Clean up temp file
    os.unlink(temp_report.name)
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    
    # Determine success (need at least 3/4 checks = 75%)
    passed = criteria_met >= 3
    
    # Build final feedback message
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\n📊 Diagnostic completeness: {criteria_met}/{total_criteria} required details found"
    
    if passed:
        feedback += "\n\n✅ Task successful! You've extracted the key diagnostic information."
        feedback += "\n💡 Insight: This video uses HEVC/H.265 codec, which many platforms don't support."
        feedback += "\n   Recommendation: Re-encode to H.264 (AVC) for broader compatibility."
        feedback += "\n   Command: ffmpeg -i input.mp4 -c:v libx264 -c:a copy output.mp4"
    else:
        feedback += "\n\n❌ Task incomplete. The diagnostic report should contain:"
        if not video_codec_found:
            feedback += "\n  • Video codec (look for 'Codec' field in VLC's Codec Information)"
        if not resolution_found:
            feedback += "\n  • Resolution (look for 'Video resolution' or dimensions)"
        if not audio_codec_found:
            feedback += "\n  • Audio codec (look for 'Audio' section in Codec Information)"
        if not sample_rate_found:
            feedback += "\n  • Sample rate (look for 'Sample rate' in Audio section)"
        feedback += "\n\n💡 Tip: In VLC, go to Tools → Codec Information (Ctrl+J) to see all technical details."
        feedback += "\n   You can also try Tools → Media Information (Ctrl+I) for more details."
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }
