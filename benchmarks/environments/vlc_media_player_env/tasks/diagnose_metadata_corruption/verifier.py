#!/usr/bin/env python3
"""
Verifier for Diagnose Metadata Corruption task

Checks:
1. Diagnostic report file exists
2. Report contains accurate actual duration (~270 seconds)
3. Report mentions the discrepancy between metadata and actual duration
4. Report documents the verification method used
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


def verify_diagnose_metadata_corruption(traj, env_info, task_info):
    """
    Verify metadata corruption diagnosis task completion.
    
    Returns:
        Dict with "passed", "score", and "feedback" keys
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available"
        }
    
    criteria_met = 0
    total_criteria = 4
    feedback_parts = []
    
    # Expected values
    TRUE_DURATION = 270  # seconds
    CLAIMED_DURATION_APPROX = 47  # seconds
    TOLERANCE = 5  # ±5 seconds acceptable
    
    # Criterion 1: Check if diagnostic report exists
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
    
    try:
        try:
            copy_from_env("/tmp/export/media_diagnostics.txt", temp_report.name)
        except Exception as e:
            logger.error(f"Error copying diagnostic report: {e}")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Diagnostic report not found at /home/ga/Documents/media_diagnostics.txt: {str(e)}"
            }
        
        criteria_met += 1
        feedback_parts.append("✅ Report exists")
        
        # Read report content
        with open(temp_report.name, 'r', encoding='utf-8', errors='ignore') as f:
            report_content = f.read()
        
        report_lower = report_content.lower()
        
        logger.info(f"Report content preview: {report_content[:500]}")
        
        # Criterion 2: Check for actual duration (should be ~270 seconds)
        actual_duration_seconds = None
        actual_duration_found = False
        
        # Look for various duration patterns
        duration_patterns = [
            # Format: "270 seconds" or "270s"
            r'actual.*?(\d+)\s*(?:seconds?|secs?|s)\b',
            # Format: "4:30" or "4 minutes 30 seconds"
            r'actual.*?(\d+)\s*(?:min|minutes?)[:\s]*(\d+)',
            r'actual.*?(\d+):(\d+)',
            # Format: "measured: 270"
            r'measured.*?(\d+)\s*(?:seconds?|secs?|s)\b',
            # Format: "true duration: 270"
            r'true.*?duration.*?(\d+)\s*(?:seconds?|secs?|s)\b',
            # Format: just a number near "actual"
            r'actual.*?[:\s]+(\d{3})',
        ]
        
        for pattern in duration_patterns:
            matches = re.search(pattern, report_lower)
            if matches:
                groups = matches.groups()
                if len(groups) == 2:  # minutes and seconds
                    mins = int(groups[0])
                    secs = int(groups[1])
                    actual_duration_seconds = mins * 60 + secs
                elif len(groups) == 1:  # just seconds
                    potential_duration = int(groups[0])
                    # Sanity check: should be between 200-300 seconds
                    if 200 <= potential_duration <= 350:
                        actual_duration_seconds = potential_duration
                
                if actual_duration_seconds:
                    actual_duration_found = True
                    feedback_parts.append(f"Actual duration found: {actual_duration_seconds}s")
                    break
        
        if actual_duration_found:
            # Check if duration is accurate (within tolerance)
            if abs(actual_duration_seconds - TRUE_DURATION) <= TOLERANCE:
                criteria_met += 1
                feedback_parts.append(f"✅ Actual duration accurate: {actual_duration_seconds}s (expected ~{TRUE_DURATION}s)")
            else:
                feedback_parts.append(f"⚠️ Actual duration inaccurate: {actual_duration_seconds}s (expected {TRUE_DURATION}±{TOLERANCE}s)")
        else:
            feedback_parts.append("❌ Actual duration not found or not in expected range")
        
        # Criterion 3: Check if discrepancy is mentioned
        discrepancy_found = False
        discrepancy_keywords = [
            r'discrep',
            r'mismatch',
            r'incorrect',
            r'corrupt',
            r'wrong',
            r'differ',
            r'actual.*longer',
            r'metadata.*wrong',
            r'claim.*47.*actually.*\d{3}',
            r'reports.*47.*but.*\d{3}',
        ]
        
        for keyword in discrepancy_keywords:
            if re.search(keyword, report_lower):
                discrepancy_found = True
                break
        
        # Also check if both claimed (47) and actual (~270) are mentioned
        claimed_mentioned = bool(re.search(r'\b47\b', report_lower) or 
                                re.search(r'0:47', report_lower) or
                                re.search(r'forty.seven', report_lower))
        actual_mentioned = actual_duration_found
        
        if discrepancy_found or (claimed_mentioned and actual_mentioned):
            criteria_met += 1
            feedback_parts.append("✅ Discrepancy documented")
        else:
            feedback_parts.append("❌ Discrepancy not clearly documented")
        
        # Criterion 4: Check if verification method is mentioned
        method_found = False
        method_keywords = [
            r'played? to (?:the )?end',
            r'ffprobe',
            r'mediainfo',
            r'vlc',
            r'manual(?:ly)? (?:play|check)',
            r'measured by',
            r'verified? by',
            r'verification method',
            r'how i (?:check|verif|determin)',
            r'method:',
            r'using\s+\w+\s+to',
            r'command',
            r'tool',
        ]
        
        for keyword in method_keywords:
            if re.search(keyword, report_lower):
                method_found = True
                feedback_parts.append(f"✅ Verification method mentioned")
                break
        
        if method_found:
            criteria_met += 1
        else:
            feedback_parts.append("⚠️ Verification method not clearly described")
        
        # Clean up temp file
        os.unlink(temp_report.name)
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Error reading diagnostic report: {str(e)}"
        }
    
    # Calculate score
    # Weights: existence(25%) + accuracy(35%) + discrepancy(25%) + method(15%)
    weights = [0.25, 0.35, 0.25, 0.15]
    
    # Create binary for each criterion (0 or 1)
    criterion_results = [0, 0, 0, 0]
    
    # Map criteria_met to individual criteria
    if criteria_met >= 1:
        criterion_results[0] = 1  # Report exists
    if actual_duration_found and abs(actual_duration_seconds - TRUE_DURATION) <= TOLERANCE:
        criterion_results[1] = 1  # Duration accurate
    if discrepancy_found or (claimed_mentioned and actual_mentioned):
        criterion_results[2] = 1  # Discrepancy documented
    if method_found:
        criterion_results[3] = 1  # Method mentioned
    
    score = sum(cr * w for cr, w in zip(criterion_results, weights)) * 100
    score = int(score)
    
    # Pass if score >= 75% or if critical criteria are met
    # Critical: report exists + duration accurate + discrepancy mentioned
    critical_criteria_met = (criterion_results[0] and criterion_results[1] and criterion_results[2])
    
    passed = (score >= 75) or critical_criteria_met
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }