#!/usr/bin/env python3
"""
Verifier for Chrome Bookmark Deduplication Task (bookmark_deduplicate@1)
Task: Remove duplicate bookmarks while preserving one instance of each unique URL

Verification Strategy:
- Parse Chrome Bookmarks JSON file
- Recursively extract all URLs from all folders
- Detect duplicates by normalizing URLs
- Verify no duplicates remain
- Ensure unique URLs are preserved
- Check appropriate reduction in bookmark count
"""

import logging
import sys
import os
import json
import tempfile
from pathlib import Path
from typing import Dict, List, Any, Tuple, Set
from collections import Counter

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


def normalize_url(url: str) -> str:
    """
    Normalize URL for duplicate detection.
    
    Handles:
    - Lowercase conversion
    - Protocol removal (http:// vs https://)
    - Trailing slash removal
    - www subdomain normalization
    
    Args:
        url: Raw URL string
        
    Returns:
        Normalized URL string for comparison
    """
    if not url:
        return ""
    
    # Convert to lowercase
    url = url.lower().strip()
    
    # Remove protocol
    url = url.replace('https://', '').replace('http://', '')
    
    # Remove trailing slashes
    url = url.rstrip('/')
    
    # Optional: normalize www subdomain
    # url = url.replace('www.', '')
    
    return url


def extract_all_urls(bookmarks_data: Dict[str, Any]) -> List[Tuple[str, str, str]]:
    """
    Recursively extract all bookmark URLs from the bookmarks structure.
    
    Args:
        bookmarks_data: Parsed bookmarks JSON data
        
    Returns:
        List of tuples: (url, name, folder_path)
    """
    urls = []
    
    def traverse(node, path=""):
        """Recursively traverse bookmark tree"""
        if isinstance(node, dict):
            node_type = node.get('type')
            
            if node_type == 'url':
                url = node.get('url', '')
                name = node.get('name', '')
                urls.append((url, name, path))
                
            elif node_type == 'folder':
                folder_name = node.get('name', '')
                new_path = f"{path}/{folder_name}" if path else folder_name
                
                children = node.get('children', [])
                for child in children:
                    traverse(child, new_path)
                    
            # Handle special case of children array
            elif 'children' in node:
                for child in node.get('children', []):
                    traverse(child, path)
        
        elif isinstance(node, list):
            for item in node:
                traverse(item, path)
    
    # Start traversal from roots
    roots = bookmarks_data.get('roots', {})
    for root_key in ['bookmark_bar', 'other', 'synced']:
        root_node = roots.get(root_key, {})
        if root_node:
            traverse(root_node, root_key)
    
    return urls


def detect_duplicates(urls: List[Tuple[str, str, str]]) -> Tuple[Dict[str, int], List[str]]:
    """
    Detect duplicate URLs in bookmark list.
    
    Args:
        urls: List of (url, name, folder_path) tuples
        
    Returns:
        Tuple of (url_counts dict, duplicate_urls list)
    """
    # Normalize and count URLs
    normalized_counts = Counter()
    url_mapping = {}  # Maps normalized URL to original
    
    for url, name, path in urls:
        normalized = normalize_url(url)
        normalized_counts[normalized] += 1
        
        if normalized not in url_mapping:
            url_mapping[normalized] = url
    
    # Find duplicates (URLs that appear more than once)
    duplicates = [
        url_mapping[norm_url] 
        for norm_url, count in normalized_counts.items() 
        if count > 1
    ]
    
    return dict(normalized_counts), duplicates


def verify_bookmarks_deduplication(bookmarks_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that bookmarks have been properly deduplicated.
    
    Verification criteria:
    1. No duplicate URLs remain (each URL appears exactly once)
    2. Unique URLs are preserved (all 7 original unique URLs still exist)
    3. Appropriate reduction in count (from 12 to ~7)
    4. File structure is valid JSON
    
    Args:
        bookmarks_data: Parsed bookmarks JSON
        
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
    
    # Expected initial state
    INITIAL_TOTAL = 12
    INITIAL_UNIQUE = 7
    INITIAL_DUPLICATES = 5
    
    # Expected final state
    EXPECTED_FINAL_COUNT = 7
    TOLERANCE = 2  # Allow ±2 bookmarks for flexibility
    
    # Extract all URLs
    all_urls = extract_all_urls(bookmarks_data)
    total_bookmarks = len(all_urls)
    
    logger.info(f"Extracted {total_bookmarks} bookmarks from structure")
    
    # Log all bookmarks for debugging
    for url, name, path in all_urls:
        logger.info(f"  {path} -> {name}: {url}")
    
    # Detect duplicates
    url_counts, duplicate_urls = detect_duplicates(all_urls)
    
    # Count unique URLs
    unique_url_count = len(url_counts)
    max_occurrences = max(url_counts.values()) if url_counts else 0
    
    logger.info(f"Unique URLs: {unique_url_count}")
    logger.info(f"Max occurrences of any URL: {max_occurrences}")
    logger.info(f"Duplicate URLs found: {len(duplicate_urls)}")
    
    # Log duplicates if any
    for norm_url, count in url_counts.items():
        if count > 1:
            logger.warning(f"  Duplicate: {norm_url} appears {count} times")
    
    # Criterion 1: No duplicates remaining (each URL appears exactly once)
    no_duplicates = (max_occurrences == 1)
    
    # Criterion 2: Unique URLs preserved (should have at least INITIAL_UNIQUE)
    unique_urls_preserved = (unique_url_count >= INITIAL_UNIQUE)
    
    # Criterion 3: Appropriate reduction in count
    count_low = EXPECTED_FINAL_COUNT - TOLERANCE
    count_high = EXPECTED_FINAL_COUNT + TOLERANCE
    appropriate_reduction = (count_low <= total_bookmarks <= count_high)
    
    # Criterion 4: File structure valid (already checked by successful parsing)
    file_structure_valid = True
    
    # Calculate score
    criteria = [
        no_duplicates,
        unique_urls_preserved,
        appropriate_reduction,
        file_structure_valid
    ]
    criteria_met = sum(criteria)
    score = int((criteria_met / 4.0) * 100)
    passed = score >= 75  # Need at least 3/4 criteria
    
    # Generate detailed feedback
    feedback_parts = []
    feedback_parts.append(f"Bookmark Deduplication Verification Results:")
    feedback_parts.append(f"")
    
    # Criterion 1 feedback
    if no_duplicates:
        feedback_parts.append(f"✓ No duplicates: Each URL appears exactly once")
    else:
        feedback_parts.append(f"✗ Duplicates remain: {len(duplicate_urls)} URLs appear multiple times")
        feedback_parts.append(f"  Maximum occurrences: {max_occurrences}x")
    
    # Criterion 2 feedback
    if unique_urls_preserved:
        feedback_parts.append(f"✓ Unique URLs preserved: {unique_url_count} unique URLs found (expected {INITIAL_UNIQUE})")
    else:
        feedback_parts.append(f"✗ Unique URLs lost: Only {unique_url_count} unique URLs (expected {INITIAL_UNIQUE})")
    
    # Criterion 3 feedback
    reduction = INITIAL_TOTAL - total_bookmarks
    if appropriate_reduction:
        feedback_parts.append(f"✓ Appropriate reduction: {total_bookmarks} bookmarks (reduced by {reduction} from {INITIAL_TOTAL})")
    else:
        if total_bookmarks > count_high:
            feedback_parts.append(f"✗ Insufficient reduction: {total_bookmarks} bookmarks (expected ~{EXPECTED_FINAL_COUNT})")
        else:
            feedback_parts.append(f"✗ Over-deletion: {total_bookmarks} bookmarks (expected ~{EXPECTED_FINAL_COUNT})")
    
    # Criterion 4 feedback
    if file_structure_valid:
        feedback_parts.append(f"✓ File structure: Valid JSON format")
    
    feedback_parts.append(f"")
    feedback_parts.append(f"{'='*50}")
    feedback_parts.append(f"Criteria met: {criteria_met}/4")
    feedback_parts.append(f"Final score: {score}%")
    feedback_parts.append(f"Result: {'PASSED ✓' if passed else 'FAILED ✗'}")
    
    if not passed:
        feedback_parts.append(f"")
        if not no_duplicates:
            feedback_parts.append(f"Tip: Open Bookmark Manager (Ctrl+Shift+O) and look for duplicate URLs")
        if not unique_urls_preserved:
            feedback_parts.append(f"Tip: Make sure not to delete ALL instances of a URL - keep one copy")
    
    feedback = "\n".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "total_bookmarks": total_bookmarks,
            "unique_urls": unique_url_count,
            "max_occurrences": max_occurrences,
            "duplicates_found": len(duplicate_urls),
            "reduction": INITIAL_TOTAL - total_bookmarks,
            "criteria_met": criteria_met,
            "no_duplicates": no_duplicates,
            "unique_preserved": unique_urls_preserved,
            "appropriate_reduction": appropriate_reduction
        }
    }


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for bookmark_deduplicate@1.
    
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
        # Copy bookmarks file from container
        logger.info("Attempting to copy bookmarks file from container...")
        
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
                    logger.info(f"✓ Successfully copied bookmarks from: {container_path}")
                    break
                else:
                    if os.path.exists(temp_path):
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
                "feedback": "Could not access bookmarks file from any known location"
            }
        
        # Verify deduplication
        result = verify_bookmarks_deduplication(bookmarks_data)
        
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
