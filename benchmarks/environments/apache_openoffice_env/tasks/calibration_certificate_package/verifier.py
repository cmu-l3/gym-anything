#!/usr/bin/env python3
"""
Verifier for calibration_certificate_package task.

Verifies that the agent created a multi-page calibration certificate document
containing the correct data, structure, and formatting.

Scoring Criteria (100 points total):
1. File exists & substantial size (>= 8KB): Gate check (0 if fail) + 10 pts
2. Document structure (Heading 1 for titles): 15 pts
3. Document structure (Heading 2 for subsections): 10 pts
4. Data presentation (Tables): 20 pts
5. Content accuracy (Serial numbers): 20 pts
6. Content completeness (Lab/Client names): 5 pts
7. Technical validity (Terms like traceability/uncertainty): 10 pts
8. Content volume (Paragraph count): 10 pts

Pass threshold: 70 points
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_calibration_certificate_package(traj, env_info, task_info):
    """
    Verify the calibration certificate package ODT file.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # Retrieve result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    score = 0
    feedback_parts = []
    
    # --- CRITERION 1: File Existence & Size (10 pts) ---
    # GATE: If file doesn't exist or is too small (<4KB), fail immediately
    file_exists = result.get('file_exists', False)
    file_size = result.get('file_size', 0)
    min_size = metadata.get('min_file_size_bytes', 8192)
    
    if not file_exists:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "FAILED: Output file 'CalCert_Package_SCP_2024_0147.odt' not found."
        }
        
    if file_size < 4000: # 4KB hard minimum for gate
        return {
            "passed": False,
            "score": 0,
            "feedback": f"FAILED: Output file is too small ({file_size} bytes). Empty or corrupted document."
        }
        
    if file_size >= min_size:
        score += 10
        feedback_parts.append(f"File exists and is substantial ({file_size} bytes)")
    else:
        score += 5
        feedback_parts.append(f"File exists but small ({file_size} bytes < {min_size})")

    # Anti-gaming check: File modified time
    if not result.get('created_during_task', False):
        feedback_parts.append("WARNING: File timestamp does not match task duration")
        # We don't fail immediately but this is suspicious
        
    # --- CRITERION 2: Heading 1 Structure (15 pts) ---
    h1_count = result.get('heading1_count', 0)
    req_h1 = metadata.get('required_h1_min', 5)
    
    if h1_count >= req_h1:
        score += 15
        feedback_parts.append(f"Heading 1 structure correct ({h1_count} found)")
    elif h1_count >= 1:
        score += 5
        feedback_parts.append(f"Heading 1 structure partial ({h1_count}/{req_h1})")
    else:
        feedback_parts.append("Heading 1 styles missing")
        
    # --- CRITERION 3: Heading 2 Structure (10 pts) ---
    h2_count = result.get('heading2_count', 0)
    req_h2 = metadata.get('required_h2_min', 8)
    
    if h2_count >= req_h2:
        score += 10
        feedback_parts.append(f"Heading 2 structure correct ({h2_count} found)")
    elif h2_count >= 1:
        score += 3
        feedback_parts.append(f"Heading 2 structure partial ({h2_count}/{req_h2})")
    else:
        feedback_parts.append("Heading 2 styles missing")

    # --- CRITERION 4: Tables (20 pts) ---
    table_count = result.get('table_count', 0)
    req_tables = metadata.get('required_tables_min', 4)
    
    if table_count >= req_tables:
        score += 20
        feedback_parts.append(f"Data tables present ({table_count} found)")
    elif table_count >= 2:
        score += 10
        feedback_parts.append(f"Some tables missing ({table_count}/{req_tables})")
    else:
        feedback_parts.append("Tables missing or insufficient")
        
    # --- CRITERION 5: Serial Numbers (20 pts) ---
    serials_found = result.get('serials_found', [])
    req_serials = metadata.get('required_serials', [])
    
    if len(serials_found) == len(req_serials):
        score += 20
        feedback_parts.append("All instrument serial numbers found")
    elif len(serials_found) > 0:
        partial_score = int(20 * (len(serials_found) / len(req_serials)))
        score += partial_score
        feedback_parts.append(f"Some serial numbers missing ({len(serials_found)}/{len(req_serials)})")
    else:
        feedback_parts.append("No instrument serial numbers found")
        
    # --- CRITERION 6: Names (5 pts) ---
    names_ok = result.get('lab_name_found', False) and result.get('client_name_found', False)
    if names_ok:
        score += 5
        feedback_parts.append("Lab and Client names found")
    elif result.get('lab_name_found', False) or result.get('client_name_found', False):
        score += 2
        feedback_parts.append("One name missing")
    else:
        feedback_parts.append("Lab/Client names missing")
        
    # --- CRITERION 7: Technical Terms (10 pts) ---
    terms_found = result.get('terms_found', [])
    req_terms = metadata.get('required_terms', [])
    unique_terms = set(terms_found)
    
    if len(unique_terms) >= 3:
        score += 10
        feedback_parts.append(f"Technical terminology used ({len(unique_terms)} terms)")
    elif len(unique_terms) >= 1:
        score += 5
        feedback_parts.append("Minimal technical terminology")
    else:
        feedback_parts.append("No calibration terminology found")
        
    # --- CRITERION 8: Content Volume (10 pts) ---
    para_count = result.get('paragraph_count', 0)
    if para_count >= 30:
        score += 10
        feedback_parts.append(f"Document content substantial ({para_count} paragraphs)")
    elif para_count >= 10:
        score += 5
        feedback_parts.append(f"Document content minimal ({para_count} paragraphs)")
    else:
        feedback_parts.append("Document content insufficient")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }