#!/usr/bin/env python3
"""
Verifier for configure_shared_workspace task.

Verifies:
1. Group 'creative_team' creation (10 pts)
2. Users 'jordan' and 'alex' added to group (20 pts)
3. Directory '/home/acmecorp/campaign_2026' creation (10 pts)
4. Directory ownership (acmecorp:creative_team) (10 pts)
5. Directory base permissions (rwx for group, none for others) (20 pts)
6. SetGID bit enabled and functional inheritance (30 pts)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_shared_workspace(traj, env_info, task_info):
    """
    Verify the shared workspace configuration.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Group Existence (10 pts)
    if result.get('group_exists', False):
        score += 10
        feedback_parts.append("Group 'creative_team' created")
    else:
        feedback_parts.append("Group 'creative_team' NOT found")

    # 2. Membership (20 pts)
    if result.get('membership_correct', False):
        score += 20
        feedback_parts.append("Users added to group correctly")
    else:
        missing = result.get('missing_members', [])
        feedback_parts.append(f"Users missing from group: {missing}")
        # Partial credit: if group exists but members missing, 0 pts for this section is fair as it's binary

    # 3. Directory Existence (10 pts)
    if result.get('directory_exists', False):
        score += 10
        feedback_parts.append("Directory created")
    else:
        feedback_parts.append("Directory '/home/acmecorp/campaign_2026' NOT found")
        # Critical failure for subsequent checks
        return {
            "passed": False, 
            "score": score, 
            "feedback": " | ".join(feedback_parts)
        }

    # 4. Ownership (10 pts)
    # Expect: Owner=acmecorp (or root, though acmecorp is better), Group=creative_team
    owner_group = result.get('directory_owner_group', '')
    owner_user = result.get('directory_owner_user', '')
    
    if owner_group == 'creative_team':
        score += 10
        feedback_parts.append("Directory group ownership correct")
    else:
        feedback_parts.append(f"Wrong directory group: {owner_group}")

    # 5. Base Permissions (20 pts)
    # We want 770 or 2770. Group must be rwx (7). Others must be --- (0).
    octal = str(result.get('directory_perm_octal', '0000'))
    # Extract last 3 digits
    base_octal = octal[-3:]
    group_digit = int(base_octal[1])
    other_digit = int(base_octal[2])

    perm_score = 0
    if group_digit == 7:
        perm_score += 10
        feedback_parts.append("Group permissions RWX")
    else:
        feedback_parts.append(f"Group permissions incorrect ({group_digit})")
        
    if other_digit == 0:
        perm_score += 10
        feedback_parts.append("Other permissions restricted")
    else:
        # Penalize less severely if they left it readable, but task asked for NO access
        feedback_parts.append(f"Others have access ({other_digit})")
    
    score += perm_score

    # 6. SetGID / Inheritance (30 pts)
    # The functional test is the gold standard. 
    # If the SetGID bit is set, inheritance SHOULD work, but we check the functional result if available.
    setgid_set = result.get('setgid_bit_set', False)
    inheritance_works = result.get('inheritance_functional_test', False)
    
    if inheritance_works:
        score += 30
        feedback_parts.append("SetGID inheritance confirmed working")
    elif setgid_set:
        # Bit is set but maybe something else blocked the functional test? Give partial credit.
        score += 25
        feedback_parts.append("SetGID bit set (functional test failed or skipped)")
    else:
        feedback_parts.append("SetGID bit NOT set (files won't inherit group)")

    # Final Pass Calculation
    # Pass if Score >= 80 (Allowing small mistakes like 'Others' having read access, but requiring Group/SetGID success)
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": result
    }