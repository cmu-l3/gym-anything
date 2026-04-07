#!/usr/bin/env python3
"""
Verifier for export_multiple_measurements_csv task.

Verification Strategy:
1. File Checks: Check if trial_data.csv and trial_screenshot.jpg exist and were created post-start.
2. CSV Content: Parse CSV. Verify it has headers and at least 3 rows containing numeric length data.
3. VLM Verification: Use trajectory frames to visually confirm that the agent interacted with the measurement
   tool and 3 distinct line annotations are visible on the DICOM viewer.
"""

import os
import json
import csv
import tempfile
import logging

try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def is_numeric(val):
    """Helper to check if a string represents a number."""
    if not isinstance(val, str):
        val = str(val)
    val = val.strip()
    try:
        float(val)
        return True
    except ValueError:
        # Also handle cases where there might be a unit attached like "45.2 mm"
        import re
        if re.search(r'\d+\.?\d*', val):
            return True
        return False


def verify_export_multiple_measurements(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    max_score = 100

    # ================================================================
    # Read result.json
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Variables from result
    csv_exists = result.get('csv_exists', False)
    csv_created = result.get('csv_created_during_task', False)
    img_exists = result.get('img_exists', False)
    csv_internal_path = result.get('csv_internal_path', '/home/ga/DICOM/exports/trial_data.csv')

    # ================================================================
    # Criteria 1: CSV File Existence & Anti-gaming (15 points)
    # ================================================================
    if csv_exists and csv_created:
        score += 15
        feedback_parts.append("✅ CSV exported during task")
    elif csv_exists:
        feedback_parts.append("❌ CSV exists but timestamp predates task (Pre-existing file)")
    else:
        feedback_parts.append("❌ CSV file not found")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # ================================================================
    # Criteria 2, 3, 4: CSV Parsing and Content Verification (55 points)
    # ================================================================
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env(csv_internal_path, temp_csv.name)
        with open(temp_csv.name, 'r', encoding='utf-8') as f:
            content = f.read().strip()
            
            if not content:
                feedback_parts.append("❌ CSV is empty")
            else:
                score += 15  # Valid text file format readable
                feedback_parts.append("✅ CSV is readable")
                
                # Use csv module to parse
                f.seek(0)
                # handle both comma and semicolon dialects
                sniffer = csv.Sniffer()
                try:
                    dialect = sniffer.sniff(content[:1024] if len(content) > 1024 else content)
                    reader = csv.reader(f, dialect)
                except csv.Error:
                    # fallback
                    reader = csv.reader(f)

                parsed_rows = [row for row in reader if any(cell.strip() for cell in row)]
                
                if len(parsed_rows) >= 4:  # Header + 3 data rows
                    score += 20
                    feedback_parts.append("✅ CSV contains >= 3 data rows (plus header)")
                    
                    # Verify numeric presence in data rows (skip header)
                    data_rows = parsed_rows[1:]
                    numeric_rows_count = sum(
                        1 for row in data_rows if any(is_numeric(cell) for cell in row)
                    )
                    
                    if numeric_rows_count >= 3:
                        score += 20
                        feedback_parts.append("✅ Numeric length values detected in CSV rows")
                    else:
                        feedback_parts.append("❌ Missing numeric length data in the rows")
                else:
                    feedback_parts.append(f"❌ Not enough rows in CSV (found {len(parsed_rows)-1} data rows, expected 3)")

    except Exception as e:
        feedback_parts.append(f"❌ Error reading CSV content: {e}")
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    # ================================================================
    # Criteria 5: Screenshot File Exists (10 points)
    # ================================================================
    if img_exists:
        score += 10
        feedback_parts.append("✅ Output screenshot image saved")
    else:
        feedback_parts.append("❌ Screenshot image not saved")

    # ================================================================
    # Criteria 6: VLM Visual Confirmation (20 points)
    # ================================================================
    if VLM_AVAILABLE and traj:
        try:
            frames = sample_trajectory_frames(traj, n=3)
            final_frame = get_final_screenshot(traj)
            images_to_check = frames + [final_frame] if final_frame else frames
            
            if images_to_check:
                prompt = """
                You are verifying a medical image analysis task in Weasis DICOM Viewer.
                Look at these sequence of screenshots representing the user's workflow.
                
                Did the user draw AT LEAST THREE distinct line measurements (distance annotations) 
                on the medical image? Look carefully for straight lines drawn on the image with numeric 
                length labels next to them.
                
                Respond with ONLY JSON format:
                {
                    "has_three_measurements": true/false,
                    "reasoning": "brief explanation of what you see"
                }
                """
                vlm_res = query_vlm(prompt=prompt, images=images_to_check)
                if vlm_res.get("success"):
                    parsed = vlm_res.get("parsed", {})
                    if parsed.get("has_three_measurements", False):
                        score += 20
                        feedback_parts.append("✅ VLM confirmed 3 distinct line measurements on the image")
                    else:
                        feedback_parts.append("❌ VLM could not confirm 3 lines are visibly drawn")
                else:
                    feedback_parts.append("⚠️ VLM query failed")
        except Exception as e:
            logger.error(f"VLM check failed: {e}")
            feedback_parts.append("⚠️ VLM verification error")

    # Final scoring: Needs CSV structure + visual confirmation
    passed = score >= 70 and csv_created and len(feedback_parts) > 0

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }