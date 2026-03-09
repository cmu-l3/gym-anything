#!/usr/bin/env python3
"""
Verifier for Preview Content Safety task

This verifier checks if the agent successfully previewed video content
at increased speed and documented problematic sections with timestamps.
"""

import sys
import os
import logging
import tempfile
import re
from pathlib import Path
from typing import Tuple, List, Dict, Any

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_review_notes(filepath: str) -> Dict[str, Any]:
    """
    Parse the content review notes file.
    
    Args:
        filepath: Path to review notes text file
        
    Returns:
        Dict with parsed data: timestamps, descriptions, recommendation, etc.
    """
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
        
        # Check if file is essentially empty or error marker
        if len(content.strip()) < 20 or "No review notes" in content:
            return {'error': 'Review notes file empty or not created'}
        
        # Extract timestamps (format: MM:SS or M:SS, with optional description after hyphen)
        # Patterns: "2:45", "10:45", "6:15", etc.
        timestamp_pattern = r'[-•*]\s*(\d{1,2}):(\d{2})\s*[-–—]'
        timestamp_matches = re.findall(timestamp_pattern, content)
        
        # Also try simpler pattern without bullet points
        if not timestamp_matches:
            timestamp_pattern_simple = r'(?:^|\n)\s*(\d{1,2}):(\d{2})'
            timestamp_matches = re.findall(timestamp_pattern_simple, content)
        
        # Convert to seconds for comparison
        timestamp_seconds = []
        timestamp_strings = []
        for m, s in timestamp_matches:
            total = int(m) * 60 + int(s)
            timestamp_seconds.append(total)
            timestamp_strings.append(f"{m}:{s}")
        
        # Remove duplicates while preserving order
        seen = set()
        unique_timestamps = []
        unique_strings = []
        for ts, ts_str in zip(timestamp_seconds, timestamp_strings):
            if ts not in seen:
                seen.add(ts)
                unique_timestamps.append(ts)
                unique_strings.append(ts_str)
        
        timestamp_seconds = unique_timestamps
        timestamp_strings = unique_strings
        
        # Check for recommendation keywords
        recommendation = None
        content_upper = content.upper()
        if 'DO NOT USE' in content_upper or 'NOT APPROVED' in content_upper:
            recommendation = 'DO NOT USE'
        elif 'NEEDS EDITING' in content_upper or 'NEEDS EDIT' in content_upper or 'WITH EDITS' in content_upper:
            recommendation = 'NEEDS EDITING'
        elif 'APPROVED' in content_upper or 'ACCEPTABLE' in content_upper or 'OK TO USE' in content_upper:
            recommendation = 'APPROVED'
        
        # Check for content-related keywords in descriptions
        concern_keywords = [
            'graphic', 'battle', 'violence', 'violent', 'combat', 'footage',
            'disturbing', 'concentration', 'camp', 'holocaust', 'imagery',
            'language', 'profanity', 'mature', 'strong language', 'inappropriate',
            'warning', 'concern', 'issue'
        ]
        
        descriptions = []
        keyword_count = 0
        
        # Extract lines that look like descriptions (lines with hyphens and text)
        desc_pattern = r'[-•*]\s*\d{1,2}:\d{2}\s*[-–—]\s*(.+?)(?:\n|$)'
        desc_matches = re.findall(desc_pattern, content, re.MULTILINE)
        
        for desc in desc_matches:
            desc_lower = desc.lower()
            descriptions.append(desc.strip())
            # Count how many concern keywords are present
            if any(keyword in desc_lower for keyword in concern_keywords):
                keyword_count += 1
        
        # Check if playback speed was mentioned
        speed_mentioned = False
        speed_value = None
        speed_pattern = r'(\d+\.?\d*)\s*x|speed.*?(\d+\.?\d*)'
        speed_match = re.search(speed_pattern, content.lower())
        if speed_match:
            speed_mentioned = True
            speed_value = speed_match.group(1) or speed_match.group(2)
        
        return {
            'timestamps': timestamp_seconds,
            'timestamp_strings': timestamp_strings,
            'timestamp_count': len(timestamp_seconds),
            'recommendation': recommendation,
            'descriptions': descriptions,
            'description_count': len(descriptions),
            'keyword_count': keyword_count,
            'speed_mentioned': speed_mentioned,
            'speed_value': speed_value,
            'content_length': len(content)
        }
        
    except Exception as e:
        logger.error(f"Error parsing review notes: {e}")
        return {'error': str(e)}


def check_playback_speed_config(vlcrc_path: str) -> Tuple[bool, float]:
    """
    Check if playback speed was configured in VLC config.
    
    Args:
        vlcrc_path: Path to VLC config file
        
    Returns:
        Tuple of (speed_was_set, rate_value)
    """
    try:
        with open(vlcrc_path, 'r', encoding='utf-8') as f:
            content = f.read()
        
        # Look for rate setting (VLC stores as float, 1.0 = normal, 1.5 = 1.5x, etc.)
        rate_pattern = r'(?:^|\n)rate=([\d.]+)'
        match = re.search(rate_pattern, content)
        
        if match:
            rate = float(match.group(1))
            # Consider speed "set" if it's >= 1.3x (faster than normal)
            return (rate >= 1.3, rate)
        
        return (False, 1.0)
        
    except Exception as e:
        logger.error(f"Error checking playback speed config: {e}")
        return (False, 1.0)


def verify_preview_content_safety(traj, env_info, task_info):
    """
    Main verification function for content preview task.
    
    Checks:
    1. Review notes file exists and is parseable
    2. At least 2 timestamps are documented
    3. Timestamps match expected problematic sections (tolerance allowed)
    4. Descriptions contain relevant concern keywords
    5. A recommendation was provided
    6. Bonus: Playback speed was increased
    
    Expected problematic sections:
    - ~165s (2:45) - Graphic battle footage
    - ~375s (6:15) - Disturbing concentration camp imagery  
    - ~645s (10:45) - Mature language
    
    Returns:
        Dict with passed (bool), score (int), feedback (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Copy function not available"
        }
    
    # Create temp directory for copied files
    temp_dir = tempfile.mkdtemp(prefix='verify_preview_')
    
    try:
        # Copy review notes file
        notes_container = '/tmp/vlc_content_review_notes.txt'
        notes_local = os.path.join(temp_dir, 'content_review_notes.txt')
        
        try:
            copy_from_env(notes_container, notes_local)
        except Exception as e:
            logger.error(f"Failed to copy review notes: {e}")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ Review notes file not found or not created: {str(e)}"
            }
        
        # Parse review notes
        notes_data = parse_review_notes(notes_local)
        
        if 'error' in notes_data:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ Failed to parse review notes: {notes_data['error']}"
            }
        
        # Scoring criteria (total 100 points)
        score = 0.0
        max_score = 100.0
        feedback_parts = []
        
        # Criterion 1: File exists and has content (10 points)
        if notes_data.get('content_length', 0) >= 50:
            score += 10
            feedback_parts.append("✅ Review notes file created")
        else:
            feedback_parts.append("❌ Review notes file too short or empty")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts)
            }
        
        # Criterion 2: Timestamp count (25 points)
        ts_count = notes_data['timestamp_count']
        if ts_count >= 3:
            score += 25
            feedback_parts.append(f"✅ {ts_count} timestamps documented")
        elif ts_count >= 2:
            score += 20
            feedback_parts.append(f"✅ {ts_count} timestamps documented (expected 3)")
        elif ts_count >= 1:
            score += 10
            feedback_parts.append(f"⚠️ Only {ts_count} timestamp found (need at least 2)")
        else:
            feedback_parts.append("❌ No timestamps found")
        
        # Criterion 3: Timestamp accuracy (30 points)
        # Expected problematic sections with tolerance windows:
        # Section 1: 165s ± 20s (145-185s) - 2:45 battle footage
        # Section 2: 375s ± 25s (350-400s) - 6:15 concentration camp  
        # Section 3: 645s ± 20s (625-665s) - 10:45 mature language
        expected_ranges = [
            (145, 185, "2:45 - Graphic battle footage"),
            (350, 400, "6:15 - Disturbing imagery"),
            (625, 665, "10:45 - Mature language")
        ]
        
        matched_sections = []
        timestamps = notes_data['timestamps']
        
        for ts in timestamps:
            for idx, (start, end, label) in enumerate(expected_ranges):
                if start <= ts <= end and idx not in matched_sections:
                    matched_sections.append(idx)
                    break
        
        match_count = len(matched_sections)
        
        if match_count == 3:
            score += 30
            feedback_parts.append("✅ All 3 problematic sections identified")
        elif match_count == 2:
            score += 25
            feedback_parts.append("✅ 2/3 problematic sections identified")
        elif match_count == 1:
            score += 15
            feedback_parts.append("⚠️ 1/3 problematic sections identified")
        else:
            feedback_parts.append("❌ Problematic sections not accurately identified")
        
        # Show which timestamps were logged
        if timestamps:
            ts_str = ", ".join(notes_data['timestamp_strings'][:5])  # Show first 5
            feedback_parts.append(f"Timestamps: [{ts_str}]")
        
        # Criterion 4: Descriptions with relevant keywords (15 points)
        desc_count = notes_data['description_count']
        keyword_count = notes_data['keyword_count']
        
        if desc_count >= 2 and keyword_count >= 2:
            score += 15
            feedback_parts.append(f"✅ {desc_count} descriptions with concern keywords")
        elif desc_count >= 1:
            score += 10
            feedback_parts.append(f"⚠️ {desc_count} description(s) provided")
        else:
            feedback_parts.append("❌ No descriptions provided")
        
        # Criterion 5: Recommendation provided (10 points)
        if notes_data['recommendation']:
            score += 10
            feedback_parts.append(f"✅ Recommendation: {notes_data['recommendation']}")
        else:
            feedback_parts.append("⚠️ No clear recommendation provided")
        
        # Criterion 6: Playback speed setting (10 points bonus)
        config_container = '/tmp/vlc_preview_config.rc'
        config_local = os.path.join(temp_dir, 'vlcrc')
        
        speed_set = False
        speed_rate = 1.0
        
        try:
            copy_from_env(config_container, config_local)
            speed_set, speed_rate = check_playback_speed_config(config_local)
            
            if speed_set:
                score += 10
                feedback_parts.append(f"✅ Playback speed set to {speed_rate:.1f}x")
            else:
                feedback_parts.append(f"⚠️ Playback speed not clearly set (was {speed_rate:.1f}x)")
        except Exception as e:
            feedback_parts.append("⚠️ Could not verify playback speed from config")
        
        # Normalize score to 0-100
        score = min(score, max_score)
        
        # Success threshold: 70/100
        passed = score >= 70
        
        # Build final feedback
        feedback = "\n".join([
            "=" * 70,
            "📋 CONTENT PREVIEW VERIFICATION RESULTS",
            "=" * 70,
            "",
            *["  " + fp for fp in feedback_parts],
            "",
            f"TOTAL SCORE: {score:.0f}/{max_score:.0f}",
            f"STATUS: {'✅ PASS' if passed else '❌ FAIL'}",
            "",
            "Expected: Identify 2-3 problematic sections (~2:45, ~6:15, ~10:45),",
            "provide descriptions with concern keywords, and make a recommendation.",
            "=" * 70
        ])
        
        return {
            "passed": passed,
            "score": int(score),
            "feedback": feedback
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification error: {str(e)}"
        }
        
    finally:
        # Cleanup temp directory
        import shutil
        if os.path.exists(temp_dir):
            try:
                shutil.rmtree(temp_dir)
            except Exception as e:
                logger.warning(f"Failed to cleanup temp directory: {e}")


# Entry point for gym-anything
def verify(copy_from_env):
    """Wrapper for gym-anything verification."""
    # This wrapper is for compatibility if the framework calls verify() directly
    # with just copy_from_env function
    return verify_preview_content_safety(
        traj=None,
        env_info={'copy_from_env': copy_from_env},
        task_info={}
    )