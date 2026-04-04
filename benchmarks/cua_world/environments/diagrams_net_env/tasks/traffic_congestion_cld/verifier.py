#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_traffic_congestion_cld(traj, env_info, task_info):
    """
    Verifies the Traffic Congestion CLD task using exported XML data and VLM.
    """
    # 1. Setup & Data Retrieval
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment access failed"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    metadata = task_info.get('metadata', {})
    required_vars = metadata.get('required_variables', [])
    required_loops = metadata.get('required_loops', [])

    score = 0
    feedback = []

    # 2. Anti-Gaming Checks (10 pts)
    # File must define content and be modified after start
    file_mtime = result.get('mtime', 0)
    task_start = result.get('start_time', 0)
    
    if result.get('exists') and file_mtime > task_start:
        score += 10
        feedback.append("File modified during task (+10)")
    else:
        feedback.append("File not modified after start (0)")

    # 3. Structure Verification (XML Analysis)
    
    # Variable Count (Start: 6, Target: 14) -> 20 pts
    # We check if specifically required variables are present (fuzzy match)
    found_labels = [l.lower() for l in result.get('labels', [])]
    found_vars_count = 0
    
    for req in required_vars:
        # Simple substring match
        if any(req.lower() in label for label in found_labels):
            found_vars_count += 1
            
    if found_vars_count >= len(required_vars):
        score += 20
        feedback.append(f"All {found_vars_count} required variables added (+20)")
    elif found_vars_count >= 4:
        score += 10
        feedback.append(f"Some variables added ({found_vars_count}/{len(required_vars)}) (+10)")
    else:
        feedback.append(f"Missing most required variables (Found: {found_vars_count}) (0)")

    # Edge Count (Start: 3, Target: ~20) -> 15 pts
    edge_count = len(result.get('edges', []))
    if edge_count >= 15:
        score += 15
        feedback.append(f"Sufficient causal links created ({edge_count}) (+15)")
    elif edge_count >= 8:
        score += 8
        feedback.append(f"Partial links created ({edge_count}) (+8)")
    else:
        feedback.append(f"Too few links ({edge_count}) (0)")

    # Polarity Labels -> 15 pts
    polarities = result.get('polarities_found', 0)
    if polarities >= 12: # Expecting ~15-20 links
        score += 15
        feedback.append("Polarity labels present (+15)")
    elif polarities >= 5:
        score += 7
        feedback.append("Some polarity labels present (+7)")
    else:
        feedback.append(f"Missing polarity labels (+/-) (Found: {polarities}) (0)")

    # Loop Annotations -> 10 pts
    found_loops = result.get('loops_found', [])
    loops_matched = 0
    for req_loop in required_loops: # R1, B1, etc
        if any(req_loop in l for l in found_loops):
            loops_matched += 1
            
    if loops_matched >= 3:
        score += 10
        feedback.append(f"Feedback loops annotated ({loops_matched}) (+10)")
    else:
        feedback.append(f"Missing loop annotations (Found: {loops_matched}) (0)")

    # PDF Export -> 10 pts
    if result.get('pdf_exists') and result.get('pdf_size', 0) > 1000:
        score += 10
        feedback.append("PDF export successful (+10)")
    else:
        feedback.append("PDF export missing or empty (0)")

    # 4. VLM Verification (20 pts)
    # Check trajectory for manual editing and final structure
    frames = sample_trajectory_frames(traj, n=4)
    final_img = get_final_screenshot(traj)
    
    vlm_prompt = """
    Review this sequence of screenshots from a system dynamics modeling task in draw.io.
    
    1. Did the agent add new variable boxes and arrows?
    2. Does the final diagram look like a Causal Loop Diagram (circles of nodes connected by curved arrows)?
    3. Can you see +/- polarity signs on the arrows?
    4. Can you see loop identifiers like "R1" or "B1"?
    
    Answer JSON: {"work_visible": bool, "structure_correct": bool, "details": str}
    """
    
    try:
        vlm_res = query_vlm(images=frames + [final_img], prompt=vlm_prompt)
        parsed = vlm_res.get('parsed', {})
        
        if parsed.get('work_visible') and parsed.get('structure_correct'):
            score += 20
            feedback.append("VLM confirms manual work and correct structure (+20)")
        elif parsed.get('work_visible'):
            score += 10
            feedback.append("VLM confirms work but structure unclear (+10)")
        else:
            feedback.append("VLM did not observe significant diagramming work (0)")
    except Exception as e:
        logger.error(f"VLM verification failed: {e}")
        # Fallback credit if programmatic checks passed strongly
        if score >= 50:
            score += 10
            feedback.append("VLM check skipped, fallback credit (+10)")

    # Final Pass Determination
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }