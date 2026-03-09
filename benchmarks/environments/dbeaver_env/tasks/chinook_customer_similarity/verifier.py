#!/usr/bin/env python3
"""
Verifier for chinook_customer_similarity task.
"""

import json
import csv
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_chinook_customer_similarity(traj, env_info, task_info):
    """
    Verify the Jaccard similarity matrix task.
    
    Scoring:
    - Connection 'Chinook' exists: 10 pts
    - CSV exists & fresh: 10 pts
    - CSV structure (columns & 20 rows): 15 pts
    - SQL script exists: 10 pts
    - Top 1 pair matches ground truth (IDs): 15 pts
    - Top 1 Jaccard value matches (tol 0.005): 10 pts
    - Set of pairs matches ground truth (>=15 pairs): 15 pts
    - Correct ordering (Jaccard DESC): 15 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            res = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []

    # 2. Retrieve Agent CSV
    agent_csv_data = []
    if res.get("csv_exists"):
        temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
        try:
            copy_from_env(res["csv_path"], temp_csv.name)
            with open(temp_csv.name, 'r', encoding='utf-8-sig') as f:
                reader = csv.DictReader(f)
                agent_csv_data = list(reader)
        except Exception as e:
            feedback.append(f"Failed to read agent CSV: {e}")
        finally:
            if os.path.exists(temp_csv.name):
                os.unlink(temp_csv.name)

    # 3. Retrieve Ground Truth
    gt_data = []
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(res["gt_path"], temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_data = json.load(f)
    except Exception as e:
        feedback.append(f"Failed to load ground truth: {e}")
        # Fatal error for verification logic relying on GT
        return {"passed": False, "score": 0, "feedback": "Verification failed: Ground Truth missing."}
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)

    # --- SCORING LOGIC ---

    # Criterion 1: Connection (10 pts)
    if res.get("connection_exists") and res.get("connection_correct"):
        score += 10
        feedback.append("DBeaver connection correct.")
    elif res.get("connection_exists"):
        score += 5
        feedback.append("DBeaver connection exists but name/path might differ.")
    else:
        feedback.append("DBeaver connection missing.")

    # Criterion 2: CSV Existence & Freshness (10 pts)
    if res.get("csv_exists") and res.get("csv_fresh"):
        score += 10
        feedback.append("Output CSV created.")
    elif res.get("csv_exists"):
        score += 5
        feedback.append("Output CSV exists but timestamp is old.")
    else:
        feedback.append("Output CSV missing.")

    # Criterion 3: CSV Structure (15 pts)
    cols_ok = res.get("csv_columns_valid")
    rows_ok = (res.get("csv_row_count") == 20)
    
    if cols_ok and rows_ok:
        score += 15
        feedback.append("CSV structure and row count correct.")
    elif cols_ok or rows_ok:
        score += 7
        feedback.append("CSV structure partial match (check columns or row count).")
    else:
        feedback.append("CSV structure incorrect.")

    # Criterion 4: SQL Script (10 pts)
    if res.get("sql_exists"):
        score += 10
        feedback.append("SQL script saved.")
    else:
        feedback.append("SQL script missing.")

    # Data Verification
    if agent_csv_data and gt_data:
        try:
            # Normalize keys for comparison (agent might use different cases if not strictly following instructions, but we assume header logic in export checks strictness. Let's be robust.)
            def get_val(row, keys):
                for k in keys:
                    if k in row: return row[k]
                    if k.lower() in row: return row[k.lower()] # Fallback
                return None

            # 4. Top 1 Match (15 pts)
            agent_top = agent_csv_data[0]
            gt_top = gt_data[0]
            
            a_idA = int(get_val(agent_top, ["CustomerIdA"]))
            a_idB = int(get_val(agent_top, ["CustomerIdB"]))
            gt_idA = gt_top["CustomerIdA"]
            gt_idB = gt_top["CustomerIdB"]

            if (a_idA == gt_idA and a_idB == gt_idB) or (a_idA == gt_idB and a_idB == gt_idA):
                score += 15
                feedback.append(f"Top pair matches ground truth ({gt_idA}, {gt_idB}).")
            else:
                feedback.append(f"Top pair mismatch. Expected ({gt_idA}, {gt_idB}), got ({a_idA}, {a_idB}).")

            # 5. Top 1 Jaccard Value (10 pts)
            try:
                a_jaccard = float(get_val(agent_top, ["JaccardSimilarity"]))
                gt_jaccard = gt_top["JaccardSimilarity"]
                if abs(a_jaccard - gt_jaccard) < 0.005:
                    score += 10
                    feedback.append(f"Top Jaccard value accurate ({a_jaccard}).")
                else:
                    feedback.append(f"Top Jaccard value inaccurate. Expected ~{gt_jaccard}, got {a_jaccard}.")
            except:
                feedback.append("Could not parse Top Jaccard value.")

            # 6. Set Matching (15 pts)
            # Count how many of the GT pairs are in the agent's top 20
            gt_pairs = set(tuple(sorted((r["CustomerIdA"], r["CustomerIdB"]))) for r in gt_data)
            agent_pairs = set()
            for r in agent_csv_data:
                try:
                    p = tuple(sorted((int(get_val(r, ["CustomerIdA"])), int(get_val(r, ["CustomerIdB"])))))
                    agent_pairs.add(p)
                except:
                    pass
            
            matches = len(gt_pairs.intersection(agent_pairs))
            if matches >= 15:
                score += 15
                feedback.append(f"Strong overlap with ground truth ({matches}/20 pairs).")
            elif matches >= 10:
                score += 8
                feedback.append(f"Moderate overlap with ground truth ({matches}/20 pairs).")
            else:
                feedback.append(f"Weak overlap with ground truth ({matches}/20 pairs).")

            # 7. Ordering (15 pts)
            # Check if agent data is sorted by Jaccard DESC
            sorted_correctly = True
            prev_val = 1.01
            for r in agent_csv_data:
                try:
                    curr = float(get_val(r, ["JaccardSimilarity"]))
                    if curr > prev_val:
                        sorted_correctly = False
                        break
                    prev_val = curr
                except:
                    pass
            
            if sorted_correctly:
                score += 15
                feedback.append("Data sorted correctly.")
            else:
                feedback.append("Data not sorted by Jaccard Similarity DESC.")

        except Exception as e:
            feedback.append(f"Error during data verification: {e}")

    # Final Score Calculation
    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }