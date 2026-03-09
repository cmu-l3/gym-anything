#!/usr/bin/env python3
"""
Verifier for Chrome History Search and Bulk Bookmark Task (history_bulk_bookmark@1)
Task: Search history for 'python' keyword, select multiple entries, bulk bookmark to 'Python Resources' folder

Verification Strategy:
- Copy both Chrome History (SQLite) and Bookmarks (JSON) files
- Query History database for URLs containing 'python' keyword
- Parse Bookmarks JSON to find 'Python Resources' folder
- Cross-reference: verify at least 3 URLs from history search are in bookmark folder
- Check folder is in bookmarks bar or other bookmarks root
- Ensure no duplicate bookmarks or folders
"""

import logging
import sys
import os
import json
import sqlite3
import tempfile
import re
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
    Main verification function for history_bulk_bookmark@1 task.
    
    Verifies:
    1. History contains URLs with 'python' keyword (at least 3)
    2. 'Python Resources' folder exists in bookmarks
    3. At least 3 URLs from history search are bookmarked in the folder
    4. Bookmarked URLs actually exist in history
    5. No duplicate folders or excessive duplicate bookmarks
    
    Args:
        traj: Trajectory data (not used)
        env_info: Environment information including copy_from_env function
        task_info: Task configuration information
        
    Returns:
        Dict with passed, score, and feedback
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available - cannot verify task"
        }

    try:
        # Get History and Bookmarks data
        history_urls = get_python_history_urls(copy_from_env)
        if history_urls is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Failed to retrieve Chrome History database"
            }
        
        bookmarks_data = get_bookmarks_data(copy_from_env)
        if bookmarks_data is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Failed to retrieve Chrome Bookmarks file"
            }
        
        # Perform verification
        result = verify_history_bulk_bookmark(history_urls, bookmarks_data)
        
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


def get_python_history_urls(copy_from_env) -> Optional[List[str]]:
    """
    Retrieve and query Chrome History database for URLs containing 'python'.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        List of URLs containing 'python' keyword, or None on failure
    """
    temp_db = None
    try:
        # Create temporary file for History database
        temp_db = tempfile.NamedTemporaryFile(delete=False, suffix='.db')
        temp_db.close()
        
        # Try to copy History database from container
        possible_paths = [
            "/tmp/history_export.db",
            "/home/ga/.config/google-chrome-cdp/Default/History",
            "/home/ga/.config/google-chrome/Default/History"
        ]
        
        copied = False
        for container_path in possible_paths:
            try:
                logger.info(f"Trying to copy History from: {container_path}")
                copy_from_env(container_path, temp_db.name)
                
                # Check if file has content
                if os.path.getsize(temp_db.name) > 0:
                    logger.info(f"✓ Successfully copied History from: {container_path}")
                    copied = True
                    break
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                continue
        
        if not copied:
            logger.error("Could not copy History database from any location")
            return None
        
        # Query database for URLs containing 'python'
        conn = sqlite3.connect(temp_db.name)
        cursor = conn.cursor()
        
        # Query for URLs and titles containing 'python' (case-insensitive)
        query = """
            SELECT url, title, last_visit_time 
            FROM urls 
            WHERE LOWER(url) LIKE '%python%' OR LOWER(title) LIKE '%python%'
            ORDER BY last_visit_time DESC
        """
        
        cursor.execute(query)
        results = cursor.fetchall()
        conn.close()
        
        # Extract URLs
        urls = [row[0] for row in results]
        
        logger.info(f"Found {len(urls)} Python-related URLs in history")
        for url in urls[:5]:  # Log first 5 for debugging
            logger.info(f"  - {url}")
        
        return urls
        
    except sqlite3.Error as e:
        logger.error(f"SQLite error querying History: {e}")
        return None
    except Exception as e:
        logger.error(f"Error retrieving History URLs: {e}")
        return None
    finally:
        # Clean up temp database file
        if temp_db and os.path.exists(temp_db.name):
            try:
                os.unlink(temp_db.name)
            except:
                pass


def get_bookmarks_data(copy_from_env) -> Optional[Dict[str, Any]]:
    """
    Retrieve and parse Chrome Bookmarks JSON file.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Parsed bookmarks data as dict, or None on failure
    """
    temp_file = None
    try:
        # Create temporary file for Bookmarks
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json', mode='w+')
        temp_file.close()
        
        # Try to copy Bookmarks file from container
        possible_paths = [
            "/tmp/bookmarks_export.json",
            "/home/ga/.config/google-chrome-cdp/Default/Bookmarks",
            "/home/ga/.config/google-chrome/Default/Bookmarks"
        ]
        
        copied = False
        for container_path in possible_paths:
            try:
                logger.info(f"Trying to copy Bookmarks from: {container_path}")
                copy_from_env(container_path, temp_file.name)
                
                # Check if file has content
                if os.path.getsize(temp_file.name) > 0:
                    logger.info(f"✓ Successfully copied Bookmarks from: {container_path}")
                    copied = True
                    break
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                continue
        
        if not copied:
            logger.error("Could not copy Bookmarks file from any location")
            return None
        
        # Parse JSON
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            bookmarks_data = json.load(f)
        
        logger.info("✓ Successfully parsed Bookmarks JSON")
        return bookmarks_data
        
    except json.JSONDecodeError as e:
        logger.error(f"JSON decode error: {e}")
        return None
    except Exception as e:
        logger.error(f"Error retrieving Bookmarks: {e}")
        return None
    finally:
        # Clean up temp file
        if temp_file and os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass


def find_folder_in_bookmarks(bookmarks_data: Dict[str, Any], folder_name: str) -> Optional[Dict[str, Any]]:
    """
    Recursively search for a folder by name in bookmarks structure.
    
    Args:
        bookmarks_data: Parsed bookmarks JSON data
        folder_name: Name of folder to find
        
    Returns:
        Folder node dict if found, None otherwise
    """
    def search_node(node):
        if node.get('type') == 'folder' and node.get('name') == folder_name:
            return node
        
        for child in node.get('children', []):
            result = search_node(child)
            if result:
                return result
        
        return None
    
    # Search in bookmark bar
    bookmark_bar = bookmarks_data.get('roots', {}).get('bookmark_bar', {})
    result = search_node(bookmark_bar)
    if result:
        return result
    
    # Search in other bookmarks
    other_bookmarks = bookmarks_data.get('roots', {}).get('other', {})
    result = search_node(other_bookmarks)
    if result:
        return result
    
    return None


def normalize_url(url: str) -> str:
    """
    Normalize URL for comparison.
    Removes protocol, trailing slashes, and converts to lowercase.
    """
    if not url:
        return ""
    
    # Remove protocol
    url = re.sub(r'^https?://', '', url)
    
    # Remove www.
    url = re.sub(r'^www\.', '', url)
    
    # Remove trailing slash
    url = url.rstrip('/')
    
    # Convert to lowercase
    url = url.lower()
    
    return url


def verify_history_bulk_bookmark(history_urls: List[str], bookmarks_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that history search results were bulk bookmarked correctly.
    
    Checks:
    1. History contains Python-related URLs (at least 3)
    2. 'Python Resources' folder exists in bookmarks
    3. At least 3 URLs from history are in the folder
    4. All bookmarked URLs exist in history
    5. No duplicate 'Python Resources' folders
    
    Args:
        history_urls: List of Python-related URLs from history
        bookmarks_data: Parsed bookmarks JSON data
        
    Returns:
        Verification result dict
    """
    FOLDER_NAME = "Python Resources"
    MIN_BOOKMARKS = 3
    
    criteria_met = 0
    total_criteria = 5
    feedback_parts = []
    
    # Criterion 1: History contains Python-related URLs
    if len(history_urls) < MIN_BOOKMARKS:
        feedback_parts.append(f"✗ Insufficient Python-related URLs in history ({len(history_urls)} found, need at least {MIN_BOOKMARKS})")
    else:
        feedback_parts.append(f"✓ History contains {len(history_urls)} Python-related URLs")
        criteria_met += 1
    
    # Criterion 2: 'Python Resources' folder exists
    folder = find_folder_in_bookmarks(bookmarks_data, FOLDER_NAME)
    if not folder:
        feedback_parts.append(f"✗ '{FOLDER_NAME}' folder not found in bookmarks")
        
        # Check for similar folder names
        all_folders = find_all_folders(bookmarks_data)
        logger.info(f"All folders found: {all_folders}")
        if all_folders:
            feedback_parts.append(f"  Found these folders instead: {', '.join(all_folders[:5])}")
    else:
        feedback_parts.append(f"✓ '{FOLDER_NAME}' folder exists in bookmarks")
        criteria_met += 1
    
    # If folder doesn't exist, cannot continue with remaining checks
    if not folder:
        score = int((criteria_met / total_criteria) * 100)
        return {
            "passed": False,
            "score": score,
            "feedback": "\n".join(feedback_parts) + f"\n\nScore: {score}% (criteria met: {criteria_met}/{total_criteria})",
            "details": {
                "history_url_count": len(history_urls),
                "folder_found": False,
                "bookmarked_count": 0,
                "criteria_met": criteria_met
            }
        }
    
    # Extract URLs from folder
    folder_urls = []
    for child in folder.get('children', []):
        if child.get('type') == 'url':
            folder_urls.append(child.get('url', ''))
    
    logger.info(f"Found {len(folder_urls)} URLs in '{FOLDER_NAME}' folder")
    for url in folder_urls[:5]:  # Log first 5
        logger.info(f"  - {url}")
    
    # Criterion 3: At least 3 URLs from history are in the folder
    normalized_history = {normalize_url(url): url for url in history_urls}
    normalized_folder = {normalize_url(url): url for url in folder_urls}
    
    matched_urls = set(normalized_history.keys()) & set(normalized_folder.keys())
    matched_count = len(matched_urls)
    
    if matched_count < MIN_BOOKMARKS:
        feedback_parts.append(f"✗ Insufficient history URLs bookmarked ({matched_count}/{MIN_BOOKMARKS} required)")
    else:
        feedback_parts.append(f"✓ Successfully bookmarked {matched_count} URLs from history")
        criteria_met += 1
    
    # Criterion 4: All bookmarked URLs exist in history
    folder_urls_not_in_history = set(normalized_folder.keys()) - set(normalized_history.keys())
    
    if len(folder_urls_not_in_history) > 0:
        feedback_parts.append(f"⚠ {len(folder_urls_not_in_history)} bookmarked URLs not found in Python-related history")
        # Partial credit if most URLs are correct
        if matched_count >= MIN_BOOKMARKS:
            criteria_met += 0.5
    else:
        if len(folder_urls) > 0:
            feedback_parts.append(f"✓ All bookmarked URLs exist in history")
            criteria_met += 1
        else:
            feedback_parts.append(f"⚠ No URLs bookmarked in folder")
    
    # Criterion 5: No duplicate 'Python Resources' folders
    all_python_folders = count_folders_by_name(bookmarks_data, FOLDER_NAME)
    
    if all_python_folders > 1:
        feedback_parts.append(f"⚠ Found {all_python_folders} '{FOLDER_NAME}' folders (should be only 1)")
        criteria_met += 0.5  # Partial credit
    else:
        feedback_parts.append(f"✓ No duplicate folders")
        criteria_met += 1
    
    # Calculate final score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75  # Need at least 3.75/5 criteria (75%)
    
    # Build final feedback
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\n{'='*50}"
    feedback += f"\nCriteria met: {criteria_met:.1f}/{total_criteria}"
    feedback += f"\nFinal score: {score}%"
    feedback += f"\nResult: {'PASSED ✓' if passed else 'FAILED ✗'}"
    
    if matched_count > 0:
        feedback += f"\n\nBookmarked URLs from history:"
        for norm_url in list(matched_urls)[:5]:  # Show first 5
            original_url = normalized_folder.get(norm_url, norm_url)
            feedback += f"\n  - {original_url}"
    
    logger.info(f"Verification complete: passed={passed}, score={score}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "history_url_count": len(history_urls),
            "folder_found": True,
            "bookmarked_count": len(folder_urls),
            "matched_count": matched_count,
            "criteria_met": criteria_met,
            "duplicate_folders": all_python_folders > 1
        }
    }


def find_all_folders(bookmarks_data: Dict[str, Any]) -> List[str]:
    """Find all folder names in bookmarks."""
    folders = []
    
    def search_node(node):
        if node.get('type') == 'folder':
            folders.append(node.get('name', 'Unnamed'))
        
        for child in node.get('children', []):
            search_node(child)
    
    for root_name in ['bookmark_bar', 'other', 'synced']:
        root = bookmarks_data.get('roots', {}).get(root_name, {})
        if root:
            search_node(root)
    
    return folders


def count_folders_by_name(bookmarks_data: Dict[str, Any], folder_name: str) -> int:
    """Count how many folders with the given name exist."""
    count = 0
    
    def search_node(node):
        nonlocal count
        if node.get('type') == 'folder' and node.get('name') == folder_name:
            count += 1
        
        for child in node.get('children', []):
            search_node(child)
    
    for root_name in ['bookmark_bar', 'other', 'synced']:
        root = bookmarks_data.get('roots', {}).get(root_name, {})
        if root:
            search_node(root)
    
    return count
