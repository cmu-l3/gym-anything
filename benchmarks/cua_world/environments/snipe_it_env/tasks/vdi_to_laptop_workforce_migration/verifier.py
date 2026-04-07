#!/usr/bin/env python3
"""
Verifier for vdi_to_laptop_workforce_migration task.

Verification Strategy: Database queries processed via export_result.sh.
Points:
  C1: All 3 Thin Clients checked in (20 pts)
  C2: All 3 Thin Clients status changed to "Retired" (15 pts)
  C3: Laptops correctly checked out to the 3 users (25 pts)
  C4: Jabra Evolve2 65 headset assigned to the 3 users (25 pts)
  C5: User locations updated to "Remote/WFH" (15 pts)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_vdi_migration(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/vdi_migration_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    users = result.get('users', {})
    tcs = result.get('thin_clients', {})
    laps = result.get('laptops', {})
    headset_assignments = result.get('headset_assigned_users', [])
    retired_id = str(result.get('retired_status_id', ''))
    remote_loc_id = str(result.get('remote_loc_id', ''))

    expected_usernames = ["aadams", "bbaker", "cclark"]
    expected_tc_tags = ["TC-001", "TC-002", "TC-003"]
    expected_lap_tags = ["LAP-WFH-001", "LAP-WFH-002", "LAP-WFH-003"]

    user_ids = []
    for uname in expected_usernames:
        if uname in users:
            user_ids.append(str(users[uname]['id']))

    if not user_ids:
        return {"passed": False, "score": 0, "feedback": "System failure: Expected users not found in DB."}

    # -- C1: Thin Clients Checked In (20 pts)
    tc_checked_in = 0
    for tag in expected_tc_tags:
        if tag in tcs:
            assigned = str(tcs[tag].get('assigned_to', ''))
            # When NULL in DB, bash might export it as 'NULL' string, empty, or 'None'
            if assigned in ['NULL', '', 'None']:
                tc_checked_in += 1

    if tc_checked_in == len(expected_tc_tags):
        score += 20
        feedback_parts.append("C1: All Thin Clients successfully checked in (+20)")
    else:
        feedback_parts.append(f"C1: {tc_checked_in}/3 Thin Clients checked in (+0)")

    # -- C2: Thin Clients Retired (15 pts)
    tc_retired = 0
    for tag in expected_tc_tags:
        if tag in tcs:
            if str(tcs[tag].get('status_id', '')) == retired_id and retired_id != "":
                tc_retired += 1

    if tc_retired == len(expected_tc_tags):
        score += 15
        feedback_parts.append("C2: All Thin Clients marked as Retired (+15)")
    elif tc_retired > 0:
        partial = int(15 * (tc_retired / len(expected_tc_tags)))
        score += partial
        feedback_parts.append(f"C2: {tc_retired}/3 Thin Clients marked Retired (+{partial})")
    else:
        feedback_parts.append("C2: No Thin Clients marked as Retired (+0)")

    # -- C3: Laptops Checked Out (25 pts)
    lap_assignments = []
    for tag in expected_lap_tags:
        if tag in laps:
            assigned = str(laps[tag].get('assigned_to', ''))
            if assigned in user_ids:
                lap_assignments.append(assigned)
    
    lap_unique_users = len(set(lap_assignments))

    if lap_unique_users == len(expected_usernames):
        score += 25
        feedback_parts.append("C3: Laptops correctly checked out to all 3 users (+25)")
    elif lap_unique_users > 0:
        partial = int(25 * (lap_unique_users / len(expected_usernames)))
        score += partial
        feedback_parts.append(f"C3: {lap_unique_users}/3 users received a laptop (+{partial})")
    else:
        feedback_parts.append("C3: No laptops checked out to correct users (+0)")

    # -- C4: Headsets Checked Out (25 pts)
    headset_correct = 0
    for uid in user_ids:
        if uid in headset_assignments:
            headset_correct += 1

    if headset_correct == len(expected_usernames):
        score += 25
        feedback_parts.append("C4: Jabra Headsets correctly checked out to all 3 users (+25)")
    elif headset_correct > 0:
        partial = int(25 * (headset_correct / len(expected_usernames)))
        score += partial
        feedback_parts.append(f"C4: {headset_correct}/3 users received a headset (+{partial})")
    else:
        feedback_parts.append("C4: No headsets checked out to target users (+0)")

    # -- C5: User Locations Updated (15 pts)
    loc_correct = 0
    for uname in expected_usernames:
        if uname in users:
            if str(users[uname].get('location_id', '')) == remote_loc_id and remote_loc_id != "":
                loc_correct += 1
    
    if loc_correct == len(expected_usernames):
        score += 15
        feedback_parts.append("C5: All user locations updated to Remote/WFH (+15)")
    elif loc_correct > 0:
        partial = int(15 * (loc_correct / len(expected_usernames)))
        score += partial
        feedback_parts.append(f"C5: {loc_correct}/3 users had locations updated (+{partial})")
    else:
        feedback_parts.append("C5: User locations not updated (+0)")

    # -- Anti-gaming: DO NOTHING CHECK
    if tc_checked_in == 0 and lap_unique_users == 0 and loc_correct == 0 and tc_retired == 0 and headset_correct == 0:
        return {"passed": False, "score": 0, "feedback": "Do nothing detected. No workflow actions observed."}

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }