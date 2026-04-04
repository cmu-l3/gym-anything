#!/usr/bin/env python3
"""
Verifier for Chrome Bookmark Organization Task (bookmark_organization@1)
Task: Organize scattered bookmarks into logical folder structure

Verification Strategy:
- Copy Bookmarks file from Chrome profile
- Parse JSON structure
- Check that folders were created in bookmark bar
- Verify bookmarks were moved into folders (not left scattered)
- Validate categorization logic (URLs match folder semantic categories)
- Provide detailed scoring based on multiple criteria
"""

import logging
import sys
import os
import json
import tempfile
import re
from pathlib import Path
from typing import Dict, List, Any, Tuple

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


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for bookmark_organization@1.
    
    Verifies:
    1. At least 3 organizational folders created in bookmark bar
    2. Expected folder names present (flexible matching)
    3. At least 80% of bookmarks organized into folders
    4. All created folders are populated (not empty)
    5. Logical categorization (bookmarks in semantically appropriate folders)
    
    Args:
        traj: Trajectory data (not used for this task)
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
            "feedback": "copy_from_env function not available"
        }

    try:
        # Close Chrome to ensure bookmarks are saved
        logger.info("Ensuring Chrome is closed to save bookmarks...")
        close_chrome()
        
        # Get bookmarks data from container
        bookmarks_data = get_bookmarks_data(copy_from_env)
        
        if bookmarks_data is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Failed to retrieve bookmarks file from Chrome profile"
            }
        
        # Perform verification
        result = verify_bookmark_organization(bookmarks_data)
        
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


def close_chrome():
    """
    Close Chrome to ensure bookmarks are persisted to disk.
    """
    import subprocess
    try:
        # Gracefully close Chrome
        subprocess.run(['pkill', '-f', 'google-chrome'], 
                      stderr=subprocess.DEVNULL, 
                      timeout=5)
        import time
        time.sleep(2)
        
        # Force kill if still running
        subprocess.run(['pkill', '-9', '-f', 'google-chrome'], 
                      stderr=subprocess.DEVNULL, 
                      timeout=2)
        time.sleep(1)
        
        logger.info("Chrome closed successfully")
    except Exception as e:
        logger.warning(f"Error closing Chrome: {e}")


def get_bookmarks_data(copy_from_env) -> Dict[str, Any]:
    """
    Retrieve bookmarks data from container.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Parsed bookmarks JSON data or None on failure
    """
    # Possible locations for Bookmarks file
    possible_paths = [
        "/home/ga/.config/google-chrome/Default/Bookmarks",
        "/home/ga/.config/google-chrome-cdp/Default/Bookmarks",
        "/tmp/bookmarks_export.json"
    ]
    
    for container_path in possible_paths:
        try:
            temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json', mode='w+')
            temp_path = temp_file.name
            temp_file.close()
            
            logger.info(f"Attempting to copy bookmarks from: {container_path}")
            copy_from_env(container_path, temp_path)
            
            # Check if file was copied successfully
            if os.path.exists(temp_path) and os.path.getsize(temp_path) > 0:
                with open(temp_path, 'r', encoding='utf-8') as f:
                    bookmarks_data = json.load(f)
                
                os.unlink(temp_path)
                logger.info(f"✓ Successfully retrieved bookmarks from: {container_path}")
                return bookmarks_data
            else:
                if os.path.exists(temp_path):
                    os.unlink(temp_path)
                    
        except Exception as e:
            logger.debug(f"Failed to copy from {container_path}: {e}")
            if 'temp_path' in locals() and os.path.exists(temp_path):
                try:
                    os.unlink(temp_path)
                except:
                    pass
            continue
    
    logger.error("Could not retrieve bookmarks from any known location")
    return None


def analyze_bookmark_structure(bookmarks_data: Dict) -> Dict[str, Any]:
    """
    Analyze the bookmark bar structure.
    
    Args:
        bookmarks_data: Parsed bookmarks JSON
        
    Returns:
        Dict with analysis results
    """
    bookmark_bar = bookmarks_data.get('roots', {}).get('bookmark_bar', {})
    children = bookmark_bar.get('children', [])
    
    # Separate folders and loose bookmarks
    folders = [c for c in children if c.get('type') == 'folder']
    loose_bookmarks = [c for c in children if c.get('type') == 'url']
    
    # Analyze folder contents
    folder_info = []
    total_bookmarks_in_folders = 0
    
    for folder in folders:
        folder_children = folder.get('children', [])
        bookmarks = [b for b in folder_children if b.get('type') == 'url']
        bookmark_count = len(bookmarks)
        total_bookmarks_in_folders += bookmark_count
        
        folder_info.append({
            'name': folder.get('name', ''),
            'bookmark_count': bookmark_count,
            'bookmarks': [{
                'name': b.get('name', ''),
                'url': b.get('url', '')
            } for b in bookmarks]
        })
    
    total_bookmarks = total_bookmarks_in_folders + len(loose_bookmarks)
    organization_ratio = total_bookmarks_in_folders / total_bookmarks if total_bookmarks > 0 else 0
    
    return {
        'folder_count': len(folders),
        'folder_info': folder_info,
        'loose_bookmark_count': len(loose_bookmarks),
        'loose_bookmarks': [b.get('name', '') for b in loose_bookmarks],
        'total_bookmarks': total_bookmarks,
        'bookmarks_in_folders': total_bookmarks_in_folders,
        'organization_ratio': organization_ratio
    }


