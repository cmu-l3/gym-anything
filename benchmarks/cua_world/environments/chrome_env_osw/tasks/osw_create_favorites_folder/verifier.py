#!/usr/bin/env python3
"""
Verifier for osw_create_favorites_folder task.
Ported from OSWorld task 2ad9387a-65d8-4e33-ad5b-7580065a27ca.

Checks that a folder named 'Favorites' exists on the bookmarks bar.
OSWorld metric: is_expected_bookmarks (bookmark_bar_folders_names)
OSWorld getter: bookmarks (reads Chrome Bookmarks JSON)
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env function available"}

    temp_dir = tempfile.mkdtemp()
    feedback = []

    try:
        # Copy Bookmarks file from Chrome profile
        bookmarks_path = os.path.join(temp_dir, "Bookmarks")
        bookmarks_data = None

        candidate_paths = [
            "/home/ga/.config/google-chrome-cdp/Default/Bookmarks",
            "/home/ga/.config/google-chrome/Default/Bookmarks",
        ]

        for candidate in candidate_paths:
            try:
                copy_from_env(candidate, bookmarks_path)
                if os.path.exists(bookmarks_path) and os.path.getsize(bookmarks_path) > 0:
                    with open(bookmarks_path, 'r', encoding='utf-8') as f:
                        bookmarks_data = json.load(f)
                    feedback.append(f"Loaded Bookmarks from {candidate}")
                    break
            except Exception as e:
                feedback.append(f"Could not load from {candidate}: {e}")
                continue

        if bookmarks_data is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Failed to load Chrome Bookmarks from any known path.\n" + "\n".join(feedback)
            }

        # Extract bookmark_bar from roots — mirrors OSWorld getter
        roots = bookmarks_data.get('roots', {})
        bookmark_bar = roots.get('bookmark_bar', {})
        children = bookmark_bar.get('children', [])

        # Check for folder named "Favorites" — mirrors OSWorld is_expected_bookmarks
        folder_names = [child['name'] for child in children if child.get('type') == 'folder']
        expected_names = {"Favorites"}

        feedback.append(f"Found bookmark bar folders: {folder_names}")

        if set(folder_names) == expected_names:
            return {
                "passed": True,
                "score": 100,
                "feedback": "Bookmarks bar has 'Favorites' folder — PASS\n" + "\n".join(feedback)
            }
        else:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Expected folders {expected_names}, got {set(folder_names)} — FAIL\n" + "\n".join(feedback)
            }

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Error during verification: {e}"}
    finally:
        import shutil
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir)
