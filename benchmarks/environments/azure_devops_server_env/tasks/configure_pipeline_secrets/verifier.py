#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_pipeline_secrets(traj, env_info, task_info):
    """
    Verifies that the agent configured the variable group and updated the pipeline.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Use a temporary file to retrieve the result JSON from the Windows VM
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_file_path = temp_file.name
    temp_file.close()

    try:
        # The path in the VM is C:\Users\Docker\task_result.json
        # The copy_from_env function handles the abstraction
        copy_from_env("C:\\Users\\Docker\\task_result.json", temp_file_path)
        
        with open(temp_file_path, 'r') as f:
            result = json.load(f)
            
    except Exception as e:
        logger.error(f"Failed to copy or parse result: {e}")
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve verification data: {str(e)}"}
    finally:
        if os.path.exists(temp_file_path):
            os.unlink(temp_file_path)

    score = 0
    feedback_parts = []
    
    # Criterion 1: Variable Group Exists (10 pts)
    if result.get('vg_exists', False):
        score += 10
        feedback_parts.append("Variable Group 'PaymentService-Prod' created.")
    else:
        feedback_parts.append("Variable Group 'PaymentService-Prod' NOT found.")

    # Criterion 2: Variables Correct (20 pts)
    if result.get('vars_correct', False):
        score += 20
        feedback_parts.append("Variables 'Gateway_Url' and 'Region_Code' set correctly.")
    else:
        feedback_parts.append("Variables missing or incorrect values.")

    # Criterion 3: Secret Key Secure (20 pts)
    if result.get('secret_secure', False):
        score += 20
        feedback_parts.append("'Live_Secret_Key' is correctly set as a secret.")
    else:
        feedback_parts.append("'Live_Secret_Key' is missing or NOT locked as secret.")

    # Criterion 4: Pipeline YAML Updated (20 pts)
    if result.get('yaml_updated', False):
        score += 20
        feedback_parts.append("azure-pipelines.yml references the variable group.")
    else:
        feedback_parts.append("azure-pipelines.yml does not reference the variable group.")

    # Criterion 5: Valid YAML Structure (30 pts)
    # We parse the content string captured by the export script
    yaml_content = result.get('yaml_content_sample', "")
    yaml_valid = False
    
    if yaml_content:
        # Simple structural check
        # We look for "variables:" followed by "- group: PaymentService-Prod"
        # Since indentation matters, we check strict simple patterns or standard yaml parsing if strictly required.
        # Given limitations, we check line logic.
        lines = [l.strip() for l in yaml_content.splitlines()]
        if 'variables:' in lines:
            # Basic check passes
            # Check for the group reference
            if any(line.startswith('- group: PaymentService-Prod') or line.startswith('- group: "PaymentService-Prod"') for line in lines):
                 # This is a loose check, but assumes the YAML isn't completely broken if the 'variables' key exists.
                 # A more robust check would use a yaml parser, but we avoid external deps here if possible.
                 yaml_valid = True
        
        # Also support the inline syntax `variables: { group: PaymentService-Prod }`?
        # The prompt asked for standard syntax.
        
        # Check if the text "group: PaymentService-Prod" is inside the yaml
        if "group: PaymentService-Prod" in yaml_content:
             yaml_valid = True

    if yaml_valid:
        score += 30
        feedback_parts.append("YAML syntax appears valid.")
    else:
        feedback_parts.append("YAML structure for variable group is invalid or missing.")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }