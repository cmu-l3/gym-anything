#!/usr/bin/env python3
"""
Verifier for map_cmdb_dependencies task.

Verifies:
1. Existence of 'Payroll Service' CI.
2. Existence of 'Payroll-DB-01' CI.
3. Existence of a relationship where Service 'Depends On' Server.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_map_cmdb_dependencies(traj, env_info, task_info):
    """
    Verify that the agent created the correct CIs and relationships in the CMDB.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata expectations
    metadata = task_info.get('metadata', {})
    expected_service_name = metadata.get('ci_service_name', 'Payroll Service')
    expected_server_name = metadata.get('ci_server_name', 'Payroll-DB-01')
    expected_rel_type = metadata.get('relationship_type', 'Depends On')

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Initialize scoring
    score = 0
    feedback = []
    
    # Extract data
    ci_data = result.get('ci_data', []) or []
    rel_data = result.get('relationship_data', []) or []
    
    # 1. Verify CIs (50 points total)
    service_ci = next((item for item in ci_data if item.get('ciname') == expected_service_name), None)
    server_ci = next((item for item in ci_data if item.get('ciname') == expected_server_name), None)

    if service_ci:
        score += 25
        feedback.append(f"✓ CI '{expected_service_name}' created.")
    else:
        feedback.append(f"✗ CI '{expected_service_name}' not found.")

    if server_ci:
        score += 25
        feedback.append(f"✓ CI '{expected_server_name}' created.")
    else:
        feedback.append(f"✗ CI '{expected_server_name}' not found.")

    # 2. Verify Relationship (50 points total)
    # Looking for: Parent=Service, Child=Server, Type~='Depends On'
    # Note: Sometimes 'Depends On' might be represented inversely depending on how the user linked it.
    # The requirement is "Payroll Service" Depends On "Payroll-DB-01".
    # In CMDB usually: Parent (Service) -- depends on --> Child (Server).
    
    relationship_found = False
    relationship_correct = False

    for rel in rel_data:
        p_name = rel.get('parent_name')
        c_name = rel.get('child_name')
        r_name = rel.get('relationshipname', '')

        # Check if these are our CIs
        if {p_name, c_name} == {expected_service_name, expected_server_name}:
            relationship_found = True
            
            # Check direction and type
            # Case A: Service -> Depends On -> Server
            if p_name == expected_service_name and c_name == expected_server_name:
                if expected_rel_type.lower() in r_name.lower():
                    relationship_correct = True
                    break
            
            # Case B: Server -> Used By -> Service (Inverse of Depends On)
            # If the user did it backwards but the semantic meaning is preserved?
            # Strict verification based on task description: "Parent: Payroll Service... Depends On... Child: Payroll-DB-01"
            # So we strictly check Case A for full points, but maybe partial for existence.

    if relationship_correct:
        score += 50
        feedback.append(f"✓ Relationship '{expected_service_name} {expected_rel_type} {expected_server_name}' established.")
    elif relationship_found:
        score += 20
        feedback.append(f"⚠ Relationship exists between CIs, but type or direction is incorrect.")
    else:
        feedback.append(f"✗ No relationship found between the CIs.")

    # 3. VLM Trajectory Check (Tie-breaker / Confirmation)
    # If score is borderline or high, verify they actually visited CMDB
    if score >= 50:
        frames = sample_trajectory_frames(traj, n=4)
        final_img = get_final_screenshot(traj)
        images = frames + ([final_img] if final_img else [])
        
        vlm_prompt = "Does the user navigate to a CMDB or Relationship Map view in the screenshots? Do you see a diagram connecting 'Payroll Service' and 'Payroll-DB-01'?"
        
        try:
            vlm_res = query_vlm(images=images, prompt=vlm_prompt)
            if vlm_res.get('success'):
                # We don't modify score heavily based on VLM here as DB is ground truth,
                # but we can use it to invalidate "magic" API-only solutions if we wanted strict UI usage.
                # For now, we just append observation.
                feedback.append(f"Visual verification: {vlm_res.get('answer', 'Analyzed')}")
        except Exception:
            pass

    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }