#!/usr/bin/env python3
"""Verifier for Auto Generate Course Groups task in Moodle."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_auto_generate_course_groups(traj, env_info, task_info):
    """
    Verify that student groups were auto-generated and assigned to a grouping.

    Scoring (100 points):
    - Criterion 1: Grouping "Lab Partnerships" exists (20 points)
    - Criterion 2: Multiple groups created with "Lab Pair %" name (20 points)
    - Criterion 3: Groups are linked to the Grouping (20 points)
    - Criterion 4: Membership distribution is correct (approx 2 per group) (20 points)
    - Criterion 5: Random/Bulk allocation used (inferred from timestamps/counts) (20 points)

    Pass threshold: 60 points (Must have created groups and grouping)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/auto_generate_groups_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {}

        # Data extraction
        grouping_exists = result.get('grouping_exists', False)
        group_count = int(result.get('lab_pair_groups_count', 0))
        linked_count = int(result.get('linked_groups_count', 0))
        groups_with_two = int(result.get('groups_with_exactly_two', 0))
        created_during_task = result.get('created_during_task', False)

        # Criterion 1: Grouping exists (20 pts)
        if grouping_exists:
            score += 20
            subscores['grouping_exists'] = True
            feedback_parts.append("Grouping 'Lab Partnerships' created")
        else:
            subscores['grouping_exists'] = False
            feedback_parts.append("Grouping 'Lab Partnerships' NOT found")

        # Criterion 2: Groups created (20 pts)
        # We expect at least 3 groups if there are 6+ students
        if group_count >= 2:
            score += 20
            subscores['groups_created'] = True
            feedback_parts.append(f"{group_count} 'Lab Pair' groups created")
        elif group_count == 1:
            score += 5  # Participation points, but clearly not auto-generated properly for multiple students
            subscores['groups_created'] = False
            feedback_parts.append("Only 1 'Lab Pair' group found (expected multiple)")
        else:
            subscores['groups_created'] = False
            feedback_parts.append("No 'Lab Pair' groups found")

        # Criterion 3: Groups linked to grouping (20 pts)
        if linked_count >= 2 and linked_count == group_count:
            score += 20
            subscores['groups_linked'] = True
            feedback_parts.append("All groups correctly linked to grouping")
        elif linked_count > 0:
            score += 10
            subscores['groups_linked'] = False
            feedback_parts.append(f"Only {linked_count}/{group_count} groups linked to grouping")
        else:
            subscores['groups_linked'] = False
            feedback_parts.append("Groups NOT linked to grouping")

        # Criterion 4: Membership distribution (20 pts)
        # Verify that most groups have exactly 2 members
        if group_count > 0:
            ratio_perfect = groups_with_two / group_count
            if ratio_perfect >= 0.7:  # 70% of groups have exactly 2 members
                score += 20
                subscores['membership_correct'] = True
                feedback_parts.append(f"Membership distribution correct ({groups_with_two} groups have 2 members)")
            elif ratio_perfect > 0:
                score += 10
                subscores['membership_correct'] = False
                feedback_parts.append(f"Membership distribution partial ({groups_with_two}/{group_count} groups have 2 members)")
            else:
                subscores['membership_correct'] = False
                feedback_parts.append("Membership distribution incorrect (groups do not have 2 members)")
        else:
            subscores['membership_correct'] = False

        # Criterion 5: Anti-gaming / Process check (20 pts)
        if created_during_task:
            if group_count >= 3:
                # High likelihood of using auto-create tool
                score += 20
                subscores['process_valid'] = True
                feedback_parts.append("Bulk creation detected (valid timestamp & count)")
            elif group_count > 0:
                score += 10
                subscores['process_valid'] = False
                feedback_parts.append("Created during task, but low group count")
        else:
            subscores['process_valid'] = False
            feedback_parts.append("Grouping/Groups appeared to exist before task started")

        # Pass determination
        passed = (score >= 60 and subscores.get('grouping_exists') and subscores.get('groups_created'))

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found - export_result.sh failed"}
    except json.JSONDecodeError:
        return {"passed": False, "score": 0, "feedback": "Invalid JSON in result file"}
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}