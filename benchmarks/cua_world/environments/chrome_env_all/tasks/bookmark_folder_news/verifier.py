#!/usr/bin/env python3
"""
Verifier for Chrome Bookmark Folder Organization Task (bookmark_folder_news@1)
Task: Create 'News' folder in bookmark bar with three news website bookmarks

Verification Strategy:
- Parse Chrome Bookmarks JSON file
- Verify 'News' folder exists in bookmark bar
- Check that folder contains exactly 3 bookmarks with correct URLs
- Validate URL accuracy and bookmark structure
"""

import logging
import sys
import os
import json
import tempfile
from pathlib import Path
from typing import Dict, List, Any, Optional, Tuple

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../utils'))
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
    - Remove trailing slashes
    - Convert to lowercase
    - Handle protocol variations
    """
    if not url:
        return ""
    
    url = url.strip().lower()
    
    # Remove protocol for comparison
    url = url.replace('https://', '').replace('http://', '')
    
    # Remove trailing slash
    url = url.rstrip('/')
    
    return url


def find_news_folder(bookmarks_data: Dict) -> Optional[Dict]:
    """
    Find the 'News' folder in the bookmark bar.
    
    Args:
        bookmarks_data: Parsed Chrome Bookmarks JSON
        
    Returns:
        Folder dict if found, None otherwise
    """
    try:
        bookmark_bar = bookmarks_data.get('roots', {}).get('bookmark_bar', {})
        children = bookmark_bar.get('children', [])
        
        for child in children:
            if child.get('type') == 'folder' and child.get('name') == 'News':
                logger.info(f"Found 'News' folder with {len(child.get('children', []))} items")
                return child
        
        logger.warning("'News' folder not found in bookmark bar")
        return None
        
    except Exception as e:
        logger.error(f"Error searching for News folder: {e}")
        return None


def extract_folder_bookmarks(folder: Dict) -> List[Dict[str, str]]:
    """
    Extract bookmark URLs and names from a folder.
    
    Args:
        folder: Folder dict from bookmarks JSON
        
    Returns:
        List of dicts with 'name', 'url', and 'type'
    """
    bookmarks = []
    
    for item in folder.get('children', []):
        if item.get('type') == 'url':
            bookmarks.append({
                'name': item.get('name', ''),
                'url': item.get('url', ''),
                'type': item.get('type', '')
            })
    
    return bookmarks


def verify_bookmark_urls(bookmarks: List[Dict[str, str]]) -> Dict[str, Any]:
    """
    Verify that bookmarks contain the expected URLs.
    
    Expected URLs:
    1. https://news.ycombinator.com (Hacker News)
    2. https://www.bbc.com/news (BBC News)
    3. https://www.reuters.com (Reuters)
    
    Args:
        bookmarks: List of bookmark dicts
        
    Returns:
        Dict with verification results
    """
    # Expected URLs (normalized for comparison)
    expected_urls = {
        'hackernews': normalize_url('https://news.ycombinator.com'),
        'bbc': normalize_url('https://www.bbc.com/news'),
        'reuters': normalize_url('https://www.reuters.com')
    }
    
    # Track which URLs were found
    found_urls = {
        'hackernews': False,
        'bbc': False,
        'reuters': False
    }
    
    found_url_list = []
    
    for bookmark in bookmarks:
        url_normalized = normalize_url(bookmark['url'])
        found_url_list.append(url_normalized)
        
        # Check against expected URLs
        if 'news.ycombinator.com' in url_normalized:
            found_urls['hackernews'] = True
        elif 'bbc.com/news' in url_normalized:
            found_urls['bbc'] = True
        elif 'reuters.com' in url_normalized:
            found_urls['reuters'] = True
    
    # Calculate results
    total_expected = len(expected_urls)
    total_found = sum(found_urls.values())
    
    return {
        'found_urls': found_urls,
        'total_expected': total_expected,
        'total_found': total_found,
        'all_found': all(found_urls.values()),
        'found_url_list': found_url_list
    }


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for bookmark_folder_news@1.
    
    Verification Criteria:
    1. 'News' folder exists in bookmark bar
    2. Folder contains exactly 3 bookmarks
    3. All three expected URLs are present (Hacker News, BBC News, Reuters)
    4. Bookmarks are in correct location (bookmark bar → News folder)
    
    Scoring:
    - 100%: All 4 criteria met
    - 75-99%: 3/4 criteria met (2 out of 3 URLs correct)
    - 50-74%: 2/4 criteria met (folder exists with at least 1 correct URL)
    - 0-49%: <2 criteria met
    
    Pass threshold: 75% (requires at least 3 out of 4 criteria)
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
                "feedback": "Failed to retrieve Chrome Bookmarks file"
            }
        
        # Perform verification
        result = verify_news_folder_bookmarks(bookmarks_data)
        
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


def get_bookmarks_data(copy_from_env) -> Optional[Dict]:
    """
    Retrieve and parse Chrome Bookmarks file from container.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Parsed bookmarks JSON dict, or None on failure
    """
    temp_file = None
    
    try:
        # Create temporary file
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json', mode='w+')
        temp_path = temp_file.name
        temp_file.close()
        
        # Try multiple possible locations
        bookmarks_paths = [
            "/tmp/bookmarks_export.json",
            "/tmp/bookmark_folder_verification/Bookmarks",
            "/home/ga/.config/google-chrome-cdp/Default/Bookmarks",
            "/home/ga/.config/google-chrome/Default/Bookmarks"
        ]
        
        bookmarks_data = None
        source_path = None
        
        for container_path in bookmarks_paths:
            try:
                logger.info(f"Trying to copy Bookmarks from: {container_path}")
                copy_from_env(container_path, temp_path)
                
                # Check if file was copied successfully
                if os.path.exists(temp_path) and os.path.getsize(temp_path) > 0:
                    with open(temp_path, 'r', encoding='utf-8') as f:
                        bookmarks_data = json.load(f)
                    
                    source_path = container_path
                    logger.info(f"✓ Successfully copied and parsed Bookmarks from: {container_path}")
                    break
                    
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                continue
        
        if bookmarks_data is None:
            logger.error("Could not copy Bookmarks file from any known location")
            return None
        
        return bookmarks_data
        
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse Bookmarks JSON: {e}")
        return None
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


def verify_news_folder_bookmarks(bookmarks_data: Dict) -> Dict[str, Any]:
    """
    Verify the News folder and its bookmarks.
    
    Args:
        bookmarks_data: Parsed Chrome Bookmarks JSON
        
    Returns:
        Verification result dict
    """
    criteria_met = 0
    total_criteria = 4
    feedback_parts = []
    
    # Criterion 1: News folder exists in bookmark bar
    news_folder = find_news_folder(bookmarks_data)
    folder_exists = news_folder is not None
    
    if folder_exists:
        feedback_parts.append("✓ 'News' folder found in bookmark bar")
        criteria_met += 1
    else:
        feedback_parts.append("✗ 'News' folder not found in bookmark bar")
        # If folder doesn't exist, other criteria automatically fail
        feedback = "\n".join(feedback_parts)
        feedback += f"\n\nCriteria met: {criteria_met}/{total_criteria}"
        feedback += f"\nScore: 0%"
        feedback += "\n\nPlease create a folder named 'News' (case-sensitive) in the bookmark bar."
        
        return {
            "passed": False,
            "score": 0,
            "feedback": feedback,
            "details": {
                "folder_exists": False,
                "bookmark_count": 0,
                "urls_found": {'hackernews': False, 'bbc': False, 'reuters': False}
            }
        }
    
    # Extract bookmarks from News folder
    bookmarks = extract_folder_bookmarks(news_folder)
    bookmark_count = len(bookmarks)
    
    logger.info(f"Found {bookmark_count} bookmarks in News folder")
    for i, bm in enumerate(bookmarks, 1):
        logger.info(f"  Bookmark {i}: {bm['name']} → {bm['url']}")
    
    # Criterion 2: Folder contains exactly 3 bookmarks
    correct_count = bookmark_count == 3
    
    if correct_count:
        feedback_parts.append(f"✓ Correct number of bookmarks: {bookmark_count}")
        criteria_met += 1
    else:
        if bookmark_count < 3:
            feedback_parts.append(f"⚠ Only {bookmark_count} bookmark(s) found (expected 3)")
            # Give partial credit if at least some bookmarks exist
            if bookmark_count > 0:
                criteria_met += 0.5
        else:
            feedback_parts.append(f"⚠ Too many bookmarks: {bookmark_count} (expected 3)")
            criteria_met += 0.7  # Minor penalty for extras
    
    # Criterion 3: All three expected URLs are present
    url_check = verify_bookmark_urls(bookmarks)
    
    if url_check['all_found']:
        feedback_parts.append(f"✓ All 3 expected URLs found")
        criteria_met += 2  # This is the most important criterion, worth 2 points
    else:
        found_count = url_check['total_found']
        feedback_parts.append(f"✗ Only {found_count}/3 expected URLs found:")
        feedback_parts.append(f"  - Hacker News: {'✓' if url_check['found_urls']['hackernews'] else '✗'}")
        feedback_parts.append(f"  - BBC News: {'✓' if url_check['found_urls']['bbc'] else '✗'}")
        feedback_parts.append(f"  - Reuters: {'✓' if url_check['found_urls']['reuters'] else '✗'}")
        
        # Partial credit based on how many URLs were found
        criteria_met += (found_count / 3.0) * 2
    
    # Calculate final score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75
    
    # Build final feedback
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\n{'='*50}"
    feedback += f"\nCriteria met: {criteria_met:.1f}/{total_criteria}"
    feedback += f"\nFinal score: {score}%"
    feedback += f"\nResult: {'PASSED ✓' if passed else 'FAILED ✗'}"
    
    if not passed:
        feedback += "\n\nTo pass, you need:"
        if not folder_exists:
            feedback += "\n  - Create 'News' folder in bookmark bar"
        if not correct_count:
            feedback += f"\n  - Add exactly 3 bookmarks (currently {bookmark_count})"
        if not url_check['all_found']:
            feedback += "\n  - Include all three URLs:"
            if not url_check['found_urls']['hackernews']:
                feedback += "\n    • https://news.ycombinator.com"
            if not url_check['found_urls']['bbc']:
                feedback += "\n    • https://www.bbc.com/news"
            if not url_check['found_urls']['reuters']:
                feedback += "\n    • https://www.reuters.com"
    else:
        feedback += "\n\n✅ Bookmark organization completed successfully!"
    
    logger.info(f"Verification complete: passed={passed}, score={score}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "folder_exists": folder_exists,
            "bookmark_count": bookmark_count,
            "correct_count": correct_count,
            "urls_found": url_check['found_urls'],
            "criteria_met": criteria_met,
            "bookmarks": [{'name': b['name'], 'url': b['url']} for b in bookmarks]
        }
    }
