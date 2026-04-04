#!/usr/bin/env python3
"""Verifier for Post Forum Announcement task in Moodle."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_post_forum_announcement(traj, env_info, task_info):
    """
    Verify that a welcome announcement was posted in BIO101's Announcements forum.

    Scoring (100 points):
    - Criterion 1: New discussion created in announcements forum (20 points) - CRITICAL
    - Criterion 2: Post in correct course / BIO101 (15 points) - wrong-target check
    - Criterion 3: Subject matches expected title (25 points)
    - Criterion 4: Message contains relevant content keywords (25 points)
    - Criterion 5: Post was newly created / discussion count increased (15 points)

    Pass threshold: 60 points (must have new post + correct course)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/post_forum_announcement_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {}

        # CRITICAL: Wrong course check
        post_forum_course = str(result.get('post_forum_course', ''))
        expected_course_id = str(result.get('course_id', ''))
        if post_forum_course and expected_course_id and post_forum_course != expected_course_id:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"CRITICAL: Post in wrong course (course_id={post_forum_course}, expected={expected_course_id})"
            }

        # Criterion 1: New discussion/post found (20 points)
        post_found = result.get('post_found', False)
        if post_found:
            score += 20
            subscores["post_found"] = True
            feedback_parts.append("Post found in announcements forum")
        else:
            subscores["post_found"] = False
            feedback_parts.append("No post found in announcements forum")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts),
                "subscores": {"post_found": False, "correct_course": False,
                              "correct_subject": False, "content_keywords": False,
                              "newly_created": False}
            }

        # Criterion 2: Correct course (15 points)
        if post_forum_course == expected_course_id:
            score += 15
            subscores["correct_course"] = True
            feedback_parts.append("Post in correct course (BIO101)")
        else:
            subscores["correct_course"] = False
            feedback_parts.append("Post course mismatch")

        # Criterion 3: Subject matches (25 points)
        subject = result.get('post_subject', '').lower().strip()
        expected_subject = metadata.get('expected_subject', '').lower().strip()

        # Check for key terms in subject
        has_welcome = 'welcome' in subject
        has_biology = 'biology' in subject
        has_spring = 'spring' in subject or '2026' in subject

        if has_welcome and has_biology:
            score += 25
            subscores["correct_subject"] = True
            feedback_parts.append("Subject matches expected title")
        elif has_welcome or has_biology:
            score += 12
            subscores["correct_subject"] = False
            feedback_parts.append(f"Subject partially matches: '{result.get('post_subject', '')}'")
        else:
            subscores["correct_subject"] = False
            feedback_parts.append(f"Subject mismatch: '{result.get('post_subject', '')}'")

        # Criterion 4: Message content keywords (25 points)
        # Check for key content terms from the expected message
        keyword_count = 0
        keywords_found = []
        if result.get('has_bio101_mention', False):
            keyword_count += 1
            keywords_found.append("biology")
        if result.get('has_cell_biology_mention', False):
            keyword_count += 1
            keywords_found.append("cell biology")
        if result.get('has_syllabus_mention', False):
            keyword_count += 1
            keywords_found.append("syllabus")

        # Also check message preview for additional keywords
        msg_preview = result.get('post_message_preview', '').lower()
        if 'office hours' in msg_preview:
            keyword_count += 1
            keywords_found.append("office hours")
        if 'genetics' in msg_preview or 'ecology' in msg_preview:
            keyword_count += 1
            keywords_found.append("course topics")

        if keyword_count >= 3:
            score += 25
            subscores["content_keywords"] = True
            feedback_parts.append(f"Message content rich ({', '.join(keywords_found)})")
        elif keyword_count >= 1:
            score += int(25 * keyword_count / 3)
            subscores["content_keywords"] = False
            feedback_parts.append(f"Message has some keywords ({', '.join(keywords_found)})")
        else:
            subscores["content_keywords"] = False
            feedback_parts.append("Message lacks expected content keywords")

        # Criterion 5: Discussion count increased (15 points)
        initial_count = int(result.get('initial_discussion_count', 0))
        current_count = int(result.get('current_discussion_count', 0))
        if current_count > initial_count:
            score += 15
            subscores["newly_created"] = True
            feedback_parts.append(f"New discussion added (count: {initial_count} -> {current_count})")
        else:
            subscores["newly_created"] = False
            feedback_parts.append("Discussion count unchanged - may be pre-existing")

        passed = (score >= 60
                  and subscores.get("post_found", False)
                  and subscores.get("correct_course", False))

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found - export may have failed"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Invalid JSON in result file: {str(e)}"}
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
