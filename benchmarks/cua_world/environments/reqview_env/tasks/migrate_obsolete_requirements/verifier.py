#!/usr/bin/env python3
"""
Verifier for migrate_obsolete_requirements task.

Criteria:
1. 'Archive' document exists in project (20 pts)
2. 'SRS' document has NO 'Obsolete' items remaining (25 pts)
3. 'Archive' document contains ALL expected 'Obsolete' items (25 pts)
4. Precision: No active items were moved to Archive (15 pts)
5. Data Integrity: IDs of moved items match original (15 pts)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def find_ids_recursive(items, id_list=None):
    """Recursively extract all IDs from a document structure."""
    if id_list is None:
        id_list = []
    
    for item in items:
        if 'id' in item:
            id_list.append(item['id'])
        if 'children' in item:
            find_ids_recursive(item['children'], id_list)
    return id_list

def find_obsolete_recursive(items, obsolete_list=None):
    """Recursively find items with status='Obsolete'."""
    if obsolete_list is None:
        obsolete_list = []
        
    for item in items:
        if item.get('status') == 'Obsolete':
            obsolete_list.append(item['id'])
        if 'children' in item:
            find_obsolete_recursive(item['children'], obsolete_list)
    return obsolete_list

def verify_migrate_requirements(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    ground_truth_path = metadata.get('ground_truth_path', '/tmp/expected_obsolete_ids.json')
    
    # 1. Fetch Ground Truth from VM
    gt_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(ground_truth_path, gt_file.name)
        with open(gt_file.name, 'r') as f:
            ground_truth = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load ground truth: {e}"}
    finally:
        if os.path.exists(gt_file.name):
            os.unlink(gt_file.name)

    project_dir = ground_truth.get('project_dir')
    expected_obsolete_ids = set(ground_truth.get('obsolete_ids', []))
    expected_active_ids = set(ground_truth.get('active_ids', []))
    
    score = 0
    feedback = []

    # 2. Fetch project.json to find document paths
    project_json_path = os.path.join(project_dir, "project.json")
    proj_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    
    srs_doc_file = None
    archive_doc_file = None
    
    try:
        copy_from_env(project_json_path, proj_file.name)
        with open(proj_file.name, 'r') as f:
            project_data = json.load(f)
            
        # Analyze project structure to find SRS and Archive docs
        # ReqView project.json usually has "documents": {"docId": {metadata...}} or list
        docs = project_data.get('documents', {})
        
        # Handle dict vs list structure
        doc_list = []
        if isinstance(docs, dict):
            doc_list = docs.values()
        elif isinstance(docs, list):
            doc_list = docs
            
        for doc in doc_list:
            name = doc.get('name', '')
            prefix = doc.get('prefix', '')
            file_name = doc.get('file', '')
            
            # Find SRS
            if name == 'SRS' or prefix == 'SRS':
                srs_doc_file = file_name
            
            # Find Archive
            if 'Archive' in name or 'ARCH' in prefix:
                archive_doc_file = file_name

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read project.json: {e}"}
    finally:
        if os.path.exists(proj_file.name):
            os.unlink(proj_file.name)

    # CHECK 1: Archive Document Exists (20 pts)
    if archive_doc_file:
        score += 20
        feedback.append(f"Archive document found ({archive_doc_file})")
    else:
        feedback.append("Archive document NOT found in project")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    # 3. Analyze Document Contents
    # Fetch SRS
    srs_content = {}
    if srs_doc_file:
        srs_path = os.path.join(project_dir, "documents", srs_doc_file)
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env(srs_path, tmp.name)
            with open(tmp.name, 'r') as f:
                srs_content = json.load(f)
        finally:
            if os.path.exists(tmp.name): os.unlink(tmp.name)
            
    # Fetch Archive
    archive_content = {}
    if archive_doc_file:
        archive_path = os.path.join(project_dir, "documents", archive_doc_file)
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env(archive_path, tmp.name)
            with open(tmp.name, 'r') as f:
                archive_content = json.load(f)
        finally:
            if os.path.exists(tmp.name): os.unlink(tmp.name)

    # Get IDs from both docs
    srs_data = srs_content.get('data', []) or srs_content.get('children', [])
    archive_data = archive_content.get('data', []) or archive_content.get('children', [])
    
    current_srs_obsolete = find_obsolete_recursive(srs_data)
    current_archive_ids = set(find_ids_recursive(archive_data))
    
    # CHECK 2: Clean SRS (25 pts)
    if len(current_srs_obsolete) == 0:
        score += 25
        feedback.append("SRS is clean (0 obsolete items)")
    else:
        feedback.append(f"SRS still contains {len(current_srs_obsolete)} obsolete items")

    # CHECK 3: Populated Archive (25 pts)
    # Check intersection of expected obsolete IDs and current archive IDs
    found_in_archive = expected_obsolete_ids.intersection(current_archive_ids)
    missing_from_archive = expected_obsolete_ids - current_archive_ids
    
    if len(missing_from_archive) == 0 and len(expected_obsolete_ids) > 0:
        score += 25
        feedback.append(f"All {len(expected_obsolete_ids)} obsolete items moved to Archive")
    elif len(found_in_archive) > 0:
        # Partial credit
        ratio = len(found_in_archive) / len(expected_obsolete_ids)
        pts = int(25 * ratio)
        score += pts
        feedback.append(f"Moved {len(found_in_archive)}/{len(expected_obsolete_ids)} items to Archive")
    else:
        feedback.append("No expected obsolete items found in Archive")

    # CHECK 4: Precision (15 pts)
    # Ensure no ACTIVE items ended up in Archive
    wrongly_moved = expected_active_ids.intersection(current_archive_ids)
    if len(wrongly_moved) == 0:
        score += 15
        feedback.append("Precision good (only obsolete items moved)")
    else:
        feedback.append(f"Precision error: {len(wrongly_moved)} active items were incorrectly moved")

    # CHECK 5: Data Integrity (15 pts)
    # If we found items in archive, check if their IDs are preserved (which we implicitly did by checking intersection)
    # This checks if the operation was likely a move rather than a manual re-type (which would generate new UIDs)
    # ReqView IDs are usually sequential or GUIDs. If the ID is in expected_obsolete_ids, it was preserved.
    if len(found_in_archive) > 0:
        score += 15
        feedback.append("Data integrity preserved (IDs match)")
    else:
        feedback.append("No items to check for integrity")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }