#!/usr/bin/env python3
"""
Verifier for Chrome Research Bookmark Organization Task
Task: Organize research tabs into hierarchical bookmark structure (Research > Papers/Datasets/Tools)

Verification Strategy:
- Parse Chrome Bookmarks JSON file
- Verify "Research" folder exists in bookmark bar
- Verify sub-folders exist: "Papers", "Datasets", "Tools"
- Check that research URLs are bookmarked in appropriate categories
- Validate bookmark organization quality
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


# Expected research URLs with categorization
EXPECTED_RESEARCH_URLS = {
    "papers": [
        "arxiv.org",
        "scholar.google.com"
    ],
    "datasets": [
        "kaggle.com",
        "archive.ics.uci.edu"
    ],
    "tools": [
        "github.com",
        "colab.research.google.com"
    ]
}


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for research_bookmark_organize@1 task.
    
    Verifies:
    1. "Research" folder exists in bookmark bar
    2. Sub-folders exist: "Papers", "Datasets", "Tools"
    3. Research URLs are bookmarked (at least 3 total)
    4. Bookmarks are in appropriate category folders
    
    Scoring:
    - 100%: All 4 criteria met with perfect categorization
    - 75-99%: 3/4 criteria met (passing threshold)
    - 50-74%: 2/4 criteria met (partial success)
    - <50%: <2 criteria met (failed)
    
    Args:
        traj: Trajectory data (not used)
        env_info: Environment information including copy_from_env
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
        bookmarks_data = get_bookmarks_data(copy_from_env)
        
        if bookmarks_data is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Failed to retrieve bookmarks file from container. Ensure Chrome was closed properly to save bookmarks."
            }
        
        # Perform verification
        verification_result = verify_research_bookmark_structure(bookmarks_data)
        
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


def get_bookmarks_data(copy_from_env) -> Optional[Dict[str, Any]]:
    """
    Retrieve and parse Chrome Bookmarks file from container.
    
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
                logger.info(f"Attempting to copy bookmarks from: {container_path}")
                copy_from_env(container_path, temp_path)
                
                # Verify file was copied and has content
                if os.path.exists(temp_path) and os.path.getsize(temp_path) > 0:
                    with open(temp_path, 'r', encoding='utf-8') as f:
                        bookmarks_data = json.load(f)
                    
                    logger.info(f"✓ Successfully retrieved bookmarks from: {container_path}")
                    os.unlink(temp_path)
                    return bookmarks_data
                else:
                    logger.warning(f"File at {temp_path} is empty or doesn't exist")
                    
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                continue
        
        # If we get here, all attempts failed
        logger.error("Could not retrieve bookmarks from any known location")
        if temp_file and os.path.exists(temp_path):
            os.unlink(temp_path)
        return None
        
    except Exception as e:
        logger.error(f"Error getting bookmarks data: {e}")
        if temp_file and os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass
        return None


def find_folder_in_bookmark_bar(bookmark_bar_children: List[Dict], folder_name: str) -> Optional[Dict]:
    """
    Find a folder by name in bookmark bar children.
    
    Args:
        bookmark_bar_children: List of bookmark bar items
        folder_name: Name of folder to find
        
    Returns:
        Folder dict if found, None otherwise
    """
    for child in bookmark_bar_children:
        if child.get('type') == 'folder' and child.get('name') == folder_name:
            return child
    return None


def get_folder_children_names(folder: Dict) -> List[str]:
    """Get names of all child items (folders and URLs) in a folder."""
    children = folder.get('children', [])
    return [child.get('name', '') for child in children]


def count_urls_in_folder(folder: Dict) -> int:
    """Count number of URL bookmarks in a folder."""
    children = folder.get('children', [])
    return sum(1 for child in children if child.get('type') == 'url')


def get_urls_in_folder(folder: Dict) -> List[str]:
    """Get all URLs in a folder."""
    children = folder.get('children', [])
    return [child.get('url', '') for child in children if child.get('type') == 'url']


def categorize_url(url: str) -> Optional[str]:
    """
    Categorize a URL based on expected research domains.
    
    Returns:
        "papers", "datasets", "tools", or None if unrecognized
    """
    url_lower = url.lower()
    
    # Check papers category
    for domain in EXPECTED_RESEARCH_URLS["papers"]:
        if domain in url_lower:
            return "papers"
    
    # Check datasets category
    for domain in EXPECTED_RESEARCH_URLS["datasets"]:
        if domain in url_lower:
            return "datasets"
    
    # Check tools category
    for domain in EXPECTED_RESEARCH_URLS["tools"]:
        if domain in url_lower:
            return "tools"
    
    return None


def verify_research_bookmark_structure(bookmarks_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify the research bookmark folder structure and organization.
    
    Checks:
    1. "Research" folder exists in bookmark bar
    2. All three sub-folders exist: Papers, Datasets, Tools
    3. At least 3 research URLs are bookmarked
    4. Bookmarks are in correct category folders
    
    Args:
        bookmarks_data: Parsed Chrome bookmarks JSON
        
    Returns:
        Verification result dict
    """
    criteria_results = {
        "research_folder_exists": False,
        "subfolders_exist": False,
        "bookmarks_present": False,
        "correct_categorization": False
    }
    
    feedback_parts = []
    
    # Navigate to bookmark bar
    try:
        bookmark_bar = bookmarks_data.get('roots', {}).get('bookmark_bar', {})
        bookmark_bar_children = bookmark_bar.get('children', [])
        
        logger.info(f"Bookmark bar has {len(bookmark_bar_children)} items")
        
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to parse bookmarks structure: {e}"
        }
    
    # Criterion 1: Check if "Research" folder exists
    research_folder = find_folder_in_bookmark_bar(bookmark_bar_children, "Research")
    
    if research_folder:
        criteria_results["research_folder_exists"] = True
        feedback_parts.append("✓ 'Research' folder found in bookmark bar")
        logger.info("✓ Research folder exists")
    else:
        feedback_parts.append("✗ 'Research' folder not found in bookmark bar")
        logger.info("✗ Research folder missing")
        
        # Can't check further criteria without Research folder
        score = 0
        feedback = "\n".join(feedback_parts)
        feedback += "\n\nTask incomplete: Create 'Research' folder in bookmark bar first."
        
        return {
            "passed": False,
            "score": score,
            "feedback": feedback,
            "criteria": criteria_results
        }
    
    # Criterion 2: Check if sub-folders exist
    research_children = research_folder.get('children', [])
    subfolder_names = {
        child.get('name') for child in research_children 
        if child.get('type') == 'folder'
    }
    
    expected_subfolders = {"Papers", "Datasets", "Tools"}
    missing_subfolders = expected_subfolders - subfolder_names
    extra_subfolders = subfolder_names - expected_subfolders
    
    if not missing_subfolders:
        criteria_results["subfolders_exist"] = True
        feedback_parts.append(f"✓ All required sub-folders found: {', '.join(sorted(expected_subfolders))}")
        logger.info("✓ All sub-folders exist")
    else:
        feedback_parts.append(f"✗ Missing sub-folders: {', '.join(sorted(missing_subfolders))}")
        logger.info(f"✗ Missing sub-folders: {missing_subfolders}")
    
    if extra_subfolders:
        feedback_parts.append(f"  ℹ Extra folders found: {', '.join(sorted(extra_subfolders))}")
    
    # Criterion 3: Check if research URLs are bookmarked
    papers_folder = find_folder_in_bookmark_bar(research_children, "Papers")
    datasets_folder = find_folder_in_bookmark_bar(research_children, "Datasets")
    tools_folder = find_folder_in_bookmark_bar(research_children, "Tools")
    
    total_bookmarks = 0
    bookmarks_by_folder = {}
    
    if papers_folder:
        papers_count = count_urls_in_folder(papers_folder)
        total_bookmarks += papers_count
        bookmarks_by_folder["Papers"] = papers_count
        logger.info(f"Papers folder has {papers_count} bookmark(s)")
    
    if datasets_folder:
        datasets_count = count_urls_in_folder(datasets_folder)
        total_bookmarks += datasets_count
        bookmarks_by_folder["Datasets"] = datasets_count
        logger.info(f"Datasets folder has {datasets_count} bookmark(s)")
    
    if tools_folder:
        tools_count = count_urls_in_folder(tools_folder)
        total_bookmarks += tools_count
        bookmarks_by_folder["Tools"] = tools_count
        logger.info(f"Tools folder has {tools_count} bookmark(s)")
    
    if total_bookmarks >= 3:
        criteria_results["bookmarks_present"] = True
        feedback_parts.append(f"✓ Sufficient bookmarks found: {total_bookmarks} total across folders")
        logger.info(f"✓ {total_bookmarks} bookmarks found")
    else:
        feedback_parts.append(f"✗ Insufficient bookmarks: {total_bookmarks} found, need at least 3")
        logger.info(f"✗ Only {total_bookmarks} bookmarks found")
    
    # Criterion 4: Check correct categorization
    categorization_errors = []
    correct_categorizations = 0
    total_categorized = 0
    
    for folder_name, folder_obj in [("Papers", papers_folder), ("Datasets", datasets_folder), ("Tools", tools_folder)]:
        if folder_obj is None:
            continue
        
        urls = get_urls_in_folder(folder_obj)
        folder_cat = folder_name.lower()
        
        for url in urls:
            total_categorized += 1
            detected_cat = categorize_url(url)
            
            if detected_cat == folder_cat:
                correct_categorizations += 1
                logger.info(f"✓ Correct: {url[:50]}... in {folder_name}")
            elif detected_cat:
                categorization_errors.append(f"{url[:50]}... in {folder_name} (should be in {detected_cat.title()})")
                logger.warning(f"✗ Wrong folder: {url[:50]}... in {folder_name}, should be in {detected_cat}")
            else:
                # URL not from expected research set - could be user's own research
                logger.info(f"ℹ Unknown research URL in {folder_name}: {url[:50]}...")
    
    if total_categorized > 0:
        categorization_rate = correct_categorizations / total_categorized
        if categorization_rate >= 0.66:  # At least 2/3 correct
            criteria_results["correct_categorization"] = True
            feedback_parts.append(f"✓ Good categorization: {correct_categorizations}/{total_categorized} bookmarks in correct folders")
            logger.info(f"✓ Categorization rate: {categorization_rate:.1%}")
        else:
            feedback_parts.append(f"✗ Poor categorization: {correct_categorizations}/{total_categorized} correct")
            logger.info(f"✗ Low categorization rate: {categorization_rate:.1%}")
            
        if categorization_errors:
            feedback_parts.append(f"  Categorization issues:")
            for error in categorization_errors[:3]:  # Show max 3 errors
                feedback_parts.append(f"    - {error}")
    else:
        # No categorized bookmarks to check
        if total_bookmarks > 0:
            # They bookmarked things, just not from our expected URLs
            # Give partial credit
            criteria_results["correct_categorization"] = True
            feedback_parts.append("ℹ Bookmarks present but not from expected research URLs")
    
    # Calculate final score
    criteria_met = sum(criteria_results.values())
    score = int((criteria_met / 4) * 100)
    passed = score >= 75  # Need 3+ criteria
    
    # Build feedback summary
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\n{'='*50}"
    feedback += f"\nCriteria met: {criteria_met}/4"
    feedback += f"\nBookmarks organized: {total_bookmarks}"
    feedback += f"\nFinal score: {score}%"
    feedback += f"\nResult: {'PASSED ✓' if passed else 'FAILED ✗'}"
    
    if not passed:
        feedback += "\n\nTo pass this task:"
        if not criteria_results["research_folder_exists"]:
            feedback += "\n  1. Create 'Research' folder in bookmark bar"
        if not criteria_results["subfolders_exist"]:
            feedback += "\n  2. Create sub-folders: Papers, Datasets, Tools"
        if not criteria_results["bookmarks_present"]:
            feedback += "\n  3. Bookmark at least 3 research tabs into folders"
        if not criteria_results["correct_categorization"]:
            feedback += "\n  4. Place bookmarks in appropriate category folders"
    
    logger.info(f"Verification complete: passed={passed}, score={score}, criteria_met={criteria_met}/4")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "criteria": criteria_results,
        "details": {
            "criteria_met": criteria_met,
            "total_bookmarks": total_bookmarks,
            "bookmarks_by_folder": bookmarks_by_folder,
            "subfolders_found": list(subfolder_names),
            "categorization_errors": len(categorization_errors)
        }
    }
