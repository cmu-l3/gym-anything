#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_ghs_sds_creation(traj, env_info, task_info):
    """
    Verifies the GHS Safety Data Sheet creation task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # Define verification weights
    SCORES = {
        "file_exists": 10,
        "valid_odt": 10,
        "structure": 40,   # 2.5 pts per section * 16
        "ingredients": 20, # Table + CAS numbers
        "hazards": 10,
        "formatting": 10   # Footer
    }

    # Load result from environment
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve or parse verification results: {str(e)}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. File Existence & Validity
    if result.get("file_exists"):
        score += SCORES["file_exists"]
        feedback_parts.append("File created")
        if result.get("valid_odt"):
            score += SCORES["valid_odt"]
            feedback_parts.append("Valid ODT format")
        else:
            feedback_parts.append("Invalid ODT format")
            return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
    else:
        return {"passed": False, "score": 0, "feedback": "Output file not found"}

    # 2. Structure (Headings)
    # We expect 16 sections formatted with Heading 1
    found_sections = result.get("sections_found", [])
    heading_count = result.get("heading_count", 0)
    
    # Calculate score based on found numbered sections
    structure_score = len(found_sections) * 2.5
    if structure_score > SCORES["structure"]: structure_score = SCORES["structure"]
    
    score += structure_score
    if len(found_sections) == 16:
        feedback_parts.append("All 16 GHS sections found")
    else:
        feedback_parts.append(f"Found {len(found_sections)}/16 GHS sections")

    # 3. Ingredients Table
    # Table must exist and CAS numbers must be present
    table_score = 0
    if result.get("table_count", 0) > 0:
        table_score += 10
        feedback_parts.append("Ingredients table found")
    else:
        feedback_parts.append("No table found")
        
    cas_found = result.get("cas_numbers_found", [])
    if len(cas_found) >= 3:
        table_score += 10
        feedback_parts.append("All CAS numbers present")
    elif len(cas_found) > 0:
        table_score += 5
        feedback_parts.append(f"Some CAS numbers missing ({len(cas_found)}/3 found)")
    else:
        feedback_parts.append("CAS numbers missing")
        
    score += table_score

    # 4. Hazards
    if result.get("hazard_text_found"):
        score += SCORES["hazards"]
        feedback_parts.append("Hazard text correct")
    else:
        feedback_parts.append("Hazard text missing")

    # 5. Formatting (Footer)
    if result.get("footer_found"):
        score += SCORES["formatting"]
        feedback_parts.append("Footer revision date found")
    else:
        feedback_parts.append("Footer missing")

    # Final Pass Check
    # Need at least 70 points AND the file must be valid AND have table
    passed = (score >= 70) and (result.get("table_count", 0) > 0)
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " | ".join(feedback_parts)
    }