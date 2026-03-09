"""
Verifier for prepare_publication_figure task.

Task: Create a publication-ready figure from VitalDB data.
Requirements:
1.  Screenshot saved to C:\\Users\\Docker\\Documents\\publication_figure.png
2.  Contains exactly 3 tracks: "Heart Rate", "Systolic BP", "SpO2"
3.  Colors: Green (HR), Red (BP), Blue/Cyan (SpO2)
4.  Order: HR (top), BP (middle), SpO2 (bottom)

Verification Strategy:
- Check file creation/timestamp via task_result.json
- Retrieve the generated image file from the environment
- Use VLM to inspect the visual properties (text labels, colors, count)
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

# Add parent directory for shared utilities
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))
from vlm_utils import query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """
You are verifying a scientific figure created from physiological data.

Goal: The figure should contain exactly 3 specific tracks with specific colors and names.

Please analyze the image and verify:
1. TRACK COUNT: Are there exactly 3 main waveform tracks visible? (Ignore the timeline bar at top).
2. LABELS: Can you read the labels "Heart Rate", "Systolic BP", and "SpO2"?
3. ORDER: Is "Heart Rate" at the top, "Systolic BP" in the middle, and "SpO2" at the bottom?
4. COLORS: 
   - Is "Heart Rate" Green?
   - Is "Systolic BP" Red?
   - Is "SpO2" Blue or Cyan?

Output JSON:
{
  "track_count": <number>,
  "labels_correct": <bool>,
  "order_correct": <bool>,
  "colors_correct": <bool>,
  "explanation": "<text>"
}
"""

def verify_publication_figure(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Check metadata and basic file existence
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_data = {}
    
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": "Could not read task result file"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    output_exists = result_data.get("output_exists", False)
    created_during = result_data.get("file_created_during_task", False)
    output_path_env = result_data.get("output_path", "C:\\Users\\Docker\\Documents\\publication_figure.png")

    score = 0
    feedback = []

    if output_exists:
        score += 10
        feedback.append("Output file exists.")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file 'publication_figure.png' not found."}

    if created_during:
        score += 10
        feedback.append("File created during task.")
    else:
        feedback.append("Warning: File timestamp suggests it wasn't created during this session.")

    # 2. Retrieve the image for VLM analysis
    temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
    image_retrieved = False
    
    try:
        copy_from_env(output_path_env, temp_img.name)
        image_retrieved = True
    except Exception as e:
        feedback.append(f"Failed to copy output image for verification: {e}")

    # 3. VLM Verification
    if image_retrieved:
        try:
            # We use the actual output file for verification as it's the deliverable
            vlm_response = query_vlm(prompt=VLM_PROMPT, image=temp_img.name)
            
            if vlm_response.get("success"):
                parsed = vlm_response.get("parsed", {})
                
                # Check track count (Target: 3)
                count = parsed.get("track_count", 0)
                if count == 3:
                    score += 20
                    feedback.append("Correct number of tracks (3).")
                else:
                    feedback.append(f"Incorrect track count: {count} (Expected 3).")

                # Check labels
                if parsed.get("labels_correct"):
                    score += 20
                    feedback.append("Labels renamed correctly.")
                else:
                    feedback.append("Labels incorrect or not readable.")

                # Check order
                if parsed.get("order_correct"):
                    score += 20
                    feedback.append("Track order correct.")
                else:
                    feedback.append("Track order incorrect.")

                # Check colors
                if parsed.get("colors_correct"):
                    score += 20
                    feedback.append("Color scheme applied correctly.")
                else:
                    feedback.append("Color scheme incorrect.")
                    
                feedback.append(f"VLM Note: {parsed.get('explanation', '')}")
                
            else:
                feedback.append(f"VLM analysis failed: {vlm_response.get('error')}")
                # Fallback: give partial credit if file exists
        except Exception as e:
            feedback.append(f"Error during VLM verification: {e}")
    else:
        feedback.append("Could not retrieve image file for content verification.")

    # Cleanup image
    if os.path.exists(temp_img.name):
        os.unlink(temp_img.name)

    passed = score >= 80  # Requires labels + colors + order mostly correct
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }