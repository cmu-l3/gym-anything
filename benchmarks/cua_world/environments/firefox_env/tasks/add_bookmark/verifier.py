#!/usr/bin/env python3
"""Verifier for add_bookmark task.

Verifies that the agent successfully added Wikipedia as a bookmark in Firefox.
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
    1. Wikipedia bookmark found in database (primary criterion)
    2. New bookmarks were added during task (secondary)
    3. Bookmark URL matches expected pattern

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
    # Criteria: database exists (10), wikipedia found (40), url matches (25), folder correct (15), new bookmarks (10)
    # Total: 100 points, 5 criteria
    score = 0
    criteria_met = 0
    total_criteria = 5
    feedback_parts = []

    # Log result for debugging
    logger.info(f"Task result: {json.dumps(result, indent=2)}")

    # Criterion 1: Places database exists (10 points)
    if result.get('places_db_exists', False):
        score += 10
        criteria_met += 1
        feedback_parts.append("Places database exists")
    else:
        feedback_parts.append("Places database NOT found - Firefox may not have been used")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts)
        }

    # Criterion 2: Wikipedia bookmark found (40 points - primary criterion)
    # Title matching: Deduct 5 points if title doesn't contain expected pattern
    wikipedia_found = result.get('wikipedia_bookmark_found', False)
    bookmark_url = result.get('bookmark_url', '')
    bookmark_title = result.get('bookmark_title', '')
    bookmark_folder_id = result.get('bookmark_folder_id', 0)
    title_matches = False

    if wikipedia_found:
        # Base score for finding Wikipedia bookmark
        base_wikipedia_score = 40
        # Verify title also matches expected pattern
        title_matches = expected_title_pattern.lower() in bookmark_title.lower() if bookmark_title else False
        if title_matches:
            score += base_wikipedia_score
            criteria_met += 1
            feedback_parts.append(f"Wikipedia bookmark found: {bookmark_title} ({bookmark_url})")
        else:
            # Deduct 5 points for title mismatch (agent may have bookmarked wrong page)
            score += (base_wikipedia_score - 5)
            criteria_met += 1
            feedback_parts.append(f"Wikipedia bookmark found but title mismatch (-5 points): {bookmark_title} (expected to contain '{expected_title_pattern}')")
    else:
        # No partial credit for pre-existing bookmarks - task must be completed
        if result.get('wikipedia_already_bookmarked', False):
            feedback_parts.append("Wikipedia was already bookmarked before task started - no action required but no points awarded")
        else:
            feedback_parts.append("Wikipedia bookmark NOT found in browser")

    # Criterion 3: Bookmark URL matches expected pattern (25 points)
    # Use proper URL parsing to avoid substring attacks (e.g., malicious-site.com/fake-wikipedia.org)
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
    # Firefox folder IDs: 2=Bookmarks Menu, 3=Bookmarks Toolbar
    # Task requires bookmark to be in Toolbar or Menu folder
    folder_correct = False
    if bookmark_folder_id in [2, 3]:
        score += 15
        criteria_met += 1
        folder_correct = True
        folder_name = "Bookmarks Menu" if bookmark_folder_id == 2 else "Bookmarks Toolbar"
        feedback_parts.append(f"Bookmark saved in correct folder: {folder_name}")
    elif bookmark_folder_id == 5:
        feedback_parts.append("Bookmark saved in 'Other Bookmarks' - should be in Toolbar or Menu")
    elif bookmark_folder_id > 0:
        feedback_parts.append(f"Bookmark in unexpected folder (ID: {bookmark_folder_id})")
    else:
        if wikipedia_found:
            feedback_parts.append("Could not determine bookmark folder location")

    # Criterion 5: New bookmarks added during task (10 points - reduced from 25)
    # Note: Firefox auto-adds Mozilla bookmarks, so we only check if at least 1 was added
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
    # Primary criteria: Wikipedia bookmark must be found AND in correct folder
    # Pass threshold: score >= 75 (requires Wikipedia found + folder correct + url matches)
    passed = wikipedia_found and folder_correct and score >= 75

    # Build final feedback
    feedback = " | ".join(feedback_parts)

    logger.info(f"Verification result - Passed: {passed}, Score: {score}, Criteria: {criteria_met}/{total_criteria}")

    # Calculate wikipedia_found subscore (40 if found with correct title, 35 if title mismatch)
    wikipedia_subscore = 0
    if wikipedia_found:
        wikipedia_subscore = 40 if title_matches else 35

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "subscores": {
            "database_exists": 10 if result.get('places_db_exists', False) else 0,
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
