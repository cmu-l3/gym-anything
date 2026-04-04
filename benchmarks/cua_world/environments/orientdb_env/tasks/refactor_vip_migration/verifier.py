#!/usr/bin/env python3
"""
Verifier for refactor_vip_migration task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_refactor_vip_migration(traj, env_info, task_info):
    """
    Verifies that the database refactoring was performed correctly.
    
    Criteria:
    1. Classes Created (VIPProfiles, Managers, ManagedBy) - 20 pts
    2. Migration Source Clean (No Japanese profiles left in base class) - 20 pts
    3. Migration Target Correct (Japanese profiles moved to VIPProfiles) - 20 pts
    4. History Preserved (Edges retained on moved vertices) - 20 pts
    5. Manager Linked (New manager created and linked to VIPs) - 20 pts
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    score = 0
    feedback = []
    
    # 1. Schema Checks (20 pts)
    schema_score = 0
    if result.get('class_vip_exists'):
        schema_score += 7
    else:
        feedback.append("Missing class 'VIPProfiles'.")
        
    if result.get('class_managers_exists'):
        schema_score += 7
    else:
        feedback.append("Missing class 'Managers'.")
        
    if result.get('class_managedby_exists'):
        schema_score += 6
    else:
        feedback.append("Missing class 'ManagedBy'.")
        
    # Check inheritance
    vip_super = result.get('vip_superclass', [])
    if isinstance(vip_super, str): vip_super = [vip_super]
    if 'Profiles' in vip_super:
        pass # Good
    elif result.get('class_vip_exists'):
        feedback.append("Warning: 'VIPProfiles' does not extend 'Profiles'.")
        schema_score -= 5
        
    score += max(0, schema_score)
    
    # 2. Migration Source Clean (20 pts)
    remaining = result.get('remaining_source_count', -1)
    if remaining == 0:
        score += 20
    elif remaining > 0:
        feedback.append(f"{remaining} Japanese profiles still remain in the base 'Profiles' class.")
    else:
        feedback.append("Could not verify source migration count.")
        
    # 3. Migration Target Correct (20 pts)
    vip_count = result.get('vip_count', 0)
    if vip_count >= 2: # We expect at least Yuki and Kai
        score += 20
    elif vip_count > 0:
        score += 10
        feedback.append(f"Only found {vip_count} VIP profiles (expected >= 2).")
    else:
        feedback.append("No profiles found in 'VIPProfiles' class.")
        
    # 4. History Preservation (20 pts)
    if result.get('yuki_found_in_vip'):
        edges_count = result.get('yuki_preserved_edges_count', 0)
        if edges_count > 0:
            score += 20
        else:
            feedback.append("Migrated profile 'Yuki' lost all previous edges (Friends/Reviews).")
    else:
        # If we didn't find Yuki in VIP, we can't check edges, but we already penalized in step 3
        pass

    # 5. Manager Linking (20 pts)
    if result.get('manager_found'):
        linked_count = result.get('linked_vip_count', 0)
        target_count = vip_count # Should match the number of VIPs
        
        if linked_count > 0 and linked_count >= target_count:
            score += 20
        elif linked_count > 0:
            score += 10
            feedback.append(f"Only {linked_count}/{target_count} VIPs are linked to the Manager.")
        else:
            feedback.append("Manager created but no 'ManagedBy' links found from VIPs.")
    else:
        feedback.append("Manager 'Akira Kurosawa' not found.")
        
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback) if feedback else "Task completed successfully."
    }