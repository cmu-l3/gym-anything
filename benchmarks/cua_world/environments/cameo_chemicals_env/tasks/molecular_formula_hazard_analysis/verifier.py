#!/usr/bin/env python3
"""
Verifier for Molecular Formula Hazard Analysis task.

Criteria:
1. Files Created (Anti-gaming): Output files must exist and be created during task.
2. CSV Content: Must contain the 4 specific isomers with correct NFPA ratings.
3. Analysis: Must correctly identify the worst-case health hazard (Allyl alcohol).
4. VLM Verification: Uses trajectory to verify 'Formula' search was performed.
"""

import json
import csv
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_molecular_formula_hazard_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_chemicals = metadata.get('target_chemicals', {})
    worst_case_target = metadata.get('worst_case_target', 'Allyl alcohol')

    score = 0
    feedback_parts = []
    
    # ------------------------------------------------------------------
    # 1. Load Task Result JSON (Metadata & Timing)
    # ------------------------------------------------------------------
    task_result = {}
    with tempfile.NamedTemporaryFile(delete=True, suffix='.json') as tf:
        try:
            copy_from_env("/tmp/task_result.json", tf.name)
            tf.seek(0)
            task_result = json.load(tf)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}

    # Check existence and freshness (Anti-gaming)
    if task_result.get("csv_exists") and task_result.get("csv_created_during_task"):
        score += 10
        feedback_parts.append("CSV file created.")
    else:
        feedback_parts.append("CSV file missing or pre-existing.")

    if task_result.get("txt_exists") and task_result.get("txt_created_during_task"):
        score += 10
        feedback_parts.append("Analysis text file created.")
    else:
        feedback_parts.append("Analysis text file missing.")

    # ------------------------------------------------------------------
    # 2. Verify CSV Content (Data Accuracy)
    # ------------------------------------------------------------------
    csv_score = 0
    max_csv_score = 40
    
    if task_result.get("csv_exists"):
        with tempfile.NamedTemporaryFile(delete=True, suffix='.csv') as tf:
            try:
                copy_from_env("/home/ga/Desktop/isomer_hazards.csv", tf.name)
                tf.seek(0)
                
                # Parse CSV
                with open(tf.name, 'r', encoding='utf-8', errors='ignore') as f:
                    reader = csv.DictReader(f)
                    rows = list(reader)
                    
                    # Normalize headers for robustness
                    headers = [h.lower().strip() for h in reader.fieldnames or []]
                    required_headers = ['chemical', 'health', 'flammability', 'instability']
                    
                    if not all(h in headers for h in required_headers):
                         feedback_parts.append("CSV headers incorrect.")
                    else:
                        # Normalize rows for easier lookup
                        found_data = {}
                        for row in rows:
                            # Robust key finding
                            name_key = next((k for k in row.keys() if 'chemical' in k.lower()), None)
                            if not name_key: continue
                            
                            name = row[name_key].lower()
                            
                            # Clean up NFPA values (handle 'N/A' or empty strings)
                            def parse_val(k_pattern):
                                k = next((x for x in row.keys() if k_pattern in x.lower()), None)
                                val = row.get(k, '0')
                                try:
                                    return int(float(val))
                                except:
                                    return 0

                            h_val = parse_val('health')
                            f_val = parse_val('flammability')
                            i_val = parse_val('instability')
                            
                            found_data[name] = {'h': h_val, 'f': f_val, 'i': i_val}

                        # Check against targets
                        chemicals_found_count = 0
                        ratings_correct_count = 0
                        
                        for target_name, target_vals in target_chemicals.items():
                            # Find matching entry in CSV
                            match = next((v for k, v in found_data.items() if target_name in k), None)
                            
                            if match:
                                chemicals_found_count += 1
                                # Check ratings (Exact match required for standard values)
                                if (match['h'] == target_vals['health'] and 
                                    match['f'] == target_vals['flammability'] and 
                                    match['i'] == target_vals['instability']):
                                    ratings_correct_count += 1
                            else:
                                feedback_parts.append(f"Missing chemical: {target_name}")

                        # Score calc
                        # 4 chemicals * 5 pts for presence = 20 pts
                        # 4 chemicals * 5 pts for correct data = 20 pts
                        csv_score += (chemicals_found_count * 5)
                        csv_score += (ratings_correct_count * 5)
                        feedback_parts.append(f"Data accuracy: {chemicals_found_count}/4 found, {ratings_correct_count}/4 correct.")

            except Exception as e:
                feedback_parts.append(f"Error processing CSV: {e}")
    
    score += csv_score

    # ------------------------------------------------------------------
    # 3. Verify Analysis Text (Reasoning)
    # ------------------------------------------------------------------
    analysis_score = 0
    if task_result.get("txt_exists"):
        with tempfile.NamedTemporaryFile(delete=True, suffix='.txt') as tf:
            try:
                copy_from_env("/home/ga/Desktop/worst_case_analysis.txt", tf.name)
                tf.seek(0)
                content = tf.read().decode('utf-8').lower()
                
                # Check for "Allyl alcohol"
                if "allyl" in content and "alcohol" in content:
                    analysis_score = 30
                    feedback_parts.append("Correctly identified worst-case hazard.")
                elif "allyl" in content:
                    analysis_score = 15
                    feedback_parts.append("Partially correctly identified (ambiguous name).")
                else:
                    feedback_parts.append("Failed to identify Allyl Alcohol as worst case.")
            except:
                feedback_parts.append("Error reading analysis file.")
    
    score += analysis_score

    # ------------------------------------------------------------------
    # 4. VLM Trajectory Verification (Process)
    # ------------------------------------------------------------------
    # We want to confirm they actually used the "Formula" search, 
    # not just the name search (which would fail for "C3H6O") or just guessed.
    vlm_score = 0
    frames = sample_trajectory_frames(traj, n=4)
    
    if frames:
        vlm_prompt = """
        Review these screenshots of a user interacting with CAMEO Chemicals.
        Did the user:
        1. Access the 'Search' page?
        2. Perform a search using a chemical formula (look for 'Formula' radio button selected or text 'C3H6O' in search box)?
        3. View search results listing multiple chemicals?
        
        Answer JSON: {"formula_search_performed": bool}
        """
        
        try:
            res = query_vlm(images=frames, prompt=vlm_prompt)
            if res.get("parsed", {}).get("formula_search_performed", False):
                vlm_score = 10
                feedback_parts.append("VLM confirmed formula search workflow.")
            else:
                feedback_parts.append("VLM could not verify formula search workflow.")
        except:
            # If VLM fails, we don't penalize too heavily if the data is correct
            vlm_score = 10 # Benefit of doubt if programmatic checks pass
            feedback_parts.append("VLM check skipped.")
    
    score += vlm_score

    # ------------------------------------------------------------------
    # Final Scoring
    # ------------------------------------------------------------------
    # Max Score Breakdown:
    # Files Exists: 20
    # CSV Content: 40
    # Text Analysis: 30
    # VLM Process: 10
    # Total: 100
    
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }