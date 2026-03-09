#!/usr/bin/env python3
"""
Verifier for add_book_section_reference task.

Criteria (100 points total):
1. Item exists with correct title: 10 pts
2. Item type is 'bookSection': 20 pts
3. Book title (Publication Title) is correct: 10 pts
4. Author 'Bix' is present with role 'author': 15 pts
5. Editor 'Coleman' is present with role 'editor': 10 pts
6. Editor 'Shapiro' is present with role 'editor': 10 pts
7. Publisher 'Oxford University Press' is present: 5 pts
8. Date '2002' is present: 5 pts
9. Pages '61-103' is present: 5 pts
10. Created during task (anti-gaming, implicitly checked by finding new item): 10 pts

Pass threshold: 85 points.
"""

import os
import json
import logging
import tempfile
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_add_book_section_reference(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any],
) -> Dict[str, Any]:
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Load result from container
    try:
        temp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        temp.close()
        try:
            copy_from_env("/tmp/task_result.json", temp.name)
            with open(temp.name) as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp.name):
                os.unlink(temp.name)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to retrieve result JSON: {e}",
        }

    if result.get("error"):
        return {"passed": False, "score": 0, "feedback": f"Error in export: {result['error']}"}

    score = 0
    feedback = []

    # 1. Check Item Existence (10 pts)
    if not result.get("item_found"):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Target item 'Natural Law: The Modern Tradition' was not found in the library.",
        }
    score += 10
    feedback.append("Item found (+10)")

    item_details = result.get("item_details", {})
    creators = result.get("creators", [])

    # 2. Check Item Type (20 pts)
    # Jurism internal name for Book Section is usually 'bookSection'
    item_type = item_details.get("type", "").lower()
    if item_type == "booksection":
        score += 20
        feedback.append("Correct item type: Book Section (+20)")
    else:
        feedback.append(f"Incorrect item type: '{item_type}' (expected 'bookSection')")

    # 3. Check Book Title (10 pts)
    # Field name in DB is usually 'publicationTitle' for book title in a section
    book_title = item_details.get("publicationTitle", "")
    if "Oxford Handbook of Jurisprudence" in book_title:
        score += 10
        feedback.append("Correct Book Title (+10)")
    else:
        feedback.append(f"Incorrect/Missing Book Title: '{book_title}'")

    # 4. Check Author (15 pts)
    bix_author = any(
        c["lastName"] == "Bix" and c["role"] == "author" for c in creators
    )
    if bix_author:
        score += 15
        feedback.append("Author 'Bix' correctly set (+15)")
    else:
        feedback.append("Author 'Bix' missing or wrong role (should be Author)")

    # 5. Check Editor Coleman (10 pts)
    coleman_editor = any(
        c["lastName"] == "Coleman" and c["role"] == "editor" for c in creators
    )
    if coleman_editor:
        score += 10
        feedback.append("Editor 'Coleman' correctly set (+10)")
    else:
        feedback.append("Editor 'Coleman' missing or wrong role (should be Editor)")

    # 6. Check Editor Shapiro (10 pts)
    shapiro_editor = any(
        c["lastName"] == "Shapiro" and c["role"] == "editor" for c in creators
    )
    if shapiro_editor:
        score += 10
        feedback.append("Editor 'Shapiro' correctly set (+10)")
    else:
        feedback.append("Editor 'Shapiro' missing or wrong role (should be Editor)")

    # 7. Check Publisher (5 pts)
    publisher = item_details.get("publisher", "")
    if "Oxford" in publisher:
        score += 5
        feedback.append("Publisher correct (+5)")
    else:
        feedback.append("Publisher missing/incorrect")

    # 8. Check Date (5 pts)
    date_val = item_details.get("date", "")
    if "2002" in date_val:
        score += 5
        feedback.append("Date correct (+5)")
    else:
        feedback.append("Date missing/incorrect")

    # 9. Check Pages (5 pts)
    pages = item_details.get("pages", "")
    if "61" in pages and "103" in pages:
        score += 5
        feedback.append("Pages correct (+5)")
    else:
        feedback.append("Pages missing/incorrect")

    # 10. Creation Check (10 pts)
    # Since we cleaned up specific items in setup, finding it now implies creation.
    score += 10
    feedback.append("Item created during task (+10)")

    passed = score >= 85
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": result,
    }