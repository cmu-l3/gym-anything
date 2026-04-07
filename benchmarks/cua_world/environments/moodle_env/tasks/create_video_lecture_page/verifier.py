#!/usr/bin/env python3
"""Verifier for Create Video Lecture Page task in Moodle."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_create_video_lecture_page(traj, env_info, task_info):
    """
    Verify creation of a Moodle Page with embedded video.

    Scoring (100 points):
    - Page resource exists in BIO101 (30 pts)
    - Resource name matches 'Supplementary Video: Cell Theory' (20 pts)
    - Content contains correct video ID/URL (30 pts)
    - Content contains instructional text (20 pts)
    
    Penalties:
    - 0 points total if a URL resource was created instead of a Page resource (wrong type).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_name', 'Supplementary Video: Cell Theory')
    video_id = metadata.get('video_id', '8IlzKri08kk')
    expected_text = metadata.get('expected_text', 'Watch this video to understand the basics of cell theory')

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/create_video_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {}

        page_found = result.get('page_found', False)
        wrong_resource_type = result.get('wrong_resource_type', False)
        page_name = result.get('page_name', '')
        page_content = result.get('page_content', '')

        # Check for Wrong Resource Type (Automatic Failure of that component)
        if wrong_resource_type and not page_found:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Incorrect resource type created. You created a 'URL' resource, but the task required a 'Page' resource.",
                "subscores": {"correct_type": False}
            }

        # Criterion 1: Page resource exists (30 pts)
        if page_found:
            score += 30
            subscores["page_created"] = True
            feedback_parts.append("Page resource created successfully")
        else:
            feedback_parts.append("No Page resource found")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts),
                "subscores": {"page_created": False}
            }

        # Criterion 2: Name matches (20 pts)
        if expected_name.lower().strip() in page_name.lower().strip():
            score += 20
            subscores["name_correct"] = True
            feedback_parts.append("Resource name correct")
        else:
            subscores["name_correct"] = False
            feedback_parts.append(f"Name mismatch: expected '{expected_name}', got '{page_name}'")

        # Criterion 3: Video content present (30 pts)
        # Check for video ID or full URL
        if video_id in page_content:
            score += 30
            subscores["video_present"] = True
            feedback_parts.append("Video embedded correctly")
        else:
            subscores["video_present"] = False
            feedback_parts.append(f"Video content missing or incorrect ID (checked for {video_id})")

        # Criterion 4: Instructional text present (20 pts)
        # Loose check for key phrase
        if "Watch this video" in page_content or "basics of cell theory" in page_content:
            score += 20
            subscores["text_present"] = True
            feedback_parts.append("Instructional text found")
        else:
            subscores["text_present"] = False
            feedback_parts.append("Instructional text missing")

        passed = score >= 80

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except json.JSONDecodeError:
        return {"passed": False, "score": 0, "feedback": "Invalid JSON result"}
    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}