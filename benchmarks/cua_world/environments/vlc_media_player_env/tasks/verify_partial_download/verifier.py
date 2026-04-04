#!/usr/bin/env python3
"""
Verifier for Verify Partial Download task
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


def parse_duration(duration_str):
    """
    Parse duration string in various formats to seconds.
    
    Supports:
    - "35:12" or "35:12.5" (MM:SS)
    - "1:35:12" (HH:MM:SS)
    - "35 minutes"
    - "2100 seconds"
    
    Returns:
        float: Duration in seconds, or None if unparseable
    """
    if not duration_str:
        return None
    
    duration_str = duration_str.strip().lower()
    
    # Try HH:MM:SS or MM:SS format
    time_match = re.search(r'(\d+):(\d+):(\d+(?:\.\d+)?)', duration_str)
    if time_match:
        hours, minutes, seconds = time_match.groups()
        return int(hours) * 3600 + int(minutes) * 60 + float(seconds)
    
    # Try MM:SS format
    time_match = re.search(r'(\d+):(\d+(?:\.\d+)?)', duration_str)
    if time_match:
        minutes, seconds = time_match.groups()
        return int(minutes) * 60 + float(seconds)
    
    # Try "X minutes" format
    min_match = re.search(r'(\d+(?:\.\d+)?)\s*min', duration_str)
    if min_match:
        return float(min_match.group(1)) * 60
    
    # Try "X seconds" format
    sec_match = re.search(r'(\d+(?:\.\d+)?)\s*sec', duration_str)
    if sec_match:
        return float(sec_match.group(1))
    
    # Try plain number (assume minutes if > 100, seconds otherwise)
    num_match = re.search(r'(\d+(?:\.\d+)?)', duration_str)
    if num_match:
        val = float(num_match.group(1))
        # If value is large, likely seconds; if small, likely minutes
        if val > 100:
            return val  # Assume seconds
        else:
            return val * 60  # Assume minutes
    
    return None


def extract_report_data(report_content):
    """
    Extract key information from the report.
    
    Returns:
        dict with keys: reported_duration, playable_duration, status, recommendation
    """
    data = {
        'reported_duration': None,
        'playable_duration': None,
        'status': None,
        'recommendation': None
    }
    
    lines = report_content.split('\n')
    
    for i, line in enumerate(lines):
        line_lower = line.lower()
        
        # Look for reported duration
        if 'reported duration' in line_lower or 'total duration' in line_lower or 'shown duration' in line_lower:
            # Extract duration from this line or next line
            duration_str = line.split(':', 1)[-1] if ':' in line else ''
            if not duration_str.strip() and i + 1 < len(lines):
                duration_str = lines[i + 1]
            data['reported_duration'] = parse_duration(duration_str)
        
        # Look for playable/actual duration
        if ('playable duration' in line_lower or 
            'actual duration' in line_lower or 
            'tested duration' in line_lower or
            'working duration' in line_lower):
            duration_str = line.split(':', 1)[-1] if ':' in line else ''
            if not duration_str.strip() and i + 1 < len(lines):
                duration_str = lines[i + 1]
            data['playable_duration'] = parse_duration(duration_str)
        
        # Look for status
        if 'status' in line_lower or 'file status' in line_lower:
            status_text = line.split(':', 1)[-1] if ':' in line else ''
            if not status_text.strip() and i + 1 < len(lines):
                status_text = lines[i + 1]
            data['status'] = status_text.strip().lower()
        
        # Look for recommendation
        if 'recommendation' in line_lower or 'suggest' in line_lower or 'advice' in line_lower:
            rec_text = line.split(':', 1)[-1] if ':' in line else ''
            if not rec_text.strip() and i + 1 < len(lines):
                rec_text = lines[i + 1]
            data['recommendation'] = rec_text.strip()
    
    # If status not explicitly labeled, search for keywords anywhere
    if not data['status']:
        content_lower = report_content.lower()
        if 'incomplete' in content_lower or 'truncated' in content_lower:
            data['status'] = 'incomplete'
        elif 'corrupt' in content_lower or 'damaged' in content_lower:
            data['status'] = 'corrupted'
    
    return data


def verify_partial_download(traj, env_info, task_info):
    """
    Verify partial download analysis task completion.
    
    Checks:
    1. Report file exists and is readable
    2. Playable duration is accurate (within ±2 minutes of actual ~35 min)
    3. Status correctly identifies file as incomplete/truncated
    4. Recommendation is present and reasonable
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_met = 0
    total_criteria = 4
    feedback_parts = []
    
    # Get ground truth duration
    ground_truth_duration = 2100.0  # 35 minutes in seconds (default)
    temp_ground_truth = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_partial_ground_truth.txt", temp_ground_truth.name)
        with open(temp_ground_truth.name, 'r') as f:
            content = f.read().strip()
            if content:
                ground_truth_duration = float(content)
        os.unlink(temp_ground_truth.name)
    except Exception as e:
        logger.warning(f"Could not get ground truth duration, using default 2100s: {e}")
    
    ground_truth_minutes = ground_truth_duration / 60
    logger.info(f"Ground truth playable duration: {ground_truth_minutes:.1f} minutes")
    
    # Criterion 1: Report exists and is readable
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
    
    try:
        copy_from_env("/tmp/vlc_partial_download_report.txt", temp_report.name)
        
        with open(temp_report.name, 'r') as f:
            report_content = f.read()
        
        if not report_content.strip() or "No report created" in report_content:
            os.unlink(temp_report.name)
            return {"passed": False, "score": 0, "feedback": "Report file not created"}
        
        criteria_met += 1
        feedback_parts.append("✅ Report exists and is readable")
        
        # Parse report data
        data = extract_report_data(report_content)
        
        logger.info(f"Extracted data: {data}")
        
        # Criterion 2: Playable duration is accurate
        if data['playable_duration'] is not None:
            playable_minutes = data['playable_duration'] / 60
            error_minutes = abs(playable_minutes - ground_truth_minutes)
            
            feedback_parts.append(f"Playable duration: {playable_minutes:.1f} min (ground truth: {ground_truth_minutes:.1f} min)")
            
            if error_minutes <= 2.0:  # Within ±2 minutes
                criteria_met += 1
                feedback_parts.append(f"✅ Duration accurate (±{error_minutes:.1f} min)")
            elif error_minutes <= 5.0:  # Partial credit
                criteria_met += 0.5
                feedback_parts.append(f"⚠️ Duration somewhat accurate (±{error_minutes:.1f} min, expected ±2 min)")
            else:
                feedback_parts.append(f"❌ Duration inaccurate (±{error_minutes:.1f} min)")
        else:
            feedback_parts.append("❌ Playable duration not found in report")
        
        # Criterion 3: Status correctly identifies incomplete/truncated
        if data['status']:
            if 'incomplete' in data['status'] or 'truncat' in data['status']:
                criteria_met += 1
                feedback_parts.append(f"✅ Status correct: {data['status']}")
            elif 'corrupt' in data['status']:
                criteria_met += 0.5  # Partial credit - wrong but reasonable
                feedback_parts.append(f"⚠️ Status identifies problem but incorrect type: {data['status']}")
            else:
                feedback_parts.append(f"⚠️ Status unclear: {data['status']}")
        else:
            feedback_parts.append("❌ File status not identified")
        
        # Criterion 4: Recommendation present
        if data['recommendation'] and len(data['recommendation']) > 10:
            criteria_met += 1
            feedback_parts.append(f"✅ Recommendation provided")
        else:
            feedback_parts.append("❌ Recommendation missing or too brief")
        
        os.unlink(temp_report.name)
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Error reading report: {str(e)}"}
    
    # Check completion marker (bonus, not counted in criteria)
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_partial_download_completed.txt", temp_marker.name)
        feedback_parts.append("✅ Task completed")
        os.unlink(temp_marker.name)
    except Exception:
        pass  # Not critical
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }