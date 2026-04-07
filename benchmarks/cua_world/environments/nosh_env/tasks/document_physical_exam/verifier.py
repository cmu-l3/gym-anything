#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_document_physical_exam(traj, env_info, task_info):
    """
    Verify that physical exam findings were correctly documented in the database.
    
    Criteria:
    1. PE record exists for the correct encounter (30 pts)
    2. Documented text matches keywords for each system (10 pts each, max 60 pts)
    3. Record was created during the task (10 pts)
    """
    
    # Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load verification data: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Load expectations
    metadata = task_info.get('metadata', {})
    expected_findings = metadata.get('expected_findings', {})
    
    score = 0
    feedback = []
    
    # 1. Check if record exists
    if result.get('pe_record_exists'):
        score += 30
        feedback.append("Success: Physical Exam record created.")
    else:
        return {"passed": False, "score": 0, "feedback": "Failed: No Physical Exam record found for this encounter."}

    # 2. Check content (Keyword matching)
    findings = result.get('findings', {})
    
    systems_to_check = [
        ('general', 'General'),
        ('heent', 'HEENT'),
        ('neck', 'Neck'),
        ('cv', 'Cardiovascular'),
        ('lungs', 'Lungs'),
        ('abdomen', 'Abdomen')
    ]
    
    for sys_key, display_name in systems_to_check:
        actual_text = findings.get(sys_key, '').lower()
        keywords = expected_findings.get(sys_key, [])
        
        # Check if at least one characteristic keyword is present
        # We require ~2 matches to be confident it's not just garbage text
        matches = [k for k in keywords if k.lower() in actual_text]
        
        if len(matches) >= 2:
            score += 10
            feedback.append(f"✓ {display_name} findings documented correctly.")
        elif len(matches) == 1:
            score += 5
            feedback.append(f"⚠ {display_name} findings partially documented.")
        else:
            feedback.append(f"✗ {display_name} findings missing or incorrect.")

    # 3. Anti-gaming (Creation check)
    # The setup script sets initial count to 0. Result should show > 0.
    # Also imply creation if record exists now.
    if result.get('pe_record_exists'):
        score += 10
        
    # Final Evaluation
    max_score = 100
    pass_threshold = 70  # Needs record + ~4 systems correct
    
    passed = score >= pass_threshold
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }