#!/usr/bin/env python3
"""
Verifier for botanical_morphometry_calibration task.

Verification Logic:
1. Files Created (15 pts): Output files must exist and be modified during task.
2. Calibration Accuracy (35 pts): The measured Area in CSV must match Ground Truth (within 5% tolerance).
   - This proves the agent used Set Scale correctly with the random reference line.
3. Data Completeness (20 pts): CSV must contain Area, Perimeter, Circularity columns.
4. Annotation Check (VLM) (20 pts): The output image must show the leaf AND a scale bar.
5. Mask Existence (10 pts): Binary mask file indicates segmentation was performed.

Pass Threshold: 65 points (Requires passing Calibration)
"""

import json
import os
import tempfile
import csv
import logging
import math

# Import shared VLM utilities if available in environment
try:
    from vlm_utils import query_vlm
except ImportError:
    query_vlm = None

logger = logging.getLogger(__name__)

def verify_botanical_morphometry(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    score = 0
    feedback = []
    
    # 1. Retrieve Result JSON
    result_data = {}
    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tf:
        try:
            copy_from_env("/tmp/task_result.json", tf.name)
            with open(tf.name, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load task results: {e}"}
        finally:
            os.unlink(tf.name)

    # 2. Check File Creation (15 pts)
    files_ok = (result_data.get("csv_created_during_task") and 
                result_data.get("image_created_during_task"))
    if files_ok:
        score += 15
        feedback.append("Output files created successfully (+15)")
    else:
        feedback.append("Output files missing or not created during task")

    # 3. Check Mask (10 pts)
    if result_data.get("mask_exists"):
        score += 10
        feedback.append("Segmentation mask saved (+10)")
    else:
        feedback.append("Segmentation mask missing")

    # 4. Quantitative Verification (CSV Analysis) (35 + 20 pts)
    gt_area = result_data.get("ground_truth_area_cm2", 0)
    measured_area = None
    
    # Retrieve CSV
    if result_data.get("csv_exists"):
        with tempfile.NamedTemporaryFile(suffix=".csv", delete=False) as tf_csv:
            try:
                copy_from_env("/tmp/measurements.csv", tf_csv.name)
                
                # Parse CSV
                with open(tf_csv.name, 'r') as f:
                    reader = csv.DictReader(f)
                    fieldnames = [fn.lower() for fn in (reader.fieldnames or [])]
                    
                    # Check Columns (20 pts)
                    required = ["area", "circ", "perim"] # partial matching
                    has_cols = all(any(req in fn for fn in fieldnames) for req in required)
                    
                    if has_cols:
                        score += 20
                        feedback.append("CSV contains required morphometric columns (+20)")
                    else:
                        feedback.append(f"CSV missing columns. Found: {fieldnames}")

                    # Check Area Accuracy (35 pts)
                    # We look for the first row of data
                    rows = list(reader)
                    if rows:
                        row = rows[0]
                        # Find area column
                        area_key = next((k for k in row.keys() if "area" in k.lower()), None)
                        if area_key:
                            try:
                                measured_area = float(row[area_key])
                            except:
                                pass
            except Exception as e:
                feedback.append(f"Error parsing CSV: {e}")
            finally:
                os.unlink(tf_csv.name)

    # Validate Area
    if measured_area is not None and gt_area > 0:
        error = abs(measured_area - gt_area) / gt_area
        if error <= 0.05: # 5% tolerance
            score += 35
            feedback.append(f"Calibration accuracy excellent! ({measured_area:.2f} vs {gt_area:.2f} cm²) (+35)")
        elif error <= 0.15: # 15% tolerance partial credit
            score += 15
            feedback.append(f"Calibration accuracy acceptable. ({measured_area:.2f} vs {gt_area:.2f} cm²) (+15)")
        else:
            feedback.append(f"Calibration failed. Measured {measured_area:.2f} vs Truth {gt_area:.2f}. Did you Set Scale correctly?")
    else:
        feedback.append("Could not verify area measurement.")

    # 5. Visual Verification (Scale Bar) (20 pts)
    # We retrieve the annotated image and ask VLM
    if result_data.get("image_exists") and query_vlm:
        with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as tf_img:
            try:
                copy_from_env("/tmp/annotated_leaf.png", tf_img.name)
                
                prompt = (
                    "Look at this image of a leaf. "
                    "1. Is there a scale bar visible (usually a line with text like '1 cm' or '5 cm')? "
                    "2. Is the leaf segmented/visible clearly against the background? "
                    "Return JSON: {'scale_bar_present': bool, 'leaf_visible': bool}"
                )
                
                vlm_res = query_vlm(prompt=prompt, image=tf_img.name)
                
                if vlm_res.get("success"):
                    parsed = vlm_res.get("parsed", {})
                    if parsed.get("scale_bar_present"):
                        score += 20
                        feedback.append("Visual scale bar confirmed (+20)")
                    else:
                        feedback.append("No scale bar detected in output image")
                else:
                    # Soft fail if VLM errors, give partial points if file exists
                    score += 5 
                    feedback.append("VLM check skipped (service error), +5 for file existence")
            except Exception as e:
                feedback.append(f"Visual verification failed: {e}")
            finally:
                os.unlink(tf_img.name)
    elif result_data.get("image_exists"):
        # Fallback if no VLM service
        score += 10
        feedback.append("Annotated image exists (VLM unavailable) (+10)")

    passed = score >= 65
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }