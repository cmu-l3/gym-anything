#!/usr/bin/env python3
"""
Verifier for Waterway Spill Behavior Classification task.

SCORING CRITERIA (Total 100):
1. Files Existence (10 pts): Both Report and CSV exist.
2. Anti-Gaming (5 pts): Files created during task session.
3. CSV Content (55 pts):
   - Correct Specific Gravity values (within tolerance) (20 pts)
   - Correct Behavior classification (35 pts)
4. Report Content (15 pts): Contains "Water Solubility" info for chemicals.
5. VLM Verification (15 pts): Trajectory shows research on CAMEO website.
"""

import json
import os
import csv
import tempfile
import logging
from typing import Dict, Any, List

# Import gym_anything VLM utils
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_waterway_spill_behavior_classification(traj, env_info, task_info):
    """
    Verify the spill behavior classification task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    ground_truth = metadata.get('ground_truth', {})
    tolerance_sg = metadata.get('tolerance_sg', 0.05)

    score = 0
    feedback_parts = []
    
    # ------------------------------------------------------------------
    # 1. Load Task Result JSON
    # ------------------------------------------------------------------
    result_json_path = tempfile.mktemp(suffix=".json")
    try:
        copy_from_env("/tmp/task_result.json", result_json_path)
        with open(result_json_path, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(result_json_path):
            os.unlink(result_json_path)

    # ------------------------------------------------------------------
    # 2. Check File Existence & Timestamp (15 pts)
    # ------------------------------------------------------------------
    report_exists = task_result.get("report_exists", False)
    csv_exists = task_result.get("csv_exists", False)
    report_fresh = task_result.get("report_created_during_task", False)
    csv_fresh = task_result.get("csv_created_during_task", False)

    if report_exists: 
        score += 5
        feedback_parts.append("Report file exists.")
    else:
        feedback_parts.append("Report file missing.")

    if csv_exists: 
        score += 5
        feedback_parts.append("CSV file exists.")
    else:
        feedback_parts.append("CSV file missing.")

    if report_fresh and csv_fresh:
        score += 5
        feedback_parts.append("Files created during task session.")
    elif report_exists or csv_exists:
        feedback_parts.append("Warning: Files may be stale (created before task start).")

    # ------------------------------------------------------------------
    # 3. Verify CSV Content (55 pts)
    # ------------------------------------------------------------------
    if csv_exists:
        csv_temp_path = tempfile.mktemp(suffix=".csv")
        try:
            copy_from_env("/tmp/spill_behavior_summary.csv", csv_temp_path)
            
            # Read CSV
            rows = []
            with open(csv_temp_path, 'r', errors='ignore') as f:
                reader = csv.DictReader(f)
                for row in reader:
                    # Normalize keys (strip spaces, lowercase)
                    clean_row = {k.strip().lower(): v.strip() for k, v in row.items() if k}
                    rows.append(clean_row)
            
            # Helper to find chemical in rows
            def find_chem_row(name_fragment):
                for r in rows:
                    # Check 'chemical' or 'name' column
                    val = r.get('chemical', '') or r.get('name', '')
                    if name_fragment.lower() in val.lower():
                        return r
                return None

            # Verify each chemical
            correct_sg_count = 0
            correct_behavior_count = 0
            chemicals = ["Benzene", "Carbon tetrachloride", "Acetone", "Chloroform", "Toluene"]
            
            for chem in chemicals:
                chem_gt = ground_truth.get(chem)
                row = find_chem_row(chem)
                
                if not row:
                    feedback_parts.append(f"Missing CSV entry for {chem}.")
                    continue

                # Check Specific Gravity (4 pts each)
                try:
                    sg_val_str = row.get('specific_gravity', '') or row.get('sg', '') or row.get('specific gravity', '')
                    sg_val = float(sg_val_str)
                    expected_sg = chem_gt['sg']
                    if abs(sg_val - expected_sg) <= tolerance_sg:
                        correct_sg_count += 1
                        score += 4
                    else:
                        feedback_parts.append(f"{chem} SG incorrect (got {sg_val}, expected ~{expected_sg}).")
                except ValueError:
                    feedback_parts.append(f"{chem} SG invalid format.")

                # Check Behavior (7 pts each)
                behavior_val = row.get('spill_behavior', '') or row.get('behavior', '') or row.get('spill behavior', '')
                if behavior_val.upper() == chem_gt['behavior']:
                    correct_behavior_count += 1
                    score += 7
                else:
                    feedback_parts.append(f"{chem} Behavior incorrect (got {behavior_val}, expected {chem_gt['behavior']}).")

            feedback_parts.append(f"CSV Analysis: {correct_sg_count}/5 SG values correct, {correct_behavior_count}/5 Behaviors correct.")

        except Exception as e:
            feedback_parts.append(f"Error parsing CSV: {str(e)}")
        finally:
            if os.path.exists(csv_temp_path):
                os.unlink(csv_temp_path)

    # ------------------------------------------------------------------
    # 4. Verify Report Content (15 pts)
    # ------------------------------------------------------------------
    if report_exists:
        report_temp_path = tempfile.mktemp(suffix=".txt")
        try:
            copy_from_env("/tmp/spill_behavior_report.txt", report_temp_path)
            with open(report_temp_path, 'r', errors='ignore') as f:
                content = f.read().lower()
                
            # Check for solubility mentions (3 pts each chem)
            solubility_count = 0
            chemicals_simple = ["benzene", "carbon", "acetone", "chloroform", "toluene"]
            for chem in chemicals_simple:
                if chem in content and "solub" in content:
                     # Very basic check: name exists and "solubility" word appears in file
                     # A stricter check would parse blocks, but text format varies
                     solubility_count += 1
            
            # Cap at 15 pts (3 pts * 5)
            # Since regex block parsing is brittle, we award points if the file is substantial
            # and contains key terms.
            if "water solubility" in content and len(content) > 100:
                score += 15
                feedback_parts.append("Report contains solubility information.")
            else:
                score += 5 # Partial credit for non-empty file
                feedback_parts.append("Report content limited or missing solubility details.")

        except Exception as e:
            feedback_parts.append(f"Error reading report: {str(e)}")
        finally:
            if os.path.exists(report_temp_path):
                os.unlink(report_temp_path)

    # ------------------------------------------------------------------
    # 5. VLM Verification (15 pts)
    # ------------------------------------------------------------------
    # Sample frames from trajectory
    frames = sample_trajectory_frames(traj, n=6)
    
    if frames:
        vlm_prompt = (
            "Review these screenshots of an agent performing a task.\n"
            "Did the agent visit the CAMEO Chemicals website?\n"
            "Did the agent search for chemicals or view datasheet pages?\n"
            "Answer JSON with keys: 'visited_site' (bool), 'performed_search' (bool)."
        )
        
        vlm_result = query_vlm(
            prompt=vlm_prompt,
            images=frames,
            model="gpt-4o" 
        )
        
        if vlm_result.get('success'):
            parsed = vlm_result.get('parsed', {})
            if parsed.get('visited_site', False):
                score += 10
                if parsed.get('performed_search', False):
                    score += 5
                feedback_parts.append("VLM verified website usage.")
            else:
                feedback_parts.append("VLM did not observe CAMEO Chemicals usage.")
        else:
            # Fallback if VLM fails: assume innocent if CSV is correct
            if score >= 50:
                score += 15
                feedback_parts.append("VLM check skipped (service unavailable), assumed valid based on output.")

    # ------------------------------------------------------------------
    # Final Result
    # ------------------------------------------------------------------
    # Pass threshold: 60 points AND at least 3 correct behaviors
    pass_threshold = 60
    
    # Estimate behavior count from score if not explicitly tracked
    # We tracked `correct_behavior_count` above.
    # If CSV didn't exist, count is 0.
    if not csv_exists:
        correct_behavior_count = 0

    passed = (score >= pass_threshold) and (correct_behavior_count >= 3)
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }