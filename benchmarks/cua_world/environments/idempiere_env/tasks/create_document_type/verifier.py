#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_document_type(traj, env_info, task_info):
    """
    Verify the creation of a Sequence and Document Type in iDempiere.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
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
    seq_data = result.get('sequence', {})
    doctype_data = result.get('doctype', {})
    
    # Metadata expectations
    meta = task_info.get('metadata', {})
    exp_seq_name = meta.get('sequence_name', 'Web_Sales_Seq_2025')
    exp_seq_start = meta.get('sequence_start', 900000)
    exp_dt_name = meta.get('doctype_name', 'Web Standard Order')
    
    score = 0
    feedback = []
    
    # --- Verify Sequence (30 points) ---
    if seq_data and seq_data.get('name') == exp_seq_name:
        score += 20
        feedback.append(f"Sequence '{exp_seq_name}' created.")
        
        # Check start number (Current Next)
        current_next = seq_data.get('currentnext', 0)
        if current_next >= exp_seq_start:
            score += 10
            feedback.append(f"Sequence start number correct ({current_next}).")
        else:
            feedback.append(f"Sequence start number incorrect (Found: {current_next}, Expected >= {exp_seq_start}).")
    else:
        feedback.append(f"Sequence '{exp_seq_name}' NOT found.")

    # --- Verify Document Type (70 points) ---
    if doctype_data and doctype_data.get('name') == exp_dt_name:
        score += 20
        feedback.append(f"Document Type '{exp_dt_name}' created.")
        
        # Check Base Type (SOO = Sales Order)
        base_type = doctype_data.get('docbasetype')
        if base_type == 'SOO':
            score += 15
            feedback.append("Document Base Type correct (Sales Order).")
        else:
            feedback.append(f"Document Base Type incorrect ({base_type}).")
            
        # Check Sub Type (SO = Standard Order)
        sub_type = doctype_data.get('docsubtypeso')
        if sub_type == 'SO':
            score += 10
            feedback.append("Sales Order Sub Type correct (Standard Order).")
        else:
            feedback.append(f"Sales Order Sub Type incorrect ({sub_type}).")
            
        # Check Linkage to Sequence
        linked_seq_name = doctype_data.get('sequence_name')
        if linked_seq_name == exp_seq_name:
            score += 25
            feedback.append("Document Type correctly linked to new sequence.")
        else:
            feedback.append(f"Document Type linked to wrong sequence ('{linked_seq_name}').")
    else:
        feedback.append(f"Document Type '{exp_dt_name}' NOT found.")

    # Pass threshold
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }