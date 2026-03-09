import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)

def verify_spindle_tracking(traj, env_info, task_info):
    """
    Verify the mitotic spindle intensity tracking task.
    Checks if the agent tracked the bright spindle pole correctly over time.
    """
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # 2. Get result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Scoring Criteria
    score = 0
    feedback = []
    
    # Criterion A: File created during task (20 pts)
    if result.get("output_exists") and result.get("file_created_during_task"):
        score += 20
        feedback.append("Output CSV created successfully.")
    elif result.get("output_exists"):
        score += 5
        feedback.append("Output CSV exists but timestamp suggests it wasn't created during this task.")
    else:
        return {"passed": False, "score": 0, "feedback": "Output CSV file not found."}

    # Criterion B: CSV Structure (20 pts)
    csv_data = result.get("csv_data", [])
    if len(csv_data) >= 5:
        score += 20
        feedback.append("CSV contains required number of data points.")
    elif len(csv_data) > 0:
        score += 10
        feedback.append(f"CSV contains incomplete data ({len(csv_data)} rows).")
    else:
        feedback.append("CSV is empty or unparseable.")

    # Criterion C: Tracking Accuracy (60 pts total)
    # We check specific frames. 
    # Logic: The spindle pole is a bright spot. 
    # Background/Cytoplasm intensity is typically < 100.
    # Spindle pole intensity is typically > 120 (often 150-250).
    # If the agent loses tracking (ROI stays in one place while pole moves),
    # the intensity will drop significantly in later frames.
    
    required_frames = [1, 10, 20, 30, 40]
    points_per_frame = 12
    intensity_threshold = 110.0  # Conservative threshold for "bright object"
    
    # Create a lookup map
    data_map = {item['frame']: item['intensity'] for item in csv_data}
    
    tracked_frames = 0
    
    for frame in required_frames:
        if frame in data_map:
            val = data_map[frame]
            # Check if value indicates a bright object (spindle pole)
            # We also check upper bound to avoid artifacts/errors
            if 110.0 <= val <= 255.0:
                score += points_per_frame
                tracked_frames += 1
            else:
                feedback.append(f"Frame {frame}: Value {val} seems incorrect (expected > {intensity_threshold}). Tracking lost?")
        else:
            feedback.append(f"Frame {frame}: Missing from data.")

    # 4. Final Verification
    passed = (score >= 64) # Requires file creation + correct tracking for at least 2 frames
    
    if tracked_frames == 5:
        feedback.append("Excellent! All frames tracked correctly.")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }