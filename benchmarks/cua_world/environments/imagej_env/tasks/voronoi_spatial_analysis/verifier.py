#!/usr/bin/env python3
"""
Verifier for Voronoi Spatial Analysis task.

Task: Segment Blobs -> Voronoi Tessellation -> Measure Cell Areas -> Report Stats (CV).

Verification Strategy:
1. File Verification (Programmatic):
   - Check if output CSV exists and was created during task.
   - Check if it contains sufficient rows (representing cells).
   - Check if values are physically plausible (area range).
   - Check if Coefficient of Variation (CV) is reported or calculable.

2. Visual Verification (VLM):
   - Check trajectory for "honeycomb" or "mosaic" patterns characteristic of Voronoi.
   - Confirm workflow progression: Image -> Threshold -> Voronoi -> Results.

Scoring (100 pts):
- Result file valid & timestamp correct: 15 pts
- Sufficient cell count (>= 20): 20 pts
- Plausible area values (median 200-5000): 20 pts
- CV reported/calculable (0.1-2.0): 20 pts
- Summary statistics present: 15 pts
- VLM confirmation of Voronoi visual: 10 pts
"""

import json
import tempfile
import os
import logging
from typing import Dict, Any

# Import VLM utilities from the environment framework
# If not available, fallback to mock or skip
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
except ImportError:
    # Mock for local testing
    def sample_trajectory_frames(traj, n=5): return []
    def get_final_screenshot(traj): return None

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_voronoi_analysis(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # Metadata expectations
    metadata = task_info.get('metadata', {})
    min_cell_count = metadata.get('min_cell_count', 20)
    median_min = metadata.get('expected_median_area_min', 200)
    median_max = metadata.get('expected_median_area_max', 5000)
    cv_min = metadata.get('expected_cv_min', 0.1)
    cv_max = metadata.get('expected_cv_max', 2.0)

    # 1. Load Programmatic Results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 2. Score Programmatic Criteria
    
    # Criterion 1: File Existence & Timestamp (15 pts)
    if result_data.get("file_exists") and result_data.get("file_created_after_task"):
        score += 15
        feedback.append("Output file created successfully.")
    else:
        feedback.append("Output file missing or pre-dates task start.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # Criterion 2: Sufficient Cell Count (20 pts)
    row_count = result_data.get("row_count", 0)
    if row_count >= min_cell_count:
        score += 20
        feedback.append(f"Cell count sufficient ({row_count}).")
    else:
        feedback.append(f"Insufficient cells measured ({row_count} < {min_cell_count}).")

    # Criterion 3: Plausible Area Values (20 pts)
    median_area = result_data.get("median_area", 0)
    if median_min <= median_area <= median_max:
        score += 20
        feedback.append(f"Area values plausible (median: {median_area:.1f}).")
    else:
        feedback.append(f"Area values implausible (median: {median_area:.1f}, expected {median_min}-{median_max}).")

    # Criterion 4: CV Reported/Calculable (20 pts)
    cv_val = result_data.get("cv_value")
    if result_data.get("cv_found") and cv_val is not None and cv_min <= cv_val <= cv_max:
        score += 20
        feedback.append(f"CV is valid ({cv_val:.3f}).")
    else:
        feedback.append("Coefficient of Variation (CV) missing or out of valid range.")

    # Criterion 5: Summary Statistics Present (15 pts)
    if result_data.get("mean_found"):
        score += 15
        feedback.append("Summary statistics (Mean) found.")
    else:
        feedback.append("Summary statistics missing.")

    # 3. Visual Verification (VLM) (10 pts)
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final_screen = get_final_screenshot(traj)
        
        if frames or final_screen:
            # Add final screen to frames if it exists
            if final_screen:
                frames.append(final_screen)
                
            prompt = """
            You are verifying an image processing task in ImageJ.
            The user should have created a 'Voronoi Diagram' from particles.
            
            Look for:
            1. A cellular mosaic pattern (honeycomb-like polygons) partitioning the image.
            2. Black lines separating white/colored regions, OR white lines separating black regions.
            3. A 'Results' table showing measurements.
            
            Does the image sequence show the creation or existence of a Voronoi diagram pattern?
            Respond with JSON: {"voronoi_visible": true/false, "confidence": "high/low"}
            """
            
            try:
                vlm_resp = query_vlm(images=frames, prompt=prompt)
                # Assuming simple dict response parsing provided by framework wrapper or raw string
                # This logic depends on the specific VLM interface; strictly using provided pattern
                if isinstance(vlm_resp, dict) and vlm_resp.get("parsed", {}).get("voronoi_visible"):
                    vlm_score = 10
                    feedback.append("VLM confirmed Voronoi pattern.")
                elif "true" in str(vlm_resp).lower(): # Fallback loose check
                    vlm_score = 10
                    feedback.append("VLM confirmed Voronoi pattern.")
                else:
                    feedback.append("VLM did not observe Voronoi pattern.")
            except Exception as e:
                logger.warning(f"VLM check failed: {e}")
                # Grant partial credit on failure if programmatic is perfect, else 0
                if score >= 90: vlm_score = 10
        
    score += vlm_score

    # Final Pass/Fail
    passed = score >= 60 and result_data.get("row_count", 0) >= min_cell_count
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }