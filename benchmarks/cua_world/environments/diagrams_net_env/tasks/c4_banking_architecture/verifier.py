#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_c4_banking_architecture(traj, env_info, task_info):
    """
    Verifies the C4 Architecture Diagram task.
    
    Criteria:
    1. File Modification (Anti-gaming)
    2. Page Structure (Must have 'System Context' and 'Container' pages)
    3. Context Diagram Content (Entities + Relationships)
    4. Container Diagram Content (Entities + Relationships)
    5. PDF Export
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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

    # Extract data
    analysis = result.get("analysis", {})
    pdf_info = result.get("pdf_export", {})
    drawio_info = result.get("drawio_file", {})
    
    metadata = task_info.get("metadata", {})
    
    score = 0
    feedback = []
    
    # ---------------------------------------------------------
    # 1. Basic File Checks (10 points)
    # ---------------------------------------------------------
    if not analysis.get("file_exists"):
        return {"passed": False, "score": 0, "feedback": "Draw.io file not found."}
        
    if drawio_info.get("modified_during_task"):
        score += 10
        feedback.append("File modified during task.")
    else:
        feedback.append("File was NOT modified (Anti-gaming check failed).")
        return {"passed": False, "score": 0, "feedback": "File not modified."}

    # ---------------------------------------------------------
    # 2. Page Structure (20 points)
    # ---------------------------------------------------------
    page_names = [p.lower() for p in analysis.get("page_names", [])]
    page_count = analysis.get("page_count", 0)
    
    if page_count >= 2:
        score += 10
        feedback.append(f"Page count valid ({page_count}).")
    else:
        feedback.append(f"Insufficient pages ({page_count}/2).")

    has_context_page = any("context" in p for p in page_names)
    has_container_page = any("container" in p for p in page_names)
    
    if has_context_page: score += 5
    if has_container_page: score += 5
    
    if has_context_page and has_container_page:
        feedback.append("Page names correct.")
    else:
        feedback.append(f"Missing required page names. Found: {page_names}")

    # ---------------------------------------------------------
    # 3. Entity Content Verification (40 points)
    # ---------------------------------------------------------
    all_text_combined = " ".join(analysis.get("all_text", [])).lower()
    
    # Check Context Entities
    context_entities = metadata.get("context_entities", [])
    found_context = 0
    for entity in context_entities:
        if entity.lower() in all_text_combined:
            found_context += 1
    
    # Check Container Entities
    container_entities = metadata.get("container_entities", [])
    found_container = 0
    for entity in container_entities:
        if entity.lower() in all_text_combined:
            found_container += 1
            
    # Calculate score based on entities found
    total_entities = len(context_entities) + len(container_entities)
    found_total = found_context + found_container
    
    # Proportional score up to 40
    entity_score = int((found_total / total_entities) * 40)
    score += entity_score
    feedback.append(f"Entities found: {found_total}/{total_entities}.")

    # ---------------------------------------------------------
    # 4. Relationships & Complexity (15 points)
    # ---------------------------------------------------------
    edge_count = analysis.get("edge_count", 0)
    # Expecting at least ~10 edges total for a full diagram
    if edge_count >= 10:
        score += 15
        feedback.append(f"Good diagram complexity ({edge_count} connections).")
    elif edge_count >= 5:
        score += 8
        feedback.append(f"Moderate diagram complexity ({edge_count} connections).")
    else:
        feedback.append(f"Diagram lacks connections ({edge_count}).")

    # Check for relationship terms
    req_terms = metadata.get("required_relationship_terms", [])
    found_terms = 0
    for term in req_terms:
        if term.lower() in all_text_combined:
            found_terms += 1
            
    if found_terms < 2:
        feedback.append("Warning: Few relationship labels found.")
        # We don't deduct hard points here as strict string matching on edges is flaky

    # ---------------------------------------------------------
    # 5. PDF Export (15 points)
    # ---------------------------------------------------------
    if pdf_info.get("exists") and pdf_info.get("created_during_task"):
        if pdf_info.get("size", 0) > 1000: # Valid non-empty PDF
            score += 15
            feedback.append("PDF exported successfully.")
        else:
            score += 5
            feedback.append("PDF exists but seems empty.")
    else:
        feedback.append("PDF export missing or not created during task.")

    # ---------------------------------------------------------
    # Final Result
    # ---------------------------------------------------------
    # Pass threshold: 60 points + Must have PDF + Must have entities
    passed = (score >= 60) and (found_total >= 4) and pdf_info.get("exists")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }