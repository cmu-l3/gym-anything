#!/usr/bin/env python3
"""
Verifier for Chrome Reading List Task: reading_list_articles@1
Task: Add 3 articles to Chrome's Reading List for later reading

Verification Strategy:
- Copy Chrome Bookmarks file from container (Reading List stored here)
- Parse JSON structure to find Reading List entries
- Check multiple possible locations for Reading List in Chrome's data structure
- Validate that at least 3 entries exist with valid URLs
- Verify entries are recent (added during this task)
- Ensure entries are in Reading List, not regular bookmarks
"""

import logging
import sys
import os
import json
import time
import tempfile
from pathlib import Path
from typing import Dict, List, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../', 'utils'))
try:
    from chrome_verification_utils import (
        copy_chrome_file,
        parse_bookmarks,
        cleanup_verification_temp
    )
    UTILS_AVAILABLE = True
except ImportError:
    logger.warning("Chrome verification utilities not available, using fallback methods")
    UTILS_AVAILABLE = False
    
    def parse_bookmarks(path):
        with open(path, 'r', encoding='utf-8') as f:
            return json.load(f)
    
    def cleanup_verification_temp():
        pass


def find_reading_list_entries(bookmarks_data: Dict[str, Any]) -> List[Dict[str, Any]]:
    """
    Find Reading List entries in Chrome's Bookmarks structure.
    
    Chrome stores Reading List in various locations depending on version:
    - roots.reading_list (newer Chrome versions)
    - roots.other with power_bookmark_meta
    - Anywhere in tree with reading list metadata
    
    Args:
        bookmarks_data: Parsed Bookmarks JSON data
        
    Returns:
        List of Reading List entry dictionaries
    """
    entries = []
    
    if not bookmarks_data or 'roots' not in bookmarks_data:
        logger.warning("Invalid bookmarks data structure")
        return entries
    
    roots = bookmarks_data.get('roots', {})
    
    # Method 1: Direct reading_list section (Chrome 89+)
    if 'reading_list' in roots:
        reading_list_section = roots['reading_list']
        children = reading_list_section.get('children', [])
        logger.info(f"Found {len(children)} entries in roots.reading_list")
        entries.extend(children)
    
    # Method 2: Check 'other' bookmarks for reading list items
    if 'other' in roots:
        other_section = roots['other']
        other_children = other_section.get('children', [])
        for child in other_children:
            if is_reading_list_item(child):
                entries.append(child)
                logger.info(f"Found reading list item in 'other': {child.get('name', 'Unknown')}")
    
    # Method 3: Recursive search for reading list items anywhere
    additional_entries = find_reading_list_recursive(bookmarks_data)
    
    # Deduplicate entries by URL
    seen_urls = set()
    unique_entries = []
    
    for entry in entries + additional_entries:
        url = entry.get('url', '')
        if url and url not in seen_urls:
            seen_urls.add(url)
            unique_entries.append(entry)
    
    logger.info(f"Total unique Reading List entries found: {len(unique_entries)}")
    return unique_entries


def is_reading_list_item(item: Dict[str, Any]) -> bool:
    """
    Check if a bookmark item is a Reading List entry.
    
    Reading List items have special metadata fields.
    
    Args:
        item: Bookmark item dictionary
        
    Returns:
        True if item is a Reading List entry
    """
    if item.get('type') != 'url':
        return False
    
    # Check for power_bookmark_meta (Reading List marker)
    meta_info = item.get('meta_info', {})
    if 'power_bookmark_meta' in meta_info:
        return True
    
    # Alternative: Check for reading list specific fields
    if 'reading_list' in str(meta_info):
        return True
    
    return False


def find_reading_list_recursive(node: Any) -> List[Dict[str, Any]]:
    """
    Recursively search for Reading List items in bookmark tree.
    
    Args:
        node: Current node in bookmark tree
        
    Returns:
        List of Reading List entries found
    """
    entries = []
    
    if isinstance(node, dict):
        # Check if this node itself is a reading list item
        if is_reading_list_item(node):
            entries.append(node)
        
        # Recurse into children
        if 'children' in node:
            for child in node['children']:
                entries.extend(find_reading_list_recursive(child))
        
        # Recurse into all dict values
        for value in node.values():
            if isinstance(value, (dict, list)):
                entries.extend(find_reading_list_recursive(value))
    
    elif isinstance(node, list):
        for item in node:
            entries.extend(find_reading_list_recursive(item))
    
    return entries


def filter_recent_entries(entries: List[Dict[str, Any]], max_age_seconds: int = 600) -> List[Dict[str, Any]]:
    """
    Filter entries to only those added recently (during this task).
    
    Args:
        entries: List of Reading List entries
        max_age_seconds: Maximum age in seconds (default: 10 minutes)
        
    Returns:
        List of recent entries
    """
    current_time_us = int(time.time() * 1000000)  # Chrome uses microseconds
    max_age_us = max_age_seconds * 1000000
    
    recent_entries = []
    
    for entry in entries:
        date_added = entry.get('date_added')
        
        if not date_added:
            logger.warning(f"Entry missing date_added: {entry.get('name', 'Unknown')}")
            continue
        
        try:
            date_added_us = int(date_added)
            age_us = current_time_us - date_added_us
            
            if 0 < age_us < max_age_us:
                recent_entries.append(entry)
                age_seconds = age_us / 1000000
                logger.info(f"Recent entry: {entry.get('name', 'Unknown')} (age: {age_seconds:.1f}s)")
            else:
                logger.debug(f"Entry too old: {entry.get('name', 'Unknown')} (age: {age_us / 1000000:.1f}s)")
        
        except (ValueError, TypeError) as e:
            logger.warning(f"Invalid date_added for entry: {e}")
            continue
    
    return recent_entries


