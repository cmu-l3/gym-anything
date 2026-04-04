#!/usr/bin/env python3
"""
Verifier for Batch Verify Raw Footage task

This verifier checks that the agent:
1. Created a QA report file
2. Analyzed all 5 video files
3. Correctly identified the problematic file (ceremony_02.mp4 - missing audio)
4. Documented valid files with correct specs
5. Included a summary section
"""

import sys
import os
import logging
import tempfile
import re
from typing import Dict, List, Tuple, Set

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_batch_verify_raw_footage(traj, env_info, task_info):
    """
    Verify batch verify raw footage task completion.
    
    Checks:
    1. QA report exists and is readable
    2. All 5 files are documented in the report
    3. Problematic file (ceremony_02.mp4) is correctly flagged
    4. Valid files show correct technical specs
    5. Summary section exists with accurate counts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "Copy function not available"}
    
    max_score = 5.0  # 5 criteria
    score = 0.0
    feedback_parts = []
    
    # Copy QA report
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
    
    try:
        copy_from_env("/tmp/vlc_batch_qa_report.txt", temp_report.name)
    except Exception as e:
        logger.error(f"Error copying QA report: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0.0,
            "feedback": f"QA report not found at /home/ga/Documents/qa_report.txt: {str(e)}"
        }
    
    # Read report content
    try:
        with open(temp_report.name, 'r', encoding='utf-8', errors='ignore') as f:
            report_content = f.read()
    except Exception as e:
        os.unlink(temp_report.name)
        return {
            "passed": False,
            "score": 0.0,
            "feedback": f"Failed to read QA report: {str(e)}"
        }
    
    # Check if report is not empty or just error marker
    if len(report_content.strip()) < 50 or "NO REPORT GENERATED" in report_content:
        os.unlink(temp_report.name)
        return {
            "passed": False,
            "score": 0.0,
            "feedback": "QA report is empty or was not generated"
        }
    
    # Criterion 1: Report exists and has content (already verified)
    score += 1.0
    feedback_parts.append("✅ QA report exists")
    
    # Criterion 2: All 5 files are documented
    required_files = [
        'ceremony_01.mp4',
        'ceremony_02.mp4',
        'reception_speeches.mp4',
        'first_dance.mp4',
        'venue_broll.mp4'
    ]
    
    files_mentioned = check_files_documented(report_content, required_files)
    
    if len(files_mentioned) == 5:
        score += 1.0
        feedback_parts.append(f"✅ All 5 files documented in report")
    elif len(files_mentioned) >= 3:
        score += 0.5
        missing = set(required_files) - files_mentioned
        feedback_parts.append(f"⚠️ Only {len(files_mentioned)}/5 files documented (missing: {', '.join(missing)})")
    else:
        feedback_parts.append(f"❌ Only {len(files_mentioned)}/5 files documented")
    
    # Criterion 3: Problematic file (ceremony_02.mp4) is correctly flagged
    problem_detected, problem_feedback = check_problem_detection(report_content)
    
    if problem_detected:
        score += 1.0
        feedback_parts.append(f"✅ {problem_feedback}")
    else:
        feedback_parts.append(f"❌ {problem_feedback}")
    
    # Criterion 4: Valid files show correct specs
    specs_score, specs_feedback = check_valid_file_specs(report_content)
    score += specs_score
    feedback_parts.extend(specs_feedback)
    
    # Criterion 5: Summary section exists
    summary_score, summary_feedback = check_summary_section(report_content)
    score += summary_score
    feedback_parts.extend(summary_feedback)
    
    # Clean up
    os.unlink(temp_report.name)
    
    # Calculate final score as percentage
    final_score = int((score / max_score) * 100)
    passed = final_score >= 80  # Need 80% to pass
    
    feedback = " | ".join(feedback_parts)
    feedback += f"\n\n📊 Final Score: {score:.1f}/{max_score} ({final_score}%)"
    
    if passed:
        feedback += "\n✅ QA report successfully completed with correct analysis!"
    else:
        feedback += "\n❌ QA report incomplete or has significant errors."
    
    return {
        "passed": passed,
        "score": final_score,
        "feedback": feedback
    }


def check_files_documented(report: str, required_files: List[str]) -> Set[str]:
    """
    Check which required files are mentioned in the report.
    
    Returns:
        Set of filenames that were found in the report
    """
    report_lower = report.lower()
    files_found = set()
    
    for filename in required_files:
        # Check for filename (case-insensitive)
        if filename.lower() in report_lower:
            files_found.add(filename)
    
    return files_found


def check_problem_detection(report: str) -> Tuple[bool, str]:
    """
    Check if ceremony_02.mp4 is correctly identified as problematic.
    
    Returns:
        Tuple of (detected: bool, feedback: str)
    """
    # Extract the section discussing ceremony_02.mp4
    report_lower = report.lower()
    
    # Find where ceremony_02 is mentioned
    if 'ceremony_02.mp4' not in report_lower and 'ceremony_02' not in report_lower:
        return False, "ceremony_02.mp4 not found in report"
    
    # Look for the section about ceremony_02
    # Try to extract context around the filename
    lines = report.split('\n')
    ceremony_02_section = []
    capturing = False
    
    for i, line in enumerate(lines):
        line_lower = line.lower()
        
        # Start capturing when we see ceremony_02
        if 'ceremony_02' in line_lower:
            capturing = True
            # Capture this line and next 5 lines
            for j in range(i, min(i+6, len(lines))):
                ceremony_02_section.append(lines[j])
            break
    
    section_text = '\n'.join(ceremony_02_section).lower()
    
    # Check for failure/problem indicators
    problem_keywords = [
        'fail', 'failed', 'failure',
        'issue', 'issues', 'problem', 'problems',
        'error', 'errors',
        'missing', 'no audio', 'without audio', 'audio: no',
        'defect', 'defective', 'corrupt', 'corrupted',
        'invalid', 'incomplete'
    ]
    
    problem_found = any(keyword in section_text for keyword in problem_keywords)
    
    # Also check for explicit audio stream issues
    audio_issue_keywords = [
        'audio stream missing',
        'no audio stream',
        'audio: missing',
        'audio: no',
        'audio: false',
        'audio not present',
        'missing audio',
        'lacks audio',
        'without audio'
    ]
    
    audio_issue_found = any(keyword in section_text for keyword in audio_issue_keywords)
    
    if audio_issue_found:
        return True, "Correctly identified ceremony_02.mp4 as missing audio stream"
    elif problem_found:
        return True, "Correctly flagged ceremony_02.mp4 as problematic"
    else:
        # Check if it's marked as PASS (which would be wrong)
        if 'pass' in section_text or 'ok' in section_text or 'valid' in section_text:
            return False, "ceremony_02.mp4 incorrectly marked as PASS (should be FAIL - missing audio)"
        else:
            return False, "ceremony_02.mp4 not clearly identified as problematic"


def check_valid_file_specs(report: str) -> Tuple[float, List[str]]:
    """
    Check if valid files show correct technical specifications.
    
    Returns:
        Tuple of (score: float, feedback: List[str])
    """
    max_score = 1.0
    score = 0.0
    feedback = []
    
    report_lower = report.lower()
    
    # Check for resolution mentions (1920x1080 or similar)
    resolution_patterns = [
        r'1920\s*x\s*1080',
        r'1920x1080',
        r'1080p',
        r'resolution.*1920.*1080',
        r'width.*1920.*height.*1080'
    ]
    
    resolution_found = any(re.search(pattern, report_lower) for pattern in resolution_patterns)
    
    # Check for codec mentions (h264, h.264)
    codec_patterns = [
        r'h\.?264',
        r'codec.*h\.?264',
        r'h\.?264.*codec'
    ]
    
    codec_found = any(re.search(pattern, report_lower) for pattern in codec_patterns)
    
    # Check for audio mentions
    audio_patterns = [
        r'audio.*yes',
        r'audio.*present',
        r'audio.*ok',
        r'audio.*true',
        r'audio stream',
        r'has audio',
        r'with audio'
    ]
    
    audio_found = any(re.search(pattern, report_lower) for pattern in audio_patterns)
    
    # Scoring
    specs_found = 0
    
    if resolution_found:
        specs_found += 1
        feedback.append("✅ Resolution specs documented")
    else:
        feedback.append("⚠️ Resolution (1920x1080) not clearly documented")
    
    if codec_found:
        specs_found += 1
        feedback.append("✅ Video codec (H.264) documented")
    else:
        feedback.append("⚠️ Video codec not clearly documented")
    
    if audio_found:
        specs_found += 1
        feedback.append("✅ Audio stream presence documented")
    else:
        feedback.append("⚠️ Audio stream status not clearly documented")
    
    # Award partial score based on specs found
    score = (specs_found / 3.0) * max_score
    
    return score, feedback


def check_summary_section(report: str) -> Tuple[float, List[str]]:
    """
    Check if summary section exists with correct counts.
    
    Returns:
        Tuple of (score: float, feedback: List[str])
    """
    max_score = 1.0
    score = 0.0
    feedback = []
    
    report_lower = report.lower()
    
    # Check for summary section
    has_summary = any(keyword in report_lower for keyword in [
        'summary', 'total', 'overview', 'conclusion', 'result'
    ])
    
    if not has_summary:
        feedback.append("⚠️ Summary section not clearly identified")
        return 0.0, feedback
    
    score += 0.2  # Found summary section
    
    # Check for correct counts
    # Looking for patterns like "total: 5", "total files: 5", "5 files"
    has_total_5 = bool(re.search(r'total.*5|5.*total|5.*files', report_lower))
    has_passed_4 = bool(re.search(r'pass.*4|4.*pass', report_lower))
    has_failed_1 = bool(re.search(r'fail.*1|1.*fail', report_lower))
    
    if has_total_5:
        score += 0.2
        feedback.append("✅ Correct total count (5)")
    else:
        feedback.append("⚠️ Total file count not clearly stated or incorrect")
    
    if has_passed_4:
        score += 0.3
        feedback.append("✅ Correct passed count (4)")
    else:
        feedback.append("⚠️ Passed file count not clearly stated or incorrect")
    
    if has_failed_1:
        score += 0.3
        feedback.append("✅ Correct failed count (1)")
    else:
        feedback.append("⚠️ Failed file count not clearly stated or incorrect")
    
    # Check for "not ready" or "NO" verdict
    not_ready_patterns = [
        r'ready.*no\b',
        r'ready.*false',
        r'not ready',
        r'ready: no',
        r'ready for edit.*no'
    ]
    
    has_not_ready = any(re.search(pattern, report_lower) for pattern in not_ready_patterns)
    
    if has_not_ready:
        feedback.append("✅ Correctly marked as NOT ready for editing")
    else:
        feedback.append("⚠️ Should indicate batch is NOT ready for editing due to failed file")
    
    return min(score, max_score), feedback