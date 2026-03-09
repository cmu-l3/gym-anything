#!/usr/bin/env python3
"""
Verifier for Create Timed Subtitles task

Validates that a properly-formatted SRT subtitle file was created with
accurate timing and reasonable content.
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


def parse_srt_time(time_str):
    """
    Convert SRT timecode to seconds.
    
    Args:
        time_str: Timecode in format HH:MM:SS,mmm
        
    Returns:
        Float seconds
    """
    try:
        h, m, s_ms = time_str.split(':')
        s, ms = s_ms.split(',')
        return int(h) * 3600 + int(m) * 60 + int(s) + int(ms) / 1000
    except Exception as e:
        logger.error(f"Error parsing timecode '{time_str}': {e}")
        raise


def verify_create_timed_subtitles(traj, env_info, task_info):
    """
    Verify create timed subtitles task completion.
    
    Checks:
    1. Subtitle file exists and is parseable
    2. Valid SRT format structure
    3. Sufficient number of subtitle entries (at least 5)
    4. Valid timing (chronological, within video duration)
    5. Content present in each subtitle segment
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_met = 0
    total_criteria = 5
    feedback_parts = []
    details = {}
    
    # Copy subtitle file from container
    temp_srt = tempfile.NamedTemporaryFile(delete=False, suffix='.srt', mode='w+')
    temp_srt.close()
    
    try:
        try:
            copy_from_env("/tmp/vlc_created_subtitles.srt", temp_srt.name)
        except Exception as e:
            logger.error(f"Error copying subtitle file: {e}")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ Subtitle file not found at /home/ga/Videos/python_tutorial.srt"
            }
        
        # Check if file exists and is not empty
        if not os.path.exists(temp_srt.name) or os.path.getsize(temp_srt.name) == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ Subtitle file is empty or not created"
            }
        
        criteria_met += 1
        feedback_parts.append("✅ Subtitle file exists")
        details['file_exists'] = True
        details['file_size_bytes'] = os.path.getsize(temp_srt.name)
        
        # Read and parse SRT file
        with open(temp_srt.name, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
        
        # SRT format validation using regex
        # Pattern: number, timecode line, text (one or more lines), blank line
        srt_pattern = r'(\d+)\s*\n(\d{2}:\d{2}:\d{2},\d{3})\s*-->\s*(\d{2}:\d{2}:\d{2},\d{3})\s*\n(.+?)(?=\n\s*\n|\n\s*\d+\s*\n|\Z)'
        
        matches = re.findall(srt_pattern, content, re.DOTALL | re.MULTILINE)
        
        if not matches:
            os.unlink(temp_srt.name)
            return {
                "passed": False,
                "score": 20,  # Got file created, but wrong format
                "feedback": "❌ Invalid SRT format - couldn't parse subtitle entries. Check format: number, timecode, text, blank line"
            }
        
        criteria_met += 1
        feedback_parts.append("✅ Valid SRT format")
        details['valid_format'] = True
        details['subtitle_count'] = len(matches)
        
        # Criterion 3: Check minimum number of subtitles (at least 5)
        if len(matches) < 5:
            feedback_parts.append(f"⚠️ Too few subtitle entries ({len(matches)}/5 minimum)")
            details['sufficient_entries'] = False
        else:
            criteria_met += 1
            feedback_parts.append(f"✅ Sufficient entries ({len(matches)} subtitles)")
            details['sufficient_entries'] = True
        
        # Parse and validate timecodes
        subtitles = []
        previous_end_time = 0
        timing_issues = []
        content_issues = []
        
        for idx, (num, start_time, end_time, text) in enumerate(matches, 1):
            text = text.strip()
            
            # Check subtitle has content
            if len(text) < 3:
                content_issues.append(f"Entry {num}: Very short/empty text")
            
            try:
                start_sec = parse_srt_time(start_time)
                end_sec = parse_srt_time(end_time)
            except Exception as e:
                timing_issues.append(f"Entry {num}: Invalid timecode format")
                details['valid_timecodes'] = False
                continue
            
            # Check timing makes sense
            if start_sec >= end_sec:
                timing_issues.append(f"Entry {num}: Start time >= end time")
            
            # Video is ~90 seconds, allow 95s buffer
            if start_sec > 95:
                timing_issues.append(f"Entry {num}: Starts after video ends ({start_sec:.1f}s)")
            
            if end_sec > 95:
                timing_issues.append(f"Entry {num}: Ends after video ends ({end_sec:.1f}s)")
            
            # Check chronological order
            if start_sec < previous_end_time - 0.1:  # Allow tiny overlap
                timing_issues.append(f"Entry {num}: Overlaps with previous subtitle")
            
            previous_end_time = max(previous_end_time, end_sec)
            
            # Check reasonable segment length (not a wall of text)
            word_count = len(text.split())
            if word_count > 40:
                content_issues.append(f"Entry {num}: Very long segment ({word_count} words)")
            
            subtitles.append({
                'number': num,
                'start': start_sec,
                'end': end_sec,
                'duration': end_sec - start_sec,
                'text': text,
                'word_count': word_count
            })
        
        details['parsed_subtitles'] = len(subtitles)
        
        # Criterion 4: Valid timing
        if not timing_issues:
            criteria_met += 1
            feedback_parts.append("✅ Valid timing (chronological, within video)")
            details['valid_timing'] = True
        else:
            feedback_parts.append(f"⚠️ Timing issues: {timing_issues[0]}" + (f" (+{len(timing_issues)-1} more)" if len(timing_issues) > 1 else ""))
            details['valid_timing'] = False
            details['timing_issues'] = timing_issues[:5]  # First 5 issues
        
        # Criterion 5: Content present
        if not content_issues and len(subtitles) > 0:
            criteria_met += 1
            feedback_parts.append("✅ All subtitles have content")
            details['has_content'] = True
        else:
            if content_issues:
                feedback_parts.append(f"⚠️ Content issues: {content_issues[0]}")
                details['content_issues'] = content_issues[:3]
            details['has_content'] = len(subtitles) > 0
        
        # Additional quality checks (informational, not scored)
        
        # Check first subtitle doesn't start at 0:00:00 (indicates actual timing)
        if subtitles and subtitles[0]['start'] < 1.0:
            feedback_parts.append("ℹ️ First subtitle starts very early")
        
        # Check for expected Python/NumPy keywords
        full_text = ' '.join([sub['text'].lower() for sub in subtitles])
        expected_keywords = ['python', 'numpy', 'array', 'import', 'function']
        found_keywords = [kw for kw in expected_keywords if kw in full_text]
        
        if found_keywords:
            details['keywords_found'] = found_keywords
            details['keyword_coverage'] = len(found_keywords) / len(expected_keywords)
        
        # Summary statistics
        if subtitles:
            avg_duration = sum(s['duration'] for s in subtitles) / len(subtitles)
            total_coverage = max(s['end'] for s in subtitles)
            details['avg_subtitle_duration'] = round(avg_duration, 1)
            details['total_time_covered'] = round(total_coverage, 1)
        
        # Clean up temp file
        os.unlink(temp_srt.name)
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        if os.path.exists(temp_srt.name):
            os.unlink(temp_srt.name)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification error: {str(e)}"
        }
    
    # Calculate final score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75
    
    # Build comprehensive feedback
    feedback = " | ".join(feedback_parts)
    
    # Add summary statistics if available
    if details.get('parsed_subtitles'):
        feedback += f"\n📊 Stats: {details['parsed_subtitles']} entries"
        if 'avg_subtitle_duration' in details:
            feedback += f", avg {details['avg_subtitle_duration']}s duration"
        if 'keywords_found' in details:
            feedback += f", keywords: {', '.join(details['keywords_found'][:3])}"
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }