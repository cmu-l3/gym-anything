#!/usr/bin/env python3
"""
Verifier for Chrome Advanced Link Opening Task (advanced_link_opening@1)
Task: Use advanced link opening techniques to open 5 articles in appropriate contexts

Verification Strategy:
- Query Chrome DevTools Protocol (CDP) for all open tabs/windows
- Verify all 5 article URLs are present
- Check that approximately 3 windows are open (original + 2 new windows)
- Verify original test page is still open
- Ensure no duplicate articles
- Validate expected tab count (6 total: original + 5 articles)
"""

import logging
import sys
import os
import json
import tempfile
from pathlib import Path
from typing import Dict, List, Any, Tuple

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utils to path
sys.path.insert(0, os.path.join(os.path.abspath(__file__), '../../../', 'utils'))
try:
    from chrome_verification_utils import cleanup_verification_temp
except ImportError:
    logger.warning("Chrome verification utilities not available, using fallback methods")
    def cleanup_verification_temp():
        pass


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for advanced_link_opening@1.
    
    Verifies that links were opened using advanced techniques:
    - Article A: Ctrl+Click (background tab)
    - Article B: Shift+Click (new window)
    - Article C: Middle-Click (background tab)
    - Article D: Right-click menu "Open link in new tab"
    - Article E: Right-click menu "Open link in new window"
    
    Verification Criteria (5 total, need 4+ to pass at 80%):
    1. All 5 article URLs present
    2. Approximately 3 windows open
    3. Original test page preserved
    4. Expected tab count (5-7 tabs)
    5. No duplicate articles
    
    Args:
        traj: Trajectory data (unused)
        env_info: Environment information with copy_from_env function
        task_info: Task configuration
        
    Returns:
        Dict with passed, score, feedback keys
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available in environment"
        }

    try:
        # Get tab data from container
        tabs_data = get_tabs_data(copy_from_env)
        if tabs_data is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Failed to retrieve tab information from Chrome CDP"
            }

        # Perform verification
        result = verify_link_opening_workflow(tabs_data)
        
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


def get_tabs_data(copy_from_env) -> List[Dict[str, Any]]:
    """
    Retrieve tab information from container via CDP export.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        List of tab dictionaries with url, title, and metadata
    """
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json', mode='w+')
        temp_path = temp_file.name
        temp_file.close()
        
        copy_from_env("/tmp/chrome_page_tabs.json", temp_path)
        
        with open(temp_path, 'r') as f:
            tabs_data = json.load(f)
        
        os.unlink(temp_path)
        
        logger.info(f"Successfully retrieved {len(tabs_data)} tab(s) from CDP")
        return tabs_data
        
    except Exception as e:
        logger.error(f"Failed to get tabs data: {e}")
        return None


def normalize_url(url: str) -> str:
    """
    Normalize URL for comparison (handle file:// paths, trailing slashes, etc.)
    
    Args:
        url: Raw URL string
        
    Returns:
        Normalized URL string
    """
    if not url:
        return ""
    
    # Convert to lowercase
    url = url.lower()
    
    # Remove trailing slashes
    url = url.rstrip('/')
    
    # Remove query parameters for file:// URLs
    if 'file://' in url and '?' in url:
        url = url.split('?')[0]
    
    return url


def verify_link_opening_workflow(tabs_data: List[Dict[str, Any]]) -> Dict[str, Any]:
    """
    Verify that link opening workflow was executed correctly.
    
    Checks:
    1. All 5 article URLs are present (article-a through article-e)
    2. Approximately 3 windows exist (original + 2 new windows from Shift+click)
    3. Original test page (index.html) is still open
    4. Tab count is reasonable (5-7 tabs expected)
    5. No duplicate articles opened
    
    Args:
        tabs_data: List of tab information from CDP
        
    Returns:
        Verification result dict
    """
    # Expected article identifiers
    expected_articles = ['article-a', 'article-b', 'article-c', 'article-d', 'article-e']
    
    # Extract URLs and titles
    tab_urls = [tab.get('url', '') for tab in tabs_data]
    tab_titles = [tab.get('title', '') for tab in tabs_data]
    
    logger.info(f"Found {len(tabs_data)} tabs")
    for i, (url, title) in enumerate(zip(tab_urls, tab_titles), 1):
        logger.info(f"  Tab {i}: {url[:80]}... | {title[:50]}...")
    
    # Normalize URLs for comparison
    normalized_urls = [normalize_url(url) for url in tab_urls]
    
    # Criterion 1: All 5 article URLs present
    articles_found = {article: False for article in expected_articles}
    for url in normalized_urls:
        for article in expected_articles:
            if article in url:
                articles_found[article] = True
    
    all_articles_present = all(articles_found.values())
    articles_count = sum(articles_found.values())
    
    logger.info(f"✓ Articles found: {articles_count}/5")
    for article, found in articles_found.items():
        logger.info(f"  - {article}: {'✓' if found else '✗'}")
    
    # Criterion 2: Window count (approximate)
    # Note: CDP doesn't directly expose window grouping, but we can estimate
    # by counting unique webSocketDebuggerUrl hosts or assuming based on tab distribution
    # For simplicity, we'll check if tab count suggests multiple windows were created
    window_indicators = set()
    for tab in tabs_data:
        ws_url = tab.get('webSocketDebuggerUrl', '')
        if ws_url:
            # Extract host/port from WebSocket URL
            parts = ws_url.split('/')
            if len(parts) >= 3:
                window_indicators.add(parts[2])
    
    estimated_windows = len(window_indicators) if window_indicators else 1
    
    # We expect 3 windows: original + 2 new windows (from Shift+click on B and E)
    # Allow 2-4 windows as acceptable range
    correct_window_count = 2 <= estimated_windows <= 4
    
    logger.info(f"✓ Estimated windows: {estimated_windows} (expected 3, acceptable: 2-4) - {'PASS' if correct_window_count else 'FAIL'}")
    
    # Criterion 3: Original test page preserved
    original_page_present = any('index.html' in url or 'link opening test' in title.lower() 
                                for url, title in zip(normalized_urls, tab_titles))
    
    logger.info(f"✓ Original test page present: {'YES' if original_page_present else 'NO'} - {'PASS' if original_page_present else 'FAIL'}")
    
    # Criterion 4: Expected tab count (6 total: 1 original + 5 articles)
    # Allow 5-7 tabs (some flexibility for agent behavior)
    expected_tab_range = range(5, 8)
    correct_tab_count = len(tabs_data) in expected_tab_range
    
    logger.info(f"✓ Tab count: {len(tabs_data)} (expected 5-7) - {'PASS' if correct_tab_count else 'FAIL'}")
    
    # Criterion 5: No duplicate articles
    article_counts = {}
    for url in normalized_urls:
        for article in expected_articles:
            if article in url:
                article_counts[article] = article_counts.get(article, 0) + 1
    
    has_duplicates = any(count > 1 for count in article_counts.values())
    no_duplicates = not has_duplicates
    
    logger.info(f"✓ No duplicates: {'YES' if no_duplicates else 'NO (found duplicates)'} - {'PASS' if no_duplicates else 'FAIL'}")
    
    # Calculate score
    criteria_results = [
        all_articles_present,
        correct_window_count,
        original_page_present,
        correct_tab_count,
        no_duplicates
    ]
    
    criteria_met = sum(criteria_results)
    score = (criteria_met / 5.0) * 100
    passed = score >= 80  # Need 4/5 criteria (80%)
    
    # Generate detailed feedback
    feedback_parts = []
    feedback_parts.append(f"Advanced Link Opening Verification: {criteria_met}/5 criteria met")
    feedback_parts.append("")
    feedback_parts.append(f"{'✓' if all_articles_present else '✗'} 1. All articles opened: {articles_count}/5 articles found")
    
    if not all_articles_present:
        missing = [art for art, found in articles_found.items() if not found]
        feedback_parts.append(f"     Missing: {', '.join(missing)}")
    
    feedback_parts.append(f"{'✓' if correct_window_count else '✗'} 2. Window count: {estimated_windows} windows (expected 3, range 2-4)")
    feedback_parts.append(f"{'✓' if original_page_present else '✗'} 3. Original page preserved: {'Yes' if original_page_present else 'No'}")
    feedback_parts.append(f"{'✓' if correct_tab_count else '✗'} 4. Tab count: {len(tabs_data)} tabs (expected 5-7)")
    feedback_parts.append(f"{'✓' if no_duplicates else '✗'} 5. No duplicates: {'No duplicates found' if no_duplicates else 'Duplicate articles detected'}")
    
    if has_duplicates:
        dupes = [f"{art}({count}x)" for art, count in article_counts.items() if count > 1]
        feedback_parts.append(f"     Duplicates: {', '.join(dupes)}")
    
    feedback_parts.append("")
    feedback_parts.append(f"Score: {int(score)}% ({criteria_met}/5 criteria)")
    
    if passed:
        feedback_parts.append("✅ Task completed successfully!")
        if criteria_met == 5:
            feedback_parts.append("Perfect execution of all link opening techniques!")
    else:
        feedback_parts.append("❌ Task incomplete - some link opening methods were not correctly executed")
        
        # Provide helpful suggestions
        if not all_articles_present:
            feedback_parts.append("")
            feedback_parts.append("Suggestion: Ensure you used the correct method for each link:")
            feedback_parts.append("  - Article A: Ctrl+Click")
            feedback_parts.append("  - Article B: Shift+Click")
            feedback_parts.append("  - Article C: Middle-Click")
            feedback_parts.append("  - Article D: Right-click → 'Open link in new tab'")
            feedback_parts.append("  - Article E: Right-click → 'Open link in new window'")
    
    feedback = "\n".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": feedback,
        "details": {
            "tab_count": len(tabs_data),
            "estimated_windows": estimated_windows,
            "articles_found": articles_found,
            "articles_count": articles_count,
            "has_duplicates": has_duplicates,
            "criteria_met": criteria_met,
            "tab_urls": tab_urls[:10]  # Limit for readability
        }
    }
