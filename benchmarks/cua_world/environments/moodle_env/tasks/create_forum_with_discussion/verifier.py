#!/usr/bin/env python3
"""Verifier for Create Forum with Discussion task in Moodle."""

import json
import tempfile
import os
import logging
import time

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_create_forum_with_discussion(traj, env_info, task_info):
    """
    Verify that a forum was created with correct settings and an initial discussion topic.

    Scoring (100 points):
    - Forum exists in BIO101 and was newly created (20 pts)
    - Forum name matches 'Clinical Case Study Discussions' (15 pts)
    - Forum type is 'general' (Standard forum) (15 pts)
    - Subscription mode is 'forced' (15 pts)
    - Discussion topic exists with correct subject (20 pts)
    - Discussion post message contains key clinical terms (15 pts)

    Pass threshold: 50 points (must at least create the forum correctly)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/create_forum_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {}
        
        # Extract data
        initial_count = int(result.get('initial_forum_count', 0))
        current_count = int(result.get('current_forum_count', 0))
        task_start_time = int(result.get('task_start_time', 0))
        
        forum_found = result.get('forum_found', False)
        forum = result.get('forum', {})
        
        disc_found = result.get('discussion_found', False)
        discussion = result.get('discussion', {})

        # Criterion 1: Forum exists and created during task (20 pts)
        newly_created = current_count > initial_count
        # Also check timemodified vs task start time if available
        forum_time = int(forum.get('timemodified', 0))
        created_during_task = forum_time >= task_start_time
        
        if forum_found:
            if newly_created or created_during_task:
                score += 20
                subscores["forum_created"] = True
                feedback_parts.append("Forum created successfully")
            else:
                score += 10
                subscores["forum_created"] = False
                feedback_parts.append("Forum found but pre-existed (count didn't increase)")
        else:
            feedback_parts.append("Forum NOT found in BIO101")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts),
                "subscores": {"forum_created": False}
            }

        # Criterion 2: Forum name matches (15 pts)
        expected_name = "Clinical Case Study Discussions"
        actual_name = forum.get('name', '')
        if expected_name.lower() in actual_name.lower():
            score += 15
            subscores["name_correct"] = True
            feedback_parts.append("Forum name correct")
        else:
            subscores["name_correct"] = False
            feedback_parts.append(f"Name mismatch: got '{actual_name}'")

        # Criterion 3: Forum type (15 pts)
        # 'general' is the database value for "Standard forum for general use"
        actual_type = forum.get('type', '')
        if actual_type == 'general':
            score += 15
            subscores["type_correct"] = True
            feedback_parts.append("Forum type correct (Standard)")
        else:
            subscores["type_correct"] = False
            feedback_parts.append(f"Type mismatch: got '{actual_type}' (expected 'general')")

        # Criterion 4: Subscription mode (15 pts)
        # 0=optional, 1=forced, 2=auto, 3=disabled
        # DB returns string usually
        actual_sub = str(forum.get('forcesubscribe', ''))
        if actual_sub == '1':
            score += 15
            subscores["subscription_correct"] = True
            feedback_parts.append("Subscription forced")
        else:
            subscores["subscription_correct"] = False
            feedback_parts.append(f"Subscription incorrect: got '{actual_sub}' (expected 1/Forced)")

        # Criterion 5: Discussion topic exists (20 pts)
        if disc_found:
            score += 20
            subscores["discussion_created"] = True
            feedback_parts.append("Discussion topic created")
        else:
            subscores["discussion_created"] = False
            feedback_parts.append("No discussion topic found")

        # Criterion 6: Discussion content (15 pts)
        # Keywords: fatigue, mitochondrial, lactic acidosis
        message = discussion.get('message', '').lower()
        keywords = ["fatigue", "mitochondrial"]
        if disc_found:
            if all(k in message for k in keywords):
                score += 15
                subscores["content_correct"] = True
                feedback_parts.append("Discussion content verified")
            else:
                subscores["content_correct"] = False
                feedback_parts.append("Discussion content missing keywords")
        else:
            subscores["content_correct"] = False

        # Pass threshold: 50 points
        passed = score >= 50

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
        return {"passed": False, "score": 0, "feedback": f"Error: {str(e)}"}