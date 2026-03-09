#!/usr/bin/env python3
"""
Verifier for Diagnose Playback Issue task
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


def verify_diagnose_playback_issue(traj, env_info, task_info):
    """
    Verify diagnose playback issue task completion.
    
    Checks:
    1. Diagnostic report file exists
    2. Report contains file reference
    3. Report contains container/format information
    4. Report contains video codec information
    5. Report contains resolution information
    6. Report identifies audio issue (missing/no audio)
    7. Report includes recommendation or problem description
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_met = 0
    total_criteria = 7
    feedback_parts = []
    
    # Copy diagnostic report
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
    
    try:
        copy_from_env("/tmp/diagnostic_report.txt", temp_report.name)
    except Exception as e:
        logger.error(f"Error copying diagnostic report: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Diagnostic report not found or inaccessible: {str(e)}"
        }
    
    # Read report content
    try:
        with open(temp_report.name, 'r', encoding='utf-8', errors='ignore') as f:
            report_content = f.read()
    except Exception as e:
        os.unlink(temp_report.name)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to read diagnostic report: {str(e)}"
        }
    
    # Check if report is too short or empty
    if len(report_content.strip()) < 50:
        os.unlink(temp_report.name)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Diagnostic report is too short or empty ({len(report_content)} chars)"
        }
    
    logger.info(f"Report length: {len(report_content)} characters")
    
    # Convert to lowercase for case-insensitive matching
    report_lower = report_content.lower()
    
    # Criterion 1: File reference (implicit - if report exists and has content, +1)
    criteria_met += 1
    feedback_parts.append("✅ Report exists")
    
    # Criterion 2: File reference - mentions the problem video
    if any(ref in report_lower for ref in ["problem_video", "problem video", ".mkv", "/home/ga/videos"]):
        criteria_met += 1
        feedback_parts.append("✅ File reference found")
    else:
        feedback_parts.append("⚠️ File reference not found")
    
    # Criterion 3: Container format information
    if any(fmt in report_lower for fmt in [
        "matroska", "mkv", "container", "format", "video format",
        "file format", "encapsulation"
    ]):
        criteria_met += 1
        feedback_parts.append("✅ Container format mentioned")
    else:
        feedback_parts.append("⚠️ Container format not mentioned")
    
    # Criterion 4: Video codec information
    if any(codec in report_lower for codec in [
        "h264", "h.264", "x264", "codec", "video codec", 
        "encoding", "avc", "mpeg"
    ]):
        criteria_met += 1
        feedback_parts.append("✅ Video codec mentioned")
    else:
        feedback_parts.append("⚠️ Video codec not mentioned")
    
    # Criterion 5: Resolution information
    if any(res in report_content for res in [
        "1280x720", "1280", "720", "720p"
    ]) or "resolution" in report_lower:
        criteria_met += 1
        feedback_parts.append("✅ Resolution mentioned")
    else:
        feedback_parts.append("⚠️ Resolution not mentioned")
    
    # Criterion 6: Audio issue identification (THE KEY PROBLEM)
    audio_issue_found = False
    audio_keywords = [
        "no audio", "missing audio", "audio track", "0 audio",
        "without audio", "lacks audio", "audio missing",
        "no sound", "missing sound", "sound track",
        "audio stream", "audio codec", "audio channels",
        "silent", "muted", "audio absent"
    ]
    
    # Check for explicit mentions of audio problem
    for keyword in audio_keywords:
        if keyword in report_lower:
            audio_issue_found = True
            break
    
    # Also check for patterns like "audio: none", "audio tracks: 0", etc.
    if not audio_issue_found:
        if ("audio" in report_lower and any(neg in report_lower for neg in [
            "none", "nil", "null", "0", "zero", "not found", "absent"
        ])):
            audio_issue_found = True
    
    if audio_issue_found:
        criteria_met += 1
        feedback_parts.append("✅ Audio issue identified")
    else:
        feedback_parts.append("❌ Audio issue not identified")
    
    # Criterion 7: Recommendation or problem description
    recommendation_found = False
    recommendation_keywords = [
        "recommend", "suggestion", "should", "needs", "requires",
        "problem", "issue", "error", "warning", "fault",
        "fix", "solution", "resolve", "re-encode", "reencode",
        "check", "verify", "missing", "add audio", "corrupt"
    ]
    
    for keyword in recommendation_keywords:
        if keyword in report_lower:
            recommendation_found = True
            break
    
    if recommendation_found:
        criteria_met += 1
        feedback_parts.append("✅ Recommendation/problem description included")
    else:
        feedback_parts.append("⚠️ Recommendation/problem description not found")
    
    # Clean up
    os.unlink(temp_report.name)
    
    # Check completion marker (optional, doesn't affect score)
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_diagnose_completed.txt", temp_marker.name)
        with open(temp_marker.name, 'r') as f:
            marker_content = f.read()
            if "Report found: true" in marker_content:
                feedback_parts.append("✅ Task completed")
        os.unlink(temp_marker.name)
    except Exception:
        feedback_parts.append("⚠️ Completion marker not found")
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 70
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": f"{feedback} | Score: {criteria_met}/{total_criteria} criteria"
    }
