#!/usr/bin/env python3
"""
Verifier for user_group_dashboard_sharing task.

Scoring Criteria (100 points total):
1. User Group Created (25 pts): Name contains "Kenema", created during task.
2. User Group Membership (10 pts): "admin" user is a member.
3. Dashboard Created (25 pts): Name contains "Kenema", created during task.
4. Dashboard Items (10 pts): At least 1 item on dashboard.
5. Sharing Configured (20 pts): Dashboard is shared with the specific User Group.
6. Access Level (10 pts): Sharing is View-Only (no Edit).

Pass Threshold: 60 points
Mandatory: User Group AND Dashboard must both exist.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_user_group_dashboard_sharing(traj, env_info, task_info):
    """Verify DHIS2 user group creation and dashboard sharing configuration."""
    
    # 1. Retrieve Result JSON
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Verifier failed: copy_from_env unavailable"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/user_group_dashboard_sharing_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Evaluate Criteria
    score = 0
    feedback_parts = []
    
    # Data extraction
    ug = result.get("user_group")
    db = result.get("dashboard")
    sharing_correct = result.get("sharing_correct", False)
    sharing_details = result.get("sharing_details", "No sharing found")

    # Criterion 1: User Group Created (25 pts)
    ug_exists = False
    if ug and "Kenema" in ug.get("name", ""):
        score += 25
        ug_exists = True
        feedback_parts.append("User Group created (+25)")
    else:
        feedback_parts.append("User Group 'Kenema District Health Team' NOT found")

    # Criterion 2: Admin in Group (10 pts)
    if ug_exists and ug.get("has_admin"):
        score += 10
        feedback_parts.append("Admin added to group (+10)")
    elif ug_exists:
        feedback_parts.append("Admin user NOT found in group")

    # Criterion 3: Dashboard Created (25 pts)
    db_exists = False
    if db and "Kenema" in db.get("name", ""):
        score += 25
        db_exists = True
        feedback_parts.append("Dashboard created (+25)")
    else:
        feedback_parts.append("Dashboard 'Kenema Health Overview' NOT found")

    # Criterion 4: Dashboard Content (10 pts)
    if db_exists:
        item_count = db.get("item_count", 0)
        if item_count > 0:
            score += 10
            feedback_parts.append(f"Dashboard has {item_count} items (+10)")
        else:
            feedback_parts.append("Dashboard is empty")

    # Criterion 5 & 6: Sharing (20 + 10 pts)
    # The export script logic already checked linkage between the specific found UG and DB
    if ug_exists and db_exists:
        # Check if shared at all
        # The export script sets 'sharing_correct' only if it's VIEW access.
        # We need to distinguish shared-but-wrong-access vs not-shared.
        
        if sharing_correct:
            # This means it matched and was View Only
            score += 30 # 20 for sharing + 10 for view only
            feedback_parts.append("Sharing configured correctly (View Only) (+30)")
        elif "Edit access" in sharing_details:
            score += 20 # 20 for sharing, 0 for view only
            feedback_parts.append("Sharing configured but with Edit access (expected View Only) (+20)")
        elif "Access string" in sharing_details:
             # Some other access level
             score += 20
             feedback_parts.append(f"Shared with group ({sharing_details}) (+20)")
        else:
             feedback_parts.append("Dashboard NOT shared with User Group")
    
    # Mandatory Gate: Must have both objects to pass
    passed = (score >= 60) and ug_exists and db_exists

    if not (ug_exists and db_exists) and score >= 60:
        score = 59 # Cap score if mandatory objects missing
        feedback_parts.append("Failed mandatory criteria: User Group and Dashboard must both exist")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }