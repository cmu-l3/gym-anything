#!/usr/bin/env python3
"""
Verifier for Extract Embedded Subtitles task
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


def validate_srt_format(filepath: str) -> tuple:
    """
    Validate SRT subtitle file format.
    
    Returns:
        Tuple of (is_valid, entry_count, feedback_message, issues)
    """
    try:
        with open(filepath, 'r', encoding='utf-8', errors='replace') as f:
            content = f.read()
        
        # Check if file is empty or too small
        if not content or len(content) < 50:
            return False, 0, "File empty or too small", ["File size < 50 bytes"]
        
        # SRT format validation
        issues = []
        
        # Match SRT timestamp pattern: HH:MM:SS,mmm --> HH:MM:SS,mmm
        timestamp_pattern = r'\d{2}:\d{2}:\d{2},\d{3}\s*-->\s*\d{2}:\d{2}:\d{2},\d{3}'
        timestamps = re.findall(timestamp_pattern, content)
        
        entry_count = len(timestamps)
        
        if entry_count < 10:
            issues.append(f"Too few subtitle entries: {entry_count} (expected ≥10)")
            return False, entry_count, f"Insufficient entries: {entry_count}", issues
        
        # Check for actual text content (not just timestamps and numbers)
        lines = content.strip().split('\n')
        text_lines = []
        
        for line in lines:
            stripped = line.strip()
            # Skip empty lines, sequence numbers, and timestamp lines
            if stripped and not stripped.isdigit() and '-->' not in stripped:
                text_lines.append(stripped)
        
        # We should have at least one text line per subtitle entry
        if len(text_lines) < entry_count * 0.5:
            issues.append("Insufficient text content relative to timestamps")
            return False, entry_count, "Missing subtitle text", issues
        
        # Check for reasonable text content (not just gibberish)
        total_text_length = sum(len(line) for line in text_lines)
        avg_text_length = total_text_length / len(text_lines) if text_lines else 0
        
        if avg_text_length < 5:
            issues.append(f"Text lines too short (avg: {avg_text_length:.1f} chars)")
        
        # Validate timestamp sequencing (at least check a few)
        timestamp_values = []
        for ts_match in timestamps[:5]:  # Check first 5
            # Parse "HH:MM:SS,mmm --> HH:MM:SS,mmm"
            parts = ts_match.split('-->')
            if len(parts) == 2:
                start_time = parts[0].strip()
                # Convert to seconds for comparison
                try:
                    h, m, s = start_time.split(':')
                    s, ms = s.split(',')
                    seconds = int(h) * 3600 + int(m) * 60 + int(s) + int(ms) / 1000
                    timestamp_values.append(seconds)
                except:
                    pass
        
        # Check if timestamps are roughly sequential
        if len(timestamp_values) >= 2:
            is_sequential = all(timestamp_values[i] <= timestamp_values[i+1] 
                              for i in range(len(timestamp_values)-1))
            if not is_sequential:
                issues.append("Timestamps not sequential")
        
        return True, entry_count, f"Valid SRT with {entry_count} entries", issues
        
    except UnicodeDecodeError:
        return False, 0, "File encoding error (not valid UTF-8)", ["Encoding error"]
    except Exception as e:
        logger.error(f"Validation error: {e}", exc_info=True)
        return False, 0, f"Validation error: {str(e)}", [str(e)]


def check_subtitle_language(filepath: str) -> tuple:
    """
    Simple heuristic check if subtitle content is likely English.
    
    Returns:
        Tuple of (likely_english, confidence, sample_text)
    """
    try:
        with open(filepath, 'r', encoding='utf-8', errors='replace') as f:
            content = f.read()
        
        # Extract text lines (skip numbers and timestamps)
        lines = content.strip().split('\n')
        text_lines = []
        for line in lines:
            stripped = line.strip()
            if stripped and not stripped.isdigit() and '-->' not in stripped:
                text_lines.append(stripped)
        
        if not text_lines:
            return False, 0.0, ""
        
        # Sample first few text lines
        sample_text = ' '.join(text_lines[:5])
        
        # Simple heuristic: check for common English words
        english_markers = ['the', 'is', 'a', 'this', 'to', 'you', 'and', 'of', 'in', 'it']
        text_lower = sample_text.lower()
        
        matches = sum(1 for marker in english_markers if marker in text_lower)
        confidence = matches / len(english_markers)
        
        # Check for Spanish/French markers (should NOT be present)
        spanish_markers = ['hola', 'este es', 'necesitas', 'múltiples', 'los subtítulos']
        french_markers = ['bonjour', 'ceci est', 'vous devez', 'plusieurs', 'les sous-titres']
        
        spanish_matches = sum(1 for marker in spanish_markers if marker in text_lower)
        french_matches = sum(1 for marker in french_markers if marker in text_lower)
        
        # If we detect Spanish or French markers, reduce confidence significantly
        if spanish_matches > 0 or french_matches > 0:
            confidence *= 0.2
        
        likely_english = confidence >= 0.3
        
        return likely_english, confidence, sample_text[:100]
        
    except Exception as e:
        logger.error(f"Language check error: {e}")
        return False, 0.0, ""


def verify_extract_subtitles(traj, env_info, task_info):
    """
    Verify extract embedded subtitles task completion.
    
    Checks:
    1. Extracted subtitle file exists
    2. File is valid SRT format with proper structure
    3. Contains sufficient subtitle entries (≥10)
    4. Proper encoding and content quality
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_met = 0
    total_criteria = 4
    feedback_parts = []
    
    # Copy extracted subtitle file
    temp_subtitle = tempfile.NamedTemporaryFile(delete=False, suffix='.srt')
    
    try:
        try:
            copy_from_env("/tmp/vlc_extracted_subtitle.srt", temp_subtitle.name)
        except Exception as e:
            logger.error(f"Error copying subtitle file: {e}", exc_info=True)
            return {"passed": False, "score": 0, "feedback": f"Subtitle file not found: {str(e)}"}
        
        # Check if file exists and has content
        if not os.path.exists(temp_subtitle.name) or os.path.getsize(temp_subtitle.name) == 0:
            return {"passed": False, "score": 0, "feedback": "Extracted subtitle file is empty or missing"}
        
        file_size_kb = os.path.getsize(temp_subtitle.name) / 1024
        
        criteria_met += 1
        feedback_parts.append(f"✅ Subtitle file exists ({file_size_kb:.1f} KB)")
        
        # Validate SRT format
        is_valid, entry_count, message, issues = validate_srt_format(temp_subtitle.name)
        
        if is_valid:
            criteria_met += 1
            feedback_parts.append(f"✅ Valid SRT format: {message}")
        else:
            feedback_parts.append(f"❌ Invalid SRT format: {message}")
            if issues:
                feedback_parts.append(f"Issues: {'; '.join(issues[:2])}")
        
        # Check entry count criterion
        if entry_count >= 10:
            criteria_met += 1
            feedback_parts.append(f"✅ Sufficient content ({entry_count} entries)")
        elif entry_count > 0:
            feedback_parts.append(f"⚠️ Incomplete extraction ({entry_count} entries, expected ≥10)")
        else:
            feedback_parts.append("❌ No subtitle entries found")
        
        # Check encoding and content quality
        try:
            with open(temp_subtitle.name, 'r', encoding='utf-8') as f:
                content = f.read()
                
                # Check for reasonable content
                if len(content) > 200 and '\n' in content:
                    criteria_met += 1
                    feedback_parts.append("✅ Proper encoding and structure")
                else:
                    feedback_parts.append("⚠️ Content may be incomplete")
        except UnicodeDecodeError:
            feedback_parts.append("❌ Encoding error (not UTF-8)")
        except Exception as e:
            feedback_parts.append(f"⚠️ Content check failed: {str(e)}")
        
        # Optional: Check if content is English (bonus, not counted in main criteria)
        if is_valid and entry_count >= 5:
            likely_english, confidence, sample = check_subtitle_language(temp_subtitle.name)
            if likely_english:
                feedback_parts.append(f"📝 Content appears English (conf: {confidence:.0%})")
            else:
                feedback_parts.append(f"⚠️ May not be English track (conf: {confidence:.0%})")
        
        # Clean up temp file
        os.unlink(temp_subtitle.name)
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        if os.path.exists(temp_subtitle.name):
            os.unlink(temp_subtitle.name)
        return {"passed": False, "score": 0, "feedback": f"Verification failed: {str(e)}"}
    
    # Check completion marker
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_extract_subs_completed.txt", temp_marker.name)
        feedback_parts.append("✅ Task completed")
        os.unlink(temp_marker.name)
    except Exception:
        feedback_parts.append("⚠️ Completion marker not found")
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }