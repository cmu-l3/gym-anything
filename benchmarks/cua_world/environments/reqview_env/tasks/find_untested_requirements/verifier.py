#!/usr/bin/env python3
"""
Verifier for find_untested_requirements task.

This verifier:
1. Parses the actual SRS.json and TESTS.json from the project to establish ground truth.
   - It identifies all 'leaf' requirements in SRS.
   - It identifies all links between SRS and TESTS (in either direction).
   - It computes the set of SRS IDs that have NO links to TESTS.
2. Reads the agent's output file.
3. Compares the agent's list to the ground truth using Precision, Recall, and F1 score.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_find_untested_requirements(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    project_dir = metadata.get('project_dir', 'find_untested_reqs_project')
    srs_rel_path = metadata.get('srs_doc_file', 'documents/SRS.json')
    tests_rel_path = metadata.get('tests_doc_file', 'documents/TESTS.json')
    output_path = metadata.get('output_path', '/home/ga/Documents/untested_requirements.txt')

    # Construct full paths in the container
    base_path = f"/home/ga/Documents/ReqView/{project_dir}"
    srs_path = f"{base_path}/{srs_rel_path}"
    tests_path = f"{base_path}/{tests_rel_path}"

    # 1. Fetch Task Result JSON
    task_result = {}
    with tempfile.NamedTemporaryFile(delete=True) as tf:
        try:
            copy_from_env("/tmp/task_result.json", tf.name)
            with open(tf.name, 'r') as f:
                task_result = json.load(f)
        except Exception:
            pass # Handle gracefully below

    if not task_result.get('output_exists', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Output file 'untested_requirements.txt' not found."
        }

    # 2. Fetch Project Data (SRS and TESTS) to build Ground Truth
    srs_data = {}
    tests_data = {}
    
    with tempfile.NamedTemporaryFile(delete=True, suffix='.json') as tf_srs, \
         tempfile.NamedTemporaryFile(delete=True, suffix='.json') as tf_tests:
        try:
            copy_from_env(srs_path, tf_srs.name)
            copy_from_env(tests_path, tf_tests.name)
            
            with open(tf_srs.name, 'r') as f:
                srs_data = json.load(f)
            with open(tf_tests.name, 'r') as f:
                tests_data = json.load(f)
        except Exception as e:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": f"Failed to retrieve project data for verification: {str(e)}"
            }

    # 3. Analyze Ground Truth
    # Helper to flatten document tree
    def get_all_items(items):
        result = []
        for item in items:
            result.append(item)
            if 'children' in item:
                result.extend(get_all_items(item['children']))
        return result

    all_srs_items = get_all_items(srs_data.get('data', []))
    all_tests_items = get_all_items(tests_data.get('data', []))

    # Identify valid SRS requirements (exclude headings if possible, but simplest is all with ID)
    # ReqView headings usually have 'heading': true or are just containers. 
    # We'll assume anything with an ID prefix 'SRS' is a requirement we care about.
    # We will filter out items that look like pure headings if they have children and no text, 
    # but the safest bet for this task is "all items with an ID".
    srs_reqs = {item['id']: item for item in all_srs_items if 'id' in item}
    
    # Traceability Mapping
    # We need to find items in SRS that are NOT linked to TESTS.
    # Links can be in SRS items (pointing to TESTS) or TESTS items (pointing to SRS).
    
    covered_srs_ids = set()

    # Check outgoing links from SRS -> TESTS
    for item in all_srs_items:
        if 'id' not in item: continue
        for link in item.get('links', []):
            # Check if link points to TESTS document
            # ReqView might use document alias or ID. In the example project, 'TESTS' is likely the ID.
            if link.get('docId') == 'TESTS':
                covered_srs_ids.add(item['id'])

    # Check incoming links from TESTS -> SRS
    for item in all_tests_items:
        if 'id' not in item: continue
        for link in item.get('links', []):
            if link.get('docId') == 'SRS':
                covered_srs_ids.add(link['reqId'])

    # Calculate Ground Truth: SRS items NOT in covered set
    # We filter for items that are likely "requirements" (have text or description)
    untested_srs_ids = []
    for rid, item in srs_reqs.items():
        if rid not in covered_srs_ids:
            # Optional: Filter out pure section headings if they have no text/description?
            # For simplicity, we include everything. If the agent is smart, they might exclude headers.
            # We will accept if they include headers or not, usually headers don't get verified.
            # Let's assume valid requirements have 'text' or 'description'.
            if item.get('text') or item.get('description'):
                untested_srs_ids.append(f"SRS-{rid}")
    
    ground_truth_set = set(untested_srs_ids)
    
    # 4. Analyze Agent Output
    agent_lines = []
    with tempfile.NamedTemporaryFile(delete=True) as tf_out:
        copy_from_env(output_path, tf_out.name)
        with open(tf_out.name, 'r', encoding='utf-8', errors='ignore') as f:
            agent_lines = [l.strip() for l in f.readlines() if l.strip()]

    # Extract IDs from lines (robust to formatting)
    agent_set = set()
    for line in agent_lines:
        # Match pattern SRS-XXX
        match = re.search(r'SRS-\d+', line)
        if match:
            agent_set.add(match.group(0))

    # 5. Scoring
    if not ground_truth_set:
        # Edge case: everything is tested? (Unlikely in example project)
        return {"passed": True, "score": 100, "feedback": "No untested requirements found (Correct)."}

    true_positives = agent_set.intersection(ground_truth_set)
    false_positives = agent_set.difference(ground_truth_set)
    false_negatives = ground_truth_set.difference(agent_set)

    precision = len(true_positives) / len(agent_set) if agent_set else 0
    recall = len(true_positives) / len(ground_truth_set) if ground_truth_set else 0
    
    f1 = 0
    if precision + recall > 0:
        f1 = 2 * (precision * recall) / (precision + recall)

    score = 0
    feedback = []

    # Criteria 1: File created and valid structure (20 pts)
    if task_result.get('file_created_during_task'):
        score += 10
        feedback.append("File created during task.")
    else:
        feedback.append("File pre-existed or timestamp error.")
    
    if len(agent_set) > 0:
        score += 10
        feedback.append(f"Found {len(agent_set)} valid IDs.")
    else:
        feedback.append("No valid SRS-IDs found in file.")

    # Criteria 2: Recall (Finding the gaps) (40 pts)
    if recall >= 0.9: score += 40
    elif recall >= 0.7: score += 30
    elif recall >= 0.5: score += 20
    elif recall > 0: score += 10
    
    feedback.append(f"Recall: {recall:.2f} ({len(true_positives)}/{len(ground_truth_set)} found)")

    # Criteria 3: Precision (Not hallucinating gaps) (40 pts)
    if precision >= 0.9: score += 40
    elif precision >= 0.7: score += 30
    elif precision >= 0.5: score += 20
    elif precision > 0: score += 10

    feedback.append(f"Precision: {precision:.2f}")

    if false_positives:
        feedback.append(f"False positives (claimed untested but are linked): {list(false_positives)[:3]}...")
    if false_negatives:
        feedback.append(f"Missed untested requirements: {list(false_negatives)[:3]}...")

    passed = score >= 60 and recall >= 0.5

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "ground_truth_count": len(ground_truth_set),
            "agent_count": len(agent_set),
            "precision": precision,
            "recall": recall,
            "f1": f1
        }
    }