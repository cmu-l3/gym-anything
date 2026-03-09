#!/usr/bin/env python3
"""
Verifier for Chrome Multi-Tab Bookmark Snapshot Task: bookmark_tabs_session@1
Task: Open multiple Wikipedia AI pages in tabs, then bookmark all tabs as 'AI Research Session'

Verification Strategy:
- Copy and parse Chrome Bookmarks JSON file
- Verify folder named "AI Research Session" exists in bookmark_bar
- Check that folder contains all 4 expected Wikipedia URLs
- Allow URLs in any order (Chrome may reorder during save)
- Validate no duplicates or excessive extra URLs
"""

import logging
import sys
import os
import json
import tempfile
from pathlib import Path
from typing import Dict, List, Any, Set

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utilities to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../', 'utils'))
try:
    from chrome_verification_utils import (
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
        with open(path, 'r', encoding='utf-8') as f:
            return json.load(f)
    
    def cleanup_verification_temp():
        pass


def normalize_url(url: str) -> str:
    """
    Normalize URL for comparison.
    
    Handles:
    - Trailing slashes
    - http vs https
    - Case insensitivity
    - Query parameters and fragments (removed for comparison)
    
    Args:
        url: URL string to normalize
        
    Returns:
        Normalized URL string
    """
    if not url:
        return ""
    
    # Convert to lowercase
    url = url.lower()
    
    # Remove http:// or https://
    url = url.replace('https://', '').replace('http://', '')
    
    # Remove trailing slashes
    url = url.rstrip('/')
    
    # Remove query parameters and fragments for cleaner comparison
    if '?' in url:
        url = url.split('?')[0]
    if '#' in url:
        url = url.split('#')[0]
    
    return url


def verify_bookmark_tabs_session(bookmarks_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify multi-tab bookmark snapshot task completion.
    
    Checks:
    1. Folder "AI Research Session" exists in bookmark_bar
    2. Folder contains all 4 expected Wikipedia URLs
    3. No missing URLs
    4. No excessive extra URLs (allows 1-2 extra for tolerance)
    5. Proper bookmark structure and naming
    
    Args:
        bookmarks_data: Parsed Chrome Bookmarks JSON
        
    Returns:
        Dict with passed, score, feedback, and details
    """
    # Expected URLs (normalized for comparison)
    expected_urls = {
        "https://en.wikipedia.org/wiki/Artificial_intelligence",
        "https://en.wikipedia.org/wiki/Machine_learning",
        "https://en.wikipedia.org/wiki/Neural_network",
        "https://en.wikipedia.org/wiki/Deep_learning"
    }
    
    expected_folder_name = "AI Research Session"
    
    # Parse bookmarks file
    if not bookmarks_data:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Could not parse Bookmarks file",
            "criteria": {
                "folder_exists": False,
                "correct_name": False,
                "all_urls_present": False,
                "no_excessive_extras": False
            }
        }
    
    # Navigate to bookmark_bar
    bookmark_bar = bookmarks_data.get('roots', {}).get('bookmark_bar', {})
    children = bookmark_bar.get('children', [])
    
    logger.info(f"Found {len(children)} items in bookmark bar")
    
    # Criterion 1: Folder exists in bookmarks bar with exact name
    folder_exists = False
    correct_name = False
    target_folder = None
    
    for child in children:
        if child.get('type') == 'folder':
            folder_name = child.get('name', '')
            logger.info(f"Found folder: {folder_name}")
            
            if folder_name == expected_folder_name:
                folder_exists = True
                correct_name = True
                target_folder = child
                break
            elif folder_name.lower() == expected_folder_name.lower():
                # Case mismatch
                folder_exists = True
                target_folder = child
                break
    
    if not folder_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Folder '{expected_folder_name}' not found in bookmark bar. Please create the folder using 'Bookmark all tabs' feature.",
            "criteria": {
                "folder_exists": False,
                "correct_name": False,
                "all_urls_present": False,
                "no_excessive_extras": False
            }
        }
    
    logger.info(f"✓ Found folder: {target_folder.get('name')}")
    
    # Extract URLs from folder
    folder_children = target_folder.get('children', [])
    actual_urls = []
    
    for item in folder_children:
        if item.get('type') == 'url':
            url = item.get('url', '')
            actual_urls.append(url)
            logger.info(f"  Bookmark: {item.get('name', 'Untitled')} -> {url}")
    
    logger.info(f"Found {len(actual_urls)} bookmarks in folder")
    
    # Normalize URLs for comparison
    normalized_expected = {normalize_url(url) for url in expected_urls}
    normalized_actual = {normalize_url(url) for url in actual_urls}
    
    # Criterion 2: Check which expected URLs are present
    matched_urls = normalized_expected.intersection(normalized_actual)
    missing_urls = normalized_expected - normalized_actual
    extra_urls = normalized_actual - normalized_expected
    
    all_urls_present = len(missing_urls) == 0
    match_count = len(matched_urls)
    
    logger.info(f"URL matching:")
    logger.info(f"  Expected: {len(expected_urls)}")
    logger.info(f"  Matched: {match_count}")
    logger.info(f"  Missing: {len(missing_urls)}")
    logger.info(f"  Extra: {len(extra_urls)}")
    
    if missing_urls:
        for url in missing_urls:
            logger.info(f"  Missing URL: {url}")
    
    if extra_urls:
        for url in extra_urls:
            logger.info(f"  Extra URL: {url}")
    
    # Criterion 3: No excessive extra URLs (allow 1-2 for tolerance)
    no_excessive_extras = len(extra_urls) <= 2
    
    # Calculate score based on criteria
    criteria_met = 0
    max_criteria = 5
    
    # Folder exists (20%)
    if folder_exists:
        criteria_met += 1
    
    # Correct folder name (20%)
    if correct_name:
        criteria_met += 1
    
    # URL presence scoring (40% - proportional to matched URLs)
    url_score = match_count / len(expected_urls)
    criteria_met += url_score * 2  # 2 criteria worth for URL matching
    
    # No excessive extras (20%)
    if no_excessive_extras:
        criteria_met += 1
    
    score = int((criteria_met / max_criteria) * 100)
    
    # Pass threshold: 75% (need at least 3.75/5 criteria)
    # This means: folder exists, correct name, and at least 3/4 URLs
    passed = score >= 75
    
    # Generate detailed feedback
    feedback_parts = []
    
    if correct_name:
        feedback_parts.append(f"✓ Folder '{expected_folder_name}' found in bookmark bar")
    elif folder_exists:
        feedback_parts.append(f"⚠ Folder found but name case mismatch: '{target_folder.get('name')}'")
    
    feedback_parts.append(f"{'✓' if all_urls_present else '✗'} URLs matched: {match_count}/{len(expected_urls)}")
    
    if missing_urls:
        feedback_parts.append(f"  Missing URLs:")
        for url in list(missing_urls)[:3]:  # Show first 3 missing
            # Reverse normalize to show original format
            for orig_url in expected_urls:
                if normalize_url(orig_url) == url:
                    feedback_parts.append(f"    - {orig_url}")
                    break
    
    if extra_urls:
        if len(extra_urls) <= 2:
            feedback_parts.append(f"⚠ {len(extra_urls)} extra URL(s) found (acceptable)")
        else:
            feedback_parts.append(f"✗ {len(extra_urls)} extra URLs found (too many)")
    
    feedback_parts.append(f"\nScore: {score}/100")
    
    if passed:
        if score == 100:
            feedback_parts.append("✅ Perfect! All tabs correctly bookmarked with exact folder name.")
        else:
            feedback_parts.append("✅ Task completed successfully with minor issues.")
    else:
        if match_count >= 2:
            feedback_parts.append("❌ Task incomplete: Some required URLs are missing from the folder.")
        else:
            feedback_parts.append("❌ Task failed: Most required URLs are missing.")
    
    feedback = "\n".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "criteria": {
            "folder_exists": folder_exists,
            "correct_name": correct_name,
            "all_urls_present": all_urls_present,
            "matched_count": match_count,
            "missing_count": len(missing_urls),
            "extra_count": len(extra_urls),
            "no_excessive_extras": no_excessive_extras
        },
        "details": {
            "matched_urls": list(matched_urls),
            "missing_urls": list(missing_urls),
            "extra_urls": list(extra_urls)
        }
    }


def get_bookmarks_data(copy_from_env) -> Dict[str, Any]:
    """
    Retrieve and parse bookmarks file from container.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Parsed bookmarks JSON or empty dict on failure
    """
    temp_file = None
    temp_path = None
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json', mode='w+')
        temp_path = temp_file.name
        temp_file.close()
        
        # Try multiple possible locations
        bookmarks_paths = [
            "/tmp/bookmarks_export.json",
            "/home/ga/.config/google-chrome-cdp/Default/Bookmarks",
            "/home/ga/.config/google-chrome/Default/Bookmarks"
        ]
        
        bookmarks_data = None
        source_path = None
        
        for container_path in bookmarks_paths:
            try:
                logger.info(f"Trying to copy bookmarks from: {container_path}")
                copy_from_env(container_path, temp_path)
                
                # Check if file was copied successfully
                if os.path.exists(temp_path) and os.path.getsize(temp_path) > 0:
                    with open(temp_path, 'r', encoding='utf-8') as f:
                        bookmarks_data = json.load(f)
                    source_path = container_path
                    logger.info(f"✓ Successfully copied bookmarks from: {container_path}")
                    break
                else:
                    logger.debug(f"File empty or not found: {temp_path}")
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                continue
        
        if not bookmarks_data:
            logger.error("Could not retrieve bookmarks from any known location")
            return {}
        
        return bookmarks_data
        
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse bookmarks JSON: {e}")
        return {}
    except Exception as e:
        logger.error(f"Error getting bookmarks data: {e}", exc_info=True)
        return {}
    finally:
        # Cleanup temp file
        if temp_path and os.path.exists(temp_path):
            try:
                os.unlink(temp_path)
            except:
                pass


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for bookmark_tabs_session@1 task.
    
    Args:
        traj: Trajectory data (not used for this verification)
        env_info: Environment information including copy_from_env function
        task_info: Task configuration information
        
    Returns:
        Dict with passed (bool), score (int), feedback (str), and details
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env function not available in environment"
        }
    
    try:
        # Get bookmarks data from container
        logger.info("Retrieving bookmarks data from container...")
        bookmarks_data = get_bookmarks_data(copy_from_env)
        
        if not bookmarks_data:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Could not access bookmarks file from container. Ensure Chrome was closed properly to save bookmarks."
            }
        
        # Verify bookmark organization
        logger.info("Verifying bookmark organization...")
        result = verify_bookmark_tabs_session(bookmarks_data)
        
        # Clean up temporary files
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
