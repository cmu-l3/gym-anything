#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_import_scan_sequence_twos(traj, env_info, task_info):
    """
    Verifies that the agent imported the image sequence and set it "on twos".
    
    Criteria:
    1. Output files exist and count is approx double input (12 input -> ~24 output).
    2. Files were created during the task.
    3. Visual pattern analysis shows alternating static/changing frames.
       - "On Twos" pattern: Frame 1==2, 2!=3, 3==4, 4!=5...
       - Difference metric: [Low, High, Low, High, ...]
    """
    
    # 1. Retrieve result from environment
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve/parse verification data: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Metrics
    file_count = result.get('file_count', 0)
    files_created = result.get('files_created_during_task', 0)
    diffs = result.get('pattern_analysis', [])
    error = result.get('error', '')

    score = 0
    feedback = []

    if error:
        feedback.append(f"Error during analysis: {error}")

    # Criterion 1: File Count (Target: ~24 frames)
    # We allow some flexibility (e.g. 23-26 frames)
    if file_count >= 20:
        score += 20
        feedback.append(f"Frame count sufficient ({file_count} frames).")
    elif file_count >= 12:
        score += 10
        feedback.append(f"Frame count low ({file_count} frames). Did you expand the exposure?")
    else:
        feedback.append(f"Frame count too low ({file_count}).")

    # Criterion 2: Anti-Gaming (Files created during task)
    if files_created >= 20:
        score += 20
        feedback.append("Output files created during task session.")
    elif files_created > 0:
        score += 10
        feedback.append(f"Only {files_created} new files detected.")
    else:
        return {"passed": False, "score": 0, "feedback": "No new output files were created."}

    # Criterion 3: Pattern Analysis ("On Twos")
    # Expected Diffs: [Low, High, Low, High, Low, High...]
    # We classify each transition as "Static" (Low diff) or "Change" (High diff)
    # Threshold for "Static": < 50 (MSE for 0-255 images) - nearly identical
    # Threshold for "Change": > 100 - definitely different
    
    # Analyze the sequence of differences
    # We look for pairs: (Diff[i], Diff[i+1]). 
    # Ideal "Twos": (Low, High), (Low, High)...
    
    twos_score = 0
    matches = 0
    total_pairs = 0
    
    threshold_static = 10.0 # Strict for generated synthetic data (should be 0)
    
    if len(diffs) > 10:
        # Check for low-high pattern
        for i in range(0, len(diffs)-1, 2):
            d1 = diffs[i]   # Frame 1->2 (Should be static)
            if i+1 < len(diffs):
                d2 = diffs[i+1] # Frame 2->3 (Should be change)
                
                # Check pair
                is_static = d1 < threshold_static
                is_change = d2 > threshold_static
                
                if is_static and is_change:
                    matches += 1
                
                total_pairs += 1

        if total_pairs > 0:
            match_rate = matches / total_pairs
            if match_rate > 0.8: # >80% of pairs match pattern
                twos_score = 60
                feedback.append("Perfect 'On Twos' timing pattern detected.")
            elif match_rate > 0.5:
                twos_score = 30
                feedback.append("Inconsistent timing pattern detected.")
            else:
                feedback.append("Timing does not match 'On Twos'. Frames appear to change every frame or not at all.")
                
                # Check if it's "On Ones" (High, High, High...)
                high_count = sum(1 for d in diffs if d > threshold_static)
                if high_count / len(diffs) > 0.9:
                    feedback.append("Detected animation 'On Ones' (changes every frame). Did you stretch the exposure?")
    else:
        feedback.append("Not enough frames to analyze timing pattern.")

    score += twos_score

    # Final Pass Logic
    passed = score >= 80 # Needs file count + creation + timing
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback),
        "details": {
            "file_count": file_count,
            "matches": matches,
            "total_pairs": total_pairs,
            "diffs_sample": diffs[:10]
        }
    }