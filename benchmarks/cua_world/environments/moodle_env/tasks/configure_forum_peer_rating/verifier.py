#!/usr/bin/env python3
"""Verifier for Configure Forum Peer Rating task in Moodle."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_configure_forum_peer_rating(traj, env_info, task_info):
    """
    Verify that the forum was created and permissions were configured correctly.

    Scoring (100 points):
    - Forum exists in BIO101 (20 pts)
    - Rating aggregation set to 'Average of ratings' (15 pts)
    - Scale set to 5 (15 pts)
    - Permission 'mod/forum:rate' allowed for Student (40 pts)
    - Permission override is context-specific (10 pts)

    Pass threshold: 60 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/configure_forum_peer_rating_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {}

        # 1. Forum Exists (20 pts)
        if result.get('forum_found', False):
            score += 20
            subscores['forum_created'] = True
            feedback_parts.append("Forum created")
        else:
            feedback_parts.append("Forum 'Nature vs Nurture Debate' not found")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts),
                "subscores": {"forum_created": False}
            }

        # 2. Rating Aggregation (15 pts)
        # assessed: 0=None, 1=Average, 2=Count, 3=Max, 4=Min, 5=Sum
        agg_type = int(result.get('aggregate_type', 0))
        if agg_type == 1:
            score += 15
            subscores['agg_type'] = True
            feedback_parts.append("Aggregation: Average")
        else:
            subscores['agg_type'] = False
            feedback_parts.append(f"Aggregation mismatch (got {agg_type}, expected 1/Average)")

        # 3. Scale (15 pts)
        # scale: positive integer = max grade, negative = scale id
        scale = int(result.get('scale', 0))
        if scale == 5:
            score += 15
            subscores['scale'] = True
            feedback_parts.append("Scale: 5 points")
        else:
            subscores['scale'] = False
            feedback_parts.append(f"Scale mismatch (got {scale}, expected 5)")

        # 4. Permission Override (40 pts)
        if result.get('permission_overridden', False):
            score += 40
            subscores['permission'] = True
            feedback_parts.append("Student rating permission enabled")
        else:
            subscores['permission'] = False
            feedback_parts.append("Student rating permission NOT enabled")

        # 5. Context Specificity (10 pts)
        # contextlevel: 70 = MODULE (Activity)
        context_level = int(result.get('context_level', 0))
        if result.get('permission_overridden', False) and context_level == 70:
            score += 10
            subscores['context'] = True
            feedback_parts.append("Override applied at Activity level")
        elif result.get('permission_overridden', False):
             feedback_parts.append(f"Override context level: {context_level} (expected 70/Module)")

        # Anti-gaming check
        if not result.get('newly_created', False):
            feedback_parts.append("Note: Forum timestamp predates task start (might be pre-existing)")
            # We don't fail immediately but flag it in feedback

        passed = score >= 60

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
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}