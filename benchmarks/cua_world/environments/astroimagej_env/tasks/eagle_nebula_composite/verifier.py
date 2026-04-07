#!/usr/bin/env python3
"""
Verifier for Create Hubble Palette Color Composite task.

Verification Strategy:
1. Programmatic Checks (85 points):
   - File exists and was created during task (10 pts)
   - Valid image format with 3 channels (RGB) (10 pts)
   - Image has adequate dynamic range/contrast stretch (10 pts)
   - Channel Mapping (55 points):
     * Red channel maps to 673nm ([SII]) (15 pts)
     * Green channel maps to 656nm (H-alpha) (15 pts)
     * Blue channel maps to 502nm ([OIII]) (15 pts)
     * Exact vs approximate mapping tolerances (10 pts bonus for perfect SHO)

2. VLM Checks on Trajectory (15 points):
   - Confirms process progression (opening multiple images, merge tool).
"""

import json
import tempfile
import os
import logging
from typing import Dict, Any

from gym_anything.vlm import get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

TRAJECTORY_PROMPT = """You are analyzing screenshots from an agent creating an RGB color composite in AstroImageJ.
Images are in chronological order.

For a successful workflow, the agent should:
1. Open multiple astronomical FITS images (grayscale star/nebula fields).
2. Use a color merge tool (like Image > Color > Merge Channels dialog).
3. Generate a final colorful RGB composite image of the nebula.

Assess:
1. MULTIPLE_IMAGES_OPENED: Are there multiple image windows or a merge dialog visible?
2. COLOR_COMPOSITE_CREATED: Does the final frame show a colorful nebula image (not grayscale)?
3. WORKFLOW_COMPLETED: Did the agent successfully produce a result?

Return JSON:
{
    "multiple_images_opened": true/false,
    "color_composite_created": true/false,
    "workflow_completed": true/false,
    "observations": "brief summary of actions"
}"""

def verify_eagle_nebula_composite(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    score = 0
    feedback = []
    
    # 1. Retrieve the task result JSON
    result = {}
    try:
        temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/eagle_task_result.json", temp.name)
        with open(temp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load container results: {e}"}
    finally:
        if os.path.exists(temp.name):
            os.unlink(temp.name)

    # If file not found, fail early
    if not result.get("output_found"):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Output file 'eagle_nebula_hubble_palette.*' not found."
        }
        
    feedback.append("✅ Output file found")
    
    # Check creation time
    if result.get("created_during_task"):
        score += 10
        feedback.append("✅ File created during task session")
    else:
        feedback.append("❌ File timestamp implies it existed before task start (possible anti-gaming violation)")

    # Check validity and channels
    if result.get("is_valid_image") and result.get("num_channels", 0) >= 3:
        score += 10
        feedback.append("✅ Valid RGB image format")
    else:
        feedback.append("❌ Image is invalid or not an RGB color composite")

    # Check dynamic range (ensure agent applied contrast stretch)
    dr = result.get("dynamic_range_std", {})
    if dr.get("R", 0) > 10 and dr.get("G", 0) > 10 and dr.get("B", 0) > 10:
        score += 10
        feedback.append("✅ Image has adequate dynamic range (contrast stretched)")
    else:
        feedback.append("❌ Image lacks dynamic range (likely too dark or pure white)")

    # Check Channel Mapping via Correlation Matrix
    corr = result.get("correlation_matrix", {})
    if corr:
        # Expected mapping: Red=673, Green=656, Blue=502
        
        # Red channel check
        r_corr = [corr.get("R_vs_502", 0), corr.get("R_vs_656", 0), corr.get("R_vs_673", 0)]
        if r_corr[2] == max(r_corr) and r_corr[2] > 0.3:
            score += 15
            feedback.append("✅ Red channel correctly mapped to 673nm ([SII])")
        else:
            feedback.append("❌ Red channel mapping incorrect (should be 673nm)")
            
        # Green channel check
        g_corr = [corr.get("G_vs_502", 0), corr.get("G_vs_656", 0), corr.get("G_vs_673", 0)]
        if g_corr[1] == max(g_corr) and g_corr[1] > 0.3:
            score += 15
            feedback.append("✅ Green channel correctly mapped to 656nm (H-alpha)")
        else:
            feedback.append("❌ Green channel mapping incorrect (should be 656nm)")
            
        # Blue channel check
        b_corr = [corr.get("B_vs_502", 0), corr.get("B_vs_656", 0), corr.get("B_vs_673", 0)]
        if b_corr[0] == max(b_corr) and b_corr[0] > 0.3:
            score += 15
            feedback.append("✅ Blue channel correctly mapped to 502nm ([OIII])")
        else:
            feedback.append("❌ Blue channel mapping incorrect (should be 502nm)")
            
        # Bonus if all mappings are perfectly SHO
        if (r_corr[2] == max(r_corr) and g_corr[1] == max(g_corr) and b_corr[0] == max(b_corr)):
            score += 10
            feedback.append("✅ Perfect Hubble Palette (SHO) mapping achieved!")
    else:
        feedback.append("⚠️ Correlation matrix unavailable. Host/Container mismatch on dependencies.")

    # 2. VLM Trajectory Verification
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            if final: frames.append(final)
            
            if frames:
                vlm_res = query_vlm(prompt=TRAJECTORY_PROMPT, images=frames)
                if vlm_res.get("success"):
                    parsed = vlm_res.get("parsed", {})
                    if parsed.get("multiple_images_opened"):
                        score += 5
                        feedback.append("✅ VLM: Multiple images/merge tool used")
                    if parsed.get("color_composite_created"):
                        score += 10
                        feedback.append("✅ VLM: Colorful composite image created")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")

    # Final determination
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": "\n".join(feedback),
        "details": result
    }