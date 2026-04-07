#!/usr/bin/env python3
"""
Verifier for classify_sensitive_data_reqs task.

Scoring Criteria:
1. Recall (50 pts): All requirements with IPs must be marked "Confidential".
2. Precision (30 pts): No requirements without IPs should be marked "Confidential".
3. File Save (10 pts): SRS.json must be modified after task start.
4. Formatting (10 pts): The 'DataClassification' attribute must be used correctly.

Logic:
- Load ground truth (list of IDs injected with IPs).
- Load final SRS.json from the environment.
- Iterate through all requirements:
    - If ID in ground_truth: Must have DataClassification="Confidential".
    - If ID NOT in ground_truth: Must NOT have DataClassification="Confidential".
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

SRS_REL_PATH = "documents/SRS.json"
GROUND_TRUTH_PATH = "/var/lib/reqview/ground_truth.json"

def verify_classify_sensitive_data_reqs(traj, env_info, task_info):
    """Verify that sensitive requirements were correctly classified."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    project_path = metadata.get('project_path', '/home/ga/Documents/ReqView/classify_sensitive_project')
    srs_path = os.path.join(project_path, SRS_REL_PATH)
    
    # 1. Fetch Result Metadata (from export_result.sh)
    # ------------------------------------------------
    task_result = {}
    temp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_res.name)
        with open(temp_res.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        logger.warning(f"Could not load task_result.json: {e}")
    finally:
        if os.path.exists(temp_res.name):
            os.unlink(temp_res.name)

    # 2. Fetch Ground Truth
    # ---------------------
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    ground_truth = {}
    try:
        copy_from_env(GROUND_TRUTH_PATH, temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            ground_truth = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load ground truth: {e}"}
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)

    target_ids = set(ground_truth.get('target_ids', []))
    
    # 3. Fetch Final SRS
    # ------------------
    temp_srs = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(srs_path, temp_srs.name)
        with open(temp_srs.name, 'r') as f:
            srs_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load SRS document: {e}"}
    finally:
        if os.path.exists(temp_srs.name):
            os.unlink(temp_srs.name)

    # 4. Analyze Data
    # ---------------
    
    # Helper to traverse requirements tree
    def get_all_requirements(nodes):
        reqs = []
        for node in nodes:
            # Check if it's a requirement (has ID)
            if 'id' in node:
                reqs.append(node)
            if 'children' in node:
                reqs.extend(get_all_requirements(node['children']))
        return reqs

    all_reqs = get_all_requirements(srs_data.get('data', []))
    
    true_positives = 0
    false_positives = 0
    false_negatives = 0
    total_targets = len(target_ids)
    
    attribute_found = False
    
    for req in all_reqs:
        req_id = req.get('id')
        
        # Check attribute value
        # Attributes in ReqView can be in 'attributes' dict or root level keys depending on version/config
        # The prompt setup injected "DataClassification" into project attributes.
        # Requirements usually store custom attributes in an 'attributes' dictionary or as direct keys matching the ID.
        # We will check both 'attributes' dict and direct keys.
        
        val = None
        if 'attributes' in req and isinstance(req['attributes'], dict):
            val = req['attributes'].get('DataClassification')
        
        # Fallback: check direct key (sometimes used for built-ins, less likely for custom but possible)
        if not val:
            val = req.get('DataClassification')

        # Check for matching value "Confidential"
        is_confidential = (str(val).lower() == "confidential") or (isinstance(val, dict) and val.get('value') == "Confidential")
        
        if is_confidential:
            attribute_found = True

        if req_id in target_ids:
            if is_confidential:
                true_positives += 1
            else:
                false_negatives += 1
        else:
            if is_confidential:
                false_positives += 1

    # 5. Calculate Score
    # ------------------
    score = 0
    feedback = []

    # Criterion 1: Recall (50 pts)
    if total_targets > 0:
        recall_pct = true_positives / total_targets
        recall_score = int(50 * recall_pct)
        score += recall_score
        feedback.append(f"Found {true_positives}/{total_targets} sensitive items ({recall_score}/50 pts)")
    else:
        score += 50 # Should not happen, but safeguard
        feedback.append("No targets existed (Error?)")

    # Criterion 2: Precision (30 pts)
    # Deduct 10 points per false positive, max deduction 30
    precision_deduction = min(30, false_positives * 10)
    precision_score = 30 - precision_deduction
    score += precision_score
    if false_positives > 0:
        feedback.append(f"Incorrectly marked {false_positives} non-sensitive items (-{precision_deduction} pts)")
    else:
        feedback.append(f"No false positives ({precision_score}/30 pts)")

    # Criterion 3: File Saved (10 pts)
    if task_result.get('srs_modified', False):
        score += 10
        feedback.append("Project saved (10/10 pts)")
    else:
        feedback.append("Project NOT saved (0/10 pts)")

    # Criterion 4: Attribute Usage (10 pts)
    if attribute_found:
        score += 10
        feedback.append("Attribute 'DataClassification' used (10/10 pts)")
    else:
        # If no attributes were found but we have false negatives, this is redundant but informative
        if score > 0: 
            feedback.append("Attribute 'DataClassification' not detected on any item")

    passed = (score >= 85)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "true_positives": true_positives,
            "false_positives": false_positives,
            "false_negatives": false_negatives,
            "total_targets": total_targets
        }
    }