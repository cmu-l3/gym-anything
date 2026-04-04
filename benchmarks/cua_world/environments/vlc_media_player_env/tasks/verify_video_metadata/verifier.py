#!/usr/bin/env python3
"""
Verifier for Verify Video Metadata task
"""

import sys
import os
import logging
import tempfile
import json
import re

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import get_video_info

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def extract_number_from_text(text, pattern, default=None):
    """Extract a number from text using regex pattern."""
    match = re.search(pattern, text, re.IGNORECASE)
    if match:
        return match.group(1)
    return default


def check_field_in_report(report_text, expected_value, field_name, tolerance=None):
    """
    Check if a field value appears in the report text.
    
    Args:
        report_text: The full report text
        expected_value: The expected value (can be string or number)
        field_name: Name of the field for feedback
        tolerance: For numeric values, tolerance for matching
    
    Returns:
        Tuple of (found, feedback_message)
    """
    report_lower = report_text.lower()
    expected_str = str(expected_value).lower()
    
    # For simple string matching
    if isinstance(expected_value, str):
        # Try exact match
        if expected_str in report_lower:
            return True, f"✅ {field_name} correct: {expected_value}"
        
        # Try partial match (for paths, etc.)
        parts = expected_str.split('/')
        if any(part in report_lower for part in parts if len(part) > 3):
            return True, f"✅ {field_name} documented: {expected_value}"
        
        return False, f"❌ {field_name} missing or incorrect (expected: {expected_value})"
    
    # For numeric values with tolerance
    elif isinstance(expected_value, (int, float)) and tolerance:
        # Try to find the number in the text
        number_patterns = [
            rf'\b{expected_value}\b',  # Exact match
            rf'\b{int(expected_value)}\b',  # Integer version
            rf'\b{expected_value:.1f}\b',  # One decimal
        ]
        
        for pattern in number_patterns:
            if re.search(pattern, report_text):
                return True, f"✅ {field_name} documented: {expected_value}"
        
        # Check within tolerance range
        min_val = expected_value - tolerance
        max_val = expected_value + tolerance
        
        # Look for any number in reasonable range
        numbers = re.findall(r'\b\d+\.?\d*\b', report_text)
        for num_str in numbers:
            try:
                num = float(num_str)
                if min_val <= num <= max_val:
                    return True, f"✅ {field_name} documented (within tolerance): {num}"
            except ValueError:
                continue
        
        return False, f"❌ {field_name} not found (expected ~{expected_value})"
    
    return False, f"⚠️ Could not verify {field_name}"


def verify_metadata_extraction(traj, env_info, task_info):
    """
    Verify video metadata extraction task completion.
    
    Checks:
    1. Report file exists and has substantial content
    2. Codec correctly identified
    3. Resolution correctly documented
    4. Duration correctly recorded
    5. Multiple metadata fields present
    6. Overall completeness and accuracy
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_met = 0
    max_criteria = 100  # Use points system
    feedback_parts = []
    
    # Copy the report file
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
    
    try:
        copy_from_env("/tmp/vlc_verification_report.txt", temp_report.name)
    except Exception as e:
        logger.error(f"Error copying report: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification report not found: {str(e)}"}
    
    # Read report content
    try:
        with open(temp_report.name, 'r', encoding='utf-8', errors='ignore') as f:
            report_content = f.read()
    except Exception as e:
        os.unlink(temp_report.name)
        return {"passed": False, "score": 0, "feedback": f"Error reading report: {str(e)}"}
    
    # Criterion 1: Report has substantial content (10 points)
    if len(report_content) < 100:
        feedback_parts.append("❌ Report too brief (< 100 characters)")
        os.unlink(temp_report.name)
        return {"passed": False, "score": 10, "feedback": " | ".join(feedback_parts)}
    elif len(report_content) < 500:
        criteria_met += 5
        feedback_parts.append(f"⚠️ Report brief ({len(report_content)} chars)")
    else:
        criteria_met += 10
        feedback_parts.append(f"✅ Report has content ({len(report_content)} chars)")
    
    # Copy ground truth data
    temp_ground_truth = tempfile.NamedTemporaryFile(delete=False, suffix='.json', mode='w+')
    ground_truth = {}
    
    try:
        copy_from_env("/tmp/vlc_ground_truth.json", temp_ground_truth.name)
        with open(temp_ground_truth.name, 'r') as f:
            ground_truth = json.load(f)
    except Exception as e:
        logger.warning(f"Could not load ground truth: {e}")
        # Fallback: try to get info from copied video
        temp_video = tempfile.NamedTemporaryFile(delete=False, suffix='.mp4')
        try:
            copy_from_env("/tmp/vlc_source_video.mp4", temp_video.name)
            ground_truth_info = get_video_info(temp_video.name)
            
            if 'error' not in ground_truth_info:
                # Convert to format similar to ffprobe output
                ground_truth = {
                    'format': {
                        'duration': str(ground_truth_info.get('duration', 0)),
                        'format_name': ground_truth_info.get('format', ''),
                    },
                    'streams': [{
                        'codec_name': ground_truth_info.get('codec', ''),
                        'width': ground_truth_info.get('width', 0),
                        'height': ground_truth_info.get('height', 0),
                        'r_frame_rate': f"{ground_truth_info.get('fps', 30)}/1",
                    }]
                }
            os.unlink(temp_video.name)
        except Exception as e2:
            logger.error(f"Fallback ground truth extraction failed: {e2}")
    
    if temp_ground_truth:
        try:
            os.unlink(temp_ground_truth.name)
        except:
            pass
    
    # Extract ground truth values
    video_stream = None
    if 'streams' in ground_truth:
        for stream in ground_truth['streams']:
            if stream.get('codec_type') == 'video' or 'codec_name' in stream:
                video_stream = stream
                break
    
    format_info = ground_truth.get('format', {})
    
    # Criterion 2: Codec identification (15 points)
    if video_stream:
        codec = video_stream.get('codec_name', '').lower()
        if codec:
            found, feedback = check_field_in_report(report_content, codec, "Codec")
            if found:
                criteria_met += 15
            else:
                criteria_met += 0
            feedback_parts.append(feedback)
    
    # Criterion 3: Resolution (15 points)
    if video_stream:
        width = video_stream.get('width', 0)
        height = video_stream.get('height', 0)
        
        if width and height:
            resolution_str = f"{width}x{height}"
            resolution_alt = f"{width} x {height}"
            
            # Check for resolution in various formats
            report_lower = report_content.lower()
            if (resolution_str in report_content or 
                resolution_alt in report_content or
                (str(width) in report_content and str(height) in report_content)):
                criteria_met += 15
                feedback_parts.append(f"✅ Resolution correct: {resolution_str}")
            else:
                feedback_parts.append(f"❌ Resolution missing (expected: {resolution_str})")
    
    # Criterion 4: Duration (10 points)
    duration_str = format_info.get('duration', '')
    if duration_str:
        try:
            duration = float(duration_str)
            found, feedback = check_field_in_report(report_content, duration, "Duration", tolerance=2.0)
            if found:
                criteria_met += 10
            feedback_parts.append(feedback)
        except ValueError:
            pass
    
    # Criterion 5: Framerate (10 points)
    if video_stream:
        fps_str = video_stream.get('r_frame_rate', '')
        if fps_str and '/' in fps_str:
            try:
                num, den = map(int, fps_str.split('/'))
                fps = num / den if den > 0 else 30
                
                # Check for fps mention
                if 'fps' in report_content.lower() or 'frame' in report_content.lower():
                    criteria_met += 10
                    feedback_parts.append(f"✅ Framerate documented")
                else:
                    feedback_parts.append("⚠️ Framerate not mentioned")
            except:
                pass
    
    # Criterion 6: Bitrate or format info (10 points)
    if 'bitrate' in report_content.lower() or 'kbps' in report_content.lower() or 'mbps' in report_content.lower():
        criteria_met += 5
        feedback_parts.append("✅ Bitrate information included")
    
    if 'mp4' in report_content.lower() or 'format' in report_content.lower():
        criteria_met += 5
        feedback_parts.append("✅ Format mentioned")
    
    # Criterion 7: Metadata fields (20 points)
    metadata_keywords = ['creation', 'date', 'time', 'timestamp', 'encoder', 'metadata', 'title', 'comment']
    found_keywords = sum(1 for keyword in metadata_keywords if keyword in report_content.lower())
    
    if found_keywords >= 4:
        criteria_met += 20
        feedback_parts.append(f"✅ Comprehensive metadata ({found_keywords} categories)")
    elif found_keywords >= 2:
        criteria_met += 10
        feedback_parts.append(f"⚠️ Some metadata documented ({found_keywords} categories)")
    else:
        feedback_parts.append(f"❌ Limited metadata extraction ({found_keywords} categories)")
    
    # Criterion 8: Verification analysis (10 points bonus)
    analysis_keywords = ['verify', 'authentic', 'claim', 'contradict', 'match', 'discrepancy', 'analysis', 'conclusion']
    if any(keyword in report_content.lower() for keyword in analysis_keywords):
        criteria_met += 10
        feedback_parts.append("✅ Includes verification analysis (bonus)")
    
    os.unlink(temp_report.name)
    
    # Calculate final score
    score = min(criteria_met, 100)
    passed = score >= 70
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }