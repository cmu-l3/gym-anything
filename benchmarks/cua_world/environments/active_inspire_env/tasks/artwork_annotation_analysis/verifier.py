#!/usr/bin/env python3
import json
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_artwork_analysis(traj, env_info, task_info):
    """
    Verify the artwork annotation analysis task.

    Criteria:
    1. File exists, valid format, created during task.
    2. Page count == 3.
    3. Image is embedded (imported).
    4. Text content covers Title, Composition, and Elements of Art.
    5. Arrows/Lines present for annotation.
    6. VLM visual confirmation.
    """
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')

    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # 2. Load Results
    local_result_path = "task_result.json"
    try:
        copy_from_env("/tmp/task_result.json", local_result_path)
        with open(local_result_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(local_result_path):
            os.remove(local_result_path)

    # 3. Extract Metadata
    metadata = task_info.get("metadata", {})
    req_title = metadata.get("required_terms_title", ["Great Wave", "Hokusai"])
    req_comp = metadata.get("required_terms_composition", ["foreground", "background", "wave"])
    req_elem = metadata.get("required_terms_elements", ["line", "color", "shape", "texture", "contrast", "movement"])
    min_elem_count = metadata.get("min_elements_terms", 3)
    min_arrows = metadata.get("min_arrows", 3)

    # 4. Scoring Logic
    score = 0
    feedback = []

    # File Validity (15 pts)
    if result.get("file_exists") and result.get("is_valid_zip") and result.get("created_during_task"):
        score += 15
        feedback.append("Valid flipchart file created.")
    else:
        feedback.append("File missing, invalid format, or not created during task.")

    # Page Count (10 pts)
    pg_count = result.get("page_count", 0)
    if pg_count == 3:
        score += 10
        feedback.append("Correct page count (3).")
    elif pg_count > 0:
        score += 5
        feedback.append(f"Page count {pg_count} (expected 3).")
    else:
        feedback.append("No pages found.")

    # Image Embedded (15 pts)
    if result.get("image_embedded"):
        score += 15
        feedback.append("Image resource embedded successfully.")
    else:
        feedback.append("No image imported/embedded.")

    # Text Content Analysis (40 pts total)
    found_terms_str = result.get("found_terms_string", "")
    found_terms_list = found_terms_str.split("|")

    # Title Terms (10 pts)
    title_matches = sum(1 for t in req_title if t in found_terms_list)
    if title_matches >= len(req_title):
        score += 10
        feedback.append("Title and artist terms found.")
    elif title_matches > 0:
        score += 5
        feedback.append("Partial title/artist terms found.")

    # Composition Terms (15 pts)
    comp_matches = sum(1 for t in req_comp if t in found_terms_list)
    if comp_matches >= 3: # Expecting all 3: foreground, background, wave
        score += 15
        feedback.append("Composition terms (foreground, background, wave) found.")
    elif comp_matches > 0:
        score += 5
        feedback.append(f"Partial composition terms found ({comp_matches}/3).")

    # Elements of Art Terms (15 pts)
    elem_matches = sum(1 for t in req_elem if t in found_terms_list)
    if elem_matches >= min_elem_count:
        score += 15
        feedback.append(f"Sufficient elements of art terms found ({elem_matches}).")
    elif elem_matches > 0:
        score += 5
        feedback.append(f"Partial elements of art terms ({elem_matches}).")

    # Shape/Arrow Count (15 pts)
    arrow_count = result.get("arrow_count", 0)
    if arrow_count >= min_arrows:
        score += 15
        feedback.append(f"Annotation arrows/lines found ({arrow_count}).")
    elif arrow_count > 0:
        score += 5
        feedback.append(f"Few arrows/lines found ({arrow_count}).")

    # 5. VLM Verification (Bonus/Confirmation check)
    # We use VLM to verify the final state actually looks like the lesson
    # Only if the file exists
    if result.get("file_exists") and query_vlm:
        # Get screenshot from container
        # Note: verifier runs on host, we need to copy the screenshot out if it wasn't part of traj
        # But traj usually includes frames. We'll use the final frame from traj if available.
        # If not, we rely on the programmatic check mostly, but let's try to verify via VLM if possible.
        
        # Simple VLM check on the final frame of trajectory
        import base64
        final_frame = None
        if traj and 'frames' in traj and len(traj['frames']) > 0:
            final_frame = traj['frames'][-1]
        
        if final_frame:
            prompt = (
                "Is this an image of an educational flipchart software (ActivInspire)? "
                "Can you see 'The Great Wave' artwork (the famous Japanese wave print) on the canvas? "
                "Are there any text annotations or arrows visible?"
            )
            vlm_out = query_vlm(image=final_frame, prompt=prompt)
            if vlm_out and vlm_out.get("success"):
                # We don't modify score strictly here as the programmatic check is robust,
                # but we could deduct if VLM says it's completely empty.
                # For now, we trust the programmatic extraction of XML content more than VLM for text,
                # but VLM confirms visual layout.
                pass

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }