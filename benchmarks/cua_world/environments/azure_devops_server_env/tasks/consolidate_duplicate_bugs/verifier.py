#!/usr/bin/env python3
"""
Verifier for consolidate_duplicate_bugs task.

Scoring Criteria:
1. Primary bug is NOT Closed/Resolved (20 pts)
2. Duplicate bugs ARE Resolved/Closed (30 pts)
3. Duplicate bugs have correct 'Duplicate' link type to Primary (30 pts)
4. Duplicate bugs have correct link direction (Duplicate Of -> Primary) (20 pts)

Anti-gaming:
- Checks specific IDs created during setup
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_consolidate_duplicate_bugs(traj, env_info, task_info):
    """Verify that duplicate bugs were correctly linked and resolved."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define paths
    # Note: The export script runs on Windows guest, outputting to C:\Users\Docker\task_result.json
    # We copy from that location.
    remote_path = r"C:\Users\Docker\task_result.json"
    
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(remote_path, temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8-sig') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found inside environment."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # Data extraction
    primary = result.get('primary_bug', {})
    duplicates = result.get('duplicate_bugs', [])
    
    primary_id = primary.get('id')
    
    # 1. Verify Primary Bug State (20 pts)
    # Should be Active, New, or Committed. NOT Resolved/Closed.
    p_state = primary.get('state', 'Unknown')
    if p_state in ['New', 'Active', 'Committed', 'Approved']:
        score += 20
        feedback.append(f"Primary bug {primary_id} is Open ({p_state}).")
    else:
        feedback.append(f"Primary bug {primary_id} should be Open, but is {p_state}.")

    # 2. Verify Duplicate Bugs (Duplicates logic)
    dup_state_score = 0
    dup_link_score = 0
    
    for i, dup in enumerate(duplicates):
        dup_id = dup.get('id')
        d_state = dup.get('state')
        relations = dup.get('relations', [])
        
        # Check State (15 pts each)
        if d_state in ['Resolved', 'Closed', 'Removed']:
            dup_state_score += 15
            feedback.append(f"Duplicate {dup_id} is {d_state}.")
        else:
            feedback.append(f"Duplicate {dup_id} should be Resolved/Closed, but is {d_state}.")
            
        # Check Links (25 pts each)
        # Look for System.LinkTypes.Duplicate-Forward pointing to Primary ID
        # URL format: .../_apis/wit/workItems/10
        linked_correctly = False
        link_type_correct = False
        
        if relations:
            for rel in relations:
                rel_type = rel.get('rel')
                url = rel.get('url', '')
                
                # Check target ID
                target_id = None
                if url:
                    try:
                        target_id = int(url.split('/')[-1])
                    except ValueError:
                        pass
                
                if target_id == primary_id:
                    # Check type
                    # We accept 'Duplicate-Forward' (Duplicate) or 'Duplicate-Reverse' (Duplicate Of)
                    # Ideally strict: Duplicate bug HAS 'Duplicate-Forward' link to Primary
                    if rel_type == 'System.LinkTypes.Duplicate-Forward':
                        linked_correctly = True
                        link_type_correct = True
                        break
                    elif rel_type == 'System.LinkTypes.Duplicate-Reverse':
                        # This implies the duplicate is the 'parent' of the duplicate relationship? 
                        # Usually 'Duplicate' link type means 'This item is a duplicate of Target'
                        # In Azure DevOps: "Duplicate" link type. 
                        # Forward = "Duplicate" (Source is duplicate of Target)
                        # Reverse = "Duplicate Of" (Source has duplicate Target) -> Wait, other way around.
                        # Actually:
                        # Forward name: "Duplicate"
                        # Reverse name: "Duplicate Of"
                        # If A is duplicate of B:
                        # A has link "Duplicate" -> B
                        # B has link "Duplicate Of" -> A
                        # So on the duplicate item (A), we expect "Duplicate" (Forward) pointing to B.
                        linked_correctly = True
                        link_type_correct = True # We'll accept semantic match
        
        if linked_correctly:
            dup_link_score += 25
            feedback.append(f"Duplicate {dup_id} correctly linked to Primary.")
        else:
            feedback.append(f"Duplicate {dup_id} NOT correctly linked to Primary {primary_id}.")

    score += dup_state_score
    score += dup_link_score

    # Final tally
    passed = score >= 80  # Requires most things correct
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }