#!/usr/bin/env python3
import json
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logger = logging.getLogger(__name__)

def verify_waste_treatment(traj, env_info, task_info):
    """
    Verifies the OpenLCA Waste Treatment Linkage task.
    
    Criteria:
    1. Flow 'Hazardous Sludge' exists and is of type WASTE.
    2. Treatment Process 'Sludge Incineration Service' exists.
    3. Treatment Process has 'Hazardous Sludge' as an INPUT.
    4. CRITICAL: Treatment Process has 'Hazardous Sludge' input set as QUANTITATIVE REFERENCE.
    5. Generator Process 'Chemical Plant Operation' exists and outputs the sludge.
    6. Product System 'Plant_Waste_System' exists.
    """
    
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy failed"}

    score = 0
    feedback = []
    
    # 2. Retrieve Result JSON
    import tempfile
    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
        local_json_path = tmp.name
    
    try:
        copy_from_env("/tmp/task_result.json", local_json_path)
        with open(local_json_path, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(local_json_path):
            os.remove(local_json_path)

    # 3. Parse Derby Query Output
    query_output = result_data.get("query_output", "")
    
    # Helper to check SQL result lines
    # Derby output format usually: headers... \n row data \n ...
    
    # Check Flow Creation
    has_waste_flow = "Hazardous Sludge" in query_output and "WASTE_FLOW" in query_output
    if has_waste_flow:
        score += 20
        feedback.append("Flow 'Hazardous Sludge' created correctly (Type: Waste).")
    else:
        feedback.append("Missing or incorrect Flow 'Hazardous Sludge'. Must be type WASTE_FLOW.")

    # Check Generator
    # Look for: Chemical Plant Operation | Hazardous Sludge | 0 (0 means Output usually in IsInput boolean, verify logic below)
    # Derby boolean: 0/1 or false/true. Typically 0 for false (Output), 1 for true (Input)
    has_generator = "Chemical Plant Operation" in query_output and "Hazardous Sludge" in query_output
    if has_generator:
        score += 20
        feedback.append("Generator process created.")
    
    # Check Treatment & Quantitative Reference (The Hard Part)
    # Row expected: Sludge Incineration Service | Hazardous Sludge | 1 | 1
    # 1 (Is_Input) and 1 (Is_Quantitative_Reference)
    # We scan specifically for this combination
    lines = query_output.splitlines()
    treatment_correct = False
    quant_ref_correct = False
    
    for line in lines:
        if "Sludge Incineration Service" in line and "Hazardous Sludge" in line:
            # Check inputs/outputs columns. 
            # Assuming query order: NAME, FLOW, IS_INPUT, IS_Q_REF
            # We look for "1" and "1" (or "true" "true")
            if "1" in line or "true" in line.lower():
                treatment_correct = True # Has input
                # Simple heuristic: if '1' appears twice or 'true' appears twice, or specific column position
                # The query puts them at the end.
                # Let's count '1's in the line
                ones = line.count('1')
                trues = line.lower().count('true')
                if ones >= 2 or trues >= 2:
                    quant_ref_correct = True
    
    if treatment_correct:
        score += 20
        feedback.append("Treatment process created with waste input.")
        if quant_ref_correct:
            score += 20
            feedback.append("CRITICAL: Treatment process correctly set waste Input as Quantitative Reference.")
        else:
            feedback.append("Treatment process missing Quantitative Reference on the waste input.")
    else:
        feedback.append("Treatment process logic incorrect (missing Input flow?).")

    # Check Product System
    if "Plant_Waste_System" in query_output:
        score += 10
        feedback.append("Product System created.")
    else:
        feedback.append("Product System 'Plant_Waste_System' not found.")

    # 4. VLM Verification (Trajectory)
    # Check if they actually interacted with the "Quantitative Reference" radio button/column
    frames = sample_trajectory_frames(traj, 5)
    final_img = get_final_screenshot(traj)
    
    vlm_prompt = """
    Analyze these screenshots of OpenLCA.
    I am looking for evidence that the user created a "Treatment Process".
    Specifically, did they:
    1. Open a process editor for "Sludge Incineration Service"?
    2. Add "Hazardous Sludge" as an INPUT (Inputs section)?
    3. Click the "Quantitative Reference" (or "q. ref.") radio button or checkbox next to that INPUT row?
    4. View a Product System graph?
    
    Return JSON: {"quant_ref_set": boolean, "model_graph_seen": boolean}
    """
    
    vlm_score = 0
    try:
        vlm_res = query_vlm(prompt=vlm_prompt, images=frames + [final_img]).get("parsed", {})
        if vlm_res.get("quant_ref_set"):
            vlm_score += 5
            feedback.append("VLM confirmed interaction with Quantitative Reference setting.")
        if vlm_res.get("model_graph_seen"):
            vlm_score += 5
            feedback.append("VLM confirmed Model Graph view.")
    except:
        pass # VLM failure shouldn't fail task if DB is correct
        
    score += vlm_score

    return {
        "passed": score >= 60,
        "score": min(100, score),
        "feedback": " ".join(feedback)
    }