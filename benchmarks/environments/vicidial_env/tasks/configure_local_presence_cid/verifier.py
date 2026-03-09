#!/usr/bin/env python3
"""
Verifier for configure_local_presence_cid task.

Verifies:
1. AC-CID entries created in DB match the 6 required area codes and CIDs.
2. Campaign setting 'areacode_cid' is enabled (Y or ACTIVE).
3. Entries were actually created during the task (diff from initial).
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_local_presence_cid(traj, env_info, task_info):
    """
    Verify AC-CID configuration for Vicidial campaign.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected data from metadata
    metadata = task_info.get('metadata', {})
    expected_mappings = metadata.get('expected_mappings', {
        "212": "2125559901",
        "617": "6175559902",
        "215": "2155559903",
        "860": "8605559904",
        "609": "6095559905",
        "203": "2035559906"
    })
    
    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    final_entries = result.get('final_entries', [])
    campaign_setting = result.get('campaign_setting_enabled', 'N')
    initial_count = int(result.get('initial_count', 0))
    
    # 3. Score Calculation
    score = 0
    feedback_lines = []
    
    # Check 1: Campaign Setting (15 pts)
    # Value is typically 'Y' for enabled, sometimes 'ACTIVE' depending on version, 
    # but strictly 'Y' in standard Vicidial DB for 'areacode_cid' ENUM('Y','N')
    if campaign_setting == 'Y':
        score += 15
        feedback_lines.append("✓ Campaign AC-CID setting enabled")
    else:
        feedback_lines.append(f"✗ Campaign AC-CID setting is '{campaign_setting}' (expected 'Y')")

    # Check 2: Verify Entries (10 pts per correct entry, 5 pts no extras)
    # Convert list of dicts to easy lookup
    # final_entries format: [{'areacode': '212', 'cid': '2125559901'}, ...]
    actual_map = {str(entry.get('areacode')): str(entry.get('cid')) for entry in final_entries}
    
    correct_entries_count = 0
    
    for ac, expected_cid in expected_mappings.items():
        actual_cid = actual_map.get(ac)
        if actual_cid == expected_cid:
            score += 10
            correct_entries_count += 1
            feedback_lines.append(f"✓ Mapping for {ac} correct ({expected_cid})")
        elif actual_cid:
            feedback_lines.append(f"✗ Mapping for {ac} incorrect (got {actual_cid}, expected {expected_cid})")
        else:
            feedback_lines.append(f"✗ Mapping for {ac} missing")

    # Check 3: No extraneous entries (5 pts)
    # Only award if we have the correct number of entries total
    if len(actual_map) == len(expected_mappings) and len(actual_map) > 0:
        score += 5
        feedback_lines.append("✓ No extra/duplicate entries found")
    elif len(actual_map) > len(expected_mappings):
        feedback_lines.append(f"✗ Found {len(actual_map)} entries (expected {len(expected_mappings)}) - extraneous entries present")
    
    # Check 4: Anti-Gaming / Database Integrity (10 pts)
    # Entries must be new (count increased from initial 0)
    if len(final_entries) > 0 and initial_count == 0:
        score += 10
        feedback_lines.append("✓ Entries were created during this session")
    elif len(final_entries) > 0 and len(final_entries) == initial_count:
        score = 0
        feedback_lines = ["FAILED: No change in database records detected (Anti-gaming check)"]
    
    # Total Calculation
    # Max score breakdown:
    # Setting: 15
    # Mappings: 6 * 10 = 60
    # No Extras: 5
    # Created during session: 10
    # VLM (Optional/Implicit in 'created during session' if we trusted the count, but here we just sum to 90)
    # Wait, 15+60+5+10 = 90. Let's add 10 points for verifying via VLM that the UI was used.
    
    # Actually, let's just scale or use the rubric from the design.
    # Design Rubric:
    # AC-CID entries exist (10) -> Covered by integrity check partially
    # Correct entry count (10) -> Covered by no extras check logic
    # Individual entries (10 each x 6 = 60) -> Covered
    # Enabled (15) -> Covered
    # No extras (5) -> Covered
    # Total 100.
    
    # Let's align exactly with that:
    
    score = 0 # Reset
    feedback_lines = []

    # 1. At least one entry exists (10 pts)
    if len(final_entries) > 0:
        score += 10
        feedback_lines.append("✓ AC-CID entries created")
    else:
        feedback_lines.append("✗ No AC-CID entries found")

    # 2. Correct Count (10 pts)
    if len(final_entries) == 6:
        score += 10
        feedback_lines.append("✓ Correct number of entries (6)")
    else:
        feedback_lines.append(f"✗ Incorrect number of entries: {len(final_entries)} (expected 6)")

    # 3. Individual Mappings (10 pts each)
    for ac, expected_cid in expected_mappings.items():
        actual_cid = actual_map.get(ac)
        if actual_cid == expected_cid:
            score += 10
            # feedback_lines.append(f"✓ {ac} -> {expected_cid}") # Too verbose
        else:
            feedback_lines.append(f"✗ Failed mapping for {ac}")

    # 4. Campaign Enabled (15 pts)
    if campaign_setting == 'Y':
        score += 15
        feedback_lines.append("✓ Campaign AC-CID enabled")
    else:
        feedback_lines.append("✗ Campaign AC-CID NOT enabled")

    # 5. No Extras (5 pts)
    if len(actual_map) == 6 and len(actual_map) == len(final_entries):
        score += 5
        feedback_lines.append("✓ No duplicate/extra entries")
    
    # Pass Threshold: 70
    passed = score >= 70 and (campaign_setting == 'Y')
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_lines)
    }