def validate_reading_list_entries(entries: List[Dict[str, Any]]) -> Tuple[List[Dict[str, Any]], List[str]]:
    """
    Validate Reading List entries have required fields.
    
    Args:
        entries: List of Reading List entries
        
    Returns:
        Tuple of (valid_entries, validation_errors)
    """
    valid_entries = []
    errors = []
    
    for i, entry in enumerate(entries):
        entry_name = entry.get('name', f'Entry {i+1}')
        
        # Check for URL
        url = entry.get('url', '')
        if not url:
            errors.append(f"{entry_name}: Missing URL")
            continue
        
        if not url.startswith('http'):
            errors.append(f"{entry_name}: Invalid URL format: {url}")
            continue
        
        # Check for type
        if entry.get('type') != 'url':
            errors.append(f"{entry_name}: Invalid type: {entry.get('type')}")
            continue
        
        valid_entries.append(entry)
    
    return valid_entries, errors


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for reading_list_articles@1 task.
    
    Verifies:
    1. Bookmarks file can be accessed
    2. Reading List section exists
    3. At least 3 entries were added
    4. Entries have valid URLs
    5. Entries are recent (added during task)
    
    Scoring:
    - 100%: 3+ valid recent Reading List entries
    - 80%: 2 valid entries
    - 50%: 1 valid entry
    - 0%: No valid entries
    
    Pass threshold: 75% (requires at least 2-3 entries)
    
    Args:
        traj: Trajectory data (not used)
        env_info: Environment information including copy_from_env
        task_info: Task configuration
        
    Returns:
        Dict with passed, score, and feedback
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env function not available"
        }
    
    try:
        # Copy Bookmarks file from container
        bookmarks_data = get_bookmarks_data(copy_from_env)
        
        if not bookmarks_data:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ Could not access Chrome Bookmarks file. Ensure Chrome was running and closed properly."
            }
        
        # Find Reading List entries
        all_entries = find_reading_list_entries(bookmarks_data)
        
        if not all_entries:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ No Reading List entries found. Did you use 'Add to Reading List' (not regular bookmarks)?\n\nHint: Right-click on page → 'Add to Reading List' or use the side panel.",
                "details": {
                    "total_entries": 0,
                    "recent_entries": 0,
                    "valid_entries": 0
                }
            }
        
        # Filter for recent entries (added during this task)
        recent_entries = filter_recent_entries(all_entries, max_age_seconds=600)
        
        if not recent_entries:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ Found {len(all_entries)} Reading List entries, but none were added during this task (check timestamps).\n\nAll entries appear to be older than 10 minutes.",
                "details": {
                    "total_entries": len(all_entries),
                    "recent_entries": 0,
                    "valid_entries": 0
                }
            }
        
        # Validate entries
        valid_entries, validation_errors = validate_reading_list_entries(recent_entries)
        
        num_valid = len(valid_entries)
        min_required = 3
        
        # Calculate score
        if num_valid >= min_required:
            score = 100
            passed = True
            feedback = f"✅ Successfully added {num_valid} articles to Reading List!"
        elif num_valid == min_required - 1:
            score = 80
            passed = True
            feedback = f"✅ Added {num_valid} articles to Reading List (expected {min_required}, close enough)"
        elif num_valid == 1:
            score = 50
            passed = False
            feedback = f"⚠️ Only {num_valid} valid Reading List entry found (need {min_required})"
        else:
            score = 0
            passed = False
            feedback = f"❌ No valid Reading List entries found"
        
        # Build detailed feedback
        feedback_parts = [feedback]
        feedback_parts.append(f"\nReading List entries added: {num_valid}/{min_required}")
        
        if valid_entries:
            feedback_parts.append("\nArticles added:")
            for i, entry in enumerate(valid_entries[:5], 1):  # Show max 5
                name = entry.get('name', 'Unknown')
                url = entry.get('url', '')
                feedback_parts.append(f"  {i}. {name}")
                feedback_parts.append(f"     URL: {url[:60]}{'...' if len(url) > 60 else ''}")
        
        if validation_errors:
            feedback_parts.append(f"\n⚠️ Validation errors: {len(validation_errors)}")
            for error in validation_errors[:3]:  # Show max 3
                feedback_parts.append(f"  - {error}")
        
        if num_valid < min_required:
            feedback_parts.append(f"\n💡 Tip: Add {min_required - num_valid} more article(s) to Reading List")
        
        final_feedback = "\n".join(feedback_parts)
        
        # Clean up
        cleanup_verification_temp()
        
        return {
            "passed": passed,
            "score": score,
            "feedback": final_feedback,
            "details": {
                "total_entries": len(all_entries),
                "recent_entries": len(recent_entries),
                "valid_entries": num_valid,
                "required": min_required,
                "validation_errors": len(validation_errors)
            }
        }
    
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        cleanup_verification_temp()
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


def get_bookmarks_data(copy_from_env) -> Optional[Dict[str, Any]]:
    """
    Copy and parse Chrome Bookmarks file from container.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Parsed Bookmarks JSON data or None if failed
    """
    temp_file = None
    
    try:
        # Create temporary file
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()
        
        # Try multiple possible locations
        bookmarks_paths = [
            "/tmp/bookmarks_export.json",
            "/home/ga/.config/google-chrome-cdp/Default/Bookmarks",
            "/home/ga/.config/google-chrome/Default/Bookmarks",
            "/home/ga/.config/chromium/Default/Bookmarks"
        ]
        
        bookmarks_data = None
        
        for container_path in bookmarks_paths:
            try:
                logger.info(f"Trying to copy Bookmarks from: {container_path}")
                copy_from_env(container_path, temp_path)
                
                # Check if file was copied successfully
                if os.path.exists(temp_path) and os.path.getsize(temp_path) > 0:
                    with open(temp_path, 'r', encoding='utf-8') as f:
                        bookmarks_data = json.load(f)
                    
                    logger.info(f"✓ Successfully copied and parsed Bookmarks from: {container_path}")
                    break
            
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                continue
        
        return bookmarks_data
    
    except Exception as e:
        logger.error(f"Error getting bookmarks data: {e}")
        return None
    
    finally:
        # Clean up temp file
        if temp_file and os.path.exists(temp_path):
            try:
                os.unlink(temp_path)
            except:
                pass
