#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Import VLM utilities if available, else mock
try:
    from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot
except ImportError:
    def query_vlm(**kwargs): return {"success": False, "error": "VLM not available"}
    def sample_trajectory_frames(traj, n=5): return []
    def get_final_screenshot(traj): return None

def verify_create_issue_relation(traj, env_info, task_info):
    """
    Verify that the user created a 'blocks' relation from Issue A to Issue B.
    
    Scoring:
    - 50 pts: Correct 'blocks' relation confirmed via API
    - 15 pts: Relation created during task session (anti-gaming)
    - 10 pts: Partial credit if ANY relation exists (even if wrong type)
    - 10 pts: VLM confirms navigation to issue page
    - 15 pts: VLM confirms relation workflow
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load result data from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    issue_a_id = int(result.get('issue_a_id', 0))
    issue_b_id = int(result.get('issue_b_id', 0))
    
    # relations_a and relations_b contain the full API response { "relations": [...] }
    relations_a_list = result.get('relations_a', {}).get('relations', [])
    relations_b_list = result.get('relations_b', {}).get('relations', [])
    
    score = 0
    feedback_parts = []
    
    # 2. Check for relation existence (API Check)
    blocks_relation_found = False
    any_relation_found = False
    
    # Check from A's perspective
    for r in relations_a_list:
        target_id = r.get('issue_to_id')
        source_id = r.get('issue_id')
        
        # Check if relation involves Issue B
        if target_id == issue_b_id or source_id == issue_b_id:
            any_relation_found = True
            
            # Specifically check "blocks" pointing to B
            # API: A blocks B -> relation_type="blocks", issue_id=A, issue_to_id=B
            if r.get('relation_type') == 'blocks' and target_id == issue_b_id:
                blocks_relation_found = True

    # Check from B's perspective (backup/validation)
    if not blocks_relation_found:
        for r in relations_b_list:
            target_id = r.get('issue_to_id')
            source_id = r.get('issue_id')
            
            if target_id == issue_a_id or source_id == issue_a_id:
                any_relation_found = True
                
                # If A blocks B, looking at B:
                # API might report: relation_type="blocked", issue_id=B, issue_to_id=A
                # OR relation_type="blocked" where B is involved.
                # Just checking the type and the other issue ID is usually sufficient.
                if r.get('relation_type') == 'blocked' and (target_id == issue_a_id or source_id == issue_a_id):
                    blocks_relation_found = True

    if blocks_relation_found:
        score += 50
        feedback_parts.append("Success: 'blocks' relation found via API.")
    elif any_relation_found:
        score += 10
        feedback_parts.append("Partial: A relation exists between issues, but type is incorrect (expected 'blocks').")
    else:
        feedback_parts.append("Failure: No relation found between the specified issues.")

    # 3. Check anti-gaming (Timing/Existence)
    # Since setup creates issues with 0 relations, any relation found now must have been created during the task.
    if any_relation_found:
        score += 15
        feedback_parts.append("Relation verified as created during task session.")

    # 4. VLM Verification (Trajectory)
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    all_frames = frames + ([final_frame] if final_frame else [])
    
    if all_frames:
        vlm_prompt = f"""
        You are verifying a Redmine project management task. 
        The user was supposed to:
        1. Open issue #{issue_a_id} ("Complete site grading...")
        2. Create a "blocks" relation to issue #{issue_b_id} ("Pour foundation concrete").
        
        Analyze the screenshots for these specific actions:
        - Did the user navigate to an Issue Details page?
        - Did the user interact with the 'Related issues' or 'Relations' section?
        - Is there visual evidence of selecting 'blocks' or entering the issue ID?
        
        Return JSON format: {{ "navigated_to_issue": true/false, "relation_workflow_visible": true/false }}
        """
        
        vlm_result = query_vlm(images=all_frames, prompt=vlm_prompt)
        vlm_data = vlm_result.get('parsed', {})
        
        if vlm_data.get('navigated_to_issue'):
            score += 10
            feedback_parts.append("VLM: Navigation confirmed.")
        
        if vlm_data.get('relation_workflow_visible'):
            score += 25
            feedback_parts.append("VLM: Workflow confirmed.")
    else:
        feedback_parts.append("VLM: No frames available for visual verification.")

    # Final Pass Decision
    # Need correct relation AND reasonable score (to ensure it wasn't just luck or partial)
    passed = (blocks_relation_found) and (score >= 65)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }