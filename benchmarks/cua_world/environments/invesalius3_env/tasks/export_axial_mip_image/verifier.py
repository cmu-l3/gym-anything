#!/usr/bin/env python3
"""
Verifier for export_axial_mip_image task.

Scoring (100 points total):
  - File Creation (30 pts):
    - File exists at correct path: 10 pts
    - File is a valid PNG: 10 pts
    - File created/modified during task: 10 pts
  - Visual Verification (VLM) (70 pts):
    - Is an Axial view of the skull: 20 pts
    - Shows "Thick Slab" / MIP characteristics (continuous vessels, dense bone projection): 50 pts

Pass threshold: 70 points
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm

logger = logging.getLogger(__name__)

# VLM Prompt to distinguish standard slice vs MIP
MIP_VERIFICATION_PROMPT = """
You are a medical imaging expert analyzing a CT scan export.
The user was asked to generate a "Maximum Intensity Projection" (MIP) or "Thick Slab" view of a cranium in the Axial plane.

Compare the provided image against these criteria:
1. Is this a medical image of a skull (Axial view)?
2. Does it look like a standard single-slice CT (noisy, granular, vessels appear as dots)?
   OR
   Does it look like a Maximum Intensity Projection / Thick Slab (smoother texture, vessels appear as continuous lines/tubes, bone structures projected on top of each other)?

Standard Slice:
- High noise/grain
- Disconnected vessel cross-sections

MIP / Thick Slab:
- Reduced noise (smoother)
- Continuous vessel structures visible
- "Dense" appearance where bone layers overlap

Respond in JSON format:
{
  "is_axial_skull": true,
  "is_standard_slice": false,
  "is_mip_thick_slab": true,
  "confidence": "high",
  "reasoning": "Visible continuous vessel tracking and bone projection indicates MIP."
}
"""

def verify_export_axial_mip_image(traj, env_info, task_info):
    """Verify that the agent exported a valid Axial MIP image."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    score = 0
    feedback_parts = []
    
    # 1. Read programmatic checks
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        copy_from_env("/tmp/export_axial_mip_image_result.json", tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not read export result: {e}",
        }

    # Criterion 1: File Existence & Format (30 pts)
    file_exists = result.get("file_exists", False)
    is_png = result.get("is_png", False)
    fresh_file = result.get("created_during_task", False)
    
    if file_exists:
        score += 10
        feedback_parts.append("File created")
    else:
        feedback_parts.append("File not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    if is_png:
        score += 10
        feedback_parts.append("Valid PNG")
    else:
        feedback_parts.append("Invalid format (not PNG)")
        
    if fresh_file:
        score += 10
        feedback_parts.append("New timestamp")
    else:
        feedback_parts.append("Stale file (not created during task)")

    # 2. VLM Verification (70 pts)
    # We check the actual exported file, not the screen, because the task is to EXPORT it.
    # However, 'traj' usually contains screenshots. We need to fetch the exported file or 
    # rely on the final screenshot if the export isn't directly accessible to VLM tools 
    # (gym_anything usually passes screenshots).
    #
    # Pattern: If possible, we should ideally look at the file content. 
    # If the framework doesn't support uploading arbitrary files for VLM, we look at the 
    # final screenshot (assuming the user might have left it on screen) OR we trust the 
    # programmatic check + a "sanity check" of the file if we can retrieve it.
    #
    # Since `query_vlm` takes an image, let's try to pull the actual exported image out 
    # of the container to pass to it.
    
    exported_image_path = None
    try:
        tmp_img = tempfile.NamedTemporaryFile(delete=False, suffix=".png")
        tmp_img.close()
        # Attempt to copy the exported PNG from the environment
        copy_from_env("/home/ga/Documents/axial_mip.png", tmp_img.name)
        if os.path.getsize(tmp_img.name) > 0:
            exported_image_path = tmp_img.name
    except Exception as e:
        logger.warning(f"Could not retrieve exported image for VLM: {e}")

    if exported_image_path:
        # Verify the EXPORTED image
        vlm_res = query_vlm(
            prompt=MIP_VERIFICATION_PROMPT,
            image=exported_image_path
        )
        # Cleanup
        os.unlink(exported_image_path)
    else:
        # Fallback: Verify final screenshot (trajectory) if export retrieve failed
        # This is risky as the view might not be active, but better than nothing.
        from gym_anything.vlm import get_final_screenshot
        final_ss = get_final_screenshot(traj)
        if final_ss:
            vlm_res = query_vlm(
                prompt=MIP_VERIFICATION_PROMPT + "\n(Note: Analyze the active view in the software screenshot)",
                image=final_ss
            )
        else:
            vlm_res = {"success": False, "error": "No image available"}

    if vlm_res.get("success"):
        parsed = vlm_res.get("parsed", {})
        is_axial = parsed.get("is_axial_skull", False)
        is_mip = parsed.get("is_mip_thick_slab", False)
        
        if is_axial:
            score += 20
            feedback_parts.append("VLM: Axial view confirmed")
        else:
            feedback_parts.append("VLM: Not recognized as axial skull")
            
        if is_mip:
            score += 50
            feedback_parts.append("VLM: MIP/Thick Slab characteristics confirmed")
        else:
            feedback_parts.append("VLM: Looks like standard slice (MIP not detected)")
    else:
        feedback_parts.append(f"VLM check failed: {vlm_res.get('error')}")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }