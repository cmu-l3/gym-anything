#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_gdpr_data_lineage(traj, env_info, task_info):
    """
    Verifies the GDPR Data Lineage Diagram task.
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

    # ---------------------------------------------------------
    # SCORING LOGIC
    # ---------------------------------------------------------
    score = 0
    feedback = []
    
    # 1. File Modification (5 pts)
    if result.get("file_modified"):
        score += 5
        feedback.append("File modified successfully.")
    else:
        feedback.append("File was NOT modified.")

    # 2. Shape Count (15 pts)
    # Started with 6 shapes. Expected addition of ~13 systems + processors.
    # Total should be > 18.
    shape_count = result.get("shape_count", 0)
    if shape_count >= 25:
        score += 15
        feedback.append(f"Excellent shape count ({shape_count}).")
    elif shape_count >= 15:
        score += 10
        feedback.append(f"Good shape count ({shape_count}).")
    elif shape_count > 6:
        score += 5
        feedback.append(f"Some shapes added ({shape_count}), but many missing.")
    else:
        feedback.append("No significant shapes added.")

    # 3. Edge Count (10 pts)
    # Started with 3 edges. Should add connections for all new systems.
    edge_count = result.get("edge_count", 0)
    if edge_count >= 20:
        score += 10
        feedback.append(f"Strong connectivity ({edge_count} edges).")
    elif edge_count >= 10:
        score += 5
        feedback.append(f"Basic connectivity ({edge_count} edges).")
    else:
        feedback.append("Diagram is poorly connected.")

    # 4. System Names Verification (25 pts)
    # Check if required systems are in the text content
    required_systems = task_info['metadata']['required_systems']
    text_content = " ".join(result.get("text_content", [])).lower()
    
    found_systems = 0
    for system in required_systems:
        if system.lower() in text_content:
            found_systems += 1
            
    # Calculate percentage of systems found
    system_score = 0
    if len(required_systems) > 0:
        pct_found = found_systems / len(required_systems)
        system_score = int(25 * pct_found)
    
    score += system_score
    feedback.append(f"Found {found_systems}/{len(required_systems)} required systems.")

    # 5. GDPR Annotations (15 pts)
    # Check for terms like "Art. 6", "Consent", "Retention"
    gdpr_terms = task_info['metadata']['gdpr_terms']
    found_terms = 0
    for term in gdpr_terms:
        if term.lower() in text_content:
            found_terms += 1
    
    if found_terms >= 4:
        score += 15
        feedback.append("GDPR annotations present.")
    elif found_terms >= 2:
        score += 8
        feedback.append("Some GDPR annotations found.")
    else:
        feedback.append("Missing GDPR legal basis/retention labels.")

    # 6. Color Coding (5 pts)
    if result.get("color_coding_used"):
        score += 5
        feedback.append("Color coding applied.")
    else:
        feedback.append("Failed to apply distinct color coding.")

    # 7. Multi-page / Cross-Border Page (15 pts)
    if result.get("page_count", 0) >= 2:
        score += 10
        if result.get("cross_border_page"):
            score += 5
            feedback.append("Cross-Border page created and titled correctly.")
        else:
            feedback.append("Second page created but title doesn't match 'Cross-Border'.")
    else:
        feedback.append("Failed to create second page.")

    # 8. PDF Export (10 pts)
    if result.get("pdf_exists") and result.get("pdf_size", 0) > 1000:
        score += 10
        feedback.append("PDF export successful.")
    else:
        feedback.append("PDF export missing or empty.")

    # Final Check
    passed = score >= 60 and result.get("file_modified")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }