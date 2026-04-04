#!/usr/bin/env python3
"""Verifier for add_bookmark task.

Verifies that the agent successfully added Wikipedia as a bookmark in Microsoft Edge.
"""

import json
import logging
import os
import tempfile
from urllib.parse import urlparse

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_add_bookmark(traj, env_info, task_info):
    """
    Verify that Wikipedia was added as a bookmark.

    Criteria:
    1. Bookmarks file exists (10 points)
    2. Wikipedia bookmark found in database (40 points - primary criterion)
    3. Bookmark URL matches expected pattern (25 points)
    4. Bookmark in correct folder - bookmark_bar or other (15 points)
    5. New bookmarks were added during task (10 points)

    Args:
        traj: Trajectory data from the agent
        env_info: Environment information including copy_from_env function
        task_info: Task metadata including expected values

    Returns:
        dict: {"passed": bool, "score": float (0-100), "feedback": str}
    """
    # Get copy function from framework
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available from framework"
        }

    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected_url_pattern = metadata.get('expected_bookmark_url_pattern', 'wikipedia.org')
    expected_title_pattern = metadata.get('expected_bookmark_title_pattern', 'Wikipedia')

    # Copy result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result file: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to read task result: {str(e)}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Initialize scoring
    # Criteria: bookmarks_file exists (10), wikipedia found (40), url matches (25), folder correct (15), new bookmarks (10)
    # Total: 100 points, 5 criteria
    score = 0
    criteria_met = 0
    total_criteria = 5
    feedback_parts = []

    # Log result for debugging
    logger.info(f"Task result: {json.dumps(result, indent=2)}")

    # Criterion 1: Bookmarks file exists (10 points)
    if result.get('bookmarks_file_exists', False):
        score += 10
        criteria_met += 1
        feedback_parts.append("Bookmarks file exists")
    else:
        feedback_parts.append("Bookmarks file NOT found - Edge may not have been used")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts)
        }

    # Criterion 2: Wikipedia bookmark found (40 points - primary criterion)
    wikipedia_found = result.get('wikipedia_bookmark_found', False)
    wikipedia_bookmark_count = result.get('wikipedia_bookmark_count', 1 if wikipedia_found else 0)
    bookmark_url = result.get('bookmark_url', '')
    bookmark_title = result.get('bookmark_title', '')
    bookmark_folder = result.get('bookmark_folder', '')
    title_matches = False

    # Check for duplicate Wikipedia bookmarks (penalize redundant actions)
    has_duplicates = wikipedia_bookmark_count > 1
    if has_duplicates:
        feedback_parts.append(f"WARNING: {wikipedia_bookmark_count} duplicate Wikipedia bookmarks detected (-5 points)")

    if wikipedia_found:
        # Base score for finding Wikipedia bookmark
        base_wikipedia_score = 40
        # Verify title matches expected pattern more strictly
        # Title should start with "Wikipedia" or be exactly "Wikipedia" (handles "Wikipedia, the free encyclopedia")
        title_lower = bookmark_title.lower() if bookmark_title else ''
        pattern_lower = expected_title_pattern.lower()
        # Stricter matching: title starts with pattern, or pattern is a complete word in title
        title_matches = (
            title_lower.startswith(pattern_lower) or
            title_lower == pattern_lower or
            f" {pattern_lower}" in f" {title_lower}" or  # Pattern at word boundary
            title_lower.endswith(f" {pattern_lower}")
        )
        if title_matches:
            wikipedia_score = base_wikipedia_score
            # Apply duplicate penalty (5 points off if duplicates found)
            if has_duplicates:
                wikipedia_score -= 5
            score += wikipedia_score
            criteria_met += 1
            feedback_parts.append(f"Wikipedia bookmark found: {bookmark_title} ({bookmark_url})")
        else:
            # Deduct 10 points for title mismatch (agent may have bookmarked wrong page)
            wikipedia_score = base_wikipedia_score - 10
            # Apply duplicate penalty (5 points off if duplicates found)
            if has_duplicates:
                wikipedia_score -= 5
            score += wikipedia_score
            criteria_met += 1
            feedback_parts.append(f"Wikipedia bookmark found but title mismatch (-10 points): {bookmark_title} (expected to start with or contain '{expected_title_pattern}')")
    else:
        # No partial credit for pre-existing bookmarks
        if result.get('wikipedia_already_bookmarked', False):
            feedback_parts.append("Wikipedia was already bookmarked before task started - no action required but no points awarded")
        else:
            feedback_parts.append("Wikipedia bookmark NOT found in browser")

    # Criterion 3: Bookmark URL matches expected pattern (25 points)
    url_matches_score = 0
    if bookmark_url:
        try:
            parsed_url = urlparse(bookmark_url)
            # Check the domain (netloc) for the pattern, not the full URL
            domain = parsed_url.netloc.lower()
            pattern_lower = expected_url_pattern.lower()

            # Validate that pattern is in the domain (not path or other parts)
            if pattern_lower in domain:
                score += 25
                criteria_met += 1
                url_matches_score = 25
                feedback_parts.append(f"URL domain '{domain}' matches pattern '{expected_url_pattern}'")
            else:
                feedback_parts.append(f"URL domain '{domain}' doesn't match expected pattern '{expected_url_pattern}'")
        except Exception as e:
            logger.warning(f"URL parsing failed for '{bookmark_url}': {e}")
            feedback_parts.append(f"URL validation failed: {str(e)}")

    # Criterion 4: Bookmark in correct folder (15 points)
    # Edge folder names: bookmark_bar, other (Other Bookmarks), synced
    # Use exact matching to prevent false positives from folder names containing these as substrings
    folder_correct = False
    folder_lower = bookmark_folder.lower().strip() if bookmark_folder else ''

    # Exact matches for standard Edge folder names
    bookmark_bar_names = ['bookmark_bar', 'bookmarks_bar', 'favorites bar', 'favorites_bar']
    other_folder_names = ['other', 'other favorites', 'other_favorites', 'other bookmarks', 'other_bookmarks']
    synced_folder_names = ['synced', 'mobile favorites', 'mobile_favorites']

    if folder_lower in bookmark_bar_names:
        score += 15
        criteria_met += 1
        folder_correct = True
        feedback_parts.append("Bookmark saved in Favorites bar")
    elif folder_lower in other_folder_names:
        score += 15
        criteria_met += 1
        folder_correct = True
        feedback_parts.append("Bookmark saved in Other Favorites")
    elif folder_lower in synced_folder_names:
        score += 10  # Partial credit for synced folder
        criteria_met += 1
        folder_correct = True
        feedback_parts.append("Bookmark saved in Synced/Mobile folder (partial credit)")
    elif bookmark_folder and wikipedia_found:
        # Some folder but not the standard ones - check if it's a subfolder of a valid location
        # e.g., "bookmark_bar/My Folder" should get partial credit
        folder_parts = folder_lower.split('/')
        if any(part in bookmark_bar_names or part in other_folder_names for part in folder_parts):
            score += 10  # Partial credit for subfolder of valid location
            folder_correct = True
            feedback_parts.append(f"Bookmark in subfolder of valid location: {bookmark_folder}")
        else:
            score += 5  # Minimal credit
            feedback_parts.append(f"Bookmark in non-standard folder: {bookmark_folder}")
    else:
        if wikipedia_found:
            feedback_parts.append("Could not determine bookmark folder location")

    # Criterion 5: New bookmarks added during task (10 points)
    new_bookmarks = result.get('new_bookmarks_added', 0)
    if new_bookmarks > 0 and wikipedia_found:
        score += 10
        criteria_met += 1
        feedback_parts.append(f"{new_bookmarks} new bookmark(s) added during task")
    else:
        initial = result.get('initial_bookmark_count', 0)
        current = result.get('current_bookmark_count', 0)
        feedback_parts.append(f"No new bookmarks detected (initial: {initial}, current: {current})")

    # Determine pass/fail
    # Primary criteria: Wikipedia bookmark must be found AND URL matches
    # Pass threshold: score >= 75 (requires Wikipedia found + URL matches + one other criterion)
    passed = wikipedia_found and url_matches_score > 0 and score >= 75

    # Build final feedback
    feedback = " | ".join(feedback_parts)

    logger.info(f"Verification result - Passed: {passed}, Score: {score}, Criteria: {criteria_met}/{total_criteria}")

    # Calculate wikipedia_found subscore (40 if found with correct title, 30 if title mismatch - 10 point deduction)
    # Additional -5 penalty for duplicate bookmarks
    wikipedia_subscore = 0
    if wikipedia_found:
        wikipedia_subscore = 40 if title_matches else 30
        if has_duplicates:
            wikipedia_subscore -= 5

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "subscores": {
            "bookmarks_file_exists": 10 if result.get('bookmarks_file_exists', False) else 0,
            "wikipedia_found": wikipedia_subscore,
            "url_matches": url_matches_score,
            "folder_correct": 15 if folder_correct else 0,
            "new_bookmarks": 10 if (new_bookmarks > 0 and wikipedia_found) else 0
        }
    }


if __name__ == "__main__":
    # For testing the verifier locally with mock data
    # This should NOT be used for actual verification
    print("This verifier should be run through the gym_anything framework.")
    print("Use: env.verify() after completing the task interactively.")
