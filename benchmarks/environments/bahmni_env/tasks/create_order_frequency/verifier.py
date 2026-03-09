#!/usr/bin/env python3
"""
Verifier for create_order_frequency task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_order_frequency(traj, env_info, task_info):
    """
    Verify the creation of the Order Frequency and its backing Concept.
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Verify Concept Creation (40 pts)
    if result.get('concept_exists'):
        score += 30
        feedback_parts.append("Concept '5 Times Daily' created.")
        
        # Check properties (10 pts)
        cls = result.get('concept_class', '')
        dtype = result.get('concept_datatype', '')
        
        # Accept Frequency or Misc for class, N/A for datatype
        if ('Frequency' in cls or 'Misc' in cls) and 'N/A' in dtype:
            score += 10
            feedback_parts.append("Concept properties correct.")
        else:
            feedback_parts.append(f"Concept properties incorrect (Class: {cls}, Datatype: {dtype}).")
    else:
        feedback_parts.append("Concept '5 Times Daily' NOT found.")

    # 2. Verify Order Frequency Creation (60 pts)
    if result.get('order_frequency_exists'):
        score += 40
        feedback_parts.append("Order Frequency created.")
        
        # Check Frequency value (10 pts)
        try:
            freq = float(result.get('frequency_per_day', 0))
            if abs(freq - 5.0) < 0.01:
                score += 10
                feedback_parts.append("Frequency per day is 5.")
            else:
                feedback_parts.append(f"Frequency per day incorrect (found {freq}, expected 5).")
        except:
            feedback_parts.append("Could not parse frequency value.")
            
        # Check Linkage (10 pts)
        # We checked linkage in export_result.sh (ORDER_FREQ_EXISTS is only true if it links to the specific concept UUID)
        # But let's double check the name matches
        linked_name = result.get('linked_concept_name', '')
        if linked_name == '5 Times Daily':
            score += 10
            feedback_parts.append("Order Frequency linked to correct concept.")
        else:
            feedback_parts.append(f"Order Frequency linked to wrong concept ('{linked_name}').")
    else:
        feedback_parts.append("Order Frequency NOT found or not linked to the new concept.")

    # Pass threshold
    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }