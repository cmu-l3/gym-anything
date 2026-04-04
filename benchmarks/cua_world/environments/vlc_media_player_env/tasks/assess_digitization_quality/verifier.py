#!/usr/bin/env python3
"""
Verifier for Assess Digitization Quality task

Checks:
1. Report file exists with proper structure
2. All three quality checks performed (Color, Aspect, Audio)
3. Each check has observations
4. Recommendation provided with reasoning
5. At least 2/3 intentional issues correctly identified
"""

import sys
import os
import logging
import tempfile
import re
from datetime import datetime
from pathlib import Path

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_assess_digitization_quality(traj, env_info, task_info):
    """
    Verify that agent created proper digitization assessment report.
    
    Args:
        traj: Trajectory information
        env_info: Environment configuration with copy_from_env function
        task_info: Task configuration
        
    Returns:
        Dict with passed, score, and feedback
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Error: copy_from_env function not available"
        }
    
    criteria_met = 0
    total_criteria = 8  # Weighted criteria
    feedback_parts = []
    
    # Copy report from container
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
    
    try:
        copy_from_env("/tmp/vlc_digitization_report.txt", temp_report.name)
    except Exception as e:
        temp_report.close()
        os.unlink(temp_report.name)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Report file not found at /home/ga/Documents/digitization_report.txt"
        }
    
    # Read report content
    try:
        with open(temp_report.name, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
    except Exception as e:
        os.unlink(temp_report.name)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Could not read report: {e}"
        }
    
    if not content or len(content.strip()) < 50:
        os.unlink(temp_report.name)
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Report file is empty or too short"
        }
    
    # Criterion 1: Check report structure/header (1 point)
    has_header = bool(
        re.search(r'DIGITIZATION.*QUALITY.*ASSESSMENT', content, re.IGNORECASE) or
        re.search(r'ASSESSMENT.*REPORT', content, re.IGNORECASE) or
        re.search(r'QUALITY.*REPORT', content, re.IGNORECASE)
    )
    
    if has_header:
        criteria_met += 1
        feedback_parts.append("✓ Report header present")
    else:
        feedback_parts.append("⚠ Missing proper report header")
    
    # Criterion 2-4: Check for THREE required assessment categories (3 points - 1 each)
    required_checks = {
        "Color Standard": r"Color(?:\s+Standard)?:\s*(YES|NO|UNCERTAIN)",
        "Aspect Ratio": r"Aspect(?:\s+Ratio)?:\s*(YES|NO|UNCERTAIN)",
        "Audio Sync": r"Audio(?:\s+Sync)?:\s*(YES|NO|UNCERTAIN)"
    }
    
    checks_found = {}
    
    for check_name, pattern in required_checks.items():
        match = re.search(pattern, content, re.IGNORECASE)
        
        if match:
            response = match.group(1).upper()
            checks_found[check_name] = response
            
            # Look for observation (more flexible pattern)
            obs_pattern = rf"{check_name.split()[0]}.*?(?:Observation|Notes?):\s*([^\n]+)"
            obs_match = re.search(obs_pattern, content, re.IGNORECASE | re.DOTALL)
            
            if obs_match:
                observation = obs_match.group(1).strip()
                # Check if observation has substance (not just "yes" or single word)
                if len(observation) > 15 and not re.match(r'^(yes|no|uncertain|n/?a)$', observation, re.IGNORECASE):
                    criteria_met += 1
                    feedback_parts.append(f"✓ {check_name}: {response} with detailed observation")
                else:
                    criteria_met += 0.5
                    feedback_parts.append(f"⚠ {check_name}: {response} but observation too brief")
            else:
                criteria_met += 0.3
                feedback_parts.append(f"⚠ {check_name}: {response} but observation missing")
        else:
            feedback_parts.append(f"✗ {check_name}: Not assessed")
    
    if len(checks_found) == 0:
        os.unlink(temp_report.name)
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ No quality checks found in report. Expected: Color Standard, Aspect Ratio, Audio Sync"
        }
    
    # Criterion 5: Check for recommendation (1 point)
    rec_pattern = r"(?:RECOMMENDATION|CONCLUSION|VERDICT):\s*(ACCEPTABLE|NEEDS[_\s-]?REPAIR|NEEDS[_\s-]?REDIGITIZATION|ACCEPT|REPAIR|REDIGITIZE)"
    rec_match = re.search(rec_pattern, content, re.IGNORECASE)
    
    if rec_match:
        recommendation = rec_match.group(1).upper()
        criteria_met += 0.5
        
        # Check for reasoning (more flexible)
        reason_pattern = r"(?:Reasoning|Rationale|Explanation|Because):\s*(.+?)(?=\n\s*\n|\n\s*[A-Z]{3,}:|\Z)"
        reason_match = re.search(reason_pattern, content, re.IGNORECASE | re.DOTALL)
        
        if reason_match:
            reasoning = reason_match.group(1).strip()
            if len(reasoning) > 20:
                criteria_met += 0.5
                feedback_parts.append(f"✓ Recommendation: {recommendation} with reasoning")
            else:
                criteria_met += 0.25
                feedback_parts.append(f"⚠ Recommendation: {recommendation} but reasoning insufficient")
        else:
            feedback_parts.append(f"⚠ Recommendation: {recommendation} but no reasoning provided")
    else:
        feedback_parts.append("✗ No recommendation provided (expected: ACCEPTABLE/NEEDS_REPAIR/NEEDS_REDIGITIZATION)")
    
    # Criterion 6-8: Check if agent identified the THREE intentional issues (3 points - critical!)
    issues_detected = []
    
    # Issue 1: Color oversaturation (should be YES)
    color_response = checks_found.get("Color Standard", "")
    if color_response == "YES":
        # Check if description mentions saturation or related terms
        if re.search(r'saturat|oversaturat|vivid|intense|unnatural|too\s+(bright|colorful)|tint|color\s+issue', content, re.IGNORECASE):
            issues_detected.append("Color")
            criteria_met += 1
            feedback_parts.append("✓✓ Correctly identified color oversaturation")
        else:
            criteria_met += 0.3
            feedback_parts.append("⚠ Marked color as issue but description unclear")
    elif color_response == "UNCERTAIN":
        criteria_met += 0.2
        feedback_parts.append("⚠ Color marked as UNCERTAIN (issue is present)")
    else:
        feedback_parts.append("✗ Missed color oversaturation issue")
    
    # Issue 2: Aspect ratio distortion (should be YES)
    aspect_response = checks_found.get("Aspect Ratio", "")
    if aspect_response == "YES":
        # Check if description mentions stretching or distortion
        if re.search(r'stretch|squish|distort|wrong|horizontal|widen|wide|narrow|tall|thin|aspect', content, re.IGNORECASE):
            issues_detected.append("Aspect")
            criteria_met += 1
            feedback_parts.append("✓✓ Correctly identified aspect ratio distortion")
        else:
            criteria_met += 0.3
            feedback_parts.append("⚠ Marked aspect as issue but description unclear")
    elif aspect_response == "UNCERTAIN":
        criteria_met += 0.2
        feedback_parts.append("⚠ Aspect marked as UNCERTAIN (issue is present)")
    else:
        feedback_parts.append("✗ Missed aspect ratio stretching issue")
    
    # Issue 3: Audio sync drift (should be YES) - This is subtle and harder to detect
    audio_response = checks_found.get("Audio Sync", "")
    if audio_response == "YES":
        # Check if description mentions sync or timing issues
        if re.search(r'sync|desync|out\s+of\s+sync|drift|delay|mismatch|lip|timing|gradual|worse|lag|behind|off', content, re.IGNORECASE):
            issues_detected.append("Audio")
            criteria_met += 1
            feedback_parts.append("✓✓ Correctly identified audio sync drift")
        else:
            criteria_met += 0.3
            feedback_parts.append("⚠ Marked audio as issue but description unclear")
    elif audio_response == "UNCERTAIN":
        criteria_met += 0.3
        feedback_parts.append("⚠ Audio marked as UNCERTAIN (subtle issue)")
    else:
        feedback_parts.append("⚠ Missed audio sync issue (subtle progressive drift)")
    
    # Cleanup
    os.unlink(temp_report.name)
    
    # Calculate final score (out of 8 criteria points)
    score_raw = (criteria_met / total_criteria) * 100
    score = int(score_raw)
    
    # Success criteria:
    # - Report exists with structure
    # - All THREE checks performed
    # - Recommendation provided
    # - Score >= 65%
    
    success = (
        score >= 65 and 
        len(checks_found) >= 3 and 
        rec_match is not None
    )
    
    feedback = "=== Digitization Assessment Report Verification ===\n\n"
    feedback += "\n".join(feedback_parts)
    feedback += f"\n\n📊 Issues correctly identified: {len(issues_detected)}/3 (Color oversaturation, Aspect distortion, Audio sync)"
    feedback += f"\n📈 Total score: {score_raw:.1f}% ({criteria_met:.1f}/{total_criteria} criteria)"
    
    if success:
        feedback += "\n\n✅ TASK SUCCESSFUL - Comprehensive digitization assessment performed"
        if len(issues_detected) >= 2:
            feedback += "\n   Agent successfully identified major quality problems."
        else:
            feedback += "\n   Agent completed assessment, though some issues were missed."
    else:
        if len(checks_found) < 3:
            feedback += "\n\n❌ TASK FAILED - Incomplete assessment (missing check categories)"
            feedback += "\n   Required: Color Standard, Aspect Ratio, Audio Sync assessments"
        elif rec_match is None:
            feedback += "\n\n❌ TASK FAILED - No recommendation provided"
            feedback += "\n   Required: Overall recommendation (ACCEPTABLE/NEEDS_REPAIR/NEEDS_REDIGITIZATION)"
        else:
            feedback += "\n\n❌ TASK FAILED - Assessment quality insufficient"
            feedback += f"\n   Score {score}% is below threshold of 65%"
    
    return {
        "passed": success,
        "score": score,
        "feedback": feedback
    }
