#!/usr/bin/env python3
"""
Verifier for Chrome Resource-Heavy Tab Cleanup Task (resource_heavy_tab_cleanup@1)
Task: Use Chrome Task Manager to identify and close resource-heavy tabs while preserving important work

Verification Strategy:
- Compare initial tab state (from setup) with final tab state (after agent action)
- Classify tabs as: high-resource (should close), important work (should preserve), neutral (optional)
- Score based on:
  1. High-resource tabs closed (primary goal)
  2. Important work tabs preserved (critical)
  3. Meaningful cleanup percentage
  4. Smart targeting (closed primarily high-resource, not random)
"""

import logging
import sys
import os
import json
import tempfile
from pathlib import Path
from typing import Dict, List, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utilities to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../', 'utils'))
try:
    from chrome_verification_utils import cleanup_verification_temp
except ImportError:
    logger.warning("Chrome verification utilities not available, using fallback")
    def cleanup_verification_temp():
        pass


# URL classification patterns
HIGH_RESOURCE_PATTERNS = [
    'youtube.com/watch',
    'youtu.be/',
    'cnn.com',
    'bbc.com',
    'giphy.com',
    'threejs.org/examples',
    'codepen.io',
    'codesandbox.io',
    'twitch.tv',
    'vimeo.com',
]

IMPORTANT_WORK_PATTERNS = [
    'docs.google.com',
    'mail.google.com',
    'gmail.com',
    'github.com',
    'stackoverflow.com/questions/',
    'drive.google.com',
]

NEUTRAL_PATTERNS = [
    'wikipedia.org',
    'example.com',
    'example.org',
]


def classify_url(url: str) -> str:
    """
    Classify a URL as 'high_resource', 'important', or 'neutral'.
    
    Args:
        url: Full URL string
        
    Returns:
        Classification string
    """
    url_lower = url.lower()
    
    # Check important patterns first (highest priority)
    for pattern in IMPORTANT_WORK_PATTERNS:
        if pattern in url_lower:
            return 'important'
    
    # Check high-resource patterns
    for pattern in HIGH_RESOURCE_PATTERNS:
        if pattern in url_lower:
            return 'high_resource'
    
    # Check neutral patterns
    for pattern in NEUTRAL_PATTERNS:
        if pattern in url_lower:
            return 'neutral'
    
    # Default to neutral for unknown URLs
    return 'neutral'


def get_tabs_data(copy_from_env, filename: str) -> List[Dict[str, Any]]:
    """
    Retrieve tab information from container.
    
    Args:
        copy_from_env: Function to copy files from container
        filename: Name of the JSON file to retrieve
        
    Returns:
        List of tab dictionaries
    """
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json', mode='w+')
        temp_path = temp_file.name
        temp_file.close()
        
        copy_from_env(f"/tmp/{filename}", temp_path)
        
        with open(temp_path, 'r') as f:
            tabs_data = json.load(f)
        
        os.unlink(temp_path)
        
        logger.info(f"Successfully retrieved {len(tabs_data)} tab(s) from {filename}")
        return tabs_data
        
    except Exception as e:
        logger.error(f"Failed to get tabs data from {filename}: {e}")
        return []


def normalize_url(url: str) -> str:
    """Normalize URL for comparison (remove fragments, trailing slashes, etc.)"""
    if not url:
        return ""
    # Remove trailing slashes
    url = url.rstrip('/')
    # Remove fragments
    if '#' in url:
        url = url.split('#')[0]
    # Normalize protocol
    url = url.replace('http://', 'https://')
    return url.lower()


def analyze_tab_changes(initial_tabs: List[Dict], final_tabs: List[Dict]) -> Dict[str, Any]:
    """
    Analyze which tabs were closed and which remain.
    
    Args:
        initial_tabs: List of initial tab data
        final_tabs: List of final tab data
        
    Returns:
        Dict with detailed analysis
    """
    # Extract and normalize URLs
    initial_urls = {normalize_url(tab.get('url', '')): tab for tab in initial_tabs}
    final_urls = {normalize_url(tab.get('url', '')): tab for tab in final_tabs}
    
    # Determine closed and remaining tabs
    closed_urls = set(initial_urls.keys()) - set(final_urls.keys())
    remaining_urls = set(final_urls.keys())
    
    # Classify tabs
    initial_classified = {
        'high_resource': [],
        'important': [],
        'neutral': []
    }
    
    for url in initial_urls.keys():
        classification = classify_url(url)
        initial_classified[classification].append(url)
    
    closed_classified = {
        'high_resource': [],
        'important': [],
        'neutral': []
    }
    
    for url in closed_urls:
        classification = classify_url(url)
        closed_classified[classification].append(url)
    
    remaining_classified = {
        'high_resource': [],
        'important': [],
        'neutral': []
    }
    
    for url in remaining_urls:
        classification = classify_url(url)
        remaining_classified[classification].append(url)
    
    return {
        'initial_count': len(initial_urls),
        'final_count': len(final_urls),
        'closed_count': len(closed_urls),
        'initial_classified': initial_classified,
        'closed_classified': closed_classified,
        'remaining_classified': remaining_classified,
        'closed_urls': list(closed_urls),
        'remaining_urls': list(remaining_urls),
    }


def verify_resource_cleanup(analysis: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that agent performed intelligent resource-heavy tab cleanup.
    
    Scoring criteria:
    1. High-resource tabs closed (40 points max)
    2. Important tabs preserved (30 points max)
    3. Meaningful cleanup (20 points max)
    4. Smart targeting (10 points max)
    
    Args:
        analysis: Tab change analysis dict
        
    Returns:
        Verification result with score, passed status, and feedback
    """
    score = 0
    feedback_parts = []
    
    initial_count = analysis['initial_count']
    final_count = analysis['final_count']
    closed_count = analysis['closed_count']
    
    initial_high_resource = len(analysis['initial_classified']['high_resource'])
    initial_important = len(analysis['initial_classified']['important'])
    
    closed_high_resource = len(analysis['closed_classified']['high_resource'])
    closed_important = len(analysis['closed_classified']['important'])
    closed_neutral = len(analysis['closed_classified']['neutral'])
    
    remaining_high_resource = len(analysis['remaining_classified']['high_resource'])
    remaining_important = len(analysis['remaining_classified']['important'])
    
    # Criterion 1: Closed high-resource tabs (40 points max)
    if closed_high_resource >= 3:
        score += 40
        feedback_parts.append(f"✓ Excellent: Closed {closed_high_resource} resource-heavy tab(s)")
    elif closed_high_resource >= 2:
        score += 30
        feedback_parts.append(f"✓ Good: Closed {closed_high_resource} resource-heavy tab(s)")
    elif closed_high_resource == 1:
        score += 15
        feedback_parts.append(f"⚠ Partial: Only closed {closed_high_resource} resource-heavy tab")
    else:
        score += 0
        feedback_parts.append(f"✗ Failed: No resource-heavy tabs were closed")
    
    # Criterion 2: Preserved important tabs (30 points max)
    if closed_important == 0 and remaining_important == initial_important:
        score += 30
        feedback_parts.append(f"✓ Perfect: All {initial_important} important work tab(s) preserved")
    elif closed_important == 0:
        score += 25
        feedback_parts.append(f"✓ Good: No important tabs closed")
    elif closed_important == 1:
        score += 10
        feedback_parts.append(f"⚠ Warning: Closed {closed_important} important work tab")
    else:
        score += 0
        feedback_parts.append(f"✗ Critical: Closed {closed_important} important work tab(s)")
    
    # Criterion 3: Meaningful cleanup (20 points max)
    if initial_count == 0:
        cleanup_pct = 0
    else:
        cleanup_pct = closed_count / initial_count
    
    if cleanup_pct >= 0.40:  # 40% or more
        score += 20
        feedback_parts.append(f"✓ Excellent cleanup: {cleanup_pct:.0%} of tabs closed")
    elif cleanup_pct >= 0.30:  # 30-39%
        score += 15
        feedback_parts.append(f"✓ Good cleanup: {cleanup_pct:.0%} of tabs closed")
    elif cleanup_pct >= 0.20:  # 20-29%
        score += 10
        feedback_parts.append(f"⚠ Modest cleanup: {cleanup_pct:.0%} of tabs closed")
    else:
        score += 0
        feedback_parts.append(f"✗ Insufficient cleanup: Only {cleanup_pct:.0%} of tabs closed")
    
    # Criterion 4: Smart targeting (10 points max)
    if closed_count > 0:
        targeting_ratio = closed_high_resource / closed_count
        if targeting_ratio >= 0.67:  # 2/3 or more of closed tabs were high-resource
            score += 10
            feedback_parts.append(f"✓ Smart targeting: {closed_high_resource}/{closed_count} closed tabs were resource-heavy")
        elif targeting_ratio >= 0.50:  # At least half
            score += 5
            feedback_parts.append(f"⚠ Moderate targeting: {closed_high_resource}/{closed_count} closed tabs were resource-heavy")
        else:
            score += 0
            feedback_parts.append(f"✗ Poor targeting: Only {closed_high_resource}/{closed_count} closed tabs were resource-heavy")
    
    # Determine pass/fail
    passed = score >= 75
    
    # Build summary feedback
    summary = []
    summary.append("=" * 60)
    summary.append("CHROME RESOURCE-HEAVY TAB CLEANUP VERIFICATION")
    summary.append("=" * 60)
    summary.append(f"Initial tabs: {initial_count} ({initial_high_resource} high-resource, {initial_important} important)")
    summary.append(f"Final tabs: {final_count}")
    summary.append(f"Tabs closed: {closed_count}")
    summary.append("")
    summary.append("Closed tab breakdown:")
    summary.append(f"  - High-resource: {closed_high_resource}")
    summary.append(f"  - Important work: {closed_important}")
    summary.append(f"  - Neutral: {closed_neutral}")
    summary.append("")
    summary.extend(feedback_parts)
    summary.append("")
    summary.append(f"Final Score: {score}/100")
    summary.append(f"Result: {'✅ PASSED' if passed else '❌ FAILED'}")
    summary.append("=" * 60)
    
    feedback = "\n".join(summary)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "initial_count": initial_count,
            "final_count": final_count,
            "closed_count": closed_count,
            "closed_high_resource": closed_high_resource,
            "closed_important": closed_important,
            "important_preserved": remaining_important == initial_important,
            "cleanup_percentage": cleanup_pct,
        }
    }


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for resource_heavy_tab_cleanup@1.
    
    Args:
        traj: Trajectory data (unused)
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
            "feedback": "Copy function not available - cannot verify task"
        }
    
    try:
        # Get initial and final tab states
        initial_tabs = get_tabs_data(copy_from_env, "initial_tabs.json")
        final_tabs = get_tabs_data(copy_from_env, "final_tabs.json")
        
        if not initial_tabs:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Failed to retrieve initial tab state - cannot verify task"
            }
        
        if not final_tabs:
            # If no tabs remain, that might mean they closed ALL tabs (failure)
            logger.warning("No final tabs found - agent may have closed all tabs")
        
        # Analyze tab changes
        analysis = analyze_tab_changes(initial_tabs, final_tabs)
        
        # Log detailed analysis
        logger.info("Tab change analysis:")
        logger.info(f"  Initial: {analysis['initial_count']} tabs")
        logger.info(f"  Final: {analysis['final_count']} tabs")
        logger.info(f"  Closed: {analysis['closed_count']} tabs")
        logger.info(f"  Closed high-resource: {len(analysis['closed_classified']['high_resource'])}")
        logger.info(f"  Closed important: {len(analysis['closed_classified']['important'])}")
        
        # Verify cleanup quality
        result = verify_resource_cleanup(analysis)
        
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