def check_expected_folder_categories(folder_info: List[Dict]) -> Tuple[bool, List[str], List[str]]:
    """
    Check if expected folder categories exist.
    
    Args:
        folder_info: List of folder information dicts
        
    Returns:
        Tuple of (categories_ok: bool, found_categories: List[str], missing_categories: List[str])
    """
    # Expected category keywords (flexible matching)
    expected_categories = {
        'news': ['news', 'media'],
        'development': ['dev', 'development', 'coding', 'programming'],
        'social': ['social', 'media'],
        'documentation': ['doc', 'documentation', 'docs', 'reference']
    }
    
    folder_names_lower = [f['name'].lower() for f in folder_info]
    
    found_categories = []
    
    for category, keywords in expected_categories.items():
        for folder_name in folder_names_lower:
            if any(keyword in folder_name for keyword in keywords):
                found_categories.append(category)
                break
    
    # Need at least 3 out of 4 expected categories (75%)
    categories_ok = len(found_categories) >= 3
    
    missing_categories = [cat for cat in expected_categories.keys() if cat not in found_categories]
    
    return categories_ok, found_categories, missing_categories


def check_logical_categorization(folder_info: List[Dict]) -> Tuple[float, List[str]]:
    """
    Check if bookmarks are logically categorized based on URL patterns.
    
    Args:
        folder_info: List of folder information dicts
        
    Returns:
        Tuple of (avg_score: float, feedback_items: List[str])
    """
    # URL patterns for each category
    category_patterns = {
        'news': ['cnn.com', 'bbc.com', 'guardian', 'news', 'nytimes', 'reuters'],
        'development': ['github.com', 'stackoverflow.com', 'npmjs.com', 'npm', 'gitlab'],
        'social': ['twitter.com', 'reddit.com', 'facebook.com', 'instagram', 'linkedin'],
        'documentation': ['developer.mozilla.org', 'w3.org', 'w3c', 'docs', 'documentation', 'mdn']
    }
    
    categorization_scores = []
    feedback_items = []
    
    for folder in folder_info:
        folder_name = folder['name'].lower()
        bookmarks = folder['bookmarks']
        
        if len(bookmarks) == 0:
            feedback_items.append(f"⚠ Folder '{folder['name']}' is empty")
            continue
        
        # Determine expected category for this folder
        expected_category = None
        for category, patterns in category_patterns.items():
            # Check if folder name contains category keywords
            if category in folder_name or any(kw in folder_name for kw in ['news', 'media'] if category == 'news'):
                expected_category = category
                break
            elif category == 'development' and any(kw in folder_name for kw in ['dev', 'code', 'programming']):
                expected_category = category
                break
            elif category == 'social' and 'social' in folder_name:
                expected_category = category
                break
            elif category == 'documentation' and any(kw in folder_name for kw in ['doc', 'reference']):
                expected_category = category
                break
        
        if not expected_category:
            # Try to infer from bookmarks
            continue
        
        # Check how many bookmarks match this category
        matching_bookmarks = 0
        mismatched = []
        
        for bookmark in bookmarks:
            bookmark_url = bookmark['url'].lower()
            patterns = category_patterns[expected_category]
            
            if any(pattern in bookmark_url for pattern in patterns):
                matching_bookmarks += 1
            else:
                mismatched.append(bookmark['name'])
        
        if len(bookmarks) > 0:
            score = matching_bookmarks / len(bookmarks)
            categorization_scores.append(score)
            
            if score < 0.6:
                feedback_items.append(f"⚠ Folder '{folder['name']}' has poor categorization ({int(score*100)}% correct)")
            elif score < 1.0:
                feedback_items.append(f"✓ Folder '{folder['name']}' mostly correct ({int(score*100)}% correct)")
            else:
                feedback_items.append(f"✓ Folder '{folder['name']}' perfectly categorized")
    
    avg_score = sum(categorization_scores) / len(categorization_scores) if categorization_scores else 0
    
    return avg_score, feedback_items


def verify_bookmark_organization(bookmarks_data: Dict) -> Dict[str, Any]:
    """
    Verify bookmark organization against all criteria.
    
    Args:
        bookmarks_data: Parsed bookmarks JSON
        
    Returns:
        Verification result dict
    """
    if not bookmarks_data:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Could not parse bookmarks file"
        }
    
    # Analyze structure
    analysis = analyze_bookmark_structure(bookmarks_data)
    
    logger.info(f"Bookmark analysis: {analysis['folder_count']} folders, "
                f"{analysis['bookmarks_in_folders']}/{analysis['total_bookmarks']} bookmarks organized "
                f"({analysis['organization_ratio']*100:.1f}%)")
    
    # Initialize scoring
    criteria_met = 0
    total_criteria = 5
    feedback_parts = []
    
    # Criterion 1: At least 3 folders created
    folders_created = analysis['folder_count'] >= 3
    if folders_created:
        criteria_met += 1
        feedback_parts.append(f"✓ Created {analysis['folder_count']} folders (need 3+)")
    else:
        feedback_parts.append(f"✗ Only {analysis['folder_count']} folders created (need 3+)")
    
    # Criterion 2: Expected folder categories present
    categories_ok, found_categories, missing_categories = check_expected_folder_categories(analysis['folder_info'])
    if categories_ok:
        criteria_met += 1
        feedback_parts.append(f"✓ Expected categories found: {', '.join(found_categories)}")
    else:
        feedback_parts.append(f"✗ Missing categories: {', '.join(missing_categories)} (found: {', '.join(found_categories)})")
    
    # Criterion 3: At least 80% of bookmarks organized into folders
    organization_ok = analysis['organization_ratio'] >= 0.8
    if organization_ok:
        criteria_met += 1
        feedback_parts.append(f"✓ Organization ratio: {analysis['organization_ratio']*100:.0f}% (need 80%+)")
    else:
        feedback_parts.append(f"✗ Organization ratio: {analysis['organization_ratio']*100:.0f}% (need 80%+)")
        if analysis['loose_bookmark_count'] > 0:
            feedback_parts.append(f"  Unorganized bookmarks: {', '.join(analysis['loose_bookmarks'][:3])}" + 
                                 (f"... ({analysis['loose_bookmark_count']} total)" if analysis['loose_bookmark_count'] > 3 else ""))
    
    # Criterion 4: All folders are populated (no empty folders)
    empty_folders = [f for f in analysis['folder_info'] if f['bookmark_count'] == 0]
    all_populated = len(empty_folders) == 0
    if all_populated:
        criteria_met += 1
        feedback_parts.append(f"✓ All folders contain bookmarks")
    else:
        criteria_met += 0.5  # Partial credit if only a few empty
        empty_names = [f['name'] for f in empty_folders]
        feedback_parts.append(f"⚠ {len(empty_folders)} empty folder(s): {', '.join(empty_names)}")
    
    # Criterion 5: Logical categorization
    categorization_score, categorization_feedback = check_logical_categorization(analysis['folder_info'])
    categorization_ok = categorization_score >= 0.6
    
    if categorization_ok:
        criteria_met += 1
        feedback_parts.append(f"✓ Good categorization quality ({categorization_score*100:.0f}%)")
    else:
        feedback_parts.append(f"✗ Poor categorization quality ({categorization_score*100:.0f}%)")
    
    # Add categorization details
    if categorization_feedback:
        feedback_parts.extend(categorization_feedback)
    
    # Calculate final score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75  # Need 4/5 criteria (or 3.5/5 with partials)
    
    # Build final feedback
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\n{'='*60}"
    feedback += f"\nCriteria met: {criteria_met:.1f}/{total_criteria}"
    feedback += f"\nFinal score: {score}%"
    feedback += f"\nResult: {'PASSED ✓' if passed else 'FAILED ✗'}"
    
    if passed:
        feedback += "\n\nBookmarks successfully organized into logical folder structure!"
    else:
        feedback += "\n\nBookmark organization incomplete. Please ensure all bookmarks are moved into appropriate folders."
    
    logger.info(f"Verification complete: passed={passed}, score={score}, criteria={criteria_met}/{total_criteria}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "criteria_met": criteria_met,
            "total_criteria": total_criteria,
            "folder_count": analysis['folder_count'],
            "organization_ratio": analysis['organization_ratio'],
            "categorization_quality": categorization_score,
            "folders": [f['name'] for f in analysis['folder_info']]
        }
    }
