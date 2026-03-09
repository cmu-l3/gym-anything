#!/usr/bin/env python3
"""
Verifier for Casualty Triage Onset Profiling task.
Verifies the JSON output against ground truth classifications and extracted text keywords.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_casualty_triage(traj, env_info, task_info):
    """
    Verify the agent's JSON report for correct structure, data extraction, and classification.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    ground_truth = metadata.get('ground_truth', {})
    onset_keywords = metadata.get('onset_keywords', {})
    expected_output_path = metadata.get('output_path', '/home/ga/Documents/triage_classification.json')

    # Copy result file
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(expected_output_path, temp_result.name)
        with open(temp_result.name, 'r') as f:
            data = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Output file triage_classification.json not found"}
    except json.JSONDecodeError:
        return {"passed": False, "score": 10, "feedback": "Output file exists but is not valid JSON"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading output file: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Validate structure
    if not isinstance(data, list):
        return {"passed": False, "score": 10, "feedback": "JSON root must be a list"}
    
    if len(data) != 5:
        return {"passed": False, "score": 15, "feedback": f"Expected 5 chemicals, found {len(data)}"}

    score = 10  # Base points for valid JSON file
    feedback_parts = []
    
    # Process each entry
    correct_classifications = 0
    correct_extractions = 0
    chemicals_found = 0

    # Create a lookup map for the agent's data (normalize names)
    agent_data_map = {}
    for item in data:
        name = item.get('chemical', '').strip()
        # Simple normalization to match "Sulfuric Acid" with "sulfuric acid"
        for key in ground_truth.keys():
            if key.lower() in name.lower():
                agent_data_map[key] = item
                break
    
    for chem_name, expected_category in ground_truth.items():
        if chem_name not in agent_data_map:
            feedback_parts.append(f"Missing chemical: {chem_name}")
            continue
        
        chemicals_found += 1
        entry = agent_data_map[chem_name]
        
        # Check extraction (Rate of Onset)
        # We check if the extracted text contains at least one expected keyword
        # This proves they actually looked it up rather than guessing
        extracted_onset = entry.get('rate_of_onset', '').lower()
        extracted_persistence = entry.get('persistence', '').lower()
        
        keywords = onset_keywords.get(chem_name, [])
        keyword_match = any(k in extracted_onset for k in keywords)
        
        if keyword_match and len(extracted_onset) > 3:
            correct_extractions += 1
        elif len(extracted_onset) < 3:
            feedback_parts.append(f"{chem_name}: Rate of onset text too short/empty")
        else:
            # If no keyword match but text exists, partial credit logic could apply, 
            # but strict verification prevents hallucination.
            feedback_parts.append(f"{chem_name}: Extracted text '{extracted_onset}' missing expected keywords {keywords}")

        # Check classification
        agent_category = entry.get('triage_category', '').upper().strip()
        if agent_category == expected_category:
            correct_classifications += 1
        else:
            feedback_parts.append(f"{chem_name}: Incorrect category '{agent_category}' (Expected {expected_category})")

    # Scoring Logic
    # 5 chemicals total
    # Extraction: 8 pts each (40 pts max)
    # Classification: 10 pts each (50 pts max)
    # File creation: 10 pts (already added)
    
    score += (correct_extractions * 8)
    score += (correct_classifications * 10)

    # Pass threshold
    # Must get at least 4/5 classifications correct AND valid data
    passed = (score >= 70) and (correct_classifications >= 4)

    final_feedback = f"Score: {score}/100. " + "; ".join(feedback_parts)
    if not feedback_parts:
        final_feedback += "All chemicals correctly extracted and classified."

    return {
        "passed": passed,
        "score": score,
        "feedback": final_feedback
    }