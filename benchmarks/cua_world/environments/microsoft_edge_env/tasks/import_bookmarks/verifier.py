#!/usr/bin/env python3
"""Verifier for import_bookmarks task.

Verifies that bookmarks were successfully imported from HTML file into Microsoft Edge.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_import_bookmarks(traj, env_info, task_info):
    """
    Verify that bookmarks were imported from HTML file.

    Criteria:
    1. Bookmarks file exists (10 points)
    2. Significant bookmarks imported (30 points - at least 20 bookmarks)
    3. Expected folders created (25 points - at least 5 folders)
    4. Sample bookmarks found (25 points - BBC News, Stack Overflow, Wikipedia, etc.)
    5. Import increased bookmark count (10 points)

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
    expected_bookmark_count = metadata.get('expected_bookmark_count', 40)
    expected_folder_count = metadata.get('expected_folder_count', 10)
    expected_folders = metadata.get('expected_folders', [])
    sample_bookmarks = metadata.get('sample_bookmarks', ['BBC News', 'Stack Overflow', 'Wikipedia'])

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

    # Criterion 2: Significant bookmarks imported (30 points)
    current_count = result.get('current_bookmark_count', 0)
    min_bookmarks = 36  # At least 90% of expected (40 * 0.9 = 36)

    if current_count >= expected_bookmark_count:
        score += 30
        criteria_met += 1
        feedback_parts.append(f"All {current_count} bookmarks imported (expected {expected_bookmark_count})")
    elif current_count >= min_bookmarks:
        partial_score = int(30 * (current_count / expected_bookmark_count))
        score += partial_score
        criteria_met += 1
        feedback_parts.append(f"Partial import: {current_count}/{expected_bookmark_count} bookmarks ({partial_score} points)")
    else:
        feedback_parts.append(f"Too few bookmarks imported: {current_count} (expected at least {min_bookmarks})")

    # Criterion 3: Expected folders created WITH content (25 points)
    found_folders = result.get('found_expected_folders', [])
    imported_folders = result.get('imported_folders', [])
    folder_count = result.get('folder_count', 0)
    folder_bookmark_counts = result.get('folder_bookmark_counts', {})

    # Verify folders have bookmarks in them (not just empty folders)
    folders_with_content = 0
    for folder_name in expected_folders:
        # Check if any folder path contains this expected folder name
        for folder_path, count in folder_bookmark_counts.items():
            if folder_name in folder_path and count > 0:
                folders_with_content += 1
                break

    min_folders = 7  # At least ~80% of expected 9 folders
    if folders_with_content >= len(expected_folders) * 0.8:  # 80% of expected folders with content
        score += 25
        criteria_met += 1
        feedback_parts.append(f"Folders with bookmarks: {folders_with_content}/{len(expected_folders)} expected folders")
    elif folders_with_content >= min_folders:
        partial_score = int(25 * (folders_with_content / len(expected_folders)))
        score += min(partial_score, 20)
        feedback_parts.append(f"Some folders have content: {folders_with_content} expected folders with bookmarks")
    elif len(found_folders) >= min_folders:
        # Fallback to folder name check if folder_bookmark_counts not available
        partial_score = int(25 * (len(found_folders) / len(expected_folders)))
        score += min(partial_score, 15)
        feedback_parts.append(f"Folders found but content not verified: {found_folders}")
    else:
        feedback_parts.append(f"Few folders found: {found_folders} (expected at least {min_folders} with content)")

    # Criterion 4: Sample bookmarks found (25 points)
    # Require at least 4 of 5 sample bookmarks for full credit
    # Note: Sample matching uses word-boundary detection in export_result.sh to prevent
    # false positives from similar bookmark names (e.g., "MyWikipediaClone" won't match "Wikipedia")
    found_samples = result.get('found_samples', [])
    sample_check_passed = result.get('sample_bookmarks_found', False)
    min_samples = 4  # Require 4 of 5 expected samples

    if len(found_samples) >= min_samples:
        score += 25
        criteria_met += 1
        feedback_parts.append(f"Sample bookmarks found: {found_samples}")
    elif len(found_samples) >= 3:
        partial_score = int(25 * (len(found_samples) / len(sample_bookmarks)))
        score += partial_score
        feedback_parts.append(f"Most sample bookmarks found: {found_samples} ({partial_score} points)")
    elif len(found_samples) >= 1:
        partial_score = int(25 * (len(found_samples) / len(sample_bookmarks)))
        score += partial_score
        feedback_parts.append(f"Some sample bookmarks found: {found_samples} ({partial_score} points)")
    else:
        feedback_parts.append("No sample bookmarks found from expected list")

    # Criterion 5: Import increased bookmark count (10 points)
    new_bookmarks = result.get('new_bookmarks_imported', 0)
    initial_count = result.get('initial_bookmark_count', 0)

    if new_bookmarks > 0 and current_count > initial_count:
        score += 10
        criteria_met += 1
        feedback_parts.append(f"{new_bookmarks} new bookmarks imported")
    else:
        feedback_parts.append(f"No new bookmarks detected (initial: {initial_count}, current: {current_count})")

    # Determine pass/fail
    # Must have imported at least 90% of bookmarks AND found at least 4 sample bookmarks AND 80% folders with content AND score >= 80
    # Use folders_with_content (not found_folders) to ensure folders actually contain bookmarks
    passed = (current_count >= min_bookmarks) and (len(found_samples) >= min_samples) and (folders_with_content >= min_folders) and score >= 80

    feedback = " | ".join(feedback_parts)

    logger.info(f"Verification result - Passed: {passed}, Score: {score}, Criteria: {criteria_met}/{total_criteria}")

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "subscores": {
            "bookmarks_file_exists": 10 if result.get('bookmarks_file_exists', False) else 0,
            "bookmarks_imported": min(30, int(30 * (current_count / max(expected_bookmark_count, 1)))),
            "folders_with_content": min(25, int(25 * (folders_with_content / max(len(expected_folders), 1)))),
            "sample_bookmarks": min(25, int(25 * (len(found_samples) / max(len(sample_bookmarks), 1)))),
            "count_increased": 10 if new_bookmarks > 0 else 0
        }
    }


if __name__ == "__main__":
    print("This verifier should be run through the gym_anything framework.")
    print("Use: env.verify() after completing the task interactively.")
