#!/usr/bin/env python3
"""
Verifier for Chrome Tab Group Organization Task: tab_group_organize@1
Task: Organize 15+ tabs into logical tab groups with names and colors

Verification Strategy:
- Parse Chrome Preferences file for tab_groups.saved_tab_groups
- Verify at least 3 distinct groups exist
- Check each group has a name (non-empty, non-default)
- Verify each group has a color assigned
- Ensure groups contain reasonable number of tabs (2+)
- Calculate grouping coverage (percentage of tabs grouped)
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
sys.path.insert(0, os.path.join(os.path.abspath(__file__), '../../../', 'utils'))
try:
    from chrome_verification_utils import (
        parse_preferences,
        cleanup_verification_temp
    )
    UTILS_AVAILABLE = True
except ImportError:
    logger.warning("Chrome verification utilities not available, using fallback methods")
    UTILS_AVAILABLE = False
    
    def parse_preferences(path):
        with open(path, 'r', encoding='utf-8') as f:
            return json.load(f)
    
    def cleanup_verification_temp():
        pass


# Chrome's tab group color palette
CHROME_TAB_GROUP_COLORS = [
    'GREY', 'BLUE', 'RED', 'YELLOW', 'GREEN', 'PINK', 'PURPLE', 'CYAN'
]


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for tab_group_organize@1 task.
    
    Verifies:
    1. At least 3 tab groups created
    2. All groups have non-empty, non-default names
    3. All groups have distinct colors
    4. Tabs are distributed across groups (80%+ grouped)
    5. Each group contains 2+ tabs (no single-tab groups)
    
    Scoring:
    - 100%: All 5 criteria met (excellent organization)
    - 85-99%: 4/5 criteria met (good organization)
    - 70-84%: 3/5 criteria met (acceptable, passing)
    - 50-69%: 2/5 criteria met (insufficient)
    - <50%: 0-1 criteria met (failed)
    
    Pass threshold: 70% (at least 3 out of 5 criteria)
    
    Args:
        traj: Trajectory data (not used)
        env_info: Environment information with copy_from_env function
        task_info: Task configuration
        
    Returns:
        Dict with passed, score, and feedback
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available - cannot verify task"
        }

    try:
        # Get Chrome Preferences data
        prefs_data = get_preferences_data(copy_from_env)
        if prefs_data is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Failed to retrieve Chrome Preferences file"
            }
        
        # Get tab count from CDP data (optional, for context)
        total_tab_count = get_tab_count_from_cdp(copy_from_env)
        
        # Perform multi-criteria verification
        verification_result = verify_tab_group_organization(
            prefs_data, 
            total_tab_count
        )
        
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


def get_preferences_data(copy_from_env) -> Optional[Dict[str, Any]]:
    """
    Retrieve and parse Chrome Preferences file from container.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Parsed preferences dict or None if failed
    """
    temp_file = None
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        
        # Try multiple possible locations
        prefs_paths = [
            "/tmp/chrome_preferences_groups.json",
            "/home/ga/.config/google-chrome-cdp/Default/Preferences",
            "/home/ga/.config/google-chrome/Default/Preferences",
        ]
        
        for container_path in prefs_paths:
            try:
                logger.info(f"Trying to copy Preferences from: {container_path}")
                copy_from_env(container_path, temp_file.name)
                
                # Check if file has content
                if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) > 0:
                    with open(temp_file.name, 'r', encoding='utf-8') as f:
                        prefs_data = json.load(f)
                    
                    logger.info(f"✓ Successfully loaded Preferences from: {container_path}")
                    return prefs_data
                    
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                continue
        
        logger.error("Could not retrieve Preferences file from any location")
        return None
        
    except Exception as e:
        logger.error(f"Error getting preferences data: {e}")
        return None
    finally:
        if temp_file and os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass


def get_tab_count_from_cdp(copy_from_env) -> int:
    """
    Get total tab count from CDP data (for context).
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Number of tabs or 0 if unavailable
    """
    temp_file = None
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        
        copy_from_env("/tmp/chrome_page_tabs_groups.json", temp_file.name)
        
        with open(temp_file.name, 'r') as f:
            tabs_data = json.load(f)
        
        return len(tabs_data)
        
    except Exception as e:
        logger.debug(f"Could not get tab count from CDP: {e}")
        return 0
    finally:
        if temp_file and os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass


def verify_tab_group_organization(
    prefs_data: Dict[str, Any],
    total_tab_count: int
) -> Dict[str, Any]:
    """
    Verify tab group organization quality.
    
    Checks:
    1. At least 3 groups exist
    2. All groups have proper names
    3. Groups have distinct colors
    4. High grouping coverage (80%+ of tabs)
    5. No trivial single-tab groups
    
    Args:
        prefs_data: Parsed Chrome Preferences
        total_tab_count: Total number of tabs open (from CDP)
        
    Returns:
        Verification result with passed, score, feedback
    """
    criteria_met = 0
    total_criteria = 5
    feedback_parts = []
    
    # Extract tab groups data
    tab_groups_section = prefs_data.get('tab_groups', {})
    saved_groups = tab_groups_section.get('saved_tab_groups', [])
    
    # Also check for other possible locations (Chrome updates location sometimes)
    if not saved_groups:
        # Try alternative path
        profile = prefs_data.get('profile', {})
        content_settings = profile.get('content_settings', {})
        if 'tab_groups' in content_settings:
            saved_groups = content_settings.get('tab_groups', [])
    
    # Check if tab groups feature was used at all
    if not isinstance(saved_groups, list):
        saved_groups = []
    
    num_groups = len(saved_groups)
    
    logger.info(f"Found {num_groups} saved tab group(s)")
    
    # Criterion 1: At least 3 groups created
    criterion_1_met = num_groups >= 3
    if criterion_1_met:
        feedback_parts.append(f"✓ Group count: {num_groups} groups created (meets requirement of 3+)")
        criteria_met += 1
    else:
        feedback_parts.append(f"✗ Group count: Only {num_groups} group(s) created (need 3+)")
    
    if num_groups == 0:
        # Early exit if no groups at all
        feedback = "\n".join(feedback_parts)
        feedback += f"\n\n{'='*50}"
        feedback += "\nNo tab groups were created!"
        feedback += "\nPlease right-click on tabs and select 'Add tab to new group'"
        feedback += "\nThen name and color-code your groups"
        feedback += f"\n\nCriteria met: 0/{total_criteria}"
        feedback += f"\nFinal score: 0%"
        feedback += f"\nResult: FAILED ✗"
        
        return {
            "passed": False,
            "score": 0,
            "feedback": feedback
        }
    
    # Extract group details
    group_names = []
    group_colors = []
    group_sizes = []
    unnamed_count = 0
    
    for i, group in enumerate(saved_groups):
        group_title = group.get('title', '').strip()
        group_color = group.get('color', '').upper()
        group_tabs = group.get('tabs', [])
        group_size = len(group_tabs)
        
        group_names.append(group_title)
        group_colors.append(group_color)
        group_sizes.append(group_size)
        
        # Check for unnamed or default-named groups
        if not group_title or group_title.lower() in ['untitled', 'new group', 'group 1', 'group 2', 'group 3']:
            unnamed_count += 1
        
        logger.info(f"  Group {i+1}: '{group_title}' ({group_color}) - {group_size} tab(s)")
    
    # Criterion 2: All groups have proper names
    criterion_2_met = unnamed_count == 0 and all(name for name in group_names)
    if criterion_2_met:
        feedback_parts.append(f"✓ Group names: All groups have meaningful names")
        criteria_met += 1
    else:
        if unnamed_count > 0:
            feedback_parts.append(f"✗ Group names: {unnamed_count} group(s) unnamed or have default names")
        else:
            feedback_parts.append(f"✗ Group names: Some groups lack names")
    
    # Criterion 3: Groups have distinct colors
    valid_colors = [c for c in group_colors if c in CHROME_TAB_GROUP_COLORS]
    distinct_colors = len(set(valid_colors))
    all_colored = len(valid_colors) == num_groups
    colors_distinct = distinct_colors == num_groups
    
    criterion_3_met = all_colored and colors_distinct
    if criterion_3_met:
        feedback_parts.append(f"✓ Group colors: All groups have distinct colors")
        criteria_met += 1
    else:
        if not all_colored:
            feedback_parts.append(f"✗ Group colors: Some groups missing valid colors")
        elif not colors_distinct:
            feedback_parts.append(f"✗ Group colors: Groups must have distinct colors (found {distinct_colors} unique)")
    
    # Criterion 4: High grouping coverage
    total_tabs_in_groups = sum(group_sizes)
    
    # Use either CDP tab count or fall back to tabs in groups
    if total_tab_count > 0:
        expected_tabs = total_tab_count
    else:
        # Estimate: tabs in groups + 1 (original tab)
        expected_tabs = max(total_tabs_in_groups, 15)  # At least 15 from setup
    
    coverage = (total_tabs_in_groups / expected_tabs) * 100 if expected_tabs > 0 else 0
    
    criterion_4_met = coverage >= 80
    if criterion_4_met:
        feedback_parts.append(f"✓ Grouping coverage: {coverage:.0f}% of tabs grouped (meets 80%+ requirement)")
        criteria_met += 1
    else:
        feedback_parts.append(f"✗ Grouping coverage: Only {coverage:.0f}% of tabs grouped (need 80%+)")
    
    # Criterion 5: No trivial single-tab groups
    single_tab_groups = sum(1 for size in group_sizes if size < 2)
    
    criterion_5_met = single_tab_groups == 0
    if criterion_5_met:
        feedback_parts.append(f"✓ Group sizes: All groups contain 2+ tabs (good organization)")
        criteria_met += 1
    else:
        feedback_parts.append(f"✗ Group sizes: {single_tab_groups} group(s) have only 1 tab (should be 2+)")
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 70
    
    # Build final feedback
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\n{'='*50}"
    feedback += f"\nGroup details:"
    for i, (name, color, size) in enumerate(zip(group_names, group_colors, group_sizes), 1):
        feedback += f"\n  {i}. '{name}' ({color}) - {size} tab(s)"
    feedback += f"\n\nCriteria met: {criteria_met}/{total_criteria}"
    feedback += f"\nFinal score: {score}%"
    feedback += f"\nResult: {'PASSED ✓' if passed else 'FAILED ✗'}"
    
    if passed:
        feedback += "\n\nExcellent tab organization!"
    elif criteria_met >= 2:
        feedback += "\n\nPartial organization detected, but needs improvement"
    else:
        feedback += "\n\nInsufficient tab group organization"
    
    logger.info(f"Verification complete: passed={passed}, score={score}, criteria={criteria_met}/{total_criteria}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "num_groups": num_groups,
            "criteria_met": criteria_met,
            "group_names": group_names,
            "group_colors": group_colors,
            "group_sizes": group_sizes,
            "total_tabs_in_groups": total_tabs_in_groups,
            "coverage_percent": round(coverage, 1)
        }
    }
