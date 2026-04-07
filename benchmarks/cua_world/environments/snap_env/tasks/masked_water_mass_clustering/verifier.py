#!/usr/bin/env python3
"""
Verifier for masked_water_mass_clustering task.

Verification Strategy:
- Programmatic checks (65 points): Parses the exported DIMAP XML to verify file 
  creation, K-Means execution, proper restriction of source bands (excluding originals), 
  and explicit conditional NaN logic in Band Maths.
- VLM Trajectory checks (35 points): Uses sampled trajectory frames to confirm 
  the visual workflow of isolating water and executing the clustering dialogs.
  
Pass threshold: 70 points
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are analyzing a sequence of screenshots from an agent performing a domain-restricted K-Means clustering in ESA SNAP Desktop.

The agent is tasked with:
1. Masking out land pixels using Band Maths.
2. Running K-Means Unsupervised Classification strictly on the water pixels.

Review the sequence of trajectory frames and the final screen to assess:
1. WORKFLOW_PROGRESSION: Does the agent open the Band Maths dialog and the K-Means Cluster Analysis tool?
2. CLUSTERING_VISIBLE: In the final frames, is a clustered/classified image visible in the main view?
3. MASKING_EVIDENCE: Does the clustered image show evidence of masking? (e.g., land is a uniform NoData color like black/white/transparent, while the water has discrete cluster colors).

Respond ONLY in valid JSON format:
{
    "workflow_progression": true/false,
    "clustering_visible": true/false,
    "masking_evidence": true/false,
    "confidence": "low/medium/high",
    "reasoning": "Brief explanation of visual evidence"
}
"""

def verify_masked_water_mass_clustering(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Programmatic Results
    result_path = tempfile.mktemp(suffix='.json')
    try:
        copy_from_env('/tmp/masked_water_mass_result.json', result_path)
        with open(result_path) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve programmatic results: {e}"}
    finally:
        if os.path.exists(result_path):
            os.unlink(result_path)

    score = 0
    feedback_parts = []

    # Criterion 1: DIMAP export valid (5 points)
    if result.get('dim_found') and result.get('dim_created_after_start'):
        score += 5
        feedback_parts.append("DIMAP product exported (+5)")
    else:
        feedback_parts.append("No valid DIMAP export found (0/5)")

    # Criterion 2: GeoTIFF export valid (10 points)
    tif_size = result.get('tif_size_bytes', 0)
    if result.get('tif_found') and result.get('tif_created_after_start') and tif_size > 10240:
        score += 10
        feedback_parts.append(f"GeoTIFF exported with valid size ({tif_size // 1024} KB) (+10)")
    else:
        feedback_parts.append("No valid GeoTIFF export found (0/10)")

    # Criterion 3: class_indices band present (10 points)
    if result.get('has_class_indices'):
        score += 10
        feedback_parts.append("Classification band 'class_indices' present (+10)")
    else:
        feedback_parts.append("No classification band found (0/10)")

    # Criterion 4: K-Means Node present in graph (15 points)
    if result.get('kmeans_run'):
        score += 15
        feedback_parts.append("K-Means tool executed (+15)")
    else:
        feedback_parts.append("K-Means execution not found in processing graph (0/15)")

    # Criterion 5: Masked Bands Input restricted appropriately (25 points)
    source_bands_str = result.get('kmeans_source_bands', '')
    if source_bands_str:
        bands_used = [b.strip() for b in source_bands_str.split(',')]
        # Default original bands the agent MUST explicitly deselect
        original_bands = ['band_1', 'band_2', 'band_3', 'band_4']
        
        used_originals = any(orig in source_bands_str.lower() for orig in original_bands)
        if not used_originals and len(bands_used) >= 1:
            score += 25
            feedback_parts.append(f"K-Means restricted to custom masked bands: {source_bands_str} (+25)")
        else:
            feedback_parts.append("K-Means utilized original unmasked bands; domain restriction failed (0/25)")
    else:
        feedback_parts.append("K-Means source bands unspecified/default used (0/25)")

    # Criterion 6: Masking Logic via NaN (10 points)
    if result.get('has_nan_logic'):
        score += 10
        feedback_parts.append("Conditional NaN logic correctly applied to isolate water (+10)")
    else:
        feedback_parts.append("No conditional NaN logic found in virtual bands (0/10)")

    # 2. VLM Trajectory Verification (25 points)
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    
    if query_vlm:
        try:
            # Import framework VLM tools dynamically
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            all_frames = frames + [final] if final else frames
            
            if all_frames:
                vlm_resp = query_vlm(images=all_frames, prompt=VLM_PROMPT)
                
                if vlm_resp and vlm_resp.get("success"):
                    vlm_data = vlm_resp.get("parsed", {})
                    
                    if vlm_data.get("workflow_progression"):
                        vlm_score += 10
                        feedback_parts.append("VLM confirmed tool progression (+10)")
                    
                    if vlm_data.get("clustering_visible") and vlm_data.get("masking_evidence"):
                        vlm_score += 15
                        feedback_parts.append("VLM confirmed visual masking logic in clustered output (+15)")
                    elif vlm_data.get("clustering_visible"):
                        vlm_score += 5
                        feedback_parts.append("VLM saw clustering, but masking evidence was lacking (+5)")
                    
                    if "reasoning" in vlm_data:
                        logger.info(f"VLM Reasoning: {vlm_data['reasoning']}")
                else:
                    feedback_parts.append("VLM query failed or returned no parsable JSON")
        except ImportError:
            feedback_parts.append("VLM tool utilities unavailable")
        except Exception as e:
            feedback_parts.append(f"VLM evaluation error: {e}")
    else:
        feedback_parts.append("VLM capability not provided in environment")

    score += vlm_score

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }