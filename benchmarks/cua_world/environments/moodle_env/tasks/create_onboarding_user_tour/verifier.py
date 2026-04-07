#!/usr/bin/env python3
"""Verifier for Create Onboarding User Tour task in Moodle."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_create_onboarding_user_tour(traj, env_info, task_info):
    """
    Verify that the user tour was created with correct settings and steps.

    Criteria:
    1. Tour exists and is enabled (20 pts)
    2. Tour path match is correct (/my/%) (15 pts)
    3. Step 1 targets Timeline block with correct title (30 pts)
    4. Step 2 targets Calendar block with correct title and backdrop (35 pts)

    Pass threshold: 70 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_tour_name', 'New Student Dashboard Guide')
    expected_path = metadata.get('expected_pathmatch', '/my/%')

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/user_tour_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {}

        tour_found = result.get('tour_found', False)
        tour = result.get('tour', {})
        steps = result.get('steps', [])

        # Criterion 1: Tour exists and enabled (20 pts)
        if tour_found:
            is_enabled = str(tour.get('enabled', '0')) == '1'
            name_match = expected_name.lower() in tour.get('name', '').lower()
            
            if name_match:
                score += 10
                feedback_parts.append("Tour name matches")
            else:
                feedback_parts.append(f"Tour found but name mismatch ('{tour.get('name')}')")

            if is_enabled:
                score += 10
                feedback_parts.append("Tour is enabled")
            else:
                feedback_parts.append("Tour is disabled")
        else:
            feedback_parts.append("Tour not found")
            return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

        # Criterion 2: Path match (15 pts)
        path = tour.get('pathmatch', '')
        if path == expected_path:
            score += 15
            feedback_parts.append(f"URL match correct ({path})")
        else:
            feedback_parts.append(f"URL match incorrect: expected '{expected_path}', got '{path}'")

        # Check steps
        if len(steps) >= 2:
            feedback_parts.append(f"Found {len(steps)} steps")
            
            # Criterion 3: Step 1 (30 pts)
            # Target should be block 'timeline'
            # Title should match 'Track Your Deadlines'
            s1 = steps[0]
            s1_config = {}
            try:
                s1_config = json.loads(s1.get('configdata', '{}'))
            except:
                pass

            # Check target type (1 = block) and value
            s1_target_type = int(s1.get('targettype', -1))
            s1_target_value = s1.get('targetvalue', '').lower()
            
            if s1_target_type == 1 and ('timeline' in s1_target_value):
                score += 15
                feedback_parts.append("Step 1 target correct (Timeline block)")
            else:
                feedback_parts.append(f"Step 1 target incorrect (Type: {s1_target_type}, Value: {s1_target_value})")

            if "track your deadlines" in s1.get('title', '').lower():
                score += 15
                feedback_parts.append("Step 1 title correct")
            else:
                feedback_parts.append(f"Step 1 title mismatch ('{s1.get('title')}')")

            # Criterion 4: Step 2 (35 pts)
            # Target should be block 'calendar_month'
            # Title 'Important Events'
            # Backdrop enabled
            s2 = steps[1]
            s2_config = {}
            try:
                s2_config = json.loads(s2.get('configdata', '{}'))
            except:
                pass

            s2_target_type = int(s2.get('targettype', -1))
            s2_target_value = s2.get('targetvalue', '').lower()

            if s2_target_type == 1 and ('calendar' in s2_target_value):
                score += 15
                feedback_parts.append("Step 2 target correct (Calendar block)")
            else:
                feedback_parts.append(f"Step 2 target incorrect (Type: {s2_target_type}, Value: {s2_target_value})")

            if "important events" in s2.get('title', '').lower():
                score += 10
                feedback_parts.append("Step 2 title correct")
            else:
                feedback_parts.append(f"Step 2 title mismatch ('{s2.get('title')}')")

            # Check backdrop in configdata (often stored as "backdrop":true or "backdrop":1)
            # Moodle configdata structure depends on settings, but usually it's a key in the JSON
            # Note: In db configdata, backdrop might be stored as "backdrop":1
            backdrop = s2_config.get('backdrop', False)
            if backdrop:
                score += 10
                feedback_parts.append("Step 2 backdrop enabled")
            else:
                feedback_parts.append("Step 2 backdrop NOT enabled")

        else:
            feedback_parts.append(f"Insufficient steps found ({len(steps)}), expected 2")

        passed = score >= 70
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}