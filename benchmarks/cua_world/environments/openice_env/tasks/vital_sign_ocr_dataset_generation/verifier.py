#!/usr/bin/env python3
"""
Verifier for Vital Sign OCR Dataset Generation task.

Verifies:
1. Dataset directory structure
2. Image cropping (dimensions check)
3. Monitor creation (OpenICE state)
4. Semantic correctness (VLM reads image number vs text label)
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

# Framework provides query_vlm in vlm_utils or passed in context
# For this script we assume it's available or we mock it if running standalone test
try:
    from gym_anything.vlm import query_vlm
except ImportError:
    # Mock for testing if not available
    def query_vlm(**kwargs):
        return {"success": False, "error": "VLM not available"}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_vital_sign_ocr_dataset(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify the generated OCR dataset.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    max_dim = metadata.get('max_image_dimension', 400) # Should be cropped, so smaller than screen
    
    # Load result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 1. Dataset Directory (10 pts)
    if result.get('dataset_dir_exists', False):
        score += 10
        feedback_parts.append("Dataset directory created")
    else:
        feedback_parts.append("Dataset directory missing")

    # 2. Monitor Active (20 pts)
    if result.get('monitor_created', False):
        score += 20
        feedback_parts.append("Multiparameter Monitor created")
    else:
        feedback_parts.append("No monitor detected")

    # 3. Process Samples
    samples = result.get('samples', [])
    valid_pairs = 0
    cropped_correctly = 0
    labels_match = 0
    
    # We need to analyze each sample
    for sample in samples:
        sample_id = sample.get('id')
        img_exists = sample.get('img_exists')
        txt_exists = sample.get('txt_exists')
        width = sample.get('width', 0)
        height = sample.get('height', 0)
        label_text = sample.get('label', "").strip()
        img_path = sample.get('img_path')

        # Check Pair Existence
        if img_exists and txt_exists:
            valid_pairs += 1
            
            # Check Cropping (Dimensions)
            # Full screen is usually ~1920x1080. Cropped ROI should be much smaller.
            if 20 < width < max_dim and 20 < height < max_dim:
                cropped_correctly += 1
                
                # Check VLM Content Match (Semantic Verification)
                # Copy image to host to run VLM
                local_img_path = tempfile.mktemp(suffix='.png')
                try:
                    copy_from_env(img_path, local_img_path)
                    
                    # Query VLM
                    prompt = f"Read the large numeric value in this image. The label provided is '{label_text}'. Does the image show the number {label_text}? Return JSON: {{'matches': bool, 'value_visible': int}}"
                    vlm_res = query_vlm(prompt=prompt, image=local_img_path)
                    
                    if vlm_res.get('success'):
                        parsed = vlm_res.get('parsed', {})
                        if parsed.get('matches', False):
                            labels_match += 1
                        else:
                            # Fallback: check if recognized value is int and matches text
                            val = parsed.get('value_visible')
                            if str(val) == label_text:
                                labels_match += 1
                except Exception as e:
                    logger.warning(f"VLM verification failed for sample {sample_id}: {e}")
                finally:
                    if os.path.exists(local_img_path):
                        os.unlink(local_img_path)
            else:
                logger.info(f"Sample {sample_id} dimensions {width}x{height} not within crop limits")

    # Scoring Logic for Samples
    
    # Existence (20 pts total, ~6.6 per pair)
    if valid_pairs >= 3:
        score += 20
        feedback_parts.append("3/3 valid file pairs found")
    else:
        score += int((valid_pairs / 3) * 20)
        feedback_parts.append(f"{valid_pairs}/3 file pairs found")

    # Cropping (20 pts total)
    if cropped_correctly >= 3:
        score += 20
        feedback_parts.append("Images correctly cropped")
    else:
        score += int((cropped_correctly / 3) * 20)
        feedback_parts.append(f"{cropped_correctly}/3 images correctly cropped")

    # Content Correctness (30 pts total - 10 per match)
    score += (labels_match * 10)
    if labels_match > 0:
        feedback_parts.append(f"{labels_match}/3 labels matched image content via VLM")
    
    passed = score >= 70 and valid_pairs >= 3
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "valid_pairs": valid_pairs,
            "cropped_correctly": cropped_correctly,
            "labels_match": labels_match
        }
    }