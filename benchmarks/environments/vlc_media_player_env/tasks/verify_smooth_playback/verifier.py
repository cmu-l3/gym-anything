#!/usr/bin/env python3
"""
Verifier for Verify Smooth Playback task
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


def extract_number(text, patterns):
    """
    Extract a number from text using multiple regex patterns.
    
    Args:
        text: Text to search
        patterns: List of regex patterns to try
        
    Returns:
        Extracted number as int, or None if not found
    """
    for pattern in patterns:
        match = re.search(pattern, text, re.IGNORECASE)
        if match:
            try:
                return int(match.group(1))
            except (ValueError, IndexError):
                continue
    return None


def extract_duration(text):
    """
    Extract duration in seconds from text.
    
    Handles formats like:
    - "Duration tested: 35.2 seconds"
    - "Duration: 35s"
    - "Tested for 35.2s"
    """
    patterns = [
        r'duration[^:]*:\s*(\d+(?:\.\d+)?)\s*s',
        r'tested[^:]*:\s*(\d+(?:\.\d+)?)\s*s',
        r'(\d+(?:\.\d+)?)\s*seconds',
    ]
    
    for pattern in patterns:
        match = re.search(pattern, text, re.IGNORECASE)
        if match:
            try:
                return float(match.group(1))
            except (ValueError, IndexError):
                continue
    return None


def verify_smooth_playback(traj, env_info, task_info):
    """
    Verify smooth playback verification task completion.
    
    Checks:
    1. Report file exists and is parseable
    2. Playback duration is sufficient (≥30 seconds)
    3. Frame statistics are present and reasonable
    4. Drop rate is calculated and assessed
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_met = 0
    total_criteria = 4
    feedback_parts = []
    
    # Copy playback report
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
    
    try:
        try:
            copy_from_env("/tmp/vlc_playback_report.txt", temp_report.name)
        except Exception as e:
            logger.error(f"Error copying playback report: {e}")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Report file not found: {str(e)}"
            }
        
        # Read and parse report
        with open(temp_report.name, 'r') as f:
            report_content = f.read()
        
        logger.info(f"Report content:\n{report_content}")
        
        if not report_content.strip():
            return {
                "passed": False,
                "score": 0,
                "feedback": "Report file is empty"
            }
        
        criteria_met += 1
        feedback_parts.append("✅ Report file exists")
        
        # Extract metrics
        duration = extract_duration(report_content)
        
        decoded_patterns = [
            r'decoded[^:]*:\s*(\d+)',
            r'frames\s+decoded[^:]*:\s*(\d+)',
            r'input[^:]*:\s*(\d+)',
        ]
        decoded = extract_number(report_content, decoded_patterns)
        
        displayed_patterns = [
            r'displayed[^:]*:\s*(\d+)',
            r'frames\s+displayed[^:]*:\s*(\d+)',
            r'output[^:]*:\s*(\d+)',
        ]
        displayed = extract_number(report_content, displayed_patterns)
        
        dropped_patterns = [
            r'dropped[^:]*:\s*(\d+)',
            r'lost[^:]*:\s*(\d+)',
            r'frames?\s+(?:lost|dropped)[^:]*:\s*(\d+)',
        ]
        dropped = extract_number(report_content, dropped_patterns)
        
        # Criterion 2: Check playback duration
        if duration is not None:
            if duration >= 30:
                criteria_met += 1
                feedback_parts.append(f"✅ Sufficient duration: {duration:.1f}s")
            elif duration >= 20:
                criteria_met += 0.5
                feedback_parts.append(f"⚠️ Short duration: {duration:.1f}s (target: 30s)")
            else:
                feedback_parts.append(f"❌ Insufficient duration: {duration:.1f}s (need: 30s)")
        else:
            feedback_parts.append("⚠️ Duration not found in report")
        
        # Criterion 3: Check frame statistics are present
        stats_found = 0
        if decoded is not None:
            stats_found += 1
            feedback_parts.append(f"Decoded: {decoded}")
        if displayed is not None:
            stats_found += 1
            feedback_parts.append(f"Displayed: {displayed}")
        if dropped is not None:
            stats_found += 1
            feedback_parts.append(f"Dropped: {dropped}")
        
        if stats_found >= 2:
            criteria_met += 1
            feedback_parts.append("✅ Frame statistics present")
        elif stats_found >= 1:
            criteria_met += 0.5
            feedback_parts.append("⚠️ Incomplete frame statistics")
        else:
            feedback_parts.append("❌ Frame statistics missing")
        
        # Criterion 4: Calculate and assess drop rate
        if decoded is not None and decoded > 0:
            # Calculate dropped frames
            if dropped is not None:
                actual_dropped = dropped
            elif displayed is not None:
                actual_dropped = max(0, decoded - displayed)
            else:
                actual_dropped = None
            
            if actual_dropped is not None:
                drop_rate = (actual_dropped / decoded) * 100
                
                # Check if report includes verdict
                has_verdict = bool(re.search(r'smooth|verdict|performance|acceptable', report_content, re.IGNORECASE))
                
                if drop_rate < 1.0:
                    criteria_met += 1
                    if has_verdict:
                        feedback_parts.append(f"✅ Smooth playback verified: {drop_rate:.2f}% drops (with verdict)")
                    else:
                        feedback_parts.append(f"✅ Smooth playback: {drop_rate:.2f}% drops (verdict missing)")
                elif drop_rate < 5.0:
                    criteria_met += 0.7
                    feedback_parts.append(f"⚠️ Borderline playback: {drop_rate:.2f}% drops")
                else:
                    criteria_met += 0.4
                    feedback_parts.append(f"⚠️ Performance issues: {drop_rate:.2f}% drops")
            else:
                feedback_parts.append("⚠️ Cannot calculate drop rate")
        elif decoded is not None and decoded == 0:
            feedback_parts.append("❌ No frames decoded (video not played)")
        else:
            # Check for minimum frame count even without decoded count
            min_frames = 700  # ~30s at 25fps
            if displayed is not None and displayed >= min_frames:
                criteria_met += 0.5
                feedback_parts.append(f"⚠️ Partial credit: {displayed} frames displayed")
            else:
                feedback_parts.append("⚠️ Insufficient data to assess performance")
        
        os.unlink(temp_report.name)
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        if os.path.exists(temp_report.name):
            os.unlink(temp_report.name)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Error parsing report: {str(e)}"
        }
    
    # Check completion marker
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_playback_completed.txt", temp_marker.name)
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
        "feedback": feedback
    }