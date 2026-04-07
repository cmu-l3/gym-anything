#!/usr/bin/env python3
"""
Verifier for extract_section_to_document task.
Verifies that:
1. A new document with prefix 'NFR' exists.
2. The 'Security' section (and children) exists in the NFR document.
3. The 'Security' section NO LONGER exists in the SRS document.
4. Changes were persisted.
"""

import json
import os
import tarfile
import tempfile
import shutil
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_extract_section(traj, env_info, task_info):
    """
    Verify the refactoring of the Security section to a new NFR document.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_prefix = metadata.get('new_doc_prefix', 'NFR')
    expected_name = metadata.get('new_doc_name', 'Non-Functional Requirements')
    section_title = metadata.get('section_title', 'Security')
    signatures = metadata.get('child_text_signatures', ["AES-256", "TLS 1.3", "Argon2"])
    
    # 1. Retrieve the result tarball
    temp_dir = tempfile.mkdtemp()
    tar_path = os.path.join(temp_dir, "result.tar.gz")
    
    try:
        copy_from_env("/tmp/task_result.tar.gz", tar_path)
        with tarfile.open(tar_path, "r:gz") as tar:
            tar.extractall(path=temp_dir)
            
        export_dir = os.path.join(temp_dir, "task_export")
        project_json_path = os.path.join(export_dir, "project.json")
        docs_dir = os.path.join(export_dir, "documents")
        
        if not os.path.exists(project_json_path):
            return {"passed": False, "score": 0, "feedback": "Project files not found (save failed?)"}
            
        with open(project_json_path, 'r') as f:
            project_data = json.load(f)
            
    except Exception as e:
        shutil.rmtree(temp_dir, ignore_errors=True)
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve/parse project data: {str(e)}"}

    score = 0
    feedback_parts = []
    
    # --- Check 1: Verify New Document Exists (20 pts) ---
    # project.json contains a list of documents. We look for one with prefix 'NFR'.
    # Structure of project.json 'documents' is usually a dict { "docId": { ... } } or list.
    
    documents_registry = project_data.get('documents', {})
    nfr_doc_id = None
    srs_doc_id = None
    
    # Normalize registry handling (it's usually a dict keyed by internal ID)
    if isinstance(documents_registry, list):
        # Convert to list of (id, data) tuples for uniform handling
        doc_items = [(d.get('id'), d) for d in documents_registry]
    else:
        doc_items = documents_registry.items()
        
    for doc_id, doc_meta in doc_items:
        prefix = doc_meta.get('prefix', '')
        name = doc_meta.get('name', '')
        
        if prefix == expected_prefix:
            nfr_doc_id = doc_id
        if prefix == "SRS": # Assuming standard SRS prefix
            srs_doc_id = doc_id
            
    if nfr_doc_id:
        score += 20
        feedback_parts.append(f"New document '{expected_prefix}' found")
    else:
        feedback_parts.append(f"New document with prefix '{expected_prefix}' NOT found")
        # Critical failure if doc doesn't exist, but we check SRS to see if they just didn't move it
        
    # --- Helper to load document content ---
    def load_doc_content(doc_id):
        # The filename usually matches the docId or is looked up in registry
        # In ReqView file structure: documents/{docId}.json
        p = os.path.join(docs_dir, f"{doc_id}.json")
        if os.path.exists(p):
            try:
                with open(p, 'r') as f:
                    return json.load(f)
            except:
                return None
        return None

    def search_content(data_list, search_terms):
        """Returns set of found terms"""
        found = set()
        if not isinstance(data_list, list):
            return found
            
        for item in data_list:
            text = item.get('text', '') + item.get('heading', '') + item.get('description', '')
            for term in search_terms:
                if term in text:
                    found.add(term)
            
            # Recurse
            if 'children' in item:
                found.update(search_content(item['children'], search_terms))
        return found

    # --- Check 2: Verify Content Moved to NFR (40 pts) ---
    nfr_content_found = False
    if nfr_doc_id:
        nfr_data = load_doc_content(nfr_doc_id)
        if nfr_data:
            # Check for heading
            found_terms = search_content(nfr_data.get('data', []), [section_title] + signatures)
            
            has_heading = section_title in found_terms
            signature_hits = len(found_terms) - (1 if has_heading else 0)
            
            if has_heading:
                score += 10
                feedback_parts.append("Security heading found in NFR")
            else:
                feedback_parts.append("Security heading missing from NFR")
                
            if signature_hits >= len(signatures):
                score += 30
                nfr_content_found = True
                feedback_parts.append("All child requirements found in NFR")
            elif signature_hits > 0:
                score += int(30 * (signature_hits / len(signatures)))
                feedback_parts.append(f"Partial requirements found in NFR ({signature_hits}/{len(signatures)})")
            else:
                feedback_parts.append("No child requirements found in NFR")
        else:
            feedback_parts.append("NFR document file empty or unreadable")
    
    # --- Check 3: Verify Content Removed from SRS (30 pts) ---
    if srs_doc_id:
        srs_data = load_doc_content(srs_doc_id)
        if srs_data:
            found_terms = search_content(srs_data.get('data', []), [section_title] + signatures)
            
            if not found_terms:
                score += 30
                feedback_parts.append("Content successfully removed from SRS")
            else:
                # If they copied but didn't delete, they lose these points
                feedback_parts.append(f"Content still present in SRS ({len(found_terms)} matches found)")
        else:
            # If SRS file is missing, that's bad (deleted the doc?), but let's assume valid removal for scoring context if NFR is good
            feedback_parts.append("SRS document file not found")
            
    # --- Check 4: Persistence / Timestamp (10 pts) ---
    # We rely on the fact that we read the files from disk which implies they were saved.
    # We can check file mtime vs start time from metadata if needed, but existence is strong proof here.
    # We'll give points if we successfully read the project.json and it wasn't empty
    if project_data:
        score += 10
        
    # Cleanup
    shutil.rmtree(temp_dir, ignore_errors=True)
    
    return {
        "passed": score >= 90,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }