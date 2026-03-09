#!/usr/bin/env python3
"""
Verifier for threat_model_mobile_banking task.
Verifies the presence of diagrams, correct shapes, connections, and metadata.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_threat_model(traj, env_info, task_info):
    """
    Verifies the STRIDE threat model diagram task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected values from metadata
    metadata = task_info.get('metadata', {})
    required_entities = set(metadata.get('required_entities', []))
    required_processes = set(metadata.get('required_processes', []))
    required_stores = set(metadata.get('required_stores', []))
    required_stride = set(metadata.get('required_stride', []))

    # Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # Check basics
    if not result.get('file_exists'):
        return {"passed": False, "score": 0, "feedback": "Diagram file not found."}
    
    if result.get('file_modified'):
        score += 5
        feedback.append("File modified.")
    else:
        feedback.append("File NOT modified.")

    analysis = result.get('analysis', {})
    
    # 1. Shape Count (Target >= 15)
    shape_count = analysis.get('shape_count', 0)
    if shape_count >= 15:
        score += 8
        feedback.append(f"Shape count good ({shape_count}).")
    elif shape_count >= 10:
        score += 4
        feedback.append(f"Shape count acceptable ({shape_count}).")
    else:
        feedback.append(f"Shape count too low ({shape_count}).")

    # 2. Edge Count (Target >= 15)
    edge_count = analysis.get('edge_count', 0)
    if edge_count >= 15:
        score += 8
        feedback.append(f"Connection count good ({edge_count}).")
    elif edge_count >= 10:
        score += 4
        feedback.append(f"Connection count acceptable ({edge_count}).")
    else:
        feedback.append(f"Connection count too low ({edge_count}).")

    # 3. Content Analysis (Keywords in labels)
    # Flatten labels to lower case
    labels = [l.lower() for l in analysis.get('labels', [])]
    label_text = " ".join(labels)

    # Check Entities
    entities_found = sum(1 for e in required_entities if e in label_text)
    if entities_found >= 3:
        score += 10
        feedback.append(f"Entities found ({entities_found}/4).")
    else:
        feedback.append(f"Missing entities (found {entities_found}/4).")

    # Check Processes
    processes_found = sum(1 for p in required_processes if p in label_text)
    if processes_found >= 4:
        score += 10
        feedback.append(f"Processes found ({processes_found}/6).")
    else:
        feedback.append(f"Missing processes (found {processes_found}/6).")

    # Check Data Stores
    stores_found = sum(1 for s in required_stores if s in label_text)
    if stores_found >= 3:
        score += 10
        feedback.append(f"Data stores found ({stores_found}/5).")
    else:
        feedback.append(f"Missing data stores (found {stores_found}/5).")

    # 4. Trust Boundaries
    tb_count = analysis.get('trust_boundaries', 0)
    if tb_count >= 2:
        score += 10
        feedback.append(f"Trust boundaries found ({tb_count}).")
    else:
        feedback.append("Missing trust boundaries.")

    # 5. Data Flow Labels (Heuristic: are edges labeled?)
    # We check if labels list has enough unique items relative to shape count
    if len(set(labels)) >= 10:
        score += 9
        feedback.append("Data flows appear labeled.")
    else:
        feedback.append("Data flows may be unlabeled.")

    # 6. STRIDE Annotations
    stride_found = sum(1 for s in required_stride if s in label_text)
    if stride_found >= 3:
        score += 10
        feedback.append(f"STRIDE annotations found ({stride_found}/6).")
    else:
        feedback.append(f"Missing STRIDE annotations (found {stride_found}/6).")

    # 7. Second Page
    if analysis.get('page_count', 0) >= 2:
        score += 10
        feedback.append("Second page created.")
    else:
        feedback.append("Second page missing.")

    # 8. Threat Summary on Page 2 (Heuristic: check for summary text)
    if analysis.get('has_summary_page'):
        score += 5
        feedback.append("Threat summary page detected.")
    
    # 9. PDF Export
    if result.get('pdf_exists'):
        score += 5
        feedback.append("PDF export found.")
    else:
        feedback.append("PDF export missing.")

    passed = score >= 55
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }