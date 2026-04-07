#!/usr/bin/env python3
"""
Verifier for process_lost_deal_followup task.

Verification Criteria:
1. Potential updated: Stage set to 'Closed Lost' (15 pts)
2. Potential updated: Description added explaining loss (10 pts)
3. Document uploaded: Linked to potential with 'Competitor Pricing' in title (15 pts)
4. File attached: The document record has a filename registered (15 pts)
5. Task scheduled: Linked to potential, due date 2026-09-09 (15 pts)
6. Task configured: Subject contains 'Follow up' (10 pts)
7. Anti-gaming check (VLM Trajectory): Ensure UI was used to complete the task (20 pts)
"""

import json
import os
import tempfile
import logging

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """
You are verifying an agent's completion of a CRM software task.
The user was asked to update a Potential (Deal) record, upload a competitor pricing document, and schedule a follow-up task.

Look at these trajectory screenshots from the session. Did the agent utilize the CRM UI (Vtiger) to interact with records?
You should look for evidence of:
- A Potential (Deal) record being edited
- A Document upload dialogue or related list interaction
- A Task/To Do being created

Respond with JSON in this format:
{
    "used_ui": true/false,
    "evidence_of_editing": true/false,
    "evidence_of_document_or_task": true/false,
    "confidence": "high/medium/low",
    "reasoning": "brief explanation"
}
"""

def verify_lost_deal_followup(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    metadata = task_info.get('metadata', {})
    expected_stage = metadata.get('expected_stage', 'Closed Lost')
    expected_task_date = metadata.get('expected_task_date', '2026-09-09')
    
    score = 0
    feedback_parts = []
    
    # Extract DB verification JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/process_lost_deal_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    # 1 & 2: Check Potential Updates
    pot = result.get('potential', {})
    if pot.get('found'):
        if pot.get('stage') == expected_stage:
            score += 15
            feedback_parts.append(f"✓ Potential stage updated to {expected_stage}")
        else:
            feedback_parts.append(f"✗ Potential stage is '{pot.get('stage')}' instead of {expected_stage}")
            
        desc = pot.get('desc', '').strip()
        if desc:
            score += 10
            feedback_parts.append("✓ Description note added")
        else:
            feedback_parts.append("✗ No description note added")
    else:
        feedback_parts.append("✗ Target Potential record missing")
        
    # 3 & 4: Check Document Upload & Linkage
    doc = result.get('document', {})
    if doc.get('found'):
        score += 15
        feedback_parts.append(f"✓ Document '{doc.get('title')}' linked to Potential")
        
        # Verify file presence in DB record
        if doc.get('filename'):
            score += 15
            feedback_parts.append("✓ File attached to Document record")
        else:
            feedback_parts.append("✗ Document record exists but no file attached")
    else:
        feedback_parts.append("✗ Linked Document with 'Competitor' in title not found")
        
    # 5 & 6: Check Follow-up Task Creation
    tsk = result.get('task', {})
    if tsk.get('found'):
        if expected_task_date in tsk.get('date', ''):
            score += 15
            feedback_parts.append(f"✓ Task due date correctly set to {expected_task_date}")
        else:
            feedback_parts.append(f"✗ Task due date is '{tsk.get('date')}', expected {expected_task_date}")
            
        if 'follow up' in tsk.get('subject', '').lower():
            score += 10
            feedback_parts.append("✓ Task subject contains 'Follow up'")
        else:
            feedback_parts.append("✗ Task subject incorrect")
    else:
        feedback_parts.append("✗ Linked follow-up Task not found")

    # 7: Trajectory Analysis via VLM
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final_frame = get_final_screenshot(traj)
        
        vlm_res = query_vlm(
            prompt=VLM_PROMPT,
            images=frames + [final_frame] if final_frame else frames
        )
        
        parsed = vlm_res.get('parsed', {})
        if parsed.get('used_ui', False) and (parsed.get('evidence_of_editing') or parsed.get('evidence_of_document_or_task')):
            score += 20
            feedback_parts.append("✓ VLM verified UI interaction")
        else:
            feedback_parts.append("✗ VLM did not find clear evidence of UI interaction for these changes")
    else:
        # Give benefit of doubt if VLM is unavailable, provided database updates happened
        if score >= 50:
            score += 20
            feedback_parts.append("✓ Assumed UI interaction (VLM not available)")
            
    # Key criteria must be met to pass: Stage updated, Document linked, Task linked
    key_criteria_met = (
        pot.get('stage') == expected_stage and 
        doc.get('found') == True and 
        tsk.get('found') == True
    )
    
    passed = score >= 80 and key_criteria_met
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }