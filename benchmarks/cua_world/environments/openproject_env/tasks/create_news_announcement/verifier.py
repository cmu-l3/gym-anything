#!/usr/bin/env python3
"""
Verifier for create_news_announcement@1.

Verifies that a news announcement was created in OpenProject with the correct
content and timestamp.

Criteria:
1. News item exists in the correct project (25 pts)
2. Title matches expected value (25 pts)
3. Summary matches expected value (25 pts)
4. Description contains 3 key requirements (25 pts)
5. Anti-gaming: Must be created during task session
"""

import json
import tempfile
import os
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _norm(text):
    """Normalize text for comparison (lowercase, strip whitespace)."""
    if not text:
        return ""
    return re.sub(r'\s+', ' ', str(text).strip().lower())


def verify_create_news_announcement(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_title = metadata.get('expected_title', "Mandatory Security Compliance Update - Q4 Deadline")
    expected_summary = metadata.get('expected_summary', "All team members must complete security training and update authentication modules before the Q4 compliance deadline.")
    description_keywords = metadata.get('description_keywords', [
        "multi-factor authentication",
        "security awareness training",
        "penetration testing"
    ])

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Check if news item was found
    if not result.get("found"):
        error = result.get("error", "Unknown error")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"No valid news announcement found. {error}"
        }

    # CRITERION 1: News Exists (25 pts)
    # The export script already filters by project and timestamp, so if found=true,
    # we know it's in the right project and created during the task.
    score += 25
    feedback_parts.append("News announcement created in correct project")

    # CRITERION 2: Title Match (25 pts)
    actual_title = result.get("title", "")
    norm_actual_title = _norm(actual_title)
    norm_expected_title = _norm(expected_title)
    
    if norm_actual_title == norm_expected_title:
        score += 25
        feedback_parts.append("Title matches exactly")
    elif "security compliance" in norm_actual_title and "q4" in norm_actual_title:
        score += 15
        feedback_parts.append(f"Title contains key phrases (partial credit). Got: '{actual_title}'")
    else:
        feedback_parts.append(f"Title incorrect. Expected '{expected_title}', got '{actual_title}'")

    # CRITERION 3: Summary Match (25 pts)
    actual_summary = result.get("summary", "")
    norm_actual_summary = _norm(actual_summary)
    norm_expected_summary = _norm(expected_summary)

    if norm_actual_summary == norm_expected_summary:
        score += 25
        feedback_parts.append("Summary matches exactly")
    elif "security training" in norm_actual_summary and "authentication" in norm_actual_summary:
        score += 15
        feedback_parts.append("Summary contains key phrases (partial credit)")
    else:
        feedback_parts.append(f"Summary incorrect. Got: '{actual_summary}'")

    # CRITERION 4: Description Content (25 pts)
    actual_description = _norm(result.get("description", ""))
    keywords_found = 0
    
    for kw in description_keywords:
        if _norm(kw) in actual_description:
            keywords_found += 1
            
    if keywords_found == 3:
        score += 25
        feedback_parts.append("Description contains all 3 required points")
    elif keywords_found > 0:
        partial_points = int(25 * (keywords_found / 3))
        score += partial_points
        feedback_parts.append(f"Description contains {keywords_found}/3 required points")
    else:
        feedback_parts.append("Description missing key requirements")

    # Final result
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }