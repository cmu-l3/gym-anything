#!/usr/bin/env python3
"""
Verifier for Rotate and Flip Transform task.

Evaluates:
1. File existence and valid JPEG size.
2. Anti-gaming creation timestamps.
3. Content validity (Structural correlation between exported JPG and ground truth mathematical transform).
4. VLM Verification (Evidence of using rotation/flip toolbars or context menus).
"""

import os
import json
import tempfile
import logging
import numpy as np

# Try importing PIL safely
try:
    from PIL import Image
    PIL_AVAILABLE = True
except ImportError:
    PIL_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are evaluating an agent's trajectory in Weasis DICOM Viewer.
The agent was asked to apply a 90° clockwise rotation AND a horizontal flip to a medical image, and then export it.

Review these sequential screenshots and answer:
1. Is there evidence the agent used the Spatial Transform tools (either toolbar buttons for rotate/flip, or the right-click "Display" context menu)?
2. Does the image display area visibly change orientation/flip across the frames?
3. Did the agent open an "Export" or "Save Image" dialog?

Respond in JSON format:
{
    "used_transform_tools": true/false,
    "image_visually_transformed": true/false,
    "opened_export_dialog": true/false,
    "reasoning": "brief explanation"
}
"""

def image_correlation(img_array, reference_array):
    """Calculate 2D Pearson Correlation Coefficient between two arrays."""
    # Flatten arrays
    a = img_array.flatten()
    b = reference_array.flatten()
    
    # Normalize (zero mean, unit variance) to handle Window/Level visual shifting
    a_std = np.std(a)
    b_std = np.std(b)
    
    if a_std == 0 or b_std == 0:
        return 0.0
        
    a_norm = (a - np.mean(a)) / a_std
    b_norm = (b - np.mean(b)) / b_std
    
    return np.corrcoef(a_norm, b_norm)[0, 1]

def verify_rotate_flip_transform(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    temp_dir = tempfile.mkdtemp()
    result_json_path = os.path.join(temp_dir, 'result.json')
    jpg_path = os.path.join(temp_dir, 'transformed_view.jpg')
    orig_npy_path = os.path.join(temp_dir, 'original.npy')
    expected_npy_path = os.path.join(temp_dir, 'expected.npy')

    try:
        # 1. Load JSON results
        copy_from_env("/tmp/task_result.json", result_json_path)
        with open(result_json_path, 'r') as f:
            result = json.load(f)

        file_exists = result.get('file_exists', False)
        file_size = result.get('file_size', 0)
        created_during_task = result.get('created_during_task', False)

        if not file_exists:
            return {"passed": False, "score": 0, "feedback": "Target export file transformed_view.jpg not found."}
        
        score += 15
        feedback_parts.append("Export file exists")

        if file_size > 2048:
            score += 10
            feedback_parts.append("File size valid")
        else:
            feedback_parts.append("File unusually small")

        if created_during_task:
            score += 15
            feedback_parts.append("Created during task")
        else:
            feedback_parts.append("File existed before task (possible gaming)")

        # 2. Structural Analysis of Exported Image
        if file_exists and file_size > 0 and PIL_AVAILABLE:
            try:
                copy_from_env("/home/ga/DICOM/exports/transformed_view.jpg", jpg_path)
                copy_from_env("/tmp/original_pixels.npy", orig_npy_path)
                copy_from_env("/tmp/expected_transform.npy", expected_npy_path)

                # Load references
                orig_ref = np.load(orig_npy_path)
                expected_ref = np.load(expected_npy_path)

                # Load exported JPG, convert to grayscale
                img = Image.open(jpg_path).convert('L')
                
                # Resize to match reference array shape (Note: PIL size is (width, height), Numpy shape is (rows, cols))
                img_resized = img.resize((expected_ref.shape[1], expected_ref.shape[0]), Image.Resampling.BILINEAR)
                img_array = np.array(img_resized, dtype=float)

                # Calculate correlations
                corr_expected = image_correlation(img_array, expected_ref)
                corr_original = image_correlation(img_array, orig_ref)
                
                logger.info(f"Correlation with expected transform: {corr_expected:.3f}")
                logger.info(f"Correlation with original: {corr_original:.3f}")

                if corr_expected > 0.4:
                    score += 20
                    feedback_parts.append("Transform structurally matches expected")
                    
                if corr_expected > corr_original + 0.1:
                    score += 20
                    feedback_parts.append("Transform verified (Differs from original)")
                else:
                    feedback_parts.append("Image correlates highly with unmodified original")
                    
            except Exception as e:
                logger.error(f"Image analysis failed: {e}")
                feedback_parts.append(f"Image analysis error: {str(e)[:50]}")

        # 3. VLM Verification
        if query_vlm:
            try:
                # Sample frames from trajectory
                from gym_anything.vlm import sample_trajectory_frames
                frames = sample_trajectory_frames(traj, n=5)
                
                vlm_result = query_vlm(prompt=VLM_PROMPT, images=frames)
                
                if vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    if parsed.get("used_transform_tools", False) and parsed.get("image_visually_transformed", False):
                        score += 15
                        feedback_parts.append("VLM: Tools used")
                    if parsed.get("opened_export_dialog", False):
                        score += 5
                        feedback_parts.append("VLM: Export verified")
            except Exception as e:
                logger.warning(f"VLM verification error: {e}")

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        # Cleanup temp files
        for f in [result_json_path, jpg_path, orig_npy_path, expected_npy_path]:
            if os.path.exists(f):
                try:
                    os.unlink(f)
                except:
                    pass
        os.rmdir(temp_dir)

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }