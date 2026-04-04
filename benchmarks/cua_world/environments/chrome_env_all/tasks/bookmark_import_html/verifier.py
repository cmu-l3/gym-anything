#!/usr/bin/env python3
"""
Verifier for Chrome Bookmark Import from HTML Task (bookmark_import_html@1)
Task: Import bookmarks from HTML file into Chrome bookmark system

Verification Strategy:
- Copy Chrome Bookmarks JSON file from container
- Parse JSON structure recursively
- Verify presence of imported folders and URLs
- Check hierarchical structure is preserved
- Validate all bookmarks from HTML are present
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
        with open(path, 'r', encoding='utf-8') as f:
            return json.load(f)
    
    def cleanup_verification_temp():
        pass


def normalize_url(url: str) -> str:
    """
    Normalize URL for comparison.
    Removes trailing slashes, converts to lowercase, removes protocol.
    
    Args:
        url: URL string to normalize
        
    Returns:
        Normalized URL string
    """
    if not url:
        return ""
    # Remove trailing slashes
    url = url.rstrip('/')
    # Convert to lowercase
    url = url.lower()
    # Remove protocol
    url = url.replace('https://', '').replace('http://', '')
    # Remove www. prefix for more flexible matching
    url = url.replace('www.', '')
    return url


def find_folder_recursive(node: Dict[str, Any], folder_name: str) -> Optional[Dict[str, Any]]:
    """
    Recursively search for a folder by name in bookmark structure.
    
    Args:
        node: Current bookmark node to search
        folder_name: Name of folder to find
        
    Returns:
        Folder node if found, None otherwise
    """
    # Check if current node is the target folder
    if node.get('type') == 'folder' and node.get('name') == folder_name:
        return node
    
    # Recursively search children
    for child in node.get('children', []):
        result = find_folder_recursive(child, folder_name)
        if result:
            return result
    
    return None


def find_url_in_folder(folder_node: Dict[str, Any], target_url: str) -> bool:
    """
    Check if a specific URL exists within a folder's immediate children.
    
    Args:
        folder_node: Folder node to search in
        target_url: URL to find (will be normalized for comparison)
        
    Returns:
        True if URL found, False otherwise
    """
    if not folder_node:
        return False
    
    target_normalized = normalize_url(target_url)
    
    for child in folder_node.get('children', []):
        if child.get('type') == 'url':
            child_url = normalize_url(child.get('url', ''))
            if child_url == target_normalized:
                return True
    
    return False


def find_url_at_root_level(bookmarks_data: Dict[str, Any], target_url: str) -> bool:
    """
    Check if a URL exists at the root level of bookmark bar.
    
    Args:
        bookmarks_data: Full bookmarks data structure
        target_url: URL to find
        
    Returns:
        True if URL found at root level, False otherwise
    """
    target_normalized = normalize_url(target_url)
    
    # Check bookmark bar root level
    bookmark_bar = bookmarks_data.get('roots', {}).get('bookmark_bar', {})
    
    for child in bookmark_bar.get('children', []):
        if child.get('type') == 'url':
            child_url = normalize_url(child.get('url', ''))
            if child_url == target_normalized:
                return True
    
    return False


def find_url_anywhere(node: Dict[str, Any], target_url: str) -> bool:
    """
    Recursively search for a URL anywhere in the bookmark structure.
    Fallback method if URL is not in expected location.
    
    Args:
        node: Current node to search
        target_url: URL to find
        
    Returns:
        True if URL found anywhere, False otherwise
    """
    target_normalized = normalize_url(target_url)
    
    # Check if current node is the target URL
    if node.get('type') == 'url':
        node_url = normalize_url(node.get('url', ''))
        if node_url == target_normalized:
            return True
    
    # Recursively search children
    for child in node.get('children', []):
        if find_url_anywhere(child, target_url):
            return True
    
    return False


def verify_bookmark_structure(bookmarks_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that all expected bookmarks from HTML file were imported correctly.
    
    Expected structure:
    - Folder: "Imported Resources"
      - URL: "https://www.wikipedia.org"
      - URL: "https://www.github.com"
    - Folder: "News Sites"
      - URL: "https://news.ycombinator.com"
      - URL: "https://www.reddit.com"
    - URL: "https://www.example.com" (root level)
    
    Args:
        bookmarks_data: Parsed bookmarks JSON data
        
    Returns:
        Dict with verification results
    """
    if not bookmarks_data or not bookmarks_data.get('roots'):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Could not parse bookmarks file or file is empty",
            "criteria_results": {}
        }
    
    # Get the bookmark bar root
    bookmark_bar = bookmarks_data.get('roots', {}).get('bookmark_bar', {})
    
    # Define expected structure
    expected_folders = {
        "Imported Resources": ["https://www.wikipedia.org", "https://www.github.com"],
        "News Sites": ["https://news.ycombinator.com", "https://www.reddit.com"]
    }
    expected_root_urls = ["https://www.example.com"]
    
    # Initialize results
    criteria_results = {}
    feedback_parts = []
    
    # Check Criterion 1: "Imported Resources" folder exists
    imported_resources_folder = find_folder_recursive(bookmark_bar, "Imported Resources")
    criteria_results["imported_resources_folder"] = imported_resources_folder is not None
    
    if imported_resources_folder:
        logger.info("✓ Found 'Imported Resources' folder")
        feedback_parts.append("✓ 'Imported Resources' folder created")
    else:
        logger.warning("✗ 'Imported Resources' folder not found")
        feedback_parts.append("✗ 'Imported Resources' folder missing")
    
    # Check Criterion 2: "News Sites" folder exists
    news_sites_folder = find_folder_recursive(bookmark_bar, "News Sites")
    criteria_results["news_sites_folder"] = news_sites_folder is not None
    
    if news_sites_folder:
        logger.info("✓ Found 'News Sites' folder")
        feedback_parts.append("✓ 'News Sites' folder created")
    else:
        logger.warning("✗ 'News Sites' folder not found")
        feedback_parts.append("✗ 'News Sites' folder missing")
    
    # Check Criterion 3: Wikipedia URL in "Imported Resources"
    wikipedia_found = find_url_in_folder(imported_resources_folder, "https://www.wikipedia.org")
    if not wikipedia_found and imported_resources_folder:
        # Fallback: check if it's anywhere in the structure
        wikipedia_found = find_url_anywhere(bookmark_bar, "https://www.wikipedia.org")
    criteria_results["wikipedia_url"] = wikipedia_found
    
    if wikipedia_found:
        logger.info("✓ Found Wikipedia URL")
        feedback_parts.append("✓ Wikipedia bookmark present")
    else:
        logger.warning("✗ Wikipedia URL not found")
        feedback_parts.append("✗ Wikipedia bookmark missing")
    
    # Check Criterion 4: GitHub URL in "Imported Resources"
    github_found = find_url_in_folder(imported_resources_folder, "https://www.github.com")
    if not github_found and imported_resources_folder:
        github_found = find_url_anywhere(bookmark_bar, "https://www.github.com")
    criteria_results["github_url"] = github_found
    
    if github_found:
        logger.info("✓ Found GitHub URL")
        feedback_parts.append("✓ GitHub bookmark present")
    else:
        logger.warning("✗ GitHub URL not found")
        feedback_parts.append("✗ GitHub bookmark missing")
    
    # Check Criterion 5: Hacker News URL in "News Sites"
    hackernews_found = find_url_in_folder(news_sites_folder, "https://news.ycombinator.com")
    if not hackernews_found and news_sites_folder:
        hackernews_found = find_url_anywhere(bookmark_bar, "https://news.ycombinator.com")
    criteria_results["hackernews_url"] = hackernews_found
    
    if hackernews_found:
        logger.info("✓ Found Hacker News URL")
        feedback_parts.append("✓ Hacker News bookmark present")
    else:
        logger.warning("✗ Hacker News URL not found")
        feedback_parts.append("✗ Hacker News bookmark missing")
    
    # Check Criterion 6: Reddit URL in "News Sites"
    reddit_found = find_url_in_folder(news_sites_folder, "https://www.reddit.com")
    if not reddit_found and news_sites_folder:
        reddit_found = find_url_anywhere(bookmark_bar, "https://www.reddit.com")
    criteria_results["reddit_url"] = reddit_found
    
    if reddit_found:
        logger.info("✓ Found Reddit URL")
        feedback_parts.append("✓ Reddit bookmark present")
    else:
        logger.warning("✗ Reddit URL not found")
        feedback_parts.append("✗ Reddit bookmark missing")
    
    # Check Criterion 7: Example Domain URL at root level
    example_found = find_url_at_root_level(bookmarks_data, "https://www.example.com")
    if not example_found:
        # Fallback: check anywhere in structure
        example_found = find_url_anywhere(bookmark_bar, "https://www.example.com")
    criteria_results["example_url"] = example_found
    
    if example_found:
        logger.info("✓ Found Example Domain URL")
        feedback_parts.append("✓ Example Domain bookmark present")
    else:
        logger.warning("✗ Example Domain URL not found")
        feedback_parts.append("✗ Example Domain bookmark missing")
    
    # Calculate score
    total_criteria = len(criteria_results)
    criteria_met = sum(1 for v in criteria_results.values() if v)
    score = int((criteria_met / total_criteria) * 100)
    
    # Determine pass/fail (need at least 5/7 = 71%, so threshold at 85% requires 6/7)
    passed = score >= 85  # At least 6 out of 7 criteria
    
    # Build comprehensive feedback
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\n{'='*50}"
    feedback += f"\nCriteria met: {criteria_met}/{total_criteria}"
    feedback += f"\nFinal score: {score}%"
    
    if passed:
        feedback += "\n✅ Bookmark import successful!"
    else:
        feedback += "\n❌ Bookmark import incomplete"
        if criteria_met >= 4:
            feedback += "\nPartial import detected - some bookmarks may be in wrong locations"
        elif criteria_met >= 2:
            feedback += "\nMinimal import detected - most bookmarks missing or incorrect"
        else:
            feedback += "\nImport appears to have failed"
    
    logger.info(f"Verification complete: {criteria_met}/{total_criteria} criteria met, score={score}%")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "criteria_results": criteria_results,
        "details": {
            "criteria_met": criteria_met,
            "total_criteria": total_criteria,
            "folders_found": {
                "imported_resources": criteria_results.get("imported_resources_folder", False),
                "news_sites": criteria_results.get("news_sites_folder", False)
            },
            "urls_found": {
                "wikipedia": criteria_results.get("wikipedia_url", False),
                "github": criteria_results.get("github_url", False),
                "hackernews": criteria_results.get("hackernews_url", False),
                "reddit": criteria_results.get("reddit_url", False),
                "example": criteria_results.get("example_url", False)
            }
        }
    }


def get_bookmarks_data(copy_from_env) -> Tuple[Optional[Dict[str, Any]], str]:
    """
    Retrieve and parse bookmarks data from container.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Tuple of (bookmarks_data dict or None, error_message)
    """
    temp_file = None
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        
        # Try multiple possible locations
        bookmarks_paths = [
            "/tmp/bookmarks_export.json",
            "/home/ga/.config/google-chrome-cdp/Default/Bookmarks",
            "/home/ga/.config/google-chrome/Default/Bookmarks",
            "/home/ga/.config/chromium/Default/Bookmarks"
        ]
        
        bookmarks_data = None
        source_path = None
        
        for container_path in bookmarks_paths:
            try:
                logger.info(f"Trying to copy bookmarks from: {container_path}")
                copy_from_env(container_path, temp_file.name)
                
                # Check if file was copied successfully
                if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) > 0:
                    with open(temp_file.name, 'r', encoding='utf-8') as f:
                        bookmarks_data = json.load(f)
                    source_path = container_path
                    logger.info(f"✓ Successfully copied bookmarks from: {container_path}")
                    break
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                continue
        
        if not bookmarks_data:
            return None, "Could not access bookmarks file from any known location"
        
        return bookmarks_data, ""
        
    except json.JSONDecodeError as e:
        return None, f"Failed to parse bookmarks JSON: {e}"
    except Exception as e:
        return None, f"Error retrieving bookmarks: {e}"
    finally:
        # Cleanup temp file
        if temp_file and os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for bookmark_import_html@1 task.
    
    Verifies that bookmarks from HTML file were properly imported into Chrome
    with correct folder structure and URLs.
    
    Args:
        traj: Trajectory data (not used)
        env_info: Environment info with copy_from_env function
        task_info: Task configuration
        
    Returns:
        Dict with passed, score, feedback, and details
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
        bookmarks_data, error_msg = get_bookmarks_data(copy_from_env)
        
        if not bookmarks_data:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to retrieve bookmarks: {error_msg}"
            }
        
        # Verify bookmark structure
        logger.info("Verifying bookmark structure...")
        result = verify_bookmark_structure(bookmarks_data)
        
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
