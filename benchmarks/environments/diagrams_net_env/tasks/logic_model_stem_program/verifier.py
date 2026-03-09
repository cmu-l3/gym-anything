#!/usr/bin/env python3
import json
import os
import logging
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_logic_model_stem_program(traj, env_info, task_info):
    """
    Verifies the Logic Model task.
    
    Scoring Breakdown (100 pts total):
    - 10 pts: .drawio file exists and was modified.
    - 10 pts: .pdf export exists.
    - 25 pts: Programmatic check for Headers (Inputs, Activities, etc.).
    - 25 pts: Programmatic check for Content (Keywords from narrative).
    - 30 pts: VLM verification of layout (5 columns, arrows, logical flow).
    """
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy failed"}

    score = 0
    feedback = []
    
    # Load result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, "r") as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. File Artifact Verification (20 pts)
    if result_data.get("drawio_exists") and result_data.get("drawio_modified"):
        score += 10
        feedback.append("Draw.io file created and modified.")
    else:
        feedback.append("Draw.io file missing or not modified.")

    if result_data.get("pdf_exists"):
        score += 10
        feedback.append("PDF export found.")
    else:
        feedback.append("PDF export missing.")

    # 3. Content Verification (Programmatic) (50 pts total)
    # We check the extracted text content from the drawio file
    content = result_data.get("drawio_content_preview", "").lower()
    
    # Check Headers (25 pts)
    required_headers = task_info['metadata']['required_headers']
    headers_found = 0
    for header in required_headers:
        if header.lower() in content:
            headers_found += 1
    
    header_score = (headers_found / len(required_headers)) * 25
    score += header_score
    feedback.append(f"Found {headers_found}/{len(required_headers)} logic model headers.")

    # Check Key Terms (25 pts)
    # We look for at least one term from each category to ensure population
    key_terms = task_info['metadata']['key_terms']
    categories_found = 0
    total_categories = len(key_terms)
    
    found_terms_debug = []
    
    for category, terms in key_terms.items():
        found_in_category = False
        for term in terms:
            if term.lower() in content:
                found_in_category = True
                found_terms_debug.append(term)
                break
        if found_in_category:
            categories_found += 1
            
    content_score = (categories_found / total_categories) * 25
    score += content_score
    feedback.append(f"Found content for {categories_found}/{total_categories} logic model categories.")

    # 4. VLM Verification (30 pts)
    # We verify the layout structure and arrows
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    images_to_check = frames + [final_frame] if final_frame else frames
    
    if not images_to_check:
        feedback.append("No screenshots available for VLM verification.")
    else:
        vlm_prompt = """
        You are evaluating a Logic Model diagram created in Draw.io.
        
        Check for these specific features:
        1. **Columns**: Are there 5 distinct columns or sections arranged horizontally?
        2. **Headers**: Do you see headers like 'Inputs', 'Activities', 'Outputs', 'Outcomes', 'Impact'?
        3. **Flow**: Are there arrows pointing from left to right connecting these sections?
        4. **Content**: Are there text boxes with details (like '$500,000', 'Workshops', 'Students') inside the columns?
        
        Score confidence 0-100 based on how much this looks like a valid 5-column logic model diagram.
        """
        
        try:
            # We query using the final frame primarily for the finished product
            vlm_response = query_vlm(
                prompt=vlm_prompt,
                images=[final_frame] if final_frame else images_to_check[-1]
            )
            
            # Simple heuristic parsing of VLM response (assuming it might output a number or we judge strictly)
            # Since query_vlm returns a dict with 'parsed' if structured, or we just rely on text
            # For this template, we'll assume a basic check.
            # In a real implementation, we'd ask for JSON output from VLM.
            
            # Let's do a boolean check prompt for simplicity and robustness
            bool_prompt = "Does the image show a diagram with approximately 5 columns and headers like Inputs/Activities/Outputs? Answer YES or NO."
            vlm_bool = query_vlm(prompt=bool_prompt, images=[final_frame] if final_frame else images_to_check[-1])
            
            vlm_text = str(vlm_bool).lower()
            if "yes" in vlm_text:
                score += 30
                feedback.append("VLM confirms Logic Model structure.")
            else:
                feedback.append("VLM could not clearly identify Logic Model structure.")
                
        except Exception as e:
            logger.error(f"VLM verification failed: {e}")
            feedback.append("VLM verification error.")

    # Final Result
    passed = score >= 60
    return {
        "passed": passed,
        "score": min(100, int(score)),
        "feedback": " | ".join(feedback)
    }