#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_http_traffic_json_export(traj, env_info, task_info):
    """
    Verify the HTTP traffic JSON export task.
    
    Criteria:
    1. Output file exists and was created during the task.
    2. Output file is valid JSON.
    3. Output contains the correct number of packets (HTTP Requests only).
    4. Required fields are present in the output.
    5. Data values match ground truth (generated via tshark).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    score = 0
    max_score = 100
    feedback = []

    # Temporary directory for file retrieval
    with tempfile.TemporaryDirectory() as temp_dir:
        result_json_path = os.path.join(temp_dir, "task_result.json")
        agent_output_path = os.path.join(temp_dir, "http_requests.json")
        ground_truth_path = os.path.join(temp_dir, "ground_truth.json")

        # 1. Retrieve Result Metadata
        try:
            copy_from_env("/tmp/task_result.json", result_json_path)
            with open(result_json_path, 'r') as f:
                result_meta = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result metadata: {str(e)}"}

        # Check file existence and creation time
        if not result_meta.get("output_exists"):
            return {"passed": False, "score": 0, "feedback": "Output file 'http_requests.json' was not found."}
        
        score += 10
        feedback.append("Output file exists.")

        if not result_meta.get("created_during_task"):
            feedback.append("Warning: Output file timestamp is older than task start (potential anti-gaming check failed).")
            # We don't fail immediately but penalize or warn
        else:
            score += 10
            feedback.append("Output file created during task.")

        # 2. Retrieve and Load Files
        try:
            copy_from_env("/home/ga/Documents/captures/http_requests.json", agent_output_path)
            copy_from_env("/tmp/ground_truth.json", ground_truth_path)
            
            with open(agent_output_path, 'r') as f:
                agent_data = json.load(f)
            
            with open(ground_truth_path, 'r') as f:
                ground_truth_data = json.load(f)
                
        except json.JSONDecodeError:
            return {"passed": False, "score": score, "feedback": "Output file is not valid JSON."}
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Error reading output or ground truth: {str(e)}"}

        score += 10
        feedback.append("Output file is valid JSON.")

        # 3. Verify Packet Count (Filtering Logic)
        # Ground truth was generated with -Y "http.request"
        expected_count = len(ground_truth_data)
        agent_count = len(agent_data)
        
        if agent_count == expected_count:
            score += 20
            feedback.append(f"Correct packet count: {agent_count}.")
        else:
            feedback.append(f"Packet count mismatch: Expected {expected_count} (HTTP Requests), got {agent_count}.")
            # If they didn't filter requests (e.g. included responses), count will be higher
            if agent_count > expected_count:
                 feedback.append("Hint: Ensure you filtered for HTTP Requests only (exclude responses).")
            return {"passed": False, "score": score, "feedback": " ".join(feedback)}

        # 4. Verify Fields and Data Content
        # We check the first and last packet to ensure fields are extracted correctly.
        required_fields = task_info['metadata']['required_fields']
        
        # Helper to extract a flattened value from tshark's JSON structure
        # Tshark JSON format: source -> layers -> field -> [value]
        # Agent might produce flat JSON or Tshark JSON. We try to be flexible.
        def get_val(item, field):
            # Check for tshark structure
            if "_source" in item and "layers" in item["_source"]:
                layers = item["_source"]["layers"]
                if field in layers:
                    return layers[field][0] # tshark arrays values
            # Check for flat structure
            if field in item:
                return item[field]
            return None

        fields_score = 0
        data_match_score = 0
        
        # Check first packet
        gt_item = ground_truth_data[0]
        agent_item = agent_data[0]
        
        missing_fields = []
        mismatched_data = []

        for field in required_fields:
            gt_val = get_val(gt_item, field)
            agent_val = get_val(agent_item, field)
            
            if agent_val is None:
                missing_fields.append(field)
            elif str(agent_val) != str(gt_val):
                # Allow minor formatting diffs (e.g. float precision) but mostly exact match expected
                mismatched_data.append(f"{field} (Expected: {gt_val}, Got: {agent_val})")

        if not missing_fields:
            fields_score += 25
            feedback.append("All required fields are present.")
        else:
            feedback.append(f"Missing fields: {', '.join(missing_fields)}.")

        if not mismatched_data:
            data_match_score += 25
            feedback.append("Data values match ground truth.")
        else:
            feedback.append(f"Data mismatch in first record: {'; '.join(mismatched_data[:3])}...")

        score += fields_score + data_match_score

    # Final Pass Determination
    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }