#!/usr/bin/env python3
"""
Verifier for Chrome Import Bookmarks from HTML Task (import_bookmarks_html@1)
Task: Import bookmarks from HTML file using Chrome's import functionality

Verification Strategy:
- Parse the Chrome Bookmarks JSON file after task completion
- Define expected bookmarks from the known HTML file
- Recursively search through bookmarks structure to find imported items
- Verify all expected URLs and titles are present
- Check that bookmarks are properly organized
- Ensure complete import (100% of bookmarks)

Scoring:
- 100%: All 5 criteria met (perfect import)
- 80-99%: 4/5 criteria met (good import with minor issues)
- 60-79%: 3/5 criteria met (partial import)
- 40-59%: 2/5 criteria met (incomplete import)
- 0-39%: <2 criteria met (import failed)

Pass threshold: 80% (4 out of 5 criteria)
"""

import logging
import sys
import os
import json
import tempfile
from pathlib import Path
from typing import Dict, List, Any, Tuple, Set

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


# Expected bookmarks from the HTML file we created
EXPECTED_BOOKMARKS = [
    {
        "title": "Python Documentation",
        "url": "https://docs.python.org/3/"
    },
    {
        "title": "Stack Overflow",
        "url": "https://stackoverflow.com/"
    },
    {
        "title": "GitHub",
        "url": "https://github.com/"
    },
    {
        "title": "MDN Web Docs",
        "url": "https://developer.mozilla.org/"
    },
    {
        "title": "W3Schools",
        "url": "https://www.w3schools.com/"
    }
]


def normalize_url(url: str) -> str:
    """
    Normalize URL for comparison by removing trailing slashes and converting to lowercase.
    """
    if not url:
        return ""
    # Remove trailing slashes
    url = url.rstrip('/')
    # Convert to lowercase for case-insensitive comparison
    url = url.lower()
    # Remove protocol for comparison
    url = url.replace('https://', '').replace('http://', '')
    return url


def find_all_bookmark_urls(bookmarks_json, urls: List[str] = None) -> List[str]:
    """
    Recursively find all bookmark URLs in the bookmarks structure.
    
    Args:
        bookmarks_json: Bookmarks JSON data (dict or list)
        urls: Accumulator list for URLs
        
    Returns:
        List of all URLs found
    """
    if urls is None:
        urls = []
    
    if isinstance(bookmarks_json, dict):
        # If this is a URL bookmark node
        if bookmarks_json.get('type') == 'url':
            url = bookmarks_json.get('url')
            if url:
                urls.append(url)
        
        # Recursively process children
        if 'children' in bookmarks_json:
            for child in bookmarks_json['children']:
                find_all_bookmark_urls(child, urls)
        
        # Process other dict values
        for key, value in bookmarks_json.items():
            if key != 'children' and isinstance(value, (dict, list)):
                find_all_bookmark_urls(value, urls)
                
    elif isinstance(bookmarks_json, list):
        for item in bookmarks_json:
            find_all_bookmark_urls(item, urls)
    
    return urls


def find_all_bookmarks_with_titles(bookmarks_json, bookmarks: List[Dict[str, str]] = None) -> List[Dict[str, str]]:
    """
    Recursively find all bookmarks (URL + title pairs) in the bookmarks structure.
    
    Args:
        bookmarks_json: Bookmarks JSON data
        bookmarks: Accumulator list for bookmark dicts
        
    Returns:
        List of dicts with 'url' and 'title' keys
    """
    if bookmarks is None:
        bookmarks = []
    
    if isinstance(bookmarks_json, dict):
        # If this is a URL bookmark node
        if bookmarks_json.get('type') == 'url':
            url = bookmarks_json.get('url')
            title = bookmarks_json.get('name')  # Chrome uses 'name' not 'title'
            if url:
                bookmarks.append({'url': url, 'title': title or ''})
        
        # Recursively process children
        if 'children' in bookmarks_json:
            for child in bookmarks_json['children']:
                find_all_bookmarks_with_titles(child, bookmarks)
        
        # Process other dict values
        for key, value in bookmarks_json.items():
            if key != 'children' and isinstance(value, (dict, list)):
                find_all_bookmarks_with_titles(value, bookmarks)
                
    elif isinstance(bookmarks_json, list):
        for item in bookmarks_json:
            find_all_bookmarks_with_titles(item, bookmarks)
    
    return bookmarks


def check_folder_exists(bookmarks_json, folder_name: str, case_sensitive: bool = False) -> bool:
    """
    Check if a folder with the given name exists anywhere in bookmarks structure.
    
    Args:
        bookmarks_json: Bookmarks JSON data
        folder_name: Name of folder to find
        case_sensitive: Whether to do case-sensitive matching
        
    Returns:
        True if folder found, False otherwise
    """
    if isinstance(bookmarks_json, dict):
        if bookmarks_json.get('type') == 'folder':
            name = bookmarks_json.get('name', '')
            if case_sensitive:
                if name == folder_name:
                    return True
            else:
                if name.lower() == folder_name.lower():
                    return True
        
        # Recursively check children and other dict values
        for value in bookmarks_json.values():
            if isinstance(value, (dict, list)):
                if check_folder_exists(value, folder_name, case_sensitive):
                    return True
                    
    elif isinstance(bookmarks_json, list):
        for item in bookmarks_json:
            if check_folder_exists(item, folder_name, case_sensitive):
                return True
    
    return False


def get_bookmarks_from_file(copy_from_env, container_path: str) -> Dict[str, Any]:
    """
    Copy bookmarks file from container and parse it.
    
    Args:
        copy_from_env: Function to copy files from container
        container_path: Path to bookmarks file in container
        
    Returns:
        Parsed bookmarks JSON as dict, or None if failed
    """
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_path = temp_file.name
    temp_file.close()
    
    try:
        logger.info(f"Attempting to copy bookmarks from: {container_path}")
        copy_from_env(container_path, temp_path)
        
        # Check if file was copied successfully
        if not os.path.exists(temp_path) or os.path.getsize(temp_path) == 0:
            logger.warning(f"File not found or empty: {container_path}")
            return None
        
        # Parse JSON
        with open(temp_path, 'r', encoding='utf-8') as f:
            data = json.load(f)
        
        logger.info(f"✓ Successfully loaded bookmarks from: {container_path}")
        return data
        
    except json.JSONDecodeError as e:
        logger.error(f"JSON decode error for {container_path}: {e}")
        return None
    except Exception as e:
        logger.debug(f"Failed to copy from {container_path}: {e}")
        return None
    finally:
        # Cleanup temp file
        if os.path.exists(temp_path):
            try:
                os.unlink(temp_path)
            except:
                pass


def verify_bookmark_import(bookmarks_data: Dict[str, Any], expected_bookmarks: List[Dict[str, str]]) -> Dict[str, Any]:
    """
    Verify that expected bookmarks were imported into Chrome.
    
    Args:
        bookmarks_data: Parsed Chrome Bookmarks JSON
        expected_bookmarks: List of expected bookmark dicts with 'url' and 'title'
        
    Returns:
        Dict with verification results including passed, score, feedback, and details
    """
    if not bookmarks_data:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Could not parse bookmarks file",
            "criteria": {}
        }
    
    # Find all bookmarks in the structure
    all_bookmarks = find_all_bookmarks_with_titles(bookmarks_data)
    all_urls = [bm['url'] for bm in all_bookmarks]
    all_titles = [bm['title'] for bm in all_bookmarks]
    
    logger.info(f"Found {len(all_bookmarks)} total bookmarks in Chrome")
    
    # Normalize URLs for comparison
    normalized_urls = {normalize_url(url) for url in all_urls}
    
    # Criterion 1: Import occurred (at least some new bookmarks detected)
    import_occurred = len(all_bookmarks) > 0
    logger.info(f"Criterion 1 - Import occurred: {import_occurred}")
    
    # Criterion 2: All expected URLs are present
    expected_normalized_urls = {normalize_url(bm['url']) for bm in expected_bookmarks}
    urls_found = {url for url in expected_normalized_urls if url in normalized_urls}
    all_urls_present = len(urls_found) == len(expected_normalized_urls)
    
    logger.info(f"Criterion 2 - URLs present: {len(urls_found)}/{len(expected_normalized_urls)}")
    for exp_bm in expected_bookmarks:
        norm_url = normalize_url(exp_bm['url'])
        found = norm_url in normalized_urls
        logger.info(f"  - {exp_bm['url']}: {'✓' if found else '✗'}")
    
    # Criterion 3: All expected titles are present
    # Note: Titles might be slightly modified by Chrome, so we do fuzzy matching
    titles_found = 0
    for expected_bm in expected_bookmarks:
        expected_title = expected_bm['title'].lower()
        # Check if any bookmark title contains the expected title or vice versa
        for actual_title in all_titles:
            if actual_title and (expected_title in actual_title.lower() or actual_title.lower() in expected_title):
                titles_found += 1
                break
    
    all_titles_present = titles_found >= len(expected_bookmarks) * 0.8  # 80% threshold for titles
    logger.info(f"Criterion 3 - Titles present: {titles_found}/{len(expected_bookmarks)} (fuzzy match)")
    
    # Criterion 4: Bookmarks are properly organized
    # Check if an "Imported" folder or "Development Resources" folder exists
    has_imported_folder = check_folder_exists(bookmarks_data, "Imported", case_sensitive=False)
    has_dev_resources_folder = check_folder_exists(bookmarks_data, "Development Resources", case_sensitive=False)
    properly_organized = has_imported_folder or has_dev_resources_folder
    
    logger.info(f"Criterion 4 - Properly organized:")
    logger.info(f"  - 'Imported' folder exists: {has_imported_folder}")
    logger.info(f"  - 'Development Resources' folder exists: {has_dev_resources_folder}")
    logger.info(f"  - Overall: {properly_organized}")
    
    # Criterion 5: Complete import (all bookmarks imported)
    import_percentage = (len(urls_found) / len(expected_normalized_urls)) * 100 if expected_normalized_urls else 0
    complete_import = import_percentage == 100
    
    logger.info(f"Criterion 5 - Complete import: {import_percentage:.0f}% ({len(urls_found)}/{len(expected_normalized_urls)})")
    
    # Calculate score based on criteria
    criteria_results = {
        "import_occurred": import_occurred,
        "all_urls_present": all_urls_present,
        "all_titles_present": all_titles_present,
        "properly_organized": properly_organized,
        "complete_import": complete_import
    }
    
    criteria_met = sum(criteria_results.values())
    score = (criteria_met / 5) * 100
    passed = score >= 80  # Need at least 4/5 criteria (80%)
    
    # Generate detailed feedback
    feedback_parts = []
    feedback_parts.append(f"Bookmark Import Verification: {criteria_met}/5 criteria met")
    feedback_parts.append("")
    
    feedback_parts.append(f"{'✓' if import_occurred else '✗'} Criterion 1: Import occurred - {len(all_bookmarks)} bookmarks found")
    feedback_parts.append(f"{'✓' if all_urls_present else '✗'} Criterion 2: All URLs present - {len(urls_found)}/{len(expected_normalized_urls)} URLs found")
    feedback_parts.append(f"{'✓' if all_titles_present else '✗'} Criterion 3: Titles valid - {titles_found}/{len(expected_bookmarks)} titles matched")
    feedback_parts.append(f"{'✓' if properly_organized else '✗'} Criterion 4: Properly organized - {'Imported' if has_imported_folder else 'Dev Resources' if has_dev_resources_folder else 'No'} folder found")
    feedback_parts.append(f"{'✓' if complete_import else '✗'} Criterion 5: Complete import - {import_percentage:.0f}% imported")
    
    feedback_parts.append("")
    if passed:
        feedback_parts.append("✅ Task completed successfully! Bookmarks were properly imported.")
    else:
        feedback_parts.append("❌ Task incomplete - import missing or incomplete.")
        if not all_urls_present:
            missing = expected_normalized_urls - urls_found
            feedback_parts.append(f"   Missing URLs: {len(missing)}")
        if not complete_import:
            feedback_parts.append(f"   Only {import_percentage:.0f}% of bookmarks were imported")
    
    feedback = "\n".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": feedback,
        "criteria": criteria_results,
        "details": {
            "total_bookmarks": len(all_bookmarks),
            "urls_found": len(urls_found),
            "urls_expected": len(expected_normalized_urls),
            "titles_found": titles_found,
            "import_percentage": import_percentage
        }
    }


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for import_bookmarks_html@1 task.
    
    Args:
        traj: Trajectory data (unused for this verification)
        env_info: Environment information including copy_from_env function
        task_info: Task configuration information
        
    Returns:
        Dict with 'passed', 'score', and 'feedback' keys
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available in environment"
        }

    try:
        # Try to get bookmarks from multiple possible locations
        logger.info("Attempting to retrieve bookmarks from container...")
        
        possible_paths = [
            "/tmp/bookmarks_after_import.json",
            "/home/ga/.config/google-chrome-cdp/Default/Bookmarks",
            "/home/ga/.config/google-chrome/Default/Bookmarks"
        ]
        
        bookmarks_data = None
        for path in possible_paths:
            bookmarks_data = get_bookmarks_from_file(copy_from_env, path)
            if bookmarks_data:
                logger.info(f"✓ Successfully loaded bookmarks from: {path}")
                break
        
        if not bookmarks_data:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Could not access Chrome bookmarks file from any location. Chrome may not have been closed properly."
            }
        
        # Verify bookmark import
        result = verify_bookmark_import(bookmarks_data, EXPECTED_BOOKMARKS)
        
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
