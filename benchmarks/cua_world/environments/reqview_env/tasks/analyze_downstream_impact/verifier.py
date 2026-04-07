#!/usr/bin/env python3
"""
Verifier for analyze_downstream_impact task.

Verification Logic:
1. Calculates Ground Truth: Parses the SRS.json from the project to find the first requirement 
   linked to the TESTS document.
2. Verifies Agent Report: Checks if the agent identified the correct Source and Target IDs.
3. Verifies System State: Checks if the "Impact Analysis Started" comment was added to the 
   correct requirement in the SRS file.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_analyze_downstream_impact(traj, env_info, task_info):
    """
    Verify the impact analysis task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_comment = metadata.get('comment_text', "Impact Analysis Started")
    target_doc_id = metadata.get('link_target_doc', "TESTS")

    # =========================================================
    # 1. Retrieve Files from Container
    # =========================================================
    
    # Get Task Result Metadata
    task_result = {}
    with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
        try:
            copy_from_env("/tmp/task_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                task_result = json.load(f)
        except Exception as e:
            logger.warning(f"Could not load task_result.json: {e}")
        finally:
            if os.path.exists(tmp.name): os.unlink(tmp.name)

    # Get Agent's Report
    agent_report = {}
    report_exists = False
    if task_result.get('report_exists'):
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
            try:
                copy_from_env("/tmp/verify_report.json", tmp.name)
                with open(tmp.name, 'r') as f:
                    agent_report = json.load(f)
                report_exists = True
            except Exception as e:
                logger.warning(f"Could not load agent report: {e}")
            finally:
                if os.path.exists(tmp.name): os.unlink(tmp.name)

    # Get SRS Data (Ground Truth Source)
    srs_data = {}
    srs_available = False
    with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
        try:
            copy_from_env("/tmp/verify_srs.json", tmp.name)
            with open(tmp.name, 'r') as f:
                srs_data = json.load(f)
            srs_available = True
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve project data for verification: {e}"}
        finally:
            if os.path.exists(tmp.name): os.unlink(tmp.name)

    # =========================================================
    # 2. Establish Ground Truth
    # =========================================================
    
    ground_truth_source = None
    ground_truth_target = None
    
    def find_first_linked_req(items):
        """Recursively find first req linked to TESTS document"""
        for item in items:
            # Check links on this item
            links = item.get('links', [])
            for link in links:
                # Check if link points to TESTS document
                # docId might be "TESTS" or the internal ID corresponding to it. 
                # In the Example Project, docId is usually the document ID string "TESTS".
                if link.get('docId') == target_doc_id:
                    return item, link
            
            # Recurse into children
            if 'children' in item:
                res, link = find_first_linked_req(item['children'])
                if res:
                    return res, link
        return None, None

    gt_req, gt_link = find_first_linked_req(srs_data.get('data', []))
    
    if not gt_req:
        return {"passed": False, "score": 0, "feedback": "Setup Error: No requirements linked to TESTS found in example project."}

    ground_truth_source = gt_req.get('id')  # e.g., "15" or "SRS-15" (ReqView usually stores raw ID "15")
    # Construct full ID if prefix missing (Example Project usually uses 'SRS-' prefix defined in document config, but ID in JSON is integer)
    # However, the task asks for "SRS-ID", and users see "SRS-15". 
    # Let's normalize comparison to handle "15" vs "SRS-15".
    
    ground_truth_target_req_id = gt_link.get('reqId')
    
    # Helper to normalize ID (strip non-digits)
    def normalize_id(val):
        return ''.join(filter(str.isdigit, str(val)))

    gt_source_norm = normalize_id(ground_truth_source)
    gt_target_norm = normalize_id(ground_truth_target_req_id)

    # =========================================================
    # 3. Scoring
    # =========================================================
    
    score = 0
    feedback = []

    # Criterion 1: Report File Exists and is Valid (10 pts)
    if report_exists and agent_report:
        score += 10
        feedback.append("Report file created")
    else:
        feedback.append("Report file missing or invalid")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # Criterion 2: Correct Source Requirement Identified (30 pts)
    agent_source = str(agent_report.get('source_requirement', ''))
    agent_source_norm = normalize_id(agent_source)
    
    if agent_source_norm == gt_source_norm and agent_source_norm != "":
        score += 30
        feedback.append(f"Correct source req identified ({agent_source})")
    else:
        feedback.append(f"Incorrect source req. Expected SRS-{gt_source_norm}, got {agent_source}")

    # Criterion 3: Correct Linked Test Case Identified (30 pts)
    agent_target = str(agent_report.get('linked_test_case', ''))
    agent_target_norm = normalize_id(agent_target)
    
    if agent_target_norm == gt_target_norm and agent_target_norm != "":
        score += 30
        feedback.append(f"Correct target link identified ({agent_target})")
    else:
        feedback.append(f"Incorrect target link. Expected TESTS-{gt_target_norm}, got {agent_target}")

    # Criterion 4: Comment Added to Requirement (20 pts)
    # We check the 'comments' field of the ground truth requirement object in the SRS JSON
    comments = gt_req.get('comments', [])
    comment_found = False
    exact_match = False
    
    for c in comments:
        # Comment object structure: {"id": "...", "date": "...", "text": "...", "author": "..."}
        text = c.get('text', '')
        if expected_comment.lower() in text.lower():
            comment_found = True
            if expected_comment == text:
                exact_match = True
            break
            
    if exact_match:
        score += 30 # 20 for existence + 10 for exact text match
        feedback.append("Comment added correctly")
    elif comment_found:
        score += 20
        feedback.append("Comment added but text casing/format slightly off")
    else:
        feedback.append("Comment not found on the requirement")

    passed = (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "ground_truth_source": gt_source_norm,
            "ground_truth_target": gt_target_norm,
            "agent_source": agent_source_norm,
            "agent_target": agent_target_norm,
            "comments_found": [c.get('text') for c in comments]
        }
    }