#!/usr/bin/env python3
"""
Verifier for Setup A-B Loop Practice task

Checks:
1. Confirmation file exists with loop parameters
2. Loop boundaries are within tolerance (42±2s to 49±2s)
3. Loop duration is reasonable (5-9 seconds, target 7s)
4. Task completion markers present
"""

import sys
import os
import logging
import tempfile
import json
import re

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_ab_loop_setup(traj, env_info, task_info):
    """
    Verify A-B loop setup task completion.
    
    Checks:
    1. Agent created confirmation file with loop parameters
    2. Loop start time is approximately 42s (±2s tolerance)
    3. Loop end time is approximately 49s (±2s tolerance)
    4. Loop duration is between 5-9 seconds (target: 7s)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Target parameters
    TARGET_START = 42.0
    TARGET_END = 49.0
    TARGET_DURATION = TARGET_END - TARGET_START  # 7 seconds
    
    START_TOLERANCE = 2.0  # ±2 seconds
    END_TOLERANCE = 2.0    # ±2 seconds
    MIN_DURATION = 5.0
    MAX_DURATION = 9.0
    
    criteria_met = 0
    total_criteria = 4
    feedback_parts = []
    
    # Criterion 1: Check if confirmation file exists
    temp_confirm = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    confirmation_found = False
    loop_start = None
    loop_end = None
    
    try:
        copy_from_env("/tmp/vlc_ab_loop_confirmation.txt", temp_confirm.name)
        confirmation_found = True
        
        with open(temp_confirm.name, 'r') as f:
            content = f.read()
        
        criteria_met += 1
        feedback_parts.append("✅ Loop confirmation file created")
        
        # Parse loop parameters from confirmation
        # Look for patterns like "start: 42" or "Loop start: 42.0"
        start_match = re.search(r'start[:\s]+(\d+\.?\d*)', content, re.IGNORECASE)
        end_match = re.search(r'end[:\s]+(\d+\.?\d*)', content, re.IGNORECASE)
        
        if start_match:
            loop_start = float(start_match.group(1))
            logger.info(f"Parsed loop start: {loop_start}s")
        
        if end_match:
            loop_end = float(end_match.group(1))
            logger.info(f"Parsed loop end: {loop_end}s")
        
        os.unlink(temp_confirm.name)
        
    except Exception as e:
        feedback_parts.append(f"❌ No confirmation file found")
        logger.warning(f"Confirmation file not found: {e}")
    
    # If confirmation file parsing failed, try result JSON as fallback
    if loop_start is None or loop_end is None:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/vlc_ab_loop_result.json", temp_result.name)
            
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
            
            if result.get('loop_start') and result['loop_start'] != 'null':
                loop_start = float(result['loop_start'])
            
            if result.get('loop_end') and result['loop_end'] != 'null':
                loop_end = float(result['loop_end'])
            
            os.unlink(temp_result.name)
            logger.info("Fallback: parsed from result JSON")
            
        except Exception as e:
            logger.warning(f"Could not parse result JSON: {e}")
    
    # If we still don't have parameters, task likely failed
    if loop_start is None or loop_end is None:
        feedback_parts.append("❌ Could not determine loop parameters")
        
        # Calculate final score
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback
        }
    
    # Criterion 2: Check loop start time
    start_diff = abs(loop_start - TARGET_START)
    if start_diff <= START_TOLERANCE:
        criteria_met += 1
        feedback_parts.append(f"✅ Loop start correct ({loop_start}s, target {TARGET_START}s)")
    else:
        feedback_parts.append(f"❌ Loop start incorrect ({loop_start}s, target {TARGET_START}±{START_TOLERANCE}s)")
    
    # Criterion 3: Check loop end time
    end_diff = abs(loop_end - TARGET_END)
    if end_diff <= END_TOLERANCE:
        criteria_met += 1
        feedback_parts.append(f"✅ Loop end correct ({loop_end}s, target {TARGET_END}s)")
    else:
        feedback_parts.append(f"❌ Loop end incorrect ({loop_end}s, target {TARGET_END}±{END_TOLERANCE}s)")
    
    # Criterion 4: Check loop duration
    loop_duration = loop_end - loop_start
    
    if MIN_DURATION <= loop_duration <= MAX_DURATION:
        criteria_met += 1
        feedback_parts.append(f"✅ Loop duration valid ({loop_duration:.1f}s, range {MIN_DURATION}-{MAX_DURATION}s)")
    else:
        if loop_duration < MIN_DURATION:
            feedback_parts.append(f"❌ Loop too short ({loop_duration:.1f}s, min {MIN_DURATION}s)")
        else:
            feedback_parts.append(f"❌ Loop too long ({loop_duration:.1f}s, max {MAX_DURATION}s)")
    
    # Check completion marker (bonus, doesn't affect score)
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_ab_loop_completed.txt", temp_marker.name)
        feedback_parts.append("✅ Task completed")
        os.unlink(temp_marker.name)
    except Exception:
        feedback_parts.append("⚠️ Completion marker not found")
    
    # Calculate final score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75  # Need 3/4 criteria = 75%
    
    # Build detailed feedback
    feedback = " | ".join(feedback_parts)
    
    # Add summary
    summary = f"\nLoop Setup: A={loop_start}s, B={loop_end}s, Duration={loop_duration:.1f}s"
    summary += f"\nTarget: A={TARGET_START}s, B={TARGET_END}s, Duration={TARGET_DURATION}s"
    summary += f"\nCriteria met: {criteria_met}/{total_criteria}"
    
    feedback += summary
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }