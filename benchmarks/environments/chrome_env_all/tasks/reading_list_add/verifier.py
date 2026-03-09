#!/usr/bin/env python3
"""
Verifier for Chrome Reading List Task: reading_list_add@1
Task: Add a Wikipedia article on Artificial Intelligence to Chrome's Reading List

Verification Strategy:
- Copy Chrome data files from container (Preferences, ReadingList, etc.)
- Parse Reading List entries from multiple possible storage locations
- Verify target URL was added during task execution window
- Check metadata: timestamp, unread status, correct URL
- Ensure no duplicate entries were created
"""

import logging
import sys
import os
import json
import tempfile
import re
from pathlib import Path
from datetime import datetime, timedelta
from typing import Dict, List, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utilities to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../', 'utils'))
try:
    from chrome_verification_utils import cleanup_verification_temp
    UTILS_AVAILABLE = True
except ImportError:
    logger.warning("Chrome verification utilities not available, using fallback")
    UTILS_AVAILABLE = False
    def cleanup_verification_temp():
        pass


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for reading_list_add@1 task.
    
    Verifies that the target Wikipedia article was successfully added to Chrome's Reading List.
    
    Args:
        traj: Trajectory data (unused for this verification)
        env_info: Environment information including copy_from_env function
        task_info: Task configuration information
        
    Returns:
        Dict with 'passed', 'score', and 'feedback' keys
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available - cannot verify task"
        }

    # Target URL that should be in Reading List
    target_url = "https://en.wikipedia.org/wiki/Artificial_intelligence"
    
    try:
        # Get Reading List data from container
        reading_list_entries = extract_reading_list_data(copy_from_env)
        
        if reading_list_entries is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Failed to extract Reading List data from Chrome profile"
            }
        
        # Get task timing information
        task_start_time, task_end_time = get_task_timing(copy_from_env)
        
        # Verify Reading List entry
        verification_result = verify_reading_list_entry(
            reading_list_entries,
            target_url,
            task_start_time,
            task_end_time
        )
        
        # Clean up temporary files
        cleanup_verification_temp()
        
        return verification_result

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        cleanup_verification_temp()
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


def extract_reading_list_data(copy_from_env) -> Optional[List[Dict[str, Any]]]:
    """
    Extract Reading List entries from Chrome data files.
    
    Chrome stores Reading List data in different locations depending on version:
    - Chrome 89+: Preferences file under 'reading_list' key
    - Some versions: Separate ReadingList file
    - Experimental: ReadingListDB SQLite database
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        List of Reading List entry dictionaries, or None if extraction fails
    """
    reading_list_entries = []
    
    # Try Method 1: Preferences file (most common in recent Chrome)
    logger.info("Attempting to extract Reading List from Preferences file...")
    entries = extract_from_preferences(copy_from_env)
    if entries:
        logger.info(f"✓ Found {len(entries)} entries in Preferences")
        reading_list_entries.extend(entries)
    
    # Try Method 2: Dedicated ReadingList file
    if not reading_list_entries:
        logger.info("Attempting to extract from ReadingList file...")
        entries = extract_from_reading_list_file(copy_from_env)
        if entries:
            logger.info(f"✓ Found {len(entries)} entries in ReadingList file")
            reading_list_entries.extend(entries)
    
    # Try Method 3: Local State file (alternative location)
    if not reading_list_entries:
        logger.info("Attempting to extract from Local State file...")
        entries = extract_from_local_state(copy_from_env)
        if entries:
            logger.info(f"✓ Found {len(entries)} entries in Local State")
            reading_list_entries.extend(entries)
    
    if not reading_list_entries:
        logger.warning("No Reading List entries found in any location")
        return None
    
    return reading_list_entries


def extract_from_preferences(copy_from_env) -> List[Dict[str, Any]]:
    """Extract Reading List from Preferences file."""
    temp_file = None
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        
        # Try multiple locations
        paths_to_try = [
            "/tmp/reading_list_export/Preferences.json",
            "/home/ga/.config/google-chrome-cdp/Default/Preferences",
            "/home/ga/.config/google-chrome/Default/Preferences"
        ]
        
        prefs_data = None
        for container_path in paths_to_try:
            try:
                logger.debug(f"Trying to copy Preferences from: {container_path}")
                copy_from_env(container_path, temp_file.name)
                
                if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) > 0:
                    with open(temp_file.name, 'r', encoding='utf-8') as f:
                        prefs_data = json.load(f)
                    logger.info(f"Successfully loaded Preferences from: {container_path}")
                    break
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                continue
        
        if not prefs_data:
            return []
        
        # Navigate to reading_list in Preferences
        # Possible structures:
        # 1. prefs['reading_list']['entries']
        # 2. prefs['reading_list']
        # 3. prefs['account_info'][...]['reading_list']
        
        reading_list = prefs_data.get('reading_list', {})
        
        if isinstance(reading_list, dict):
            entries = reading_list.get('entries', [])
            if entries:
                return entries
        
        # Try alternative structure
        if 'account_info' in prefs_data:
            for account in prefs_data.get('account_info', []):
                if isinstance(account, dict) and 'reading_list' in account:
                    entries = account['reading_list'].get('entries', [])
                    if entries:
                        return entries
        
        return []
        
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse Preferences JSON: {e}")
        return []
    except Exception as e:
        logger.error(f"Error extracting from Preferences: {e}")
        return []
    finally:
        if temp_file and os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass


def extract_from_reading_list_file(copy_from_env) -> List[Dict[str, Any]]:
    """Extract Reading List from dedicated ReadingList file."""
    temp_file = None
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False)
        temp_file.close()
        
        paths_to_try = [
            "/tmp/reading_list_export/ReadingList",
            "/home/ga/.config/google-chrome-cdp/Default/ReadingList",
            "/home/ga/.config/google-chrome/Default/ReadingList"
        ]
        
        for container_path in paths_to_try:
            try:
                copy_from_env(container_path, temp_file.name)
                
                if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) > 0:
                    # Try to parse as JSON
                    with open(temp_file.name, 'r', encoding='utf-8') as f:
                        data = json.load(f)
                    
                    if isinstance(data, list):
                        return data
                    elif isinstance(data, dict):
                        return data.get('entries', [])
            except Exception as e:
                logger.debug(f"Failed to extract from {container_path}: {e}")
                continue
        
        return []
        
    except Exception as e:
        logger.error(f"Error extracting from ReadingList file: {e}")
        return []
    finally:
        if temp_file and os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass


def extract_from_local_state(copy_from_env) -> List[Dict[str, Any]]:
    """Extract Reading List from Local State file."""
    temp_file = None
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        
        paths_to_try = [
            "/tmp/reading_list_export/LocalState.json",
            "/home/ga/.config/google-chrome-cdp/Local State",
            "/home/ga/.config/google-chrome/Local State"
        ]
        
        for container_path in paths_to_try:
            try:
                copy_from_env(container_path, temp_file.name)
                
                if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) > 0:
                    with open(temp_file.name, 'r', encoding='utf-8') as f:
                        data = json.load(f)
                    
                    reading_list = data.get('reading_list', {})
                    if isinstance(reading_list, dict):
                        entries = reading_list.get('entries', [])
                        if entries:
                            return entries
            except Exception as e:
                logger.debug(f"Failed to extract from {container_path}: {e}")
                continue
        
        return []
        
    except Exception as e:
        logger.error(f"Error extracting from Local State: {e}")
        return []
    finally:
        if temp_file and os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass


def get_task_timing(copy_from_env) -> Tuple[Optional[int], Optional[int]]:
    """
    Get task start and end times from exported timing files.
    
    Returns:
        Tuple of (start_timestamp, end_timestamp) in seconds since epoch
    """
    try:
        temp_start = tempfile.NamedTemporaryFile(delete=False)
        temp_start.close()
        copy_from_env("/tmp/reading_list_export/task_start_time.txt", temp_start.name)
        
        with open(temp_start.name, 'r') as f:
            start_time = int(f.read().strip())
        
        os.unlink(temp_start.name)
        
        temp_end = tempfile.NamedTemporaryFile(delete=False)
        temp_end.close()
        copy_from_env("/tmp/reading_list_export/task_end_time.txt", temp_end.name)
        
        with open(temp_end.name, 'r') as f:
            end_time = int(f.read().strip())
        
        os.unlink(temp_end.name)
        
        logger.info(f"Task timing: start={start_time}, end={end_time}, duration={end_time - start_time}s")
        return start_time, end_time
        
    except Exception as e:
        logger.warning(f"Could not get task timing: {e}")
        # Return None to skip timestamp validation
        return None, None


def verify_reading_list_entry(
    entries: List[Dict[str, Any]],
    target_url: str,
    task_start_time: Optional[int],
    task_end_time: Optional[int]
) -> Dict[str, Any]:
    """
    Verify that the target URL was added to Reading List with correct metadata.
    
    Checks:
    1. Target URL exists in Reading List
    2. Entry was added during task execution window (timestamp validation)
    3. Entry is marked as unread
    4. Only one instance of the URL exists (no duplicates)
    
    Args:
        entries: List of Reading List entry dictionaries
        target_url: Expected URL that should be in Reading List
        task_start_time: Task start timestamp (seconds since epoch)
        task_end_time: Task end timestamp (seconds since epoch)
        
    Returns:
        Verification result dictionary
    """
    if not entries:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No Reading List entries found. The Reading List appears to be empty."
        }
    
    logger.info(f"Analyzing {len(entries)} Reading List entries...")
    
    # Normalize target URL for comparison
    target_normalized = normalize_url(target_url)
    
    # Find matching entries
    matching_entries = []
    for entry in entries:
        entry_url = entry.get('url', '')
        if normalize_url(entry_url) == target_normalized:
            matching_entries.append(entry)
    
    # Criterion 1: URL exists
    url_exists = len(matching_entries) > 0
    
    if not url_exists:
        # Check if a similar Wikipedia AI article was added
        similar_entries = []
        for entry in entries:
            entry_url = entry.get('url', '').lower()
            if 'wikipedia.org' in entry_url and 'artificial' in entry_url:
                similar_entries.append(entry)
        
        if similar_entries:
            feedback = f"Target URL not found, but found similar Wikipedia article(s): {[e.get('url', '') for e in similar_entries]}"
            return {
                "passed": False,
                "score": 50,
                "feedback": feedback,
                "details": {
                    "url_exists": False,
                    "similar_found": True,
                    "similar_urls": [e.get('url', '') for e in similar_entries]
                }
            }
        
        # List what URLs were found for debugging
        found_urls = [e.get('url', '') for e in entries[:5]]  # First 5 entries
        feedback = f"Target URL not found in Reading List. Found {len(entries)} total entries. Sample URLs: {found_urls}"
        return {
            "passed": False,
            "score": 0,
            "feedback": feedback,
            "details": {
                "url_exists": False,
                "total_entries": len(entries),
                "sample_urls": found_urls
            }
        }
    
    logger.info(f"✓ Found {len(matching_entries)} matching entry(ies)")
    
    # Use the first matching entry for detailed verification
    entry = matching_entries[0]
    
    # Criterion 2: Recent addition (timestamp validation)
    timestamp_ok = True
    timestamp_feedback = ""
    
    if task_start_time and task_end_time:
        # Chrome timestamps are typically in microseconds since Windows epoch
        # or Unix epoch - we need to parse and convert
        
        creation_time = entry.get('creation_time', entry.get('time_added', entry.get('timestamp', 0)))
        
        if creation_time:
            # Try to convert Chrome timestamp to Unix timestamp
            # Chrome uses microseconds since Windows epoch (1601-01-01)
            # Windows epoch to Unix epoch: 11644473600 seconds
            
            try:
                if creation_time > 1e16:  # Likely in microseconds
                    creation_time_seconds = creation_time / 1e6
                    
                    # Check if it's Windows epoch (very large number)
                    if creation_time_seconds > 1e10:
                        # Convert from Windows epoch to Unix epoch
                        creation_time_unix = creation_time_seconds - 11644473600
                    else:
                        creation_time_unix = creation_time_seconds
                else:
                    creation_time_unix = creation_time
                
                # Add buffer of 300 seconds before start and after end
                buffer = 300
                if not (task_start_time - buffer <= creation_time_unix <= task_end_time + buffer):
                    timestamp_ok = False
                    timestamp_feedback = f"Entry timestamp ({datetime.fromtimestamp(creation_time_unix)}) outside task window"
                    logger.warning(timestamp_feedback)
                else:
                    timestamp_feedback = "Entry added during task execution"
                    logger.info(f"✓ {timestamp_feedback}")
            except Exception as e:
                logger.warning(f"Could not parse timestamp: {e}")
                timestamp_feedback = "Timestamp validation skipped"
        else:
            timestamp_feedback = "No timestamp found in entry"
            logger.warning(timestamp_feedback)
    else:
        timestamp_feedback = "Task timing not available, timestamp check skipped"
        logger.info(timestamp_feedback)
    
    # Criterion 3: Unread status
    is_read = entry.get('read', entry.get('status', '') == 'read')
    is_unread = not is_read
    
    if is_unread:
        logger.info("✓ Entry marked as unread")
    else:
        logger.warning("Entry marked as read (expected unread)")
    
    # Criterion 4: No duplicates
    no_duplicates = len(matching_entries) == 1
    
    if no_duplicates:
        logger.info("✓ No duplicate entries")
    else:
        logger.warning(f"Found {len(matching_entries)} duplicate entries")
    
    # Calculate score
    criteria_results = [
        url_exists,  # Always True at this point
        timestamp_ok,
        is_unread,
        no_duplicates
    ]
    
    criteria_met = sum(criteria_results)
    score = (criteria_met / 4) * 100
    passed = score >= 75  # Need at least 3/4 criteria
    
    # Generate feedback
    feedback_parts = []
    feedback_parts.append(f"Reading List Verification: {criteria_met}/4 criteria met")
    feedback_parts.append(f"- URL present: ✓ (found in Reading List)")
    feedback_parts.append(f"- Recent addition: {'✓' if timestamp_ok else '✗'} ({timestamp_feedback})")
    feedback_parts.append(f"- Unread status: {'✓' if is_unread else '✗'} (marked as {'unread' if is_unread else 'read'})")
    feedback_parts.append(f"- No duplicates: {'✓' if no_duplicates else '✗'} ({len(matching_entries)} instance(s) found)")
    
    if passed:
        feedback_parts.append("✅ Successfully added article to Reading List!")
    else:
        feedback_parts.append("⚠ Article added but with issues - see criteria above")
    
    feedback = "\n".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": feedback,
        "details": {
            "url_exists": url_exists,
            "timestamp_ok": timestamp_ok,
            "is_unread": is_unread,
            "no_duplicates": no_duplicates,
            "criteria_met": criteria_met,
            "matching_entries_count": len(matching_entries),
            "total_entries": len(entries)
        }
    }


def normalize_url(url: str) -> str:
    """
    Normalize URL for comparison.
    
    Handles:
    - Protocol differences (http vs https)
    - Trailing slashes
    - URL encoding
    - Case sensitivity
    """
    if not url:
        return ""
    
    url = url.lower().strip()
    
    # Remove protocol
    url = re.sub(r'^https?://', '', url)
    
    # Remove www. prefix
    url = re.sub(r'^www\.', '', url)
    
    # Remove trailing slash
    url = url.rstrip('/')
    
    # Remove URL fragments
    url = re.sub(r'#.*$', '', url)
    
    # Remove query parameters for comparison (optional)
    # url = re.sub(r'\?.*$', '', url)
    
    return url
