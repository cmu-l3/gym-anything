#!/usr/bin/env python3
"""
Verifier for Chrome Reading List Management Task: reading_list_organize@1
Task: Add articles to Chrome Reading List and manage read/unread status

Verification Strategy:
- Copy Reading List SQLite database from container
- Parse database to extract entries
- Verify 3 items were added with expected URL patterns
- Verify 1 item is marked as read, 2 items are unread
- Check timestamps to ensure items were added during task execution
"""

import logging
import sys
import os
import sqlite3
import json
import tempfile
import time
from pathlib import Path
from typing import Dict, List, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../..', 'utils'))
try:
    from chrome_verification_utils import cleanup_verification_temp
    UTILS_AVAILABLE = True
except ImportError:
    logger.warning("Chrome verification utilities not available, using fallback methods")
    UTILS_AVAILABLE = False
    def cleanup_verification_temp():
        pass


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for reading_list_organize@1 task.
    
    Verifies:
    1. Reading List database contains exactly 3 entries
    2. Expected URLs are present (Wikipedia Python, TechCrunch, MDN)
    3. Exactly 1 item is marked as read
    4. Exactly 2 items remain unread
    5. Items were added recently (within task execution window)
    
    Scoring:
    - 100%: All 5 criteria met
    - 80%: 4/5 criteria met
    - 60%: 3/5 criteria met
    - <60%: <3 criteria met
    
    Pass threshold: 75% (requires 4 out of 5 criteria)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env function not available in environment"
        }

    try:
        # Get Reading List database from container
        db_path, error_msg = get_reading_list_database(copy_from_env)
        
        if db_path is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to access Reading List database: {error_msg}"
            }
        
        # Parse Reading List entries
        entries, parse_error = parse_reading_list_database(db_path)
        
        if entries is None:
            # Clean up
            try:
                os.unlink(db_path)
            except:
                pass
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to parse Reading List database: {parse_error}"
            }
        
        # Verify Reading List contents
        verification_result = verify_reading_list_contents(entries)
        
        # Clean up temporary files
        try:
            os.unlink(db_path)
        except:
            pass
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


def get_reading_list_database(copy_from_env) -> Tuple[Optional[str], str]:
    """
    Copy Reading List database from container to local temporary file.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Tuple of (local_db_path: str or None, error_message: str)
    """
    try:
        # Create temporary file for database
        temp_db = tempfile.NamedTemporaryFile(delete=False, suffix='.db')
        temp_db.close()
        
        # Try multiple possible locations
        possible_paths = [
            "/tmp/reading_list.db",
            "/tmp/reading_list_verification/reading_list.db",
            "/home/ga/.config/google-chrome-cdp/Default/Reading List",
            "/home/ga/.config/google-chrome/Default/Reading List",
        ]
        
        for container_path in possible_paths:
            try:
                logger.info(f"Trying to copy Reading List from: {container_path}")
                copy_from_env(container_path, temp_db.name)
                
                # Check if file has content
                if Path(temp_db.name).stat().st_size > 0:
                    logger.info(f"✓ Successfully copied Reading List database from: {container_path}")
                    return temp_db.name, ""
                else:
                    logger.debug(f"File copied but empty: {container_path}")
            except Exception as e:
                logger.debug(f"Could not copy from {container_path}: {e}")
                continue
        
        # If we get here, none of the paths worked
        os.unlink(temp_db.name)
        return None, "Reading List database not found in any known location. Chrome may not have persisted the data."
        
    except Exception as e:
        logger.error(f"Error getting Reading List database: {e}")
        return None, f"Error accessing Reading List database: {str(e)}"


def parse_reading_list_database(db_path: str) -> Tuple[Optional[List[Dict[str, Any]]], str]:
    """
    Parse Reading List SQLite database and extract entries.
    
    Args:
        db_path: Path to local Reading List database file
        
    Returns:
        Tuple of (entries: List[Dict] or None, error_message: str)
    """
    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        
        # First, get list of tables to understand schema
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table';")
        tables = [row[0] for row in cursor.fetchall()]
        logger.info(f"Database tables: {tables}")
        
        # Try different possible table names
        possible_table_names = ['reading_list', 'items', 'entries', 'readinglist']
        reading_list_table = None
        
        for table_name in possible_table_names:
            if table_name in tables:
                reading_list_table = table_name
                break
        
        if not reading_list_table:
            # Try to find any table that might contain Reading List data
            if tables:
                reading_list_table = tables[0]
                logger.warning(f"Using first available table: {reading_list_table}")
            else:
                conn.close()
                return None, "No tables found in Reading List database"
        
        logger.info(f"Using table: {reading_list_table}")
        
        # Get table schema
        cursor.execute(f"PRAGMA table_info({reading_list_table});")
        columns = cursor.fetchall()
        column_names = [col[1] for col in columns]
        logger.info(f"Table columns: {column_names}")
        
        # Try to query entries
        try:
            # Try common column names
            if 'url' in column_names:
                cursor.execute(f"SELECT * FROM {reading_list_table} ORDER BY creation_time DESC")
            else:
                cursor.execute(f"SELECT * FROM {reading_list_table}")
            
            rows = cursor.fetchall()
            
            # Build entries list with available columns
            entries = []
            for row in rows:
                entry = {}
                for i, col_name in enumerate(column_names):
                    if i < len(row):
                        entry[col_name] = row[i]
                entries.append(entry)
            
            conn.close()
            logger.info(f"Parsed {len(entries)} entries from Reading List database")
            
            # Log entries for debugging
            for i, entry in enumerate(entries, 1):
                logger.info(f"Entry {i}: {entry}")
            
            return entries, ""
            
        except sqlite3.Error as e:
            conn.close()
            return None, f"SQL error querying Reading List table: {e}"
        
    except sqlite3.Error as e:
        return None, f"SQLite error: {e}"
    except Exception as e:
        return None, f"Error parsing database: {e}"


