#!/usr/bin/env python3
import json
import os
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

def verify_create_casting_mold(traj, env_info, task_info):
    """
    Verifies the casting mold task based on:
    1. File creation and validity
    2. Geometric correctness (Enclosure, Margin, Cut Operation)
    3. Visual check (Transparency, internal cavity)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON from Container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # Extract Data
    output_exists = result.get('output_exists', False)
    file_fresh = result.get('file_created_during_task', False)
    analysis = result.get('geometry_analysis', {})
    
    # --- Check 1: File Existence & Anti-Gaming (20 pts) ---
    if output_exists:
        score += 10
        if file_fresh:
            score += 10
            feedback.append("File created successfully.")
        else:
            feedback.append("File exists but was not created during this task.")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file mold_cavity.FCStd not found."}

    # --- Check 2: Geometric Analysis (60 pts) ---
    geo_score = 0
    valid_solid = analysis.get('valid_solid', False)
    
    if valid_solid:
        geo_score += 10
        
        # Get dimensions
        mold_vol = analysis.get('mold_volume', 0)
        mold_bbox = analysis.get('mold_bbox', [0,0,0])
        mold_center = analysis.get('mold_center', [0,0,0])
        
        bracket_vol = analysis.get('bracket_volume', 0)
        bracket_bbox = analysis.get('bracket_bbox', [0,0,0])
        bracket_center = analysis.get('bracket_center', [0,0,0])
        
        # A. Margin Check (20 pts)
        # Verify mold is larger than bracket by at least 18mm (allowing slight tolerance for 20mm diff)
        margins_ok = all(m > b + 18 for m, b in zip(mold_bbox, bracket_bbox))
        if margins_ok:
            geo_score += 20
            feedback.append("Mold dimensions satisfy margin requirements.")
        else:
            feedback.append("Mold is not large enough to encapsulate the part with 10mm margins.")

        # B. Cut Operation Verification (20 pts)
        # Theoretical box volume (approximate, assuming it's a box)
        box_vol_approx = mold_bbox[0] * mold_bbox[1] * mold_bbox[2]
        
        # The mold volume should be roughly (Box - Bracket). 
        # If they just made a box without cutting, volume ~= Box.
        # If they cut correctly, Volume < Box.
        # Ideally: Mold_Vol ≈ Box_Vol - Bracket_Vol
        # Note: If the box is exactly the bounding box size, Box_Vol = product(mold_bbox).
        
        # Calculate expected volume based on the bounding box of the mold minus the known bracket volume
        # This assumes the mold is rectangular (which the task asks for).
        expected_vol = box_vol_approx - bracket_vol
        
        # Allow 5% tolerance (meshing or float errors)
        if abs(mold_vol - expected_vol) < (0.05 * box_vol_approx):
            geo_score += 20
            feedback.append("Boolean Cut verified (Volume matches expected).")
        elif mold_vol > expected_vol + (0.5 * bracket_vol):
             feedback.append("Cavity not detected (Volume too high). Did you perform the cut?")
        else:
             geo_score += 10 # Partial credit if it's kinda close
             feedback.append(f"Volume check ambiguous (Exp: {expected_vol:.0f}, Act: {mold_vol:.0f}).")

        # C. Centering Check (10 pts)
        # Dist between centers should be small (< 2mm)
        dist = sum((m - b)**2 for m, b in zip(mold_center, bracket_center)) ** 0.5
        if dist < 2.0:
            geo_score += 10
            feedback.append("Centering is accurate.")
        else:
            feedback.append(f"Mold not centered on part (Offset: {dist:.1f}mm).")

    else:
        feedback.append("File does not contain a valid solid shape.")

    score += geo_score

    # --- Check 3: Transparency (10 pts) ---
    transparency = analysis.get('transparency', 0)
    if 40 <= transparency <= 60:
        score += 10
        feedback.append(f"Transparency set correctly ({transparency}%).")
    elif transparency > 0:
        score += 5
        feedback.append(f"Transparency set but out of range ({transparency}%).")
    else:
        feedback.append("Transparency not set.")

    # --- Check 4: VLM Verification (10 pts) ---
    # Visual check for the "ghostly" box with internal shape
    frames = sample_trajectory_frames(traj, n=4)
    final_img = get_final_screenshot(traj)
    
    if final_img:
        vlm_res = query_vlm(
            images=frames + [final_img],
            prompt="Looking at the final FreeCAD workspace: Is there a semi-transparent (see-through) rectangular block visible? Can you see a darker shape (the bracket) inside it? Reply 'YES' if it looks like a mold block with a cavity."
        )
        if vlm_res.get("success") and "YES" in vlm_res.get("response", "").upper():
            score += 10
            feedback.append("VLM confirms visual appearance.")
    
    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }