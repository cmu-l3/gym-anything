#!/usr/bin/env python3
"""
Verifier for Chrome Bookmarks Folder Organization Task (bookmarks_folder_organize@1)
Task: Create 'News' folder in bookmark bar and move 3 news bookmarks into it

Verification Strategy:
- Copy Chrome Bookmarks JSON file from container
- Parse bookmark_bar structure
- Verify 'News' folder exists in bookmark bar
- Verify exactly 3 news bookmarks are inside the News folder
- Verify exactly 3 tech bookmarks remain in the bookmark bar (outside folder)
- Check URLs match expected news/tech sites
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
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../utils'))
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


# Expected URLs for verification
NEWS_URLS = [
    "https://www.bbc.com/news",
    "https://www.cnn.com",
    "https://www.theguardian.com"
]

TECH_URLS = [
    "https://techcrunch.com",
    "https://news.ycombinator.com",
    "https://arstechnica.com"
]


def normalize_url(url: str) -> str:
    """
    Normalize URL for comparison by removing trailing slashes and converting to lowercase.
    """
    if not url:
        return ""
    url = url.rstrip('/')
    url = url.lower()
    return url


def is_news_bookmark(url: str) -> bool:
    """Check if URL is one of the expected news sites."""
    url_norm = normalize_url(url)
    for news_url in NEWS_URLS:
        if normalize_url(news_url) == url_norm:
            return True
    # Also check by domain keywords
    if any(keyword in url_norm for keyword in ['bbc.com/news', 'cnn.com', 'theguardian.com']):
        return True
    return False


def is_tech_bookmark(url: str) -> bool:
    """Check if URL is one of the expected tech sites."""
    url_norm = normalize_url(url)
    for tech_url in TECH_URLS:
        if normalize_url(tech_url) == url_norm:
            return True
    # Also check by domain keywords
    if any(keyword in url_norm for keyword in ['techcrunch.com', 'news.ycombinator.com', 'arstechnica.com']):
        return True
    return False


def find_news_folder(bookmark_bar_children: List[Dict]) -> Optional[Dict]:
    """
    Find the 'News' folder in bookmark bar children.
    
    Returns:
        The News folder dict if found, None otherwise
    """
    for child in bookmark_bar_children:
        if child.get('type') == 'folder' and child.get('name') == 'News':
            return child
    return None


def count_bookmarks_in_folder(folder: Dict) -> Tuple[int, int, int]:
    """
    Count bookmarks in a folder.
    
    Returns:
        Tuple of (total_count, news_count, tech_count)
    """
    if not folder or 'children' not in folder:
        return 0, 0, 0
    
    children = folder.get('children', [])
    total = 0
    news = 0
    tech = 0
    
    for child in children:
        if child.get('type') == 'url':
            total += 1
            url = child.get('url', '')
            if is_news_bookmark(url):
                news += 1
            elif is_tech_bookmark(url):
                tech += 1
    
    return total, news, tech


def count_bookmarks_in_bar(bookmark_bar_children: List[Dict], exclude_folders: bool = True) -> Tuple[int, int, int]:
    """
    Count bookmarks directly in bookmark bar (not in folders).
    
    Returns:
        Tuple of (total_count, news_count, tech_count)
    """
    total = 0
    news = 0
    tech = 0
    
    for child in bookmark_bar_children:
        if child.get('type') == 'url':
            total += 1
            url = child.get('url', '')
            if is_news_bookmark(url):
                news += 1
            elif is_tech_bookmark(url):
                tech += 1
    
    return total, news, tech


def verify_bookmarks_organization(bookmarks_data: Dict) -> Dict[str, Any]:
    """
    Verify that bookmarks were properly organized.
    
    Verification criteria:
    1. 'News' folder exists in bookmark bar
    2. Exactly 3 news bookmarks are inside the News folder
    3. News folder contains correct URLs (matching expected news sites)
    4. Exactly 3 tech bookmarks remain in bookmark bar (outside folder)
    5. No data loss - all 6 original bookmarks still exist
    
    Returns:
        Dict with passed, score, feedback, and details
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
    
    logger.info(f"Found {len(children)} items in bookmark bar")
    
    # Criterion 1: News folder exists
    news_folder = find_news_folder(children)
    folder_exists = news_folder is not None
    
    logger.info(f"✓ Criterion 1 - News folder exists: {folder_exists}")
    
    # Criterion 2 & 3: News folder contains exactly 3 news bookmarks with correct URLs
    folder_total, folder_news, folder_tech = count_bookmarks_in_folder(news_folder)
    correct_count_in_folder = folder_news == 3
    no_tech_in_folder = folder_tech == 0
    
    logger.info(f"✓ Criterion 2 - News folder contains 3 news bookmarks: {correct_count_in_folder} (found {folder_news})")
    logger.info(f"  - Total in folder: {folder_total}, News: {folder_news}, Tech: {folder_tech}")
    
    # Verify correct URLs are in folder
    correct_urls_in_folder = True
    if news_folder:
        folder_children = news_folder.get('children', [])
        folder_urls = [child.get('url', '') for child in folder_children if child.get('type') == 'url']
        logger.info(f"  - URLs in News folder: {folder_urls}")
        
        # Check that all URLs in folder are news URLs
        for url in folder_urls:
            if not is_news_bookmark(url):
                correct_urls_in_folder = False
                logger.warning(f"  - Non-news URL found in folder: {url}")
    
    logger.info(f"✓ Criterion 3 - Correct URLs in folder: {correct_urls_in_folder}")
    
    # Criterion 4: Exactly 3 tech bookmarks remain in bookmark bar (outside folder)
    bar_total, bar_news, bar_tech = count_bookmarks_in_bar(children)
    correct_tech_in_bar = bar_tech == 3
    no_news_in_bar = bar_news == 0
    
    logger.info(f"✓ Criterion 4 - 3 tech bookmarks in bar: {correct_tech_in_bar} (found {bar_tech})")
    logger.info(f"  - Directly in bar: Total: {bar_total}, News: {bar_news}, Tech: {bar_tech}")
    
    # Criterion 5: No data loss - all 6 bookmarks still exist
    total_bookmarks = folder_total + bar_total
    no_data_loss = total_bookmarks == 6
    
    logger.info(f"✓ Criterion 5 - No data loss: {no_data_loss} (found {total_bookmarks} total bookmarks)")
    
    # Calculate score based on criteria
    criteria_results = [
        folder_exists,
        correct_count_in_folder,
        correct_urls_in_folder,
        correct_tech_in_bar,
        no_data_loss
    ]
    
    criteria_met = sum(criteria_results)
    score = (criteria_met / 5.0) * 100
    passed = score >= 80  # Need at least 4/5 criteria
    
    # Generate detailed feedback
    feedback_parts = []
    feedback_parts.append(f"Bookmarks Organization Verification: {criteria_met}/5 criteria met")
    feedback_parts.append("")
    
    if folder_exists:
        feedback_parts.append("✓ 'News' folder exists in bookmark bar")
    else:
        feedback_parts.append("✗ 'News' folder not found in bookmark bar")
    
    if correct_count_in_folder:
        feedback_parts.append(f"✓ Exactly 3 news bookmarks in News folder")
    else:
        feedback_parts.append(f"✗ Wrong number of news bookmarks in folder (found {folder_news}, expected 3)")
    
    if correct_urls_in_folder:
        feedback_parts.append("✓ Correct news URLs in folder")
    else:
        feedback_parts.append("✗ Incorrect URLs found in News folder")
    
    if correct_tech_in_bar:
        feedback_parts.append(f"✓ Exactly 3 tech bookmarks remain in bookmark bar")
    else:
        feedback_parts.append(f"✗ Wrong number of tech bookmarks in bar (found {bar_tech}, expected 3)")
    
    if no_data_loss:
        feedback_parts.append(f"✓ No data loss - all 6 bookmarks preserved")
    else:
        feedback_parts.append(f"✗ Data loss detected (found {total_bookmarks} bookmarks, expected 6)")
    
    feedback_parts.append("")
    if passed:
        feedback_parts.append("✅ Task completed successfully!")
    else:
        feedback_parts.append("❌ Task incomplete - organization criteria not met")
    
    feedback = "\n".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": feedback,
        "details": {
            "criteria_met": criteria_met,
            "folder_exists": folder_exists,
            "news_in_folder": folder_news,
            "tech_in_bar": bar_tech,
            "total_bookmarks": total_bookmarks,
            "news_in_bar": bar_news,
            "folder_total": folder_total
        }
    }


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for bookmarks_folder_organize@1.
    
    Args:
        traj: Trajectory data (not used)
        env_info: Environment information including copy_from_env function
        task_info: Task configuration
        
    Returns:
        Dict with passed, score, and feedback
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
                "feedback": "Failed to retrieve bookmarks data from container"
            }
        
        # Perform verification
        result = verify_bookmarks_organization(bookmarks_data)
        
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
    Retrieve bookmarks data from container.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Parsed bookmarks JSON dict, or None if failed
    """
    temp_file = None
    try:
        # Create temp file
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json', mode='w+')
        temp_path = temp_file.name
        temp_file.close()
        
        # Try multiple possible locations
        bookmarks_paths = [
            "/tmp/bookmarks_export.json",
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
                    
                    logger.info(f"✓ Successfully copied bookmarks from: {container_path}")
                    return bookmarks_data
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                continue
        
        # If we get here, all paths failed
        logger.error("Could not copy bookmarks file from any known location")
        return None
        
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse bookmarks JSON: {e}")
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
