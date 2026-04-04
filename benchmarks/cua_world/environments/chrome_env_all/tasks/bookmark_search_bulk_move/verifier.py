#!/usr/bin/env python3
"""
Verifier for Chrome Bookmark Manager Search and Bulk Organization Task
Task: bookmark_search_bulk_move@1

Task: Use Bookmark Manager to search for tech news bookmarks, select multiple,
      create 'Tech News' folder, and bulk organize them.

Verification Strategy:
- Parse Chrome Bookmarks JSON file
- Verify 'Tech News' folder exists in bookmark bar
- Check that bookmarks matching 'techcrunch' or 'verge' patterns are inside the folder
- Ensure no matching bookmarks remain scattered outside the folder
- Validate data integrity (URLs and names preserved)
"""

import logging
import sys
import os
import json
import tempfile
from pathlib import Path
from typing import Dict, List, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../', 'utils'))
try:
    from chrome_verification_utils import (
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


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for bookmark_search_bulk_move@1.
    
    Verifies:
    1. 'Tech News' folder created in bookmark bar
    2. At least 3 matching bookmarks moved to folder
    3. No matching bookmarks remain outside folder
    4. Data integrity (URLs/names preserved)
    
    Scoring:
    - 100%: All 5 criteria met (perfect organization)
    - 80-99%: 4/5 criteria met (minor issue, still passing)
    - 60-79%: 3/5 criteria met (partial success)
    - 40-59%: 2/5 criteria met (significant issues)
    - 0-39%: 0-1 criteria met (task failed)
    
    Pass threshold: 80% (requires 4 out of 5 criteria)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available in environment"
        }

    try:
        # Get bookmarks data from container
        bookmarks_data = get_bookmarks_data(copy_from_env)
        
        if bookmarks_data is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Failed to retrieve bookmarks file from container"
            }
        
        # Perform verification
        result = verify_bookmark_organization(bookmarks_data)
        
        # Clean up
        cleanup_verification_temp()
        
        return result
        
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
    Retrieve bookmarks file from container.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Parsed bookmarks JSON data or None if failed
    """
    temp_file = None
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json', mode='w+')
        temp_path = temp_file.name
        temp_file.close()
        
        # Try multiple possible locations
        bookmarks_paths = [
            "/tmp/bookmarks_final.json",
            "/home/ga/.config/google-chrome-cdp/Default/Bookmarks",
            "/home/ga/.config/google-chrome/Default/Bookmarks"
        ]
        
        for container_path in bookmarks_paths:
            try:
                logger.info(f"Trying to copy bookmarks from: {container_path}")
                copy_from_env(container_path, temp_path)
                
                # Check if file was copied successfully
                if os.path.exists(temp_path) and os.path.getsize(temp_path) > 0:
                    with open(temp_path, 'r', encoding='utf-8') as f:
                        bookmarks_data = json.load(f)
                    logger.info(f"✓ Successfully loaded bookmarks from: {container_path}")
                    os.unlink(temp_path)
                    return bookmarks_data
                    
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                continue
        
        # Clean up temp file if all attempts failed
        if os.path.exists(temp_path):
            os.unlink(temp_path)
        
        return None
        
    except Exception as e:
        logger.error(f"Error getting bookmarks data: {e}")
        if temp_file and os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass
        return None


def verify_bookmark_organization(bookmarks_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that bookmarks were properly organized into 'Tech News' folder.
    
    Args:
        bookmarks_data: Parsed Chrome bookmarks JSON
        
    Returns:
        Verification result with passed, score, and feedback
    """
    # Expected patterns for tech news bookmarks
    TECH_PATTERNS = ['techcrunch', 'verge']
    FOLDER_NAME = 'Tech News'
    
    # Navigate to bookmark bar
    try:
        bookmark_bar = bookmarks_data.get('roots', {}).get('bookmark_bar', {})
        children = bookmark_bar.get('children', [])
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to parse bookmarks structure: {e}"
        }
    
    # Criterion 1: Check if 'Tech News' folder exists
    tech_news_folder = None
    for child in children:
        if child.get('type') == 'folder' and child.get('name') == FOLDER_NAME:
            tech_news_folder = child
            break
    
    folder_exists = tech_news_folder is not None
    logger.info(f"Criterion 1 - Folder exists: {folder_exists}")
    
    if not folder_exists:
        return {
            "passed": False,
            "score": 20,
            "feedback": f"'{FOLDER_NAME}' folder not found in bookmark bar. Please create the folder and organize bookmarks.",
            "criteria": {
                "folder_created": False,
                "bookmarks_moved": False,
                "complete_migration": False,
                "data_integrity": False,
                "no_duplicates": False
            }
        }
    
    # Criterion 2: Get bookmarks inside Tech News folder
    folder_bookmarks = tech_news_folder.get('children', [])
    folder_urls = [item for item in folder_bookmarks if item.get('type') == 'url']
    
    # Check which ones match tech patterns
    matching_in_folder = []
    for bookmark in folder_urls:
        url = bookmark.get('url', '').lower()
        name = bookmark.get('name', '').lower()
        for pattern in TECH_PATTERNS:
            if pattern in url or pattern in name:
                matching_in_folder.append(bookmark)
                break
    
    bookmarks_moved_count = len(matching_in_folder)
    bookmarks_moved_ok = bookmarks_moved_count >= 3  # Need at least 3 out of 4
    logger.info(f"Criterion 2 - Bookmarks moved: {bookmarks_moved_count} (need ≥3)")
    
    # Criterion 3: Check for stragglers (matching bookmarks outside folder)
    all_bookmarks = get_all_bookmarks_recursive(bookmarks_data)
    
    stragglers = []
    for bookmark in all_bookmarks:
        # Skip if it's already in the Tech News folder
        if bookmark in matching_in_folder:
            continue
        
        url = bookmark.get('url', '').lower()
        name = bookmark.get('name', '').lower()
        for pattern in TECH_PATTERNS:
            if pattern in url or pattern in name:
                stragglers.append(bookmark)
                break
    
    complete_migration = len(stragglers) == 0
    logger.info(f"Criterion 3 - Complete migration: {complete_migration} ({len(stragglers)} stragglers)")
    
    # Criterion 4: Data integrity check (URLs and names preserved)
    expected_bookmarks = [
        ("techcrunch.com/category/artificial-intelligence", "TechCrunch AI"),
        ("techcrunch.com/category/startups", "TechCrunch Startups"),
        ("theverge.com/tech", "Verge Tech"),
        ("theverge.com/science", "Verge Science")
    ]
    
    integrity_checks = 0
    for expected_url_part, expected_name_part in expected_bookmarks:
        for bookmark in matching_in_folder:
            url = bookmark.get('url', '')
            name = bookmark.get('name', '')
            if expected_url_part in url and expected_name_part in name:
                integrity_checks += 1
                break
    
    data_integrity_ok = integrity_checks >= 3  # At least 3 out of 4 preserved correctly
    logger.info(f"Criterion 4 - Data integrity: {integrity_checks}/4 bookmarks with preserved data")
    
    # Criterion 5: No duplicate bookmarks
    folder_urls_list = [b.get('url', '') for b in folder_bookmarks if b.get('type') == 'url']
    unique_urls = len(set(folder_urls_list))
    total_urls = len(folder_urls_list)
    no_duplicates = unique_urls == total_urls
    logger.info(f"Criterion 5 - No duplicates: {no_duplicates} ({unique_urls} unique out of {total_urls})")
    
    # Calculate score
    criteria_results = [
        folder_exists,        # 1
        bookmarks_moved_ok,   # 2
        complete_migration,   # 3
        data_integrity_ok,    # 4
        no_duplicates         # 5
    ]
    
    criteria_met = sum(criteria_results)
    score = int((criteria_met / 5) * 100)
    passed = score >= 80  # Need 4 out of 5 criteria
    
    # Generate detailed feedback
    feedback_parts = []
    feedback_parts.append(f"Bookmark Organization Verification: {criteria_met}/5 criteria met")
    feedback_parts.append("")
    feedback_parts.append(f"✓ Folder '{FOLDER_NAME}' created: {'Yes' if folder_exists else 'No'}")
    feedback_parts.append(f"{'✓' if bookmarks_moved_ok else '✗'} Bookmarks moved to folder: {bookmarks_moved_count} (expected ≥3)")
    feedback_parts.append(f"{'✓' if complete_migration else '✗'} Complete migration: {len(stragglers)} bookmarks still outside folder")
    feedback_parts.append(f"{'✓' if data_integrity_ok else '✗'} Data integrity: {integrity_checks}/4 bookmarks preserved correctly")
    feedback_parts.append(f"{'✓' if no_duplicates else '✗'} No duplicate bookmarks: {unique_urls} unique out of {total_urls}")
    feedback_parts.append("")
    
    if stragglers:
        feedback_parts.append(f"⚠ Warning: {len(stragglers)} matching bookmark(s) remain outside 'Tech News' folder:")
        for straggler in stragglers[:3]:  # Show up to 3
            feedback_parts.append(f"  - {straggler.get('name', 'Unknown')}: {straggler.get('url', '')[:50]}...")
    
    if passed:
        if score == 100:
            feedback_parts.append("🎉 Perfect! All tech news bookmarks successfully organized into 'Tech News' folder.")
        else:
            feedback_parts.append("✅ Task completed successfully with minor issues.")
    else:
        feedback_parts.append("❌ Task incomplete. Please ensure all matching bookmarks are moved to 'Tech News' folder.")
    
    feedback = "\n".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "criteria": {
            "folder_created": folder_exists,
            "bookmarks_moved": bookmarks_moved_ok,
            "complete_migration": complete_migration,
            "data_integrity": data_integrity_ok,
            "no_duplicates": no_duplicates
        },
        "details": {
            "folder_exists": folder_exists,
            "bookmarks_in_folder": bookmarks_moved_count,
            "stragglers": len(stragglers),
            "data_integrity_score": integrity_checks,
            "total_folder_items": len(folder_bookmarks)
        }
    }


def get_all_bookmarks_recursive(bookmarks_root, collected=None) -> List[Dict[str, Any]]:
    """
    Recursively collect all URL bookmarks from entire bookmark tree.
    
    Args:
        bookmarks_root: Root of bookmarks structure or any node
        collected: List to accumulate results
        
    Returns:
        List of all bookmark dictionaries with type='url'
    """
    if collected is None:
        collected = []
    
    if isinstance(bookmarks_root, dict):
        # If this is a URL bookmark, add it
        if bookmarks_root.get('type') == 'url':
            collected.append(bookmarks_root)
        
        # If this is a folder, recurse into children
        elif bookmarks_root.get('type') == 'folder':
            for child in bookmarks_root.get('children', []):
                get_all_bookmarks_recursive(child, collected)
        
        # If this is a roots structure, recurse into each root
        elif 'roots' in bookmarks_root:
            for root_name, root_data in bookmarks_root['roots'].items():
                get_all_bookmarks_recursive(root_data, collected)
        
        # If this has children but no type, recurse
        elif 'children' in bookmarks_root:
            for child in bookmarks_root['children']:
                get_all_bookmarks_recursive(child, collected)
    
    elif isinstance(bookmarks_root, list):
        for item in bookmarks_root:
            get_all_bookmarks_recursive(item, collected)
    
    return collected
