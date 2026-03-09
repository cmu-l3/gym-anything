#!/usr/bin/env python3
"""
Verifier for Rail Transport STCC Lookup task.
Checks if the agent correctly extracted STCC codes, Hazard Classes, and Labels for 5 chemicals
and saved them in the requested JSON format.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_rail_transport_stcc_lookup(traj, env_info, task_info):
    """
    Verifies the rail manifest JSON output.
    """
    # 1. Setup and helper functions
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    def normalize_string(s):
        """Normalize string for comparison (lower case, strip)."""
        if not isinstance(s, str):
            return str(s)
        return s.lower().strip()

    # 2. Ground Truth Data
    # Note: STCCs and Classes can have slight variations in display, we look for key substrings.
    ground_truth = {
        "chlorine": {
            "stcc_indicators": ["4904210", "4920523"], # Common STCCs for Chlorine
            "class_indicators": ["2.3"],
            "label_indicators": ["poison gas", "toxic gas"]
        },
        "vinyl chloride": {
            "stcc_indicators": ["4905792"],
            "class_indicators": ["2.1"],
            "label_indicators": ["flammable gas"]
        },
        "styrene": {
            "stcc_indicators": ["4907265"],
            "class_indicators": ["3"],
            "label_indicators": ["flammable liquid"]
        },
        "propane": {
            "stcc_indicators": ["4905781"],
            "class_indicators": ["2.1"],
            "label_indicators": ["flammable gas"]
        },
        "ammonia": {
            "stcc_indicators": ["4904210", "4920359", "4904877"],
            "class_indicators": ["2.2", "2.3"], # Domestic 2.2, Int'l 2.3 often cited
            "label_indicators": ["non-flammable gas", "poison gas", "toxic gas"]
        }
    }

    score = 0
    max_score = 100
    feedback_parts = []

    # 3. Retrieve Result Metadata
    temp_meta = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_meta.name)
        with open(temp_meta.name, 'r') as f:
            meta = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task metadata: {e}"}
    finally:
        if os.path.exists(temp_meta.name):
            os.unlink(temp_meta.name)

    # 4. Check File Existence and Creation (Anti-Gaming)
    if not meta.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output file ~/Documents/rail_manifest.json not found."}
    
    score += 10 # File exists
    
    if meta.get("file_created_during_task", False):
        score += 10 # File created during task
    else:
        feedback_parts.append("Warning: Output file timestamp indicates it wasn't created during this task session.")

    # 5. Retrieve and Parse Content
    temp_output = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/home/ga/Documents/rail_manifest.json", temp_output.name)
        with open(temp_output.name, 'r') as f:
            data = json.load(f)
            
        if not isinstance(data, list):
            return {"passed": False, "score": score, "feedback": "JSON root must be a list of objects."}
            
        score += 10 # Valid JSON list
        
    except json.JSONDecodeError:
        return {"passed": False, "score": score, "feedback": "Output file is not valid JSON."}
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Error reading output file: {e}"}
    finally:
        if os.path.exists(temp_output.name):
            os.unlink(temp_output.name)

    # 6. Verify Content
    chemicals_found = 0
    stcc_correct = 0
    class_correct = 0
    label_correct = 0
    
    # Points per field (5 chemicals * 3 fields = 15 checks)
    # Total remaining points = 70. 
    # Let's allocate: 
    # - 10 points for having all 5 chemicals
    # - 60 points for data accuracy (4 points per correct field value per chemical)
    
    processed_chemicals = set()

    for entry in data:
        chem_name = normalize_string(entry.get("chemical", ""))
        
        # Identify which chemical this entry corresponds to
        matched_key = None
        for key in ground_truth:
            if key in chem_name:
                matched_key = key
                break
        
        if not matched_key:
            continue
            
        if matched_key in processed_chemicals:
            continue # specific chemical already processed
            
        processed_chemicals.add(matched_key)
        chemicals_found += 1
        
        gt = ground_truth[matched_key]
        
        # Check STCC
        val_stcc = normalize_string(entry.get("stcc_number", ""))
        if any(ind in val_stcc for ind in gt["stcc_indicators"]):
            stcc_correct += 1
            
        # Check Class
        val_class = normalize_string(entry.get("hazard_class", ""))
        if any(ind in val_class for ind in gt["class_indicators"]):
            class_correct += 1
            
        # Check Label
        val_label = normalize_string(entry.get("hazard_label", ""))
        if any(ind in val_label for ind in gt["label_indicators"]):
            label_correct += 1

    # Scoring details
    if chemicals_found == 5:
        score += 10
        feedback_parts.append("All 5 chemicals found in output.")
    else:
        feedback_parts.append(f"Found {chemicals_found}/5 chemicals.")
        
    # Accuracy scoring (max 60 points distributed)
    # We have 5 chemicals. Each has 3 fields. Total 15 items to check.
    # 60 points / 15 items = 4 points per correct item.
    
    accuracy_points = (stcc_correct * 4) + (class_correct * 4) + (label_correct * 4)
    score += accuracy_points
    
    feedback_parts.append(f"STCC Accuracy: {stcc_correct}/5")
    feedback_parts.append(f"Class Accuracy: {class_correct}/5")
    feedback_parts.append(f"Label Accuracy: {label_correct}/5")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }