#!/usr/bin/env python3
"""
Verifier for Chrome Bookmark All Tabs Task: bookmark_all_tabs@1
Task: Open multiple Wikipedia AI/ML articles and bookmark all tabs into a folder

Verification Strategy:
- Parse Chrome Bookmarks JSON file
- Check for folder "AI Research Resources" in bookmark bar
- Verify folder contains expected Wikipedia URLs
- Allow 3/4 URLs for partial credit (75%)
- Full credit for all 4 URLs (100%)
"""

import logging
import sys
import os
import json
import re
import tempfile
from pathlib import Path
from typing import Dict, List, Any, Tuple, Set

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add Chrome verification utilities to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../utils'))
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
        with open(path, 'r', encoding='utf-8') as f:
            return json.load(f)
    
    def cleanup_verification_temp():
        pass


def normalize_url(url: str) -> str:
    """
    Normalize URL for comparison by removing trailing slashes,
    converting to lowercase, and handling protocol variations.
    
    Args:
        url: URL string to normalize
        
    Returns:
        Normalized URL string
    """
    if not url:
        return ""
    
    # Convert to lowercase
    url = url.lower()
    
    # Remove trailing slashes
    url = url.rstrip('/')
    
    # Handle protocol variations (http vs https)
    url = url.replace('http://', '').replace('https://', '')
    
    return url


def check_url_match(actual_url: str, expected_url: str) -> bool:
    """
    Check if two URLs match, accounting for minor variations.
    
    Args:
        actual_url: URL found in bookmarks
        expected_url: Expected URL pattern
        
    Returns:
        True if URLs match, False otherwise
    """
    actual_norm = normalize_url(actual_url)
    expected_norm = normalize_url(expected_url)
    
    # Exact match
    if actual_norm == expected_norm:
        return True
    
    # Check if expected is a substring (handles query parameters, fragments)
    if expected_norm in actual_norm:
        return True
    
    return False


def verify_bookmark_all_tabs(bookmarks_data: Dict[str, Any],
                             expected_folder: str,
                             expected_urls: List[str]) -> Dict[str, Any]:
    """
    Verify that all tabs were bookmarked into a named folder.
    
    Args:
        bookmarks_data: Parsed Chrome Bookmarks JSON
        expected_folder: Expected folder name (case-insensitive)
        expected_urls: List of URLs that should be bookmarked
        
    Returns:
        Dict with verification results including passed, score, feedback, and details
    """
    if not bookmarks_data:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Could not parse bookmarks file",
            "details": {}
        }
    
    # Navigate to bookmark bar
    bookmark_bar = bookmarks_data.get('roots', {}).get('bookmark_bar', {})
    children = bookmark_bar.get('children', [])
    
    logger.info(f"Bookmark bar has {len(children)} items")
    
    # Criterion 1: Folder exists in bookmark bar
    folder_exists = False
    target_folder = None
    actual_folder_name = ""
    
    for child in children:
        if child.get('type') == 'folder':
            folder_name = child.get('name', '')
            logger.info(f"Found folder: '{folder_name}'")
            
            # Case-insensitive matching with fuzzy logic
            if folder_name.lower() == expected_folder.lower():
                folder_exists = True
                target_folder = child
                actual_folder_name = folder_name
                logger.info(f"✓ Exact match for folder: '{folder_name}'")
                break
            elif expected_folder.lower() in folder_name.lower() or folder_name.lower() in expected_folder.lower():
                # Partial match (e.g., "AI Research" matches "AI Research Resources")
                folder_exists = True
                target_folder = child
                actual_folder_name = folder_name
                logger.info(f"✓ Partial match for folder: '{folder_name}'")
                break
    
    if not folder_exists:
        logger.warning(f"Folder '{expected_folder}' not found in bookmark bar")
        all_folders = [c.get('name', '') for c in children if c.get('type') == 'folder']
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Folder '{expected_folder}' not found in bookmark bar. Found folders: {all_folders if all_folders else 'none'}",
            "details": {
                "folder_exists": False,
                "found_folders": all_folders,
                "urls_matched": 0,
                "total_expected": len(expected_urls)
            }
        }
    
    # Criterion 2: Extract URLs from folder
    folder_urls = []
    folder_items = target_folder.get('children', [])
    
    logger.info(f"Folder '{actual_folder_name}' has {len(folder_items)} items")
    
    for item in folder_items:
        if item.get('type') == 'url':
            item_url = item.get('url', '')
            item_name = item.get('name', '')
            folder_urls.append(item_url)
            logger.info(f"  - Bookmark: '{item_name}' -> {item_url}")
    
    # Criterion 3: Match URLs
    matched_urls: Set[str] = set()
    missing_urls: List[str] = []
    
    for expected_url in expected_urls:
        matched = False
        for folder_url in folder_urls:
            if check_url_match(folder_url, expected_url):
                matched = True
                matched_urls.add(expected_url)
                logger.info(f"✓ Matched: {expected_url}")
                break
        
        if not matched:
            missing_urls.append(expected_url)
            logger.warning(f"✗ Missing: {expected_url}")
    
    # Calculate score based on criteria
    num_matched = len(matched_urls)
    num_expected = len(expected_urls)
    match_ratio = num_matched / num_expected if num_expected > 0 else 0
    
    # Scoring breakdown:
    # - Folder exists and in correct location: 25 points
    # - Each URL matched: 75 points / num_expected per URL
    
    folder_score = 25
    url_score = int(75 * match_ratio)
    total_score = folder_score + url_score
    
    # Pass threshold: 75% (need at least 3/4 URLs or equivalent)
    passed = total_score >= 75
    
    # Generate detailed feedback
    feedback_parts = []
    feedback_parts.append(f"✓ Folder '{actual_folder_name}' found in bookmark bar")
    feedback_parts.append(f"URLs matched: {num_matched}/{num_expected}")
    
    if num_matched == num_expected:
        feedback_parts.append("✓ All expected URLs bookmarked successfully!")
    elif num_matched >= (num_expected * 0.75):
        feedback_parts.append(f"⚠ Most URLs bookmarked, but missing: {[url.split('/')[-1] for url in missing_urls]}")
    else:
        feedback_parts.append(f"✗ Insufficient URLs bookmarked")
    
    if missing_urls:
        feedback_parts.append(f"Missing URLs ({len(missing_urls)}): {', '.join([url.split('/')[-1].replace('_', ' ') for url in missing_urls])}")
    
    # Check for extra URLs (not necessarily bad, but informative)
    extra_url_count = len(folder_urls) - num_matched
    if extra_url_count > 0:
        feedback_parts.append(f"Note: {extra_url_count} additional URL(s) also bookmarked in this folder")
    
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\nFinal Score: {total_score}/100 ({'PASSED ✓' if passed else 'FAILED ✗'})"
    
    logger.info(f"Verification complete: {num_matched}/{num_expected} URLs matched, score={total_score}, passed={passed}")
    
    return {
        "passed": passed,
        "score": total_score,
        "feedback": feedback,
        "details": {
            "folder_exists": folder_exists,
            "folder_name": actual_folder_name,
            "urls_matched": num_matched,
            "urls_missing": len(missing_urls),
            "total_expected": num_expected,
            "match_ratio": match_ratio,
            "matched_urls": list(matched_urls),
            "missing_urls": missing_urls,
            "extra_urls": extra_url_count
        }
    }


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for bookmark_all_tabs@1 task.
    
    Args:
        traj: Trajectory data (not used for this verification)
        env_info: Environment information including copy_from_env function
        task_info: Task configuration information
        
    Returns:
        Dict with passed, score, feedback, and details
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env function not available in environment"
        }
    
    # Task parameters
    expected_folder = "AI Research Resources"
    expected_urls = [
        "https://en.wikipedia.org/wiki/Artificial_intelligence",
        "https://en.wikipedia.org/wiki/Machine_learning",
        "https://en.wikipedia.org/wiki/Deep_learning",
        "https://en.wikipedia.org/wiki/Neural_network"
    ]
    
    try:
        logger.info("Starting bookmark verification...")
        logger.info(f"Expected folder: '{expected_folder}'")
        logger.info(f"Expected URLs: {len(expected_urls)}")
        
        # Try to copy bookmarks file from container
        bookmarks_data = None
        
        # Try multiple possible locations
        bookmarks_paths = [
            "/tmp/bookmarks_export.json",
            "/home/ga/.config/google-chrome-cdp/Default/Bookmarks",
            "/home/ga/.config/google-chrome/Default/Bookmarks"
        ]
        
        for container_path in bookmarks_paths:
            try:
                temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json', mode='w+')
                temp_path = temp_file.name
                temp_file.close()
                
                logger.info(f"Trying to copy bookmarks from: {container_path}")
                copy_from_env(container_path, temp_path)
                
                # Check if file was copied successfully
                if os.path.exists(temp_path) and os.path.getsize(temp_path) > 0:
                    with open(temp_path, 'r', encoding='utf-8') as f:
                        bookmarks_data = json.load(f)
                    os.unlink(temp_path)
                    logger.info(f"✓ Successfully loaded bookmarks from: {container_path}")
                    break
                else:
                    os.unlink(temp_path)
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                if os.path.exists(temp_path):
                    try:
                        os.unlink(temp_path)
                    except:
                        pass
                continue
        
        if not bookmarks_data:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Could not access bookmarks file from any known location. Ensure Chrome was properly closed to save bookmarks."
            }
        
        # Verify bookmark structure
        result = verify_bookmark_all_tabs(
            bookmarks_data,
            expected_folder,
            expected_urls
        )
        
        # Clean up
        cleanup_verification_temp()
        
        return result
        
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse bookmarks JSON: {e}")
        cleanup_verification_temp()
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to parse bookmarks file: {str(e)}"
        }
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        cleanup_verification_temp()
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
