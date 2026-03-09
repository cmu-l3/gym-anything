#!/usr/bin/env python3
"""
Verifier for compile_investigation_report task.

Verifies:
1. Valid JSON output file exists.
2. Recall: All "Operation Nightshade" cases from ground truth are present.
3. Precision: No unrelated cases (distractors) are present.
4. Accuracy: Field values (Case Number, Title, Priority) match.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_investigation_report(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # Temp files for extraction
    agent_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    truth_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_manifest_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')

    try:
        # 1. Get Manifest
        try:
            copy_from_env("/tmp/task_result.json", result_manifest_file.name)
            with open(result_manifest_file.name, 'r') as f:
                manifest = json.load(f)
        except Exception:
            return {"passed": False, "score": 0, "feedback": "Failed to retrieve task result manifest"}

        # Basic Check: File existence
        if not manifest.get("output_exists", False):
            return {"passed": False, "score": 0, "feedback": "Output file not found at /home/ga/Documents/nightshade_report.json"}
        
        score += 10 # File exists

        if manifest.get("file_created_during_task", False):
            score += 10 # Anti-gaming: Created now
        else:
            feedback_parts.append("Warning: File timestamp indicates it was not created during this session.")

        # 2. Get Agent Output and Ground Truth
        try:
            copy_from_env("/tmp/agent_output.json", agent_file.name)
            copy_from_env("/tmp/ground_truth.json", truth_file.name)
            
            with open(agent_file.name, 'r') as f:
                agent_data = json.load(f)
            with open(truth_file.name, 'r') as f:
                truth_data = json.load(f)
        except json.JSONDecodeError:
            return {"passed": False, "score": score, "feedback": "Output file is not valid JSON"}
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Error retrieving data files: {str(e)}"}

        if not isinstance(agent_data, list):
            return {"passed": False, "score": score, "feedback": "JSON root must be a list/array"}
        
        score += 10 # Valid JSON structure

        # 3. Analyze Content
        # Create dictionaries for easier lookup. 
        # Normalize keys to handle case sensitivity issues in field names slightly gracefully
        truth_map = {item['caseNumber']: item for item in truth_data}
        
        # Helper to normalize agent item keys
        def normalize_item(item):
            return {k.lower(): v for k, v in item.items()}
            
        agent_items_norm = [normalize_item(item) for item in agent_data]
        
        # Map agent items by case number (assuming key is 'casenumber' after normalization)
        agent_map = {}
        for item in agent_items_norm:
            cn = item.get('casenumber')
            if cn:
                agent_map[cn] = item

        # Metric A: Recall (Did they find the target cases?)
        # Max 30 points
        target_count = len(truth_map)
        found_count = 0
        missing_cases = []

        for case_num in truth_map:
            if case_num in agent_map:
                found_count += 1
            else:
                missing_cases.append(case_num)
        
        recall_score = (found_count / target_count) * 30
        score += int(recall_score)
        
        if found_count == target_count:
            feedback_parts.append(f"Found all {target_count} target cases.")
        else:
            feedback_parts.append(f"Missed {len(missing_cases)} target cases.")

        # Metric B: Precision (Did they avoid distractors?)
        # Max 20 points
        # Any case number in agent_map that IS NOT in truth_map is a distractor
        distractor_count = 0
        for case_num in agent_map:
            if case_num not in truth_map:
                distractor_count += 1
        
        if distractor_count == 0:
            score += 20
            feedback_parts.append("Precision perfect: No distractor cases included.")
        else:
            # Deduct points for distractors
            penalty = min(20, distractor_count * 10)
            score += (20 - penalty)
            feedback_parts.append(f"Included {distractor_count} irrelevant cases (distractors).")

        # Metric C: Data Accuracy (Title and Priority)
        # Max 20 points
        accuracy_points = 0
        accuracy_checks = 0
        
        for case_num, truth_item in truth_map.items():
            if case_num in agent_map:
                agent_item = agent_map[case_num]
                accuracy_checks += 1
                item_correct = True
                
                # Check Priority (Case-insensitive)
                if truth_item['priority'].lower() != agent_item.get('priority', '').lower():
                    item_correct = False
                    feedback_parts.append(f"Wrong priority for {case_num}.")
                
                # Check Title (Substring match allowed for robustness)
                if truth_item['title'] not in agent_item.get('title', ''):
                    # Try reverse check or loose match
                    if agent_item.get('title', '') not in truth_item['title']:
                        item_correct = False
                        feedback_parts.append(f"Title mismatch for {case_num}.")

                if item_correct:
                    accuracy_points += 1

        if accuracy_checks > 0:
            final_accuracy_score = (accuracy_points / accuracy_checks) * 20
            score += int(final_accuracy_score)
        elif found_count == 0:
            # If no cases found, no accuracy points possible
            pass

        # Final Evaluation
        passed = score >= 80 and found_count == target_count and distractor_count == 0

        return {
            "passed": passed,
            "score": score,
            "feedback": " ".join(feedback_parts)
        }

    finally:
        # Cleanup
        for fname in [agent_file.name, truth_file.name, result_manifest_file.name]:
            if os.path.exists(fname):
                os.unlink(fname)