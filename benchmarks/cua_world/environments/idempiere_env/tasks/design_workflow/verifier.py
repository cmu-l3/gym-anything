#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_design_workflow(traj, env_info, task_info):
    """
    Verify the creation of a specific Workflow in iDempiere.
    
    Expected Structure:
    - Workflow Name: Project_Initiation_WF
    - Table: C_Project
    - Nodes: WF_Start, WF_Review, WF_Approved
    - Start Node: WF_Start
    - Transitions: WF_Start -> WF_Review -> WF_Approved
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Verify Workflow Header (20 pts)
    if result.get('workflow_found'):
        if result.get('workflow_name') == 'Project_Initiation_WF':
            score += 20
            feedback.append("Workflow header created correctly.")
        else:
            feedback.append(f"Workflow found but name mismatch: {result.get('workflow_name')}")
    else:
        feedback.append("Workflow 'Project_Initiation_WF' not found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # 2. Verify Table (10 pts)
    # The DB stores C_Project in AD_Table.TableName usually
    # Note: user might select 'Project' which maps to C_Project table.
    # We accept 'C_Project' or 'Project'
    table_name = result.get('table_name', '').upper()
    if 'PROJECT' in table_name:
        score += 10
        feedback.append(f"Correct table selected ({result.get('table_name')}).")
    else:
        feedback.append(f"Incorrect table: {result.get('table_name')}")

    # 3. Verify Nodes (30 pts)
    # Expect: WF_Start, WF_Review, WF_Approved
    expected_nodes = {'WF_Start', 'WF_Review', 'WF_Approved'}
    actual_nodes = {n['name'] for n in result.get('nodes', [])}
    
    # Check for exact matches or slight case variations
    normalized_actual = {n.upper() for n in actual_nodes}
    normalized_expected = {n.upper() for n in expected_nodes}
    
    common = normalized_actual.intersection(normalized_expected)
    if len(common) == 3:
        score += 30
        feedback.append("All 3 nodes created correctly.")
    elif len(common) > 0:
        partial = 10 * len(common)
        score += partial
        feedback.append(f"Found {len(common)}/3 expected nodes.")
    else:
        feedback.append("No correct nodes found.")

    # 4. Verify Start Node (10 pts)
    start_node = result.get('start_node_name', '')
    if start_node == 'WF_Start':
        score += 10
        feedback.append("Start node correctly configured.")
    else:
        feedback.append(f"Start node incorrect (found: '{start_node}').")

    # 5. Verify Transitions (30 pts)
    # Expect: WF_Start -> WF_Review AND WF_Review -> WF_Approved
    transitions = result.get('transitions', [])
    # Normalize to tuples (Source, Target)
    trans_set = {(t['source'], t['target']) for t in transitions}
    
    has_start_review = False
    has_review_approved = False
    
    for s, t in trans_set:
        if s == 'WF_Start' and t == 'WF_Review':
            has_start_review = True
        if s == 'WF_Review' and t == 'WF_Approved':
            has_review_approved = True
            
    if has_start_review:
        score += 15
        feedback.append("Transition 'Start -> Review' exists.")
    else:
        feedback.append("Transition 'Start -> Review' missing.")
        
    if has_review_approved:
        score += 15
        feedback.append("Transition 'Review -> Approved' exists.")
    else:
        feedback.append("Transition 'Review -> Approved' missing.")

    # Final Pass check
    # We require the workflow header + at least 2 nodes + 1 correct transition to pass
    passed = (score >= 80)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }