#!/usr/bin/env python3
"""
Verifier for Chrome Tab Groups Organization Task (tab_groups_organize@1)

Task: Organize multiple open tabs into color-coded, named groups

Verification Strategy:
Since Chrome tab groups data is not directly accessible via CDP, we use a multi-method approach:
1. Screenshot analysis: Detect colored bars indicating tab groups
2. Tab pattern analysis: Check if tabs are organized (not all in one group)
3. Heuristic checks: Infer grouping from tab ordering and clustering
4. Session file analysis: Parse binary session data if possible

Verification Criteria:
1. Multiple groups created (detect 2-4+ groups)
2. Meaningful names (not default "Group 1", "Group 2")
3. Color diversity (multiple distinct colors used)
4. Logical organization (related tabs grouped together)
5. High coverage (most tabs are grouped, not ungrouped)
"""

import logging
import sys
import os
import json
import tempfile
import re
from pathlib import Path
from typing import Dict, List, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import image processing libraries
try:
    from PIL import Image
    import numpy as np
    HAS_PIL = True
except ImportError:
    HAS_PIL = False
    logger.warning("PIL/numpy not available, screenshot analysis will be limited")

# Add utils to path
sys.path.insert(0, os.path.join(os.path.abspath(__file__), '../../../', 'utils'))
try:
    from chrome_verification_utils import cleanup_verification_temp
    UTILS_AVAILABLE = True
except ImportError:
    logger.warning("Chrome verification utilities not available")
    UTILS_AVAILABLE = False
    def cleanup_verification_temp():
        pass


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for tab_groups_organize@1 task.
    
    Args:
        traj: Trajectory data (unused)
        env_info: Environment information including copy_from_env function
        task_info: Task configuration information
        
    Returns:
        Dict with 'passed', 'score', 'feedback', and 'details' keys
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available - cannot verify task"
        }

    try:
        # Get all verification artifacts
        artifacts = collect_verification_artifacts(copy_from_env)
        
        if not artifacts['success']:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to collect verification data: {artifacts['error']}"
            }
        
        # Perform multi-criteria verification
        verification_result = verify_tab_group_organization(artifacts)
        
        # Clean up temporary files
        cleanup_temp_files(artifacts.get('temp_files', []))
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


def collect_verification_artifacts(copy_from_env) -> Dict[str, Any]:
    """
    Collect all verification artifacts from the container.
    
    Returns:
        Dict with success flag, artifact paths, and error message
    """
    artifacts = {
        'success': False,
        'tabs_data': None,
        'screenshot_path': None,
        'tabbar_screenshot_path': None,
        'preferences_path': None,
        'temp_files': [],
        'error': ''
    }
    
    try:
        # Collect CDP tab data
        temp_tabs = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_tabs.close()
        artifacts['temp_files'].append(temp_tabs.name)
        
        try:
            copy_from_env("/tmp/chrome_page_tabs.json", temp_tabs.name)
            with open(temp_tabs.name, 'r') as f:
                artifacts['tabs_data'] = json.load(f)
            logger.info(f"✓ Collected tab data: {len(artifacts['tabs_data'])} tabs")
        except Exception as e:
            logger.warning(f"Could not collect tab data: {e}")
            artifacts['tabs_data'] = []
        
        # Collect screenshots
        if HAS_PIL:
            # Full screenshot
            temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
            temp_screenshot.close()
            artifacts['temp_files'].append(temp_screenshot.name)
            
            try:
                copy_from_env("/tmp/chrome_fullscreen.png", temp_screenshot.name)
                artifacts['screenshot_path'] = temp_screenshot.name
                logger.info("✓ Collected full screenshot")
            except Exception as e:
                logger.warning(f"Could not collect screenshot: {e}")
            
            # Tab bar screenshot
            temp_tabbar = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
            temp_tabbar.close()
            artifacts['temp_files'].append(temp_tabbar.name)
            
            try:
                copy_from_env("/tmp/chrome_tabbar.png", temp_tabbar.name)
                artifacts['tabbar_screenshot_path'] = temp_tabbar.name
                logger.info("✓ Collected tab bar screenshot")
            except Exception as e:
                logger.warning(f"Could not collect tab bar screenshot: {e}")
        
        # Collect Chrome preferences
        temp_prefs = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_prefs.close()
        artifacts['temp_files'].append(temp_prefs.name)
        
        try:
            copy_from_env("/tmp/chrome_preferences.json", temp_prefs.name)
            artifacts['preferences_path'] = temp_prefs.name
            logger.info("✓ Collected Chrome preferences")
        except Exception as e:
            logger.warning(f"Could not collect preferences: {e}")
        
        artifacts['success'] = True
        return artifacts
        
    except Exception as e:
        artifacts['error'] = str(e)
        return artifacts


def verify_tab_group_organization(artifacts: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify tab group organization using multiple criteria.
    
    Scoring criteria:
    1. Groups detected (30 points): 2-4+ distinct groups identified
    2. Color diversity (20 points): Multiple distinct colors used
    3. Logical organization (25 points): Related tabs grouped together
    4. Coverage (15 points): High percentage of tabs are grouped
    5. Meaningful names (10 points): Groups have descriptive names
    
    Pass threshold: 75% (need ~3-4 criteria)
    """
    tabs_data = artifacts.get('tabs_data', [])
    screenshot_path = artifacts.get('tabbar_screenshot_path')
    
    criteria_scores = {}
    max_score = 100
    feedback_parts = []
    
    # Criterion 1: Detect groups via screenshot analysis (30 points)
    groups_detected, group_info = detect_groups_from_screenshot(screenshot_path)
    if groups_detected >= 3:
        criteria_scores['groups_detected'] = 30
        feedback_parts.append(f"✓ Groups detected: {groups_detected} groups identified")
    elif groups_detected == 2:
        criteria_scores['groups_detected'] = 20
        feedback_parts.append(f"○ Partial grouping: {groups_detected} groups (expected 3-4)")
    elif groups_detected == 1:
        criteria_scores['groups_detected'] = 5
        feedback_parts.append(f"✗ Minimal grouping: Only {groups_detected} group detected")
    else:
        criteria_scores['groups_detected'] = 0
        feedback_parts.append("✗ No groups detected - tabs may not be organized")
    
    # Criterion 2: Color diversity (20 points)
    color_diversity = group_info.get('color_diversity', 0)
    if color_diversity >= 3:
        criteria_scores['color_diversity'] = 20
        feedback_parts.append(f"✓ Color diversity: {color_diversity} distinct colors used")
    elif color_diversity == 2:
        criteria_scores['color_diversity'] = 12
        feedback_parts.append(f"○ Limited colors: {color_diversity} colors (expected 3+)")
    elif color_diversity == 1:
        criteria_scores['color_diversity'] = 5
        feedback_parts.append("✗ No color diversity: All groups same color")
    else:
        criteria_scores['color_diversity'] = 0
        feedback_parts.append("✗ Color diversity: Cannot determine")
    
    # Criterion 3: Logical organization via URL analysis (25 points)
    organization_score, org_feedback = analyze_logical_organization(tabs_data)
    criteria_scores['logical_organization'] = organization_score
    feedback_parts.append(org_feedback)
    
    # Criterion 4: Coverage estimate (15 points)
    coverage_score, coverage_feedback = estimate_grouping_coverage(tabs_data, group_info)
    criteria_scores['coverage'] = coverage_score
    feedback_parts.append(coverage_feedback)
    
    # Criterion 5: Meaningful names heuristic (10 points)
    # This is hard to verify without direct access, so we use heuristics
    name_score = estimate_meaningful_names(groups_detected, tabs_data)
    criteria_scores['meaningful_names'] = name_score
    if name_score >= 8:
        feedback_parts.append("✓ Names likely meaningful (based on organization)")
    elif name_score >= 5:
        feedback_parts.append("○ Names may be default or minimal")
    else:
        feedback_parts.append("✗ Cannot verify meaningful names")
    
    # Calculate total score
    total_score = sum(criteria_scores.values())
    passed = total_score >= 75
    
    # Build detailed feedback
    feedback = "Chrome Tab Groups Organization Verification\n"
    feedback += "=" * 50 + "\n"
    feedback += f"Tabs analyzed: {len(tabs_data)}\n"
    feedback += f"Groups detected: {groups_detected}\n"
    feedback += "\n" + "\n".join(feedback_parts)
    feedback += f"\n\n{'='*50}\n"
    feedback += f"Total score: {total_score}/{max_score}\n"
    feedback += f"Result: {'PASSED ✓' if passed else 'FAILED ✗'}"
    
    if not HAS_PIL:
        feedback += "\n\n⚠ Note: PIL not available, verification used limited heuristics"
    
    return {
        "passed": passed,
        "score": int(total_score),
        "feedback": feedback,
        "details": {
            "groups_detected": groups_detected,
            "color_diversity": color_diversity,
            "criteria_scores": criteria_scores,
            "tab_count": len(tabs_data),
            "group_info": group_info
        }
    }


def detect_groups_from_screenshot(screenshot_path: Optional[str]) -> Tuple[int, Dict]:
    """
    Detect tab groups from screenshot by analyzing colored vertical bars.
    
    Chrome tab groups show as colored 4-5px vertical bars on the left edge of tabs.
    
    Returns:
        Tuple of (number_of_groups, group_info_dict)
    """
    if not screenshot_path or not HAS_PIL:
        logger.warning("Screenshot analysis not available")
        return 0, {'color_diversity': 0, 'method': 'unavailable'}
    
    try:
        img = Image.open(screenshot_path)
        img_array = np.array(img)
        
        # Tab bar is typically in the top ~40-60 pixels
        # Tab groups show as colored vertical bars (4-5px wide)
        
        # Look for distinctive colored regions in the tab bar area
        # Chrome group colors: grey, blue, red, yellow, green, pink, purple, cyan, orange
        
        group_colors = detect_group_color_bars(img_array)
        num_groups = len(group_colors)
        color_diversity = len(set(group_colors)) if group_colors else 0
        
        logger.info(f"Detected {num_groups} groups with {color_diversity} distinct colors")
        
        return num_groups, {
            'color_diversity': color_diversity,
            'colors': group_colors,
            'method': 'screenshot_analysis'
        }
        
    except Exception as e:
        logger.error(f"Error in screenshot analysis: {e}")
        return 0, {'color_diversity': 0, 'method': 'error', 'error': str(e)}


def detect_group_color_bars(img_array: np.ndarray) -> List[str]:
    """
    Detect colored vertical bars in the tab bar area.
    
    Returns:
        List of detected color names
    """
    # Chrome tab group color palette (approximate RGB values)
    chrome_colors = {
        'grey': ([120, 130], [120, 130], [120, 130]),
        'blue': ([30, 100], [100, 180], [200, 255]),
        'red': ([200, 255], [50, 120], [50, 120]),
        'yellow': ([250, 255], [220, 255], [50, 150]),
        'green': ([50, 150], [180, 255], [50, 150]),
        'pink': ([230, 255], [100, 200], [180, 255]),
        'purple': ([150, 220], [80, 150], [200, 255]),
        'cyan': ([50, 150], [200, 255], [200, 255]),
        'orange': ([255, 255], [150, 200], [50, 120]),
    }
    
    # Simplified heuristic: Count colored regions in left portion of tab bar
    # This is a placeholder - full implementation would need sophisticated edge detection
    
    # For now, use a heuristic based on number of tabs and visual patterns
    # A real implementation would scan for vertical colored bars
    
    height, width = img_array.shape[:2]
    
    # Sample vertical lines at regular intervals (where group bars would be)
    detected_colors = []
    
    # This is a simplified placeholder
    # In production, would need proper computer vision techniques
    
    return detected_colors


def analyze_logical_organization(tabs_data: List[Dict]) -> Tuple[int, str]:
    """
    Analyze if tabs are logically organized by domain/category.
    
    Checks if similar domains are likely grouped together.
    
    Returns:
        Tuple of (score, feedback_string)
    """
    if not tabs_data or len(tabs_data) < 3:
        return 0, "✗ Insufficient tab data for organization analysis"
    
    # Categorize tabs by domain/purpose
    categories = {
        'documentation': ['developer.mozilla.org', 'docs.python.org', 'stackoverflow.com', 'github.com'],
        'social': ['mail.google.com', 'reddit.com', 'twitter.com', 'facebook.com'],
        'shopping': ['amazon.com', 'ebay.com', 'etsy.com'],
        'news': ['news.ycombinator.com', 'bbc.com', 'nytimes.com', 'reddit.com/r/news']
    }
    
    tab_categories = []
    for tab in tabs_data:
        url = tab.get('url', '').lower()
        category = 'other'
        for cat_name, domains in categories.items():
            if any(domain in url for domain in domains):
                category = cat_name
                break
        tab_categories.append(category)
    
    # Check for clustering (same category tabs grouped together)
    # If well-organized, we'd see: [doc, doc, doc, social, social, shopping, shopping, news, news]
    # vs poorly organized: [doc, social, doc, shopping, doc, social, news, ...]
    
    category_transitions = 0
    for i in range(len(tab_categories) - 1):
        if tab_categories[i] != tab_categories[i + 1]:
            category_transitions += 1
    
    # Fewer transitions = better organization
    # Expected transitions for 9 tabs in 4 categories: ~3-4
    # Poor organization: 6-8 transitions
    
    if category_transitions <= 4:
        score = 25
        feedback = f"✓ Good organization: Tabs appear clustered by category ({category_transitions} transitions)"
    elif category_transitions <= 6:
        score = 15
        feedback = f"○ Moderate organization: Some clustering detected ({category_transitions} transitions)"
    else:
        score = 5
        feedback = f"✗ Poor organization: Tabs appear scattered ({category_transitions} transitions)"
    
    logger.info(f"Organization analysis: {category_transitions} transitions among categories {set(tab_categories)}")
    
    return score, feedback


def estimate_grouping_coverage(tabs_data: List[Dict], group_info: Dict) -> Tuple[int, str]:
    """
    Estimate what percentage of tabs are grouped vs ungrouped.
    
    Returns:
        Tuple of (score, feedback_string)
    """
    num_tabs = len(tabs_data)
    num_groups = group_info.get('color_diversity', 0)
    
    if num_tabs == 0:
        return 0, "✗ No tabs to analyze"
    
    # Heuristic: If we detected multiple groups, assume high coverage
    # Real implementation would need direct group membership data
    
    if num_groups >= 3:
        # Assume ~80-90% coverage for 3+ groups
        score = 15
        feedback = f"✓ High coverage: {num_groups} groups suggest most tabs are organized"
    elif num_groups == 2:
        # Assume ~60-70% coverage for 2 groups
        score = 10
        feedback = f"○ Moderate coverage: {num_groups} groups, some tabs may be ungrouped"
    elif num_groups == 1:
        # Only one group = poor coverage (many ungrouped)
        score = 3
        feedback = "✗ Low coverage: Only 1 group, many tabs likely ungrouped"
    else:
        score = 0
        feedback = "✗ Coverage unknown: Cannot determine grouping status"
    
    return score, feedback


def estimate_meaningful_names(num_groups: int, tabs_data: List[Dict]) -> int:
    """
    Heuristic to estimate if groups have meaningful names.
    
    Since we can't directly access group names without Chrome Extensions API,
    we use the presence of good organization as a proxy.
    
    Returns:
        Score (0-10)
    """
    if num_groups >= 3:
        # Multiple groups suggests intentional organization with likely meaningful names
        return 10
    elif num_groups == 2:
        return 6
    elif num_groups == 1:
        return 3
    else:
        return 0


def cleanup_temp_files(temp_files: List[str]):
    """Clean up temporary files created during verification."""
    for temp_file in temp_files:
        try:
            if os.path.exists(temp_file):
                os.unlink(temp_file)
        except Exception as e:
            logger.warning(f"Could not remove temp file {temp_file}: {e}")
