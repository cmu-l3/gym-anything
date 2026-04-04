#!/usr/bin/env python3
"""
Verifier for Decision Tree Classification task (JASP).
Checks:
1. .jasp file creation and internal configuration (Seed=123, Depth=4)
2. Report file content (Accuracy and Root Node)
3. Anti-gaming (timestamps)
"""

import json
import os
import zipfile
import tempfile
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_decision_tree_cancer(traj, env_info, task_info):
    """
    Verify the JASP decision tree task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    valid_root_nodes = [n.lower() for n in metadata.get('valid_root_nodes', ["pointsmean", "concavepointsmean"])]
    required_seed = metadata.get('required_seed', 123)
    required_depth = metadata.get('required_depth', 4)

    score = 0
    max_score = 100
    feedback_parts = []
    
    # =========================================================
    # Retrieve Result JSON
    # =========================================================
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # =========================================================
    # CRITERION 1: JASP Project File Existence & Config (50 pts)
    # =========================================================
    project_exists = result_data.get('project_exists', False)
    project_time_ok = result_data.get('project_valid_time', False)
    
    config_correct = False
    
    if project_exists and project_time_ok:
        score += 20
        feedback_parts.append("Project file created.")
        
        # Verify internal configuration by unzipping .jasp file
        temp_jasp = tempfile.NamedTemporaryFile(delete=False, suffix='.zip')
        try:
            copy_from_env("/tmp/cancer_tree.jasp", temp_jasp.name)
            
            # .jasp files are ZIPs. We search for configuration in the JSONs inside.
            with zipfile.ZipFile(temp_jasp.name, 'r') as z:
                # Iterate through all files in zip to find analysis config
                found_seed = False
                found_depth = False
                
                for filename in z.namelist():
                    if filename.endswith('.json'):
                        try:
                            content = z.read(filename).decode('utf-8', errors='ignore')
                            # Simple regex search to avoid complex JSON parsing of unknown JASP schema versions
                            # Looking for "seed": 123 or "seed":123
                            if re.search(f'["\']seed["\']\s*:\s*{required_seed}', content):
                                found_seed = True
                            # Looking for "maxDepth": 4 or "max_depth": 4
                            if re.search(f'["\']maxDepth["\']\s*:\s*{required_depth}', content, re.IGNORECASE):
                                found_depth = True
                        except:
                            continue
                
                if found_seed:
                    score += 15
                    feedback_parts.append(f"Seed verified ({required_seed}).")
                else:
                    feedback_parts.append(f"Incorrect/Missing Seed (Expected {required_seed}).")
                    
                if found_depth:
                    score += 15
                    feedback_parts.append(f"Max Depth verified ({required_depth}).")
                    config_correct = True
                else:
                    feedback_parts.append(f"Incorrect/Missing Max Depth (Expected {required_depth}).")

        except Exception as e:
            feedback_parts.append(f"Failed to inspect JASP file: {str(e)}")
        finally:
            if os.path.exists(temp_jasp.name):
                os.unlink(temp_jasp.name)
    else:
        feedback_parts.append("Project file missing or created before task start.")

    # =========================================================
    # CRITERION 2: Report Content (50 pts)
    # =========================================================
    report_exists = result_data.get('report_exists', False)
    report_content = result_data.get('report_content', "")
    
    if report_exists:
        # Check Accuracy (25 pts)
        # Look for "Test Accuracy: 0.94" or similar
        acc_match = re.search(r'Accuracy:?\s*(0\.\d+|1\.0|1)', report_content, re.IGNORECASE)
        accuracy_passed = False
        if acc_match:
            try:
                val = float(acc_match.group(1))
                if 0.85 <= val <= 1.0:
                    score += 25
                    accuracy_passed = True
                    feedback_parts.append(f"Accuracy reported correctly ({val}).")
                else:
                    feedback_parts.append(f"Reported accuracy {val} out of expected range (0.85-1.0).")
            except:
                feedback_parts.append("Could not parse accuracy value.")
        else:
            feedback_parts.append("Accuracy not found in report.")

        # Check Root Node (25 pts)
        # Check if any valid root node name appears in the report
        root_match = False
        for valid_node in valid_root_nodes:
            if valid_node in report_content.lower():
                root_match = True
                break
        
        if root_match:
            score += 25
            feedback_parts.append("Root split variable identified correctly.")
        else:
            feedback_parts.append("Root split variable incorrect or missing.")
    else:
        feedback_parts.append("Report file missing.")

    # =========================================================
    # Final Result
    # =========================================================
    passed = (score >= 75)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }