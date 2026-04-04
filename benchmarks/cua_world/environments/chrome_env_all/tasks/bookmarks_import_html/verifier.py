#!/usr/bin/env python3
"""
Verifier for Chrome Bookmarks Import from HTML Task (bookmarks_import_html@1)
Task: Import bookmarks from HTML file into Chrome Bookmark Manager

Verification Strategy:
- Copy Chrome Bookmarks JSON file from container
- Parse the bookmark structure
- Check for 3 expected folders: "Development Resources", "Design Tools", "Productivity"
- Within each folder, verify presence of 3 specific bookmarks with correct URLs
- Score based on completeness: folders found × bookmarks per folder
- Pass threshold: 75% (at least 2 complete folders with all bookmarks)
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

# Add Chrome verification utilities to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../..', 'utils'))
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
        """Fallback bookmark parser"""
        with open(path, 'r', encoding='utf-8') as f:
            return json.load(f)
    
    def cleanup_verification_temp():
        """Fallback cleanup"""
        pass


# Expected bookmark structure after import
EXPECTED_STRUCTURE = {
    "Development Resources": [
        {"name": "GitHub", "url": "https://github.com"},
        {"name": "Stack Overflow", "url": "https://stackoverflow.com"},
        {"name": "MDN Web Docs", "url": "https://developer.mozilla.org"}
    ],
    "Design Tools": [
        {"name": "Figma", "url": "https://figma.com"},
        {"name": "Dribbble", "url": "https://dribbble.com"},
        {"name": "Behance", "url": "https://behance.net"}
    ],
    "Productivity": [
        {"name": "Notion", "url": "https://notion.so"},
        {"name": "Trello", "url": "https://trello.com"},
        {"name": "Asana", "url": "https://asana.com"}
    ]
}


def normalize_url(url: str) -> str:
    """
    Normalize URL for comparison by removing protocol and trailing slashes.
    
    Args:
        url: URL string to normalize
        
    Returns:
        Normalized URL string
    """
    if not url:
        return ""
    
    # Convert to lowercase
    url = url.lower().strip()
    
    # Remove protocol
    for protocol in ['https://', 'http://', 'www.']:
        if url.startswith(protocol):
            url = url[len(protocol):]
    
    # Remove trailing slash
    url = url.rstrip('/')
    
    return url


def find_folder_by_name(bookmark_bar: Dict, folder_name: str) -> Optional[Dict]:
    """
    Find a folder in the bookmark bar by name.
    
    Args:
        bookmark_bar: Bookmark bar data structure
        folder_name: Name of folder to find
        
    Returns:
        Folder dict if found, None otherwise
    """
    children = bookmark_bar.get('children', [])
    
    for child in children:
        if child.get('type') == 'folder' and child.get('name') == folder_name:
            return child
    
    return None


def check_bookmark_in_folder(folder: Dict, expected_url: str) -> Tuple[bool, Optional[str]]:
    """
    Check if a bookmark with the expected URL exists in the folder.
    
    Args:
        folder: Folder data structure
        expected_url: Expected URL to find
        
    Returns:
        Tuple of (found: bool, actual_name: str or None)
    """
    folder_children = folder.get('children', [])
    normalized_expected = normalize_url(expected_url)
    
    for item in folder_children:
        if item.get('type') == 'url':
            item_url = item.get('url', '')
            if normalize_url(item_url) == normalized_expected:
                return True, item.get('name', '')
    
    return False, None


def verify_bookmark_import(bookmarks_data: Dict) -> Dict[str, Any]:
    """
    Verify that bookmarks were correctly imported from HTML file.
    
    Checks:
    1. All 3 folders are present in bookmark bar
    2. Each folder contains all 3 expected bookmarks
    3. Bookmark URLs match expected values
    4. Calculate score based on completeness
    
    Args:
        bookmarks_data: Parsed Chrome Bookmarks JSON
        
    Returns:
        Dict with verification results including passed, score, feedback
    """
    if not bookmarks_data:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Could not parse bookmarks data",
            "details": {
                "folders_found": 0,
                "bookmarks_found": 0,
                "total_expected": 9
            }
        }
    
    # Navigate to bookmark bar
    try:
        bookmark_bar = bookmarks_data.get('roots', {}).get('bookmark_bar', {})
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Invalid bookmarks structure: {e}",
            "details": {"folders_found": 0, "bookmarks_found": 0, "total_expected": 9}
        }
    
    # Track verification results
    folders_found = []
    folders_missing = []
    bookmarks_found = 0
    total_expected_bookmarks = 9  # 3 folders × 3 bookmarks
    
    detailed_results = {}
    
    # Check each expected folder
    for folder_name, expected_bookmarks in EXPECTED_STRUCTURE.items():
        logger.info(f"Checking folder: {folder_name}")
        folder = find_folder_by_name(bookmark_bar, folder_name)
        
        if not folder:
            logger.warning(f"  ✗ Folder '{folder_name}' not found")
            folders_missing.append(folder_name)
            detailed_results[folder_name] = {
                "found": False,
                "bookmarks": []
            }
            continue
        
        logger.info(f"  ✓ Folder '{folder_name}' found")
        folders_found.append(folder_name)
        
        # Check bookmarks within this folder
        folder_bookmarks_found = []
        folder_bookmarks_missing = []
        
        for expected_bookmark in expected_bookmarks:
            expected_name = expected_bookmark['name']
            expected_url = expected_bookmark['url']
            
            found, actual_name = check_bookmark_in_folder(folder, expected_url)
            
            if found:
                logger.info(f"    ✓ Bookmark '{expected_name}' found (URL: {expected_url})")
                bookmarks_found += 1
                folder_bookmarks_found.append({
                    "name": expected_name,
                    "url": expected_url,
                    "actual_name": actual_name
                })
            else:
                logger.warning(f"    ✗ Bookmark '{expected_name}' not found (expected URL: {expected_url})")
                folder_bookmarks_missing.append({
                    "name": expected_name,
                    "url": expected_url
                })
        
        detailed_results[folder_name] = {
            "found": True,
            "bookmarks_found": folder_bookmarks_found,
            "bookmarks_missing": folder_bookmarks_missing,
            "count": len(folder_bookmarks_found)
        }
    
    # Calculate score
    # Each folder with all bookmarks = 33.33 points
    # Partial credit for folders with some bookmarks
    folders_complete = sum(1 for f in detailed_results.values() if f.get('found') and f.get('count', 0) == 3)
    
    score = (bookmarks_found / total_expected_bookmarks) * 100
    passed = score >= 75  # Need at least 7/9 bookmarks (roughly 2 complete folders)
    
    # Generate detailed feedback
    feedback_parts = []
    feedback_parts.append(f"Bookmark Import Verification:")
    feedback_parts.append(f"  Folders found: {len(folders_found)}/3")
    feedback_parts.append(f"  Bookmarks imported: {bookmarks_found}/{total_expected_bookmarks}")
    feedback_parts.append(f"  Complete folders: {folders_complete}/3")
    feedback_parts.append("")
    
    # Detailed folder breakdown
    for folder_name in EXPECTED_STRUCTURE.keys():
        if folder_name in folders_found:
            folder_result = detailed_results[folder_name]
            found_count = folder_result.get('count', 0)
            if found_count == 3:
                feedback_parts.append(f"✓ {folder_name}: All 3 bookmarks imported")
            else:
                feedback_parts.append(f"⚠ {folder_name}: Only {found_count}/3 bookmarks imported")
                missing = folder_result.get('bookmarks_missing', [])
                for bm in missing:
                    feedback_parts.append(f"    Missing: {bm['name']} ({bm['url']})")
        else:
            feedback_parts.append(f"✗ {folder_name}: Folder not found")
    
    feedback_parts.append("")
    if passed:
        feedback_parts.append(f"✅ Import successful! Score: {score:.0f}%")
    else:
        feedback_parts.append(f"❌ Import incomplete. Score: {score:.0f}% (need ≥75%)")
        feedback_parts.append("")
        feedback_parts.append("Troubleshooting:")
        feedback_parts.append("  1. Ensure you opened Bookmark Manager (Ctrl+Shift+O)")
        feedback_parts.append("  2. Click the ⋮ menu in Bookmark Manager")
        feedback_parts.append("  3. Select 'Import bookmarks'")
        feedback_parts.append("  4. Choose 'bookmarks_to_import.html' from Downloads")
    
    feedback = "\n".join(feedback_parts)
    
    logger.info(f"Verification complete: {bookmarks_found}/{total_expected_bookmarks} bookmarks, score={score:.0f}%")
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": feedback,
        "details": {
            "folders_found": len(folders_found),
            "folders_expected": 3,
            "folders_complete": folders_complete,
            "bookmarks_found": bookmarks_found,
            "total_expected": total_expected_bookmarks,
            "folder_details": detailed_results
        }
    }


def get_bookmarks_data(copy_from_env) -> Optional[Dict]:
    """
    Retrieve bookmarks data from container.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Parsed bookmarks dict or None if failed
    """
    temp_file = None
    
    try:
        # Create temporary file for copying
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json', mode='w+')
        temp_path = temp_file.name
        temp_file.close()
        
        # Try multiple possible locations for Bookmarks file
        bookmarks_paths = [
            "/tmp/bookmarks_export.json",
            "/home/ga/.config/google-chrome-cdp/Default/Bookmarks",
            "/home/ga/.config/google-chrome/Default/Bookmarks"
        ]
        
        bookmarks_data = None
        source_path = None
        
        for container_path in bookmarks_paths:
            try:
                logger.info(f"Attempting to copy from: {container_path}")
                copy_from_env(container_path, temp_path)
                
                # Check if file was copied successfully and has content
                if os.path.exists(temp_path) and os.path.getsize(temp_path) > 10:
                    with open(temp_path, 'r', encoding='utf-8') as f:
                        bookmarks_data = json.load(f)
                    source_path = container_path
                    logger.info(f"✓ Successfully copied bookmarks from: {container_path}")
                    break
                    
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                continue
        
        if bookmarks_data:
            logger.info(f"Successfully retrieved bookmarks data from: {source_path}")
            return bookmarks_data
        else:
            logger.error("Could not retrieve bookmarks from any location")
            return None
            
    except Exception as e:
        logger.error(f"Error getting bookmarks data: {e}", exc_info=True)
        return None
        
    finally:
        # Cleanup temporary file
        if temp_file and os.path.exists(temp_path):
            try:
                os.unlink(temp_path)
            except:
                pass


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for bookmarks_import_html@1 task.
    
    Args:
        traj: Trajectory data (not used for this verification)
        env_info: Environment information including copy_from_env function
        task_info: Task configuration information
        
    Returns:
        Dict with passed (bool), score (int 0-100), and feedback (str)
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
        logger.info("Retrieving bookmarks data from container...")
        bookmarks_data = get_bookmarks_data(copy_from_env)
        
        if not bookmarks_data:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Could not access Chrome bookmarks file. Ensure Chrome was closed properly to save bookmarks."
            }
        
        # Verify bookmark import
        logger.info("Verifying bookmark import...")
        verification_result = verify_bookmark_import(bookmarks_data)
        
        # Clean up
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
