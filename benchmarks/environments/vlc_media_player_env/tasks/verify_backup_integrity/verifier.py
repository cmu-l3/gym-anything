#!/usr/bin/env python3
"""
Verifier for Verify Backup Integrity task
"""

import sys
import os
import logging
import tempfile
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


def verify_backup_integrity(traj, env_info, task_info):
    """
    Verify backup integrity verification task completion.
    
    Checks:
    1. Verification report exists and has content
    2. Report mentions key metrics (size, duration, codec)
    3. Report includes clear assessment (PASS/FAIL or SAFE/NOT SAFE)
    4. Backup file is actually valid (independent check)
    5. Report mentions size comparison
    6. Report indicates playback was verified
    7. Report mentions metadata comparison
    8. End-to-end integrity check mentioned
    
    Pass threshold: 88% (7/8 criteria required)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_met = 0
    total_criteria = 8
    feedback_parts = []
    
    # Criterion 1: Verification report exists and has content
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
    
    try:
        copy_from_env("/tmp/vlc_backup_verification_report.txt", temp_report.name)
        
        with open(temp_report.name, 'r') as f:
            report_content = f.read()
        
        if not report_content or len(report_content) < 50:
            feedback_parts.append("❌ Report is empty or too short")
            os.unlink(temp_report.name)
            return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
        
        criteria_met += 1
        feedback_parts.append(f"✅ Report exists ({len(report_content)} chars)")
        
        # Convert report to lowercase for case-insensitive matching
        report_lower = report_content.lower()
        
        # Criterion 2: Report mentions size comparison
        size_keywords = ['size', 'byte', 'kb', 'mb', 'gb', 'file size']
        if any(keyword in report_lower for keyword in size_keywords):
            criteria_met += 1
            feedback_parts.append("✅ Report mentions size comparison")
        else:
            feedback_parts.append("⚠️ Report missing size comparison")
        
        # Criterion 3: Report mentions duration
        duration_keywords = ['duration', 'length', 'time', 'second', 'minute']
        if any(keyword in report_lower for keyword in duration_keywords):
            criteria_met += 1
            feedback_parts.append("✅ Report mentions duration")
        else:
            feedback_parts.append("⚠️ Report missing duration info")
        
        # Criterion 4: Report mentions codec or resolution
        metadata_keywords = ['codec', 'resolution', 'width', 'height', 'h264', 'mp4', 'mpeg', 'bitrate']
        if any(keyword in report_lower for keyword in metadata_keywords):
            criteria_met += 1
            feedback_parts.append("✅ Report mentions metadata (codec/resolution)")
        else:
            feedback_parts.append("⚠️ Report missing codec/resolution info")
        
        # Criterion 5: Report indicates playback was verified
        playback_keywords = ['playback', 'play', 'played', 'plays', 'vlc', 'watch', 'view']
        if any(keyword in report_lower for keyword in playback_keywords):
            criteria_met += 1
            feedback_parts.append("✅ Report mentions playback verification")
        else:
            feedback_parts.append("⚠️ Report missing playback verification")
        
        # Criterion 6: Report includes clear assessment
        assessment_pass = ['safe', 'pass', 'verified', 'ok', 'identical', 'match', 'valid', 'complete']
        assessment_fail = ['fail', 'not safe', 'not verified', 'corrupt', 'invalid', 'incomplete', 'differ']
        
        has_assessment = (any(keyword in report_lower for keyword in assessment_pass) or 
                         any(keyword in report_lower for keyword in assessment_fail))
        
        if has_assessment:
            criteria_met += 1
            # Check if it's a positive assessment
            is_positive = any(keyword in report_lower for keyword in assessment_pass)
            assessment_type = "SAFE" if is_positive else "NOT SAFE"
            feedback_parts.append(f"✅ Report has clear assessment ({assessment_type})")
        else:
            feedback_parts.append("⚠️ Report missing clear PASS/FAIL assessment")
        
        os.unlink(temp_report.name)
        
    except Exception as e:
        logger.error(f"Error reading verification report: {e}", exc_info=True)
        feedback_parts.append(f"❌ Could not read report: {str(e)}")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
    
    # Criterion 7: Independent verification - backup file is valid
    success, backup_info, error = setup_verification_environment(
        copy_from_env,
        "/tmp/vlc_backup_file.mp4",
        file_type='video'
    )
    
    if success:
        backup_data = backup_info.get('data', {})
        
        # Check backup file has valid properties
        if (backup_data.get('duration', 0) > 0 and 
            backup_data.get('width', 0) > 0 and
            backup_data.get('codec', '') != ''):
            criteria_met += 1
            feedback_parts.append(f"✅ Backup file valid ({backup_data.get('duration', 0):.1f}s, {backup_data.get('codec', 'unknown')})")
        else:
            feedback_parts.append("❌ Backup file appears invalid")
        
        cleanup_verification_environment(backup_info.get('temp_dir'))
    else:
        feedback_parts.append(f"⚠️ Could not verify backup file: {error}")
    
    # Criterion 8: Compare original and backup files match
    success_orig, orig_info, error_orig = setup_verification_environment(
        copy_from_env,
        "/tmp/vlc_original_file.mp4",
        file_type='video'
    )
    
    if success and success_orig:
        orig_data = orig_info.get('data', {})
        backup_data = backup_info.get('data', {})
        
        # Check if duration and resolution match
        duration_match = abs(orig_data.get('duration', 0) - backup_data.get('duration', 0)) < 0.5
        resolution_match = (orig_data.get('width') == backup_data.get('width') and 
                           orig_data.get('height') == backup_data.get('height'))
        codec_match = orig_data.get('codec') == backup_data.get('codec')
        
        if duration_match and resolution_match and codec_match:
            criteria_met += 1
            feedback_parts.append("✅ Original and backup files match (independent verification)")
        else:
            feedback_parts.append("⚠️ Files may not match perfectly (independent check)")
        
        cleanup_verification_environment(orig_info.get('temp_dir'))
    else:
        feedback_parts.append("⚠️ Could not independently compare files")
    
    # Check completion marker
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_backup_integrity_completed.txt", temp_marker.name)
        # Don't add to criteria, just log
        logger.info("Task completion marker found")
        os.unlink(temp_marker.name)
    except Exception:
        logger.warning("Completion marker not found")
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 88  # Requires 7/8 criteria (88%)
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "criteria_met": criteria_met,
        "total_criteria": total_criteria
    }