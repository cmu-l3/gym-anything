#!/usr/bin/env python3
"""
Verifier for Chrome Bookmark Organization Task
Task: Navigate to GitHub trending, create 'Dev Resources' folder, bookmark as 'Trending Projects'
"""

import logging
import sys
import os
import json
import tempfile
from pathlib import Path

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Import Chrome verification utilities
sys.path.insert(0, os.path.join(os.path.abspath(__file__), '../../../', 'utils'))
try:
    from chrome_verification_utils import (
        setup_chrome_verification,
        parse_bookmarks,
        get_bookmark_bar_folders,
        get_folder_bookmarks,
        cleanup_verification_temp
    )
except ImportError:
    logger.warning("Could not import chrome_verification_utils, using fallback methods")
    # Fallback implementations if utils not available
    def parse_bookmarks(path):
        with open(path, 'r', encoding='utf-8') as f:
            return json.load(f)
    
    def cleanup_verification_temp():
        pass


def verify_bookmark_organization(bookmarks_data, folder_name, bookmark_name, expected_url):
    """
    Verify bookmark was properly organized into folder in bookmarks bar
    
    Args:
        bookmarks_data: Parsed bookmarks JSON data
        folder_name: Expected folder name in bookmarks bar
        bookmark_name: Expected bookmark name within folder
        expected_url: Expected URL of the bookmark
        
    Returns:
        Dict with verification results
    """
    if not bookmarks_data:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Could not parse bookmarks file",
            "criteria": {
                "folder_created": False,
                "bookmark_present": False,
                "custom_name": False,
                "correct_location": False
            }
        }
    
    # Navigate to bookmark bar
    bookmark_bar = bookmarks_data.get('roots', {}).get('bookmark_bar', {})
    children = bookmark_bar.get('children', [])
    
    # Criterion 1: Folder exists in bookmarks bar
    folder_exists = False
    target_folder = None
    for child in children:
        if child.get('type') == 'folder' and child.get('name') == folder_name:
            folder_exists = True
            target_folder = child
            break
    
    # Criterion 2 & 3: Bookmark with correct URL and name exists in folder
    bookmark_exists = False
    correct_name = False
    bookmark_url = None
    
    if target_folder:
        folder_children = target_folder.get('children', [])
        for item in folder_children:
            if item.get('type') == 'url':
                item_url = item.get('url', '')
                # Normalize URLs for comparison (handle trailing slashes, http vs https)
                if normalize_url(item_url) == normalize_url(expected_url):
                    bookmark_exists = True
                    bookmark_url = item_url
                    if item.get('name') == bookmark_name:
                        correct_name = True
                    break
    
    # Criterion 4: Bookmark is in correct location
    correct_location = folder_exists and bookmark_exists
    
    # Calculate score
    criteria_met = sum([folder_exists, bookmark_exists, correct_name, correct_location])
    score = (criteria_met / 4.0) * 100
    
    # Generate feedback
    feedback_parts = []
    if not folder_exists:
        feedback_parts.append(f"Folder '{folder_name}' not found in bookmarks bar")
    if not bookmark_exists:
        feedback_parts.append(f"Bookmark with URL '{expected_url}' not found in folder")
    if bookmark_exists and not correct_name:
        feedback_parts.append(f"Bookmark found but name is not '{bookmark_name}'")
    
    if criteria_met >= 3:
        feedback = "Bookmark organization successful"
        if criteria_met == 3:
            feedback += f" with minor issues: {'; '.join(feedback_parts)}"
    else:
        feedback = f"Bookmark organization failed: {'; '.join(feedback_parts)}"
    
    # Log detailed information
    logger.info(f"Verification results:")
    logger.info(f"  Folder '{folder_name}' exists: {folder_exists}")
    logger.info(f"  Bookmark exists: {bookmark_exists}")
    logger.info(f"  Correct name: {correct_name}")
    logger.info(f"  Correct location: {correct_location}")
    logger.info(f"  Score: {score}/100")
    
    return {
        "passed": score >= 75,
        "score": int(score),
        "feedback": feedback,
        "criteria": {
            "folder_created": folder_exists,
            "bookmark_present": bookmark_exists,
            "custom_name": correct_name,
            "correct_location": correct_location
        }
    }


def normalize_url(url):
    """Normalize URL for comparison"""
    if not url:
        return ""
    # Remove trailing slashes
    url = url.rstrip('/')
    # Convert to lowercase
    url = url.lower()
    # Handle http vs https
    url = url.replace('http://', '').replace('https://', '')
    return url


def verify_task(traj, env_info, task_info):
    """
    Main verification function for bookmark organization task
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available"
        }
    
    # Task parameters
    folder_name = "Dev Resources"
    bookmark_name = "Trending Projects"
    expected_url = "https://github.com/trending"
    
    try:
        # Try to copy bookmarks file from container
        logger.info("Attempting to copy bookmarks file from container...")
        
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
                temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json', mode='w+')
                temp_path = temp_file.name
                temp_file.close()
                
                logger.info(f"Trying to copy from: {container_path}")
                copy_from_env(container_path, temp_path)
                
                # Check if file was copied successfully
                if os.path.exists(temp_path) and os.path.getsize(temp_path) > 0:
                    with open(temp_path, 'r', encoding='utf-8') as f:
                        bookmarks_data = json.load(f)
                    source_path = container_path
                    os.unlink(temp_path)
                    logger.info(f"Successfully copied bookmarks from: {container_path}")
                    break
                else:
                    os.unlink(temp_path)
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                if os.path.exists(temp_path):
                    os.unlink(temp_path)
                continue
        
        if not bookmarks_data:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Could not access bookmarks file from any known location"
            }
        
        # Verify bookmark organization
        result = verify_bookmark_organization(
            bookmarks_data,
            folder_name,
            bookmark_name,
            expected_url
        )
        
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
