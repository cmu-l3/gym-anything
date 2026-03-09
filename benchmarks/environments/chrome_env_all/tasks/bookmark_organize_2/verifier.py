#!/usr/bin/env python3
"""
Verifier for Chrome Bookmark Organization Task
Task: Organize scattered bookmarks into logical category folders

Verification Strategy:
1. Check folder structure (3-6 folders created)
2. Verify bookmark bar is clean (no loose bookmarks)
3. Check folders are populated
4. Assess categorization quality using semantic analysis
5. Ensure no bookmarks were lost
"""

import logging
import sys
import os
import json
import re
import tempfile
from pathlib import Path
from typing import Dict, List, Any, Tuple

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utils path
# Do not use /workspace/utils, since the verification runs on the host machine, not the container.
# USE Relative path to the utils folder.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

# Category patterns for semantic analysis
CATEGORY_PATTERNS = {
    'news': r'(news|media|press|times|post|reuters|bbc|cnn|npr|guardian|techcrunch|verge)',
    'shopping': r'(shop|buy|store|amazon|ebay|etsy|cart|commerce|retail|market|walmart)',
    'social': r'(facebook|twitter|reddit|linkedin|instagram|tiktok|social|snapchat|pinterest)',
    'dev': r'(github|gitlab|stackoverflow|stack|docs|developer|mdn|dev|code|programming|bitbucket)',
    'video': r'(youtube|vimeo|netflix|video|stream|twitch)',
    'work': r'(work|office|enterprise|business|slack|teams|zoom)',
}

def verify_task(traj, env_info, task_info):
    """
    Main verification function for bookmark organization task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        # Get bookmarks data
        bookmarks_data = get_bookmarks_data(copy_from_env)
        if bookmarks_data is None:
            return {"passed": False, "score": 0, "feedback": "Failed to retrieve bookmarks data"}

        # Analyze bookmark organization
        analysis = analyze_bookmark_organization(bookmarks_data)
        
        # Calculate score
        passed, score, feedback = calculate_score(analysis)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}


def get_bookmarks_data(copy_from_env) -> Dict[str, Any]:
    """
    Copy and parse Chrome Bookmarks file from container.
    """
    try:
        # Create temp file for bookmarks
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json', mode='w+')
        temp_path = temp_file.name
        temp_file.close()
        
        # Copy bookmarks from container
        success, error = copy_from_env("/tmp/final_bookmarks.json", temp_path)
        
        if not success:
            logger.error(f"Failed to copy bookmarks: {error}")
            return None
        
        # Parse JSON
        with open(temp_path, 'r', encoding='utf-8') as f:
            bookmarks = json.load(f)
        
        # Clean up temp file
        os.unlink(temp_path)
        
        return bookmarks
        
    except Exception as e:
        logger.error(f"Error getting bookmarks data: {e}", exc_info=True)
        return None


def analyze_bookmark_organization(bookmarks: Dict[str, Any]) -> Dict[str, Any]:
    """
    Comprehensive analysis of bookmark organization.
    
    Returns dictionary with:
    - num_folders: Number of folders on bookmark bar
    - loose_bookmarks: Number of bookmarks not in folders
    - folder_details: List of folder info (name, count, category)
    - total_organized: Total bookmarks in folders
    - categorization_quality: Percentage of well-categorized bookmarks
    - all_bookmarks_accounted: Whether all original bookmarks are present
    """
    try:
        bookmark_bar = bookmarks.get('roots', {}).get('bookmark_bar', {})
        children = bookmark_bar.get('children', [])
        
        # Separate folders and loose bookmarks
        folders = [c for c in children if c.get('type') == 'folder']
        loose_bookmarks = [c for c in children if c.get('type') == 'url']
        
        num_folders = len(folders)
        num_loose = len(loose_bookmarks)
        
        # Analyze each folder
        folder_details = []
        total_organized = 0
        correctly_categorized = 0
        
        for folder in folders:
            folder_name = folder.get('name', '').lower()
            folder_bookmarks = folder.get('children', [])
            folder_urls = []
            folder_titles = []
            
            for bookmark in folder_bookmarks:
                if bookmark.get('type') == 'url':
                    folder_urls.append(bookmark.get('url', ''))
                    folder_titles.append(bookmark.get('name', ''))
            
            bookmark_count = len(folder_urls)
            total_organized += bookmark_count
            
            # Detect folder category
            detected_category = detect_category_from_name(folder_name)
            
            # Check if bookmarks match the folder's category
            if detected_category:
                pattern = CATEGORY_PATTERNS[detected_category]
                for url, title in zip(folder_urls, folder_titles):
                    combined = f"{url} {title}".lower()
                    if re.search(pattern, combined, re.IGNORECASE):
                        correctly_categorized += 1
            else:
                # If we can't detect category from folder name, try to infer from contents
                # Give partial credit if contents are at least consistent with each other
                if bookmark_count > 0:
                    # Check if bookmarks seem related
                    categories_in_folder = set()
                    for url, title in zip(folder_urls, folder_titles):
                        combined = f"{url} {title}".lower()
                        for cat, pattern in CATEGORY_PATTERNS.items():
                            if re.search(pattern, combined, re.IGNORECASE):
                                categories_in_folder.add(cat)
                    
                    # If all bookmarks fall into same category, count them as correct
                    if len(categories_in_folder) == 1:
                        correctly_categorized += bookmark_count
                    elif len(categories_in_folder) <= 2 and bookmark_count >= 2:
                        # Partial credit if mostly consistent
                        correctly_categorized += bookmark_count * 0.7
            
            folder_details.append({
                'name': folder.get('name', 'Unnamed'),
                'bookmark_count': bookmark_count,
                'detected_category': detected_category
            })
        
        # Calculate categorization quality
        categorization_rate = 0.0
        if total_organized > 0:
            categorization_rate = (correctly_categorized / total_organized) * 100
        
        # Check if all bookmarks are accounted for (12 original bookmarks)
        original_count = 12
        current_total = total_organized + num_loose
        all_accounted = (original_count - 2) <= current_total <= (original_count + 2)  # Allow small variance
        
        return {
            'num_folders': num_folders,
            'loose_bookmarks': num_loose,
            'folder_details': folder_details,
            'total_organized': total_organized,
            'categorization_quality': categorization_rate,
            'all_bookmarks_accounted': all_accounted,
            'original_count': original_count,
            'current_total': current_total
        }
        
    except Exception as e:
        logger.error(f"Error analyzing bookmarks: {e}", exc_info=True)
        return {
            'num_folders': 0,
            'loose_bookmarks': 999,
            'folder_details': [],
            'total_organized': 0,
            'categorization_quality': 0.0,
            'all_bookmarks_accounted': False,
            'original_count': 12,
            'current_total': 0
        }


def detect_category_from_name(folder_name: str) -> str:
    """
    Detect category from folder name.
    """
    folder_name = folder_name.lower()
    
    for category, pattern in CATEGORY_PATTERNS.items():
        if re.search(pattern, folder_name, re.IGNORECASE):
            return category
    
    return None


def calculate_score(analysis: Dict[str, Any]) -> Tuple[bool, int, str]:
    """
    Calculate final score based on multi-criteria analysis.
    
    Scoring breakdown:
    - Folder structure (25 points): 3-6 folders created
    - Clean bookmark bar (25 points): No loose bookmarks
    - Bookmarks organized (25 points): At least 8 bookmarks in folders
    - Categorization quality (25 points): At least 70% correctly categorized
    
    Pass threshold: 75 points
    """
    score = 0
    feedback_parts = []
    
    # Criterion 1: Folder structure (25 points)
    num_folders = analysis['num_folders']
    if 3 <= num_folders <= 6:
        score += 25
        feedback_parts.append(f"✅ Folder structure: Created {num_folders} folders (ideal range)")
    elif 2 <= num_folders < 3:
        score += 15
        feedback_parts.append(f"⚠️ Folder structure: Only {num_folders} folders (need at least 3)")
    elif num_folders > 6:
        score += 15
        feedback_parts.append(f"⚠️ Folder structure: {num_folders} folders (over-fragmented, ideal is 3-6)")
    else:
        feedback_parts.append(f"❌ Folder structure: {num_folders} folders (need at least 3)")
    
    # Criterion 2: Clean bookmark bar (25 points)
    loose_count = analysis['loose_bookmarks']
    if loose_count == 0:
        score += 25
        feedback_parts.append("✅ Bookmark bar: Completely organized (no loose bookmarks)")
    elif loose_count <= 2:
        score += 15
        feedback_parts.append(f"⚠️ Bookmark bar: {loose_count} loose bookmarks remaining")
    else:
        feedback_parts.append(f"❌ Bookmark bar: {loose_count} loose bookmarks (not organized)")
    
    # Criterion 3: Bookmarks organized (25 points)
    total_organized = analysis['total_organized']
    if total_organized >= 10:
        score += 25
        feedback_parts.append(f"✅ Organization: {total_organized} bookmarks in folders (excellent)")
    elif total_organized >= 8:
        score += 20
        feedback_parts.append(f"✅ Organization: {total_organized} bookmarks in folders (good)")
    elif total_organized >= 5:
        score += 10
        feedback_parts.append(f"⚠️ Organization: Only {total_organized} bookmarks in folders")
    else:
        feedback_parts.append(f"❌ Organization: Only {total_organized} bookmarks organized")
    
    # Criterion 4: Categorization quality (25 points)
    cat_quality = analysis['categorization_quality']
    if cat_quality >= 90:
        score += 25
        feedback_parts.append(f"✅ Categorization: Excellent ({cat_quality:.1f}% correct)")
    elif cat_quality >= 75:
        score += 20
        feedback_parts.append(f"✅ Categorization: Good ({cat_quality:.1f}% correct)")
    elif cat_quality >= 70:
        score += 15
        feedback_parts.append(f"⚠️ Categorization: Adequate ({cat_quality:.1f}% correct)")
    elif cat_quality >= 50:
        score += 10
        feedback_parts.append(f"⚠️ Categorization: Poor ({cat_quality:.1f}% correct)")
    else:
        feedback_parts.append(f"❌ Categorization: Very poor ({cat_quality:.1f}% correct)")
    
    # Add folder details to feedback
    feedback_parts.append("\nFolder Details:")
    for folder in analysis['folder_details']:
        cat = folder['detected_category'] or 'unknown'
        feedback_parts.append(f"  • {folder['name']}: {folder['bookmark_count']} bookmarks (category: {cat})")
    
    # Data loss check
    if not analysis['all_bookmarks_accounted']:
        feedback_parts.append(f"\n⚠️ Warning: Expected ~{analysis['original_count']} bookmarks, found {analysis['current_total']}")
    
    # Final score
    passed = score >= 75
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\nFinal Score: {score}/100 ({'PASS' if passed else 'FAIL'})"
    
    return passed, score, feedback
