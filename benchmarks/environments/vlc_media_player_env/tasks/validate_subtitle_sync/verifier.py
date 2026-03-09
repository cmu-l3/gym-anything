#!/usr/bin/env python3
"""
Verifier for Validate Subtitle Sync task

This verifier checks that the agent properly validated subtitle synchronization
by creating a structured report documenting checks at multiple timestamps.
"""

import sys
import os
import logging
import tempfile
import re
from pathlib import Path

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_validate_subtitle_sync(traj, env_info, task_info):
    """
    Verify validate subtitle sync task completion.
    
    Checks:
    1. Validation report exists and is parseable
    2. Report contains "Subtitles Loaded" status
    3. Video duration is documented
    4. Subtitle end time is documented
    5. Three checkpoints are assessed (Beginning, Middle, End)
    6. Overall verdict is present
    7. Notes section exists
    
    Scoring:
    - Each criterion contributes to overall score
    - Must achieve 70% to pass
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "❌ Copy function not available"}
    
    criteria_met = 0.0
    max_score = 7.0  # 7 main criteria
    feedback_parts = []
    
    # Copy validation report
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
    
    try:
        copy_from_env("/tmp/vlc_subtitle_validation_report.txt", temp_report.name)
        
        with open(temp_report.name, 'r', encoding='utf-8', errors='ignore') as f:
            report_content = f.read()
        
        logger.info(f"Report content:\n{report_content}")
        
    except Exception as e:
        logger.error(f"Error reading report: {e}", exc_info=True)
        os.unlink(temp_report.name)
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"❌ Validation report not found or unreadable: {str(e)}"
        }
    
    # Check if report is empty or just marker
    if not report_content or len(report_content.strip()) < 20 or "REPORT_NOT_FOUND" in report_content:
        os.unlink(temp_report.name)
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Validation report not found at /home/ga/subtitle_validation_report.txt"
        }
    
    # Criterion 1: Report contains "Subtitles Loaded" status (1 point)
    subtitles_loaded_pattern = re.search(
        r'Subtitles?\s+Loaded\s*:\s*(YES|NO)',
        report_content,
        re.IGNORECASE
    )
    
    if subtitles_loaded_pattern:
        status = subtitles_loaded_pattern.group(1).upper()
        if status == "YES":
            criteria_met += 1.0
            feedback_parts.append("✅ Subtitles loaded: YES")
        else:
            criteria_met += 0.5
            feedback_parts.append("⚠️ Report indicates subtitles NOT loaded")
    else:
        feedback_parts.append("❌ Missing 'Subtitles Loaded' status")
    
    # Criterion 2: Video duration reported (0.5 points)
    duration_pattern = re.search(
        r'Video\s+Duration\s*:\s*(\d+)',
        report_content,
        re.IGNORECASE
    )
    
    if duration_pattern:
        duration = duration_pattern.group(1)
        criteria_met += 0.5
        feedback_parts.append(f"✅ Video duration: {duration}s")
    else:
        feedback_parts.append("⚠️ Video duration not documented")
    
    # Criterion 3: Subtitle end time reported (0.5 points)
    subtitle_end_pattern = re.search(
        r'Subtitle\s+End\s+Time\s*:\s*(\d+:\d+:\d+|[\d:]+)',
        report_content,
        re.IGNORECASE
    )
    
    if subtitle_end_pattern:
        criteria_met += 0.5
        feedback_parts.append(f"✅ Subtitle end time: {subtitle_end_pattern.group(1)}")
    else:
        feedback_parts.append("⚠️ Subtitle end time not documented")
    
    # Criteria 4-6: Three checkpoint validations (1.5 points each = 4.5 points total)
    checkpoint_patterns = [
        (r'Checkpoint\s+1\s*[:\(\[].*?[:\)\]]\s*:\s*(PASS|FAIL)', "Beginning (Checkpoint 1)"),
        (r'Checkpoint\s+2\s*[:\(\[].*?[:\)\]]\s*:\s*(PASS|FAIL)', "Middle (Checkpoint 2)"),
        (r'Checkpoint\s+3\s*[:\(\[].*?[:\)\]]\s*:\s*(PASS|FAIL)', "Near-end (Checkpoint 3)")
    ]
    
    checkpoint_passes = 0
    for pattern, name in checkpoint_patterns:
        match = re.search(pattern, report_content, re.IGNORECASE | re.DOTALL)
        if match:
            status = match.group(1).upper()
            if status == "PASS":
                criteria_met += 1.5
                checkpoint_passes += 1
                feedback_parts.append(f"✅ {name}: PASS")
            else:
                criteria_met += 0.5  # Partial credit for documenting
                feedback_parts.append(f"⚠️ {name}: FAIL")
        else:
            feedback_parts.append(f"❌ {name}: Not assessed")
    
    # Criterion 7: Overall verdict (1 point)
    verdict_pattern = re.search(
        r'Overall\s+Verdict\s*:\s*(PASS|FAIL)',
        report_content,
        re.IGNORECASE
    )
    
    if verdict_pattern:
        verdict = verdict_pattern.group(1).upper()
        # Check if verdict is consistent with checkpoints
        expected_verdict = "PASS" if checkpoint_passes == 3 else "FAIL"
        
        if verdict == expected_verdict:
            criteria_met += 1.0
            feedback_parts.append(f"✅ Overall verdict: {verdict} (correct)")
        else:
            criteria_met += 0.5
            feedback_parts.append(f"⚠️ Overall verdict '{verdict}' inconsistent with checkpoints")
    else:
        feedback_parts.append("❌ Missing overall verdict")
    
    # Bonus: Notes section exists (already covered in max_score, just checking)
    notes_pattern = re.search(r'Notes\s*:', report_content, re.IGNORECASE)
    if notes_pattern:
        # Don't add to score, but mention in feedback
        notes_content = report_content[notes_pattern.end():].strip()[:100]
        if notes_content:
            feedback_parts.append(f"✅ Notes included")
    
    # Check completion marker
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_subtitle_validation_completed.txt", temp_marker.name)
        feedback_parts.append("✅ Task export completed")
        os.unlink(temp_marker.name)
    except Exception:
        feedback_parts.append("⚠️ Export completion marker not found")
    
    # Clean up
    os.unlink(temp_report.name)
    
    # Calculate final score
    score = int((criteria_met / max_score) * 100)
    passed = score >= 70  # 70% threshold
    
    # Build feedback string
    feedback_header = f"Score: {criteria_met:.1f}/{max_score:.1f} ({score}%)"
    feedback_body = "\n".join(feedback_parts)
    
    if passed:
        feedback = f"✅ TASK SUCCESS\n\n{feedback_header}\n{feedback_body}"
    else:
        feedback = f"❌ TASK INCOMPLETE\n\n{feedback_header}\n{feedback_body}"
    
    logger.info(f"Verification result: passed={passed}, score={score}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }
