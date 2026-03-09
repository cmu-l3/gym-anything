#!/usr/bin/env python3
"""
Verifier for Export Playback History task
"""

import sys
import os
import logging
import tempfile
import csv
from pathlib import Path
from typing import Dict, List, Any

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def is_media_file(filename: str) -> bool:
    """Check if filename appears to be a media file."""
    media_extensions = {
        '.mp4', '.mkv', '.avi', '.mov', '.flv', '.wmv', '.webm', '.m4v',
        '.mp3', '.flac', '.aac', '.ogg', '.wav', '.wma', '.m4a',
        '.mpg', '.mpeg', '.3gp', '.ogv', '.vob', '.ts'
    }
    
    filename_lower = filename.lower()
    return any(ext in filename_lower for ext in media_extensions)


def has_timestamp_like_data(value: str) -> bool:
    """Check if value looks like timestamp data."""
    if not value or len(str(value)) < 5:
        return False
    
    value_str = str(value)
    
    # Check for various timestamp patterns
    timestamp_indicators = [
        ':',  # Time separator (HH:MM:SS)
        '-',  # Date separator (YYYY-MM-DD)
        '/',  # Date separator (MM/DD/YYYY)
        ' ',  # Date-time separator
    ]
    
    # Check if it's a Unix timestamp (large number)
    if value_str.isdigit() and len(value_str) >= 10:
        return True
    
    # Check for timestamp patterns
    return any(indicator in value_str for indicator in timestamp_indicators)


def is_human_readable(value: str) -> bool:
    """Check if value is in human-readable format (not just encoded URI or epoch)."""
    if not value:
        return False
    
    value_str = str(value)
    
    # Human readable if contains readable separators
    human_indicators = [':', '-', ' ', '/']
    has_indicators = any(ind in value_str for ind in human_indicators)
    
    # Not human readable if it's URL encoded
    if '%20' in value_str or '%2F' in value_str:
        return False
    
    # Not human readable if it's just a large number (Unix epoch)
    if value_str.isdigit() and len(value_str) >= 10:
        return False
    
    return has_indicators


def verify_export_playback_history(traj, env_info, task_info):
    """
    Verify export playback history task completion.
    
    Checks:
    1. CSV file exists
    2. Valid CSV format with headers
    3. Has expected column names (filename/path/timestamp)
    4. At least 3 media file entries
    5. Valid filenames with media extensions
    6. Timestamp/date information present
    7. Human-readable format (not encoded URIs or raw epoch)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria = {
        'file_exists': False,
        'valid_format': False,
        'has_headers': False,
        'sufficient_entries': False,
        'valid_filenames': False,
        'timestamp_present': False,
        'human_readable': False
    }
    
    feedback_parts = []
    
    # Copy CSV file from container
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv', mode='w+')
    temp_csv_path = temp_csv.name
    temp_csv.close()
    
    try:
        copy_from_env("/tmp/vlc_history_export.csv", temp_csv_path)
    except Exception as e:
        logger.error(f"Failed to copy CSV file: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"CSV file not found or could not be copied: {str(e)}"
        }
    
    # Check file exists and has content
    if not os.path.exists(temp_csv_path):
        os.unlink(temp_csv_path)
        return {
            "passed": False,
            "score": 0,
            "feedback": "CSV file not found at expected location"
        }
    
    file_size = os.path.getsize(temp_csv_path)
    if file_size < 50:  # Very small file
        os.unlink(temp_csv_path)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"CSV file too small ({file_size} bytes), likely empty or incomplete"
        }
    
    criteria['file_exists'] = True
    feedback_parts.append(f"✅ CSV file exists ({file_size} bytes)")
    
    # Parse CSV
    try:
        with open(temp_csv_path, 'r', encoding='utf-8', errors='ignore') as f:
            # Try to detect delimiter
            sample = f.read(1024)
            f.seek(0)
            
            # Use csv.Sniffer to detect format
            try:
                dialect = csv.Sniffer().sniff(sample)
                reader = csv.DictReader(f, dialect=dialect)
            except:
                # Fallback to default comma delimiter
                f.seek(0)
                reader = csv.DictReader(f)
            
            headers = reader.fieldnames
            rows = list(reader)
            
    except Exception as e:
        logger.error(f"Failed to parse CSV: {e}")
        os.unlink(temp_csv_path)
        return {
            "passed": False,
            "score": int((1 / 7) * 100),  # Only file_exists passed
            "feedback": f"CSV file exists but has invalid format: {str(e)}"
        }
    
    criteria['valid_format'] = True
    feedback_parts.append("✅ Valid CSV format")
    
    # Check headers
    if not headers or len(headers) == 0:
        os.unlink(temp_csv_path)
        return {
            "passed": False,
            "score": int((2 / 7) * 100),
            "feedback": "CSV has no headers"
        }
    
    # Check for expected column names (flexible matching)
    headers_lower = [h.lower().strip() for h in headers if h]
    
    has_filename = any(
        'name' in h or 'file' in h or 'title' in h or 'media' in h 
        for h in headers_lower
    )
    
    has_path = any(
        'path' in h or 'location' in h or 'url' in h or 'uri' in h
        for h in headers_lower
    )
    
    has_timestamp = any(
        'time' in h or 'date' in h or 'played' in h or 'stamp' in h or 'when' in h
        for h in headers_lower
    )
    
    # Need at least 2 of 3 expected header types
    header_score = sum([has_filename, has_path, has_timestamp])
    
    if header_score >= 2:
        criteria['has_headers'] = True
        feedback_parts.append(f"✅ Has expected headers ({', '.join(headers[:4])})")
    else:
        feedback_parts.append(f"⚠️ Headers may be incomplete ({', '.join(headers[:4])})")
    
    # Check entry count
    num_rows = len(rows)
    
    if num_rows >= 3:
        criteria['sufficient_entries'] = True
        feedback_parts.append(f"✅ Has {num_rows} entries (≥3 required)")
    else:
        feedback_parts.append(f"❌ Only {num_rows} entries (need ≥3)")
    
    # Check for valid media filenames
    valid_media_count = 0
    has_timestamps_count = 0
    human_readable_count = 0
    
    for row in rows:
        # Check if any cell contains a media filename
        row_text = ' '.join(str(v) for v in row.values() if v)
        
        if is_media_file(row_text):
            valid_media_count += 1
        
        # Check for timestamp-like data
        for value in row.values():
            if value and has_timestamp_like_data(str(value)):
                has_timestamps_count += 1
                break
        
        # Check for human readability
        for value in row.values():
            if value and is_human_readable(str(value)):
                human_readable_count += 1
                break
    
    if valid_media_count >= 3:
        criteria['valid_filenames'] = True
        feedback_parts.append(f"✅ {valid_media_count} valid media files found")
    else:
        feedback_parts.append(f"⚠️ Only {valid_media_count} valid media files found")
    
    if has_timestamps_count >= 2:
        criteria['timestamp_present'] = True
        feedback_parts.append(f"✅ Timestamps present ({has_timestamps_count} entries)")
    else:
        feedback_parts.append(f"❌ Insufficient timestamp data ({has_timestamps_count} entries)")
    
    # Human readable check (either timestamps OR filenames should be readable)
    if human_readable_count >= 2 or valid_media_count >= 3:
        criteria['human_readable'] = True
        feedback_parts.append("✅ Data is human-readable")
    else:
        feedback_parts.append("⚠️ Data may not be fully human-readable")
    
    # Clean up temp file
    os.unlink(temp_csv_path)
    
    # Calculate score
    criteria_met = sum(criteria.values())
    score = int((criteria_met / len(criteria)) * 100)
    passed = score >= 70  # Need 5/7 criteria (≈71%)
    
    feedback = " | ".join(feedback_parts)
    
    logger.info(f"Verification complete: {criteria_met}/{len(criteria)} criteria met")
    logger.info(f"Score: {score}%, Passed: {passed}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "criteria_met": criteria_met,
        "total_criteria": len(criteria),
        "details": criteria
    }