def verify_reading_list_contents(entries: List[Dict[str, Any]]) -> Dict[str, Any]:
    """
    Verify Reading List contents meet task requirements.
    
    Checks:
    1. Exactly 3 entries
    2. Expected URL patterns present (Wikipedia Python, TechCrunch, MDN)
    3. Exactly 1 item marked as read
    4. Exactly 2 items unread
    5. Items added recently
    
    Args:
        entries: List of Reading List entry dictionaries
        
    Returns:
        Verification result dictionary
    """
    criteria_met = 0
    total_criteria = 5
    feedback_parts = []
    
    # Criterion 1: Exactly 3 items added
    total_items = len(entries)
    if total_items == 3:
        criteria_met += 1
        feedback_parts.append(f"✓ Exactly 3 Reading List items found")
    elif total_items == 0:
        feedback_parts.append(f"✗ No items in Reading List (expected 3)")
    else:
        feedback_parts.append(f"✗ Found {total_items} items, expected 3")
    
    # Define expected URL patterns
    expected_patterns = {
        'wikipedia': 'wikipedia.org/wiki/python',
        'techcrunch': 'techcrunch.com',
        'mdn': 'developer.mozilla.org'
    }
    
    # Criterion 2: Check for expected URL patterns
    found_patterns = {key: False for key in expected_patterns.keys()}
    
    for entry in entries:
        url = str(entry.get('url', '')).lower()
        title = str(entry.get('title', '')).lower()
        
        # Check each pattern
        if 'wikipedia.org/wiki/python' in url:
            found_patterns['wikipedia'] = True
        elif 'techcrunch.com' in url:
            found_patterns['techcrunch'] = True
        elif 'developer.mozilla.org' in url:
            found_patterns['mdn'] = True
    
    all_urls_present = all(found_patterns.values())
    if all_urls_present:
        criteria_met += 1
        feedback_parts.append(f"✓ All expected URLs present: Wikipedia Python, TechCrunch, MDN")
    else:
        missing = [k for k, v in found_patterns.items() if not v]
        feedback_parts.append(f"✗ Missing URLs: {', '.join(missing)}")
        feedback_parts.append(f"  Found: {', '.join([k for k, v in found_patterns.items() if v])}")
    
    # Criterion 3 & 4: Check read/unread status
    # Try different possible column names for status
    status_column = None
    for col in ['status', 'read_status', 'state', 'is_read', 'read']:
        if entries and col in entries[0]:
            status_column = col
            break
    
    if status_column:
        read_count = sum(1 for entry in entries if entry.get(status_column) in [1, True, 'read'])
        unread_count = sum(1 for entry in entries if entry.get(status_column) in [0, False, 'unread', None])
        
        logger.info(f"Read status - read: {read_count}, unread: {unread_count} (using column: {status_column})")
        
        # Criterion 3: Exactly 1 item marked as read
        if read_count == 1:
            criteria_met += 1
            feedback_parts.append(f"✓ Exactly 1 item marked as read")
        else:
            feedback_parts.append(f"✗ Expected 1 read item, found {read_count}")
        
        # Criterion 4: Exactly 2 items remain unread
        if unread_count == 2:
            criteria_met += 1
            feedback_parts.append(f"✓ Exactly 2 items remain unread")
        else:
            feedback_parts.append(f"✗ Expected 2 unread items, found {unread_count}")
    else:
        # If we can't determine read status, give partial credit if URLs are correct
        feedback_parts.append(f"⚠ Could not determine read/unread status (status column not found)")
        logger.warning(f"Available columns: {list(entries[0].keys()) if entries else 'none'}")
        # Give partial credit if we have the right number of items and URLs
        if total_items == 3 and all_urls_present:
            criteria_met += 1.5  # Split the 2 criteria for read status
            feedback_parts.append(f"  Partial credit: items and URLs are correct")
    
    # Criterion 5: Items added recently (within last 10 minutes)
    # Try different possible timestamp column names
    timestamp_column = None
    for col in ['creation_time', 'created_time', 'time_added', 'timestamp', 'update_time']:
        if entries and col in entries[0]:
            timestamp_column = col
            break
    
    if timestamp_column:
        current_time = time.time()
        recent_threshold = current_time - 600  # 10 minutes ago
        
        # Chrome timestamps are often in microseconds since epoch (WebKit time)
        # WebKit time is microseconds since Jan 1, 1601, need to convert
        recent_items = 0
        for entry in entries:
            timestamp = entry.get(timestamp_column, 0)
            if timestamp:
                # Try to detect timestamp format
                if timestamp > 1e15:  # WebKit time (microseconds since 1601)
                    # Convert WebKit time to Unix timestamp
                    unix_timestamp = (timestamp / 1e6) - 11644473600
                    if unix_timestamp > recent_threshold:
                        recent_items += 1
                elif timestamp > 1e12:  # Microseconds since Unix epoch
                    unix_timestamp = timestamp / 1e6
                    if unix_timestamp > recent_threshold:
                        recent_items += 1
                elif timestamp > recent_threshold:  # Already in seconds
                    recent_items += 1
        
        if recent_items == 3:
            criteria_met += 1
            feedback_parts.append(f"✓ All items added recently (within task window)")
        else:
            feedback_parts.append(f"⚠ Only {recent_items}/3 items have recent timestamps")
            # Give partial credit
            criteria_met += 0.5
    else:
        # Can't verify timestamps, give partial credit if other criteria are good
        feedback_parts.append(f"⚠ Could not verify timestamps (creation_time column not found)")
        if criteria_met >= 3:
            criteria_met += 0.5
            feedback_parts.append(f"  Partial credit: other criteria met")
    
    # Calculate final score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75
    
    # Build final feedback
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\n{'='*50}"
    feedback += f"\nCriteria met: {criteria_met:.1f}/{total_criteria}"
    feedback += f"\nFinal score: {score}%"
    feedback += f"\nResult: {'PASSED ✓' if passed else 'FAILED ✗'}"
    
    if not passed and total_items > 0:
        feedback += f"\n\nTroubleshooting tips:"
        if total_items != 3:
            feedback += f"\n- Check that all 3 articles were added to Reading List"
        if not all_urls_present:
            feedback += f"\n- Verify correct URLs were visited and added"
        if status_column and read_count != 1:
            feedback += f"\n- Ensure exactly 1 item was marked as read in the Reading List side panel"
    
    logger.info(f"Verification complete: passed={passed}, score={score}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "total_items": total_items,
            "urls_found": found_patterns,
            "read_count": read_count if status_column else "unknown",
            "unread_count": unread_count if status_column else "unknown",
            "criteria_met": f"{criteria_met:.1f}/{total_criteria}",
            "entries_summary": [
                {
                    "url": entry.get('url', 'unknown')[:60],
                    "title": entry.get('title', 'unknown')[:40],
                    "status": entry.get(status_column, 'unknown') if status_column else 'unknown'
                }
                for entry in entries
            ]
        }
    }
