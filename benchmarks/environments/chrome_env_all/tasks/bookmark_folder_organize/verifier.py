#!/usr/bin/env python3
"""
Verifier for Chrome Bookmark Folder Organization Task (bookmark_folder_organize@1)

Task: Create 'Tech Resources' folder in Bookmark Bar with 3 specific bookmarks:
  1. GitHub - https://github.com
  2. Stack Overflow - https://stackoverflow.com
  3. MDN Web Docs - https://developer.mozilla.org

Verification Strategy:
- Copy Chrome Bookmarks JSON file from container
- Parse the hierarchical bookmark structure
- Verify 'Tech Resources' folder exists in Bookmark Bar
- Verify all 3 bookmarks exist with correct names and URLs
- Validate folder structure and organization
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

# Add utilities to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../', 'utils'))
try:
    from chrome_verification_utils import (
        setup_chrome_verification,
        parse_bookmarks,
        get_bookmark_bar_folders,
        get_folder_bookmarks,
        cleanup_verification_temp
    )
    UTILS_AVAILABLE = True
except ImportError:
    logger.warning("Chrome verification utilities not available, using fallback methods")
    UTILS_AVAILABLE = False
    
    def parse_bookmarks(path):
        """Fallback bookmark parser"""
        with open(path, 'r', encoding='utf-8') as f:
            return json.load(f)
    
    def cleanup_verification_temp():
        """Fallback cleanup function"""
        pass


def normalize_url(url: str) -> str:
    """
    Normalize URL for comparison by removing trailing slashes and converting to lowercase.
    
    Args:
        url: URL string to normalize
        
    Returns:
        Normalized URL string
    """
    if not url:
        return ""
    
    # Remove trailing slashes
    url = url.rstrip('/')
    
    # Convert to lowercase for case-insensitive comparison
    url = url.lower()
    
    return url


def find_folder_in_bookmark_bar(bookmarks_data: Dict, folder_name: str) -> Optional[Dict]:
    """
    Find a folder by name in the bookmark bar.
    
    Args:
        bookmarks_data: Parsed bookmarks JSON data
        folder_name: Name of folder to find
        
    Returns:
        Folder dict if found, None otherwise
    """
    try:
        bookmark_bar = bookmarks_data.get('roots', {}).get('bookmark_bar', {})
        children = bookmark_bar.get('children', [])
        
        for child in children:
            if child.get('type') == 'folder' and child.get('name') == folder_name:
                return child
        
        return None
    except Exception as e:
        logger.error(f"Error finding folder: {e}")
        return None


def verify_bookmark_in_folder(folder: Dict, name: str, url: str) -> Tuple[bool, str]:
    """
    Verify that a bookmark with specific name and URL exists in a folder.
    
    Args:
        folder: Folder dict containing children
        name: Expected bookmark name
        url: Expected bookmark URL
        
    Returns:
        Tuple of (found: bool, actual_url: str or "")
    """
    folder_children = folder.get('children', [])
    normalized_expected = normalize_url(url)
    
    for child in folder_children:
        if child.get('type') == 'url':
            child_name = child.get('name', '')
            child_url = child.get('url', '')
            normalized_child = normalize_url(child_url)
            
            # Check if both name and URL match
            if child_name == name and normalized_child == normalized_expected:
                return True, child_url
    
    return False, ""


def get_all_bookmarks_in_folder(folder: Dict) -> List[Dict[str, str]]:
    """
    Get all bookmarks in a folder.
    
    Args:
        folder: Folder dict
        
    Returns:
        List of dicts with 'name' and 'url' keys
    """
    bookmarks = []
    folder_children = folder.get('children', [])
    
    for child in folder_children:
        if child.get('type') == 'url':
            bookmarks.append({
                'name': child.get('name', ''),
                'url': child.get('url', '')
            })
    
    return bookmarks


def verify_bookmark_folder_organization(bookmarks_data: Dict) -> Dict[str, Any]:
    """
    Main verification logic for bookmark folder organization.
    
    Checks:
    1. 'Tech Resources' folder exists in Bookmark Bar
    2. Folder is in correct location (direct child of Bookmark Bar)
    3. GitHub bookmark exists with correct URL
    4. Stack Overflow bookmark exists with correct URL
    5. MDN Web Docs bookmark exists with correct URL
    6. Folder contains exactly 3 bookmarks (no extras)
    7. No duplicate bookmarks within folder
    
    Args:
        bookmarks_data: Parsed bookmarks JSON data
        
    Returns:
        Verification result dict with passed, score, feedback, and details
    """
    FOLDER_NAME = "Tech Resources"
    EXPECTED_BOOKMARKS = [
        {"name": "GitHub", "url": "https://github.com"},
        {"name": "Stack Overflow", "url": "https://stackoverflow.com"},
        {"name": "MDN Web Docs", "url": "https://developer.mozilla.org"}
    ]
    
    criteria_results = {}
    feedback_parts = []
    
    # Criterion 1: Folder exists in Bookmark Bar
    logger.info("Checking if 'Tech Resources' folder exists...")
    tech_folder = find_folder_in_bookmark_bar(bookmarks_data, FOLDER_NAME)
    
    if tech_folder is None:
        criteria_results['folder_exists'] = False
        feedback_parts.append(f"✗ Folder '{FOLDER_NAME}' not found in Bookmark Bar")
        
        # List existing folders for debugging
        bookmark_bar = bookmarks_data.get('roots', {}).get('bookmark_bar', {})
        children = bookmark_bar.get('children', [])
        existing_folders = [c.get('name') for c in children if c.get('type') == 'folder']
        
        if existing_folders:
            feedback_parts.append(f"  Found folders: {', '.join(existing_folders)}")
        else:
            feedback_parts.append("  No folders found in Bookmark Bar")
        
        return {
            "passed": False,
            "score": 0,
            "feedback": "\n".join(feedback_parts),
            "criteria": criteria_results
        }
    
    criteria_results['folder_exists'] = True
    feedback_parts.append(f"✓ Folder '{FOLDER_NAME}' found in Bookmark Bar")
    logger.info(f"✓ Folder '{FOLDER_NAME}' exists")
    
    # Criterion 2: Check each expected bookmark
    bookmarks_found = {}
    
    for expected in EXPECTED_BOOKMARKS:
        bookmark_name = expected['name']
        bookmark_url = expected['url']
        
        logger.info(f"Checking for bookmark: {bookmark_name} → {bookmark_url}")
        found, actual_url = verify_bookmark_in_folder(tech_folder, bookmark_name, bookmark_url)
        
        criteria_results[f'bookmark_{bookmark_name.lower().replace(" ", "_")}'] = found
        bookmarks_found[bookmark_name] = found
        
        if found:
            feedback_parts.append(f"✓ Bookmark '{bookmark_name}' found with correct URL")
            logger.info(f"✓ Found: {bookmark_name}")
        else:
            feedback_parts.append(f"✗ Bookmark '{bookmark_name}' not found or incorrect URL")
            logger.info(f"✗ Missing: {bookmark_name}")
    
    # Criterion 3: Check bookmark count (should be exactly 3)
    all_bookmarks = get_all_bookmarks_in_folder(tech_folder)
    bookmark_count = len(all_bookmarks)
    
    logger.info(f"Folder contains {bookmark_count} bookmark(s)")
    criteria_results['correct_count'] = (bookmark_count == 3)
    
    if bookmark_count == 3:
        feedback_parts.append(f"✓ Folder contains exactly 3 bookmarks")
    elif bookmark_count < 3:
        feedback_parts.append(f"✗ Folder contains only {bookmark_count} bookmark(s), expected 3")
    else:
        feedback_parts.append(f"⚠ Folder contains {bookmark_count} bookmarks (expected 3)")
        # List extra bookmarks
        extra_names = [b['name'] for b in all_bookmarks]
        feedback_parts.append(f"  All bookmarks: {', '.join(extra_names)}")
    
    # Criterion 4: Check for duplicates
    bookmark_urls = [normalize_url(b['url']) for b in all_bookmarks]
    has_duplicates = len(bookmark_urls) != len(set(bookmark_urls))
    criteria_results['no_duplicates'] = not has_duplicates
    
    if has_duplicates:
        feedback_parts.append("⚠ Warning: Duplicate URLs detected in folder")
    
    # Calculate score based on criteria
    # Folder exists: 20%
    # Each bookmark (3): 25% each = 75%
    # Correct count: 5%
    
    score = 0
    if criteria_results['folder_exists']:
        score += 20
    
    for bookmark_name in ['github', 'stack_overflow', 'mdn_web_docs']:
        key = f'bookmark_{bookmark_name}'
        if criteria_results.get(key, False):
            score += 25
    
    if criteria_results.get('correct_count', False):
        score += 5
    
    # Bonus for no duplicates
    if criteria_results.get('no_duplicates', True):
        score += 5
    
    # Cap at 100
    score = min(score, 100)
    
    # Determine pass/fail (need at least 85% - folder + all 3 bookmarks)
    passed = (criteria_results['folder_exists'] and 
              all(bookmarks_found.values()) and
              score >= 85)
    
    # Generate summary
    bookmarks_correct = sum(1 for found in bookmarks_found.values() if found)
    feedback_parts.append("")
    feedback_parts.append("=" * 60)
    feedback_parts.append(f"Summary: {bookmarks_correct}/3 bookmarks correct in '{FOLDER_NAME}' folder")
    feedback_parts.append(f"Score: {score}/100")
    feedback_parts.append(f"Result: {'PASSED ✓' if passed else 'FAILED ✗'}")
    
    feedback = "\n".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": feedback,
        "criteria": criteria_results,
        "details": {
            "folder_found": criteria_results['folder_exists'],
            "bookmarks_found": bookmarks_found,
            "total_bookmarks": bookmark_count,
            "has_duplicates": has_duplicates
        }
    }


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for bookmark_folder_organize@1.
    
    Args:
        traj: Trajectory data (not used)
        env_info: Environment info with copy_from_env function
        task_info: Task configuration
        
    Returns:
        Verification result dict
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
        logger.info("Retrieving bookmarks file from container...")
        bookmarks_data = get_bookmarks_data(copy_from_env)
        
        if bookmarks_data is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Failed to retrieve or parse Chrome bookmarks file"
            }
        
        # Perform verification
        logger.info("Starting bookmark verification...")
        result = verify_bookmark_folder_organization(bookmarks_data)
        
        # Cleanup
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


def get_bookmarks_data(copy_from_env) -> Optional[Dict]:
    """
    Retrieve and parse Chrome bookmarks file from container.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Parsed bookmarks dict or None on failure
    """
    # Try multiple possible locations
    bookmarks_paths = [
        "/tmp/bookmarks_export.json",
        "/home/ga/.config/google-chrome-cdp/Default/Bookmarks",
        "/home/ga/.config/google-chrome/Default/Bookmarks"
    ]
    
    for container_path in bookmarks_paths:
        try:
            logger.info(f"Trying to copy bookmarks from: {container_path}")
            
            temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json', mode='w+')
            temp_path = temp_file.name
            temp_file.close()
            
            copy_from_env(container_path, temp_path)
            
            # Check if file was copied successfully and has content
            if os.path.exists(temp_path) and os.path.getsize(temp_path) > 0:
                with open(temp_path, 'r', encoding='utf-8') as f:
                    bookmarks_data = json.load(f)
                
                os.unlink(temp_path)
                logger.info(f"✓ Successfully loaded bookmarks from: {container_path}")
                return bookmarks_data
            else:
                if os.path.exists(temp_path):
                    os.unlink(temp_path)
                logger.debug(f"File empty or not found at: {container_path}")
                
        except json.JSONDecodeError as e:
            logger.error(f"Invalid JSON in bookmarks file at {container_path}: {e}")
            if os.path.exists(temp_path):
                os.unlink(temp_path)
        except Exception as e:
            logger.debug(f"Failed to copy from {container_path}: {e}")
            if 'temp_path' in locals() and os.path.exists(temp_path):
                os.unlink(temp_path)
            continue
    
    logger.error("Could not retrieve bookmarks from any known location")
    return None
