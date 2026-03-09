#!/usr/bin/env python3
"""
Verifier for chinook_artist_affinity_analysis@1

Criteria:
1. DBeaver Connection 'Chinook' created (10 pts)
2. CSV Export exists and was created during task (10 pts)
3. CSV Headers match required format (10 pts)
4. Logic Check: Artist_A is alphabetically before Artist_B (No duplicates) (20 pts)
5. Data Accuracy: Top 5 pairs match ground truth (30 pts)
6. SQL Script saved (20 pts)
"""

import json
import os
import csv
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_chinook_artist_affinity_analysis(traj, env_info, task_info):
    # 1. Setup Environment Access
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 2. Load Task Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 3. Load Ground Truth JSON (generated in setup_task.sh)
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/affinity_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            ground_truth = json.load(f)
    except Exception as e:
        # If GT is missing, we can't verify accuracy, but don't fail immediately
        logger.error(f"Failed to load ground truth: {e}")
        ground_truth = {"top_pairs": []}
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)

    score = 0
    feedback = []

    # --- Criterion 1: Connection (10 pts) ---
    if result_data.get('connection_exists') and result_data.get('connection_name_match'):
        score += 10
        feedback.append("✅ DBeaver connection 'Chinook' verified.")
    elif result_data.get('connection_exists'):
        score += 5
        feedback.append("⚠️ Connection exists but name might not be exactly 'Chinook'.")
    else:
        feedback.append("❌ DBeaver connection not found.")

    # --- Criterion 2: SQL Script (20 pts) ---
    if result_data.get('sql_exists'):
        score += 20
        feedback.append("✅ SQL script saved.")
    else:
        feedback.append("❌ SQL script not found.")

    # --- Criterion 3: CSV Existence & Timeliness (10 pts) ---
    csv_path = result_data.get('csv_path')
    if result_data.get('csv_exists') and result_data.get('csv_created_during_task'):
        score += 10
        feedback.append("✅ CSV export found and created during task.")
    elif result_data.get('csv_exists'):
        score += 5
        feedback.append("⚠️ CSV export found but timestamp check failed (pre-existing?).")
    else:
        feedback.append("❌ CSV export file not found.")
        return {"passed": False, "score": score, "feedback": "\n".join(feedback)}

    # --- Analyze CSV Content (Remaining 60 pts) ---
    # We need to copy the actual CSV out to read it
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env(csv_path, temp_csv.name)
        
        with open(temp_csv.name, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            headers = reader.fieldnames
            rows = list(reader)

        # Check Headers (10 pts)
        required_headers = {'Artist_A', 'Artist_B', 'CoOccurrenceCount'}
        # Allow case-insensitive matching or slight variations if robust, but task spec was strict.
        # Strict check:
        if headers and required_headers.issubset(set(headers)):
            score += 10
            feedback.append("✅ CSV headers are correct.")
        else:
            feedback.append(f"❌ Incorrect headers. Found: {headers}, Expected: {required_headers}")

        # Check Logic: A < B (20 pts)
        # We check the first 20 rows (or all if less)
        violation_count = 0
        for i, row in enumerate(rows[:20]):
            a = row.get('Artist_A', '')
            b = row.get('Artist_B', '')
            # Determine if alphabetical order is respected. 
            # Note: The query should filter WHERE a < b. If we see a > b, they missed the dedupe logic.
            if a >= b:
                violation_count += 1
        
        if len(rows) > 0 and violation_count == 0:
            score += 20
            feedback.append("✅ Artist pairs are correctly deduplicated (A < B).")
        elif len(rows) == 0:
            feedback.append("❌ CSV is empty.")
        else:
            feedback.append(f"❌ Logic Error: Found {violation_count} pairs in top 20 where Artist_A >= Artist_B.")

        # Check Accuracy: Match Ground Truth (30 pts)
        # We compare the top 5 rows from user against top 5 from GT
        gt_pairs = ground_truth.get('top_pairs', [])
        match_count = 0
        
        # Normalize data for comparison (strip whitespace, ensure types)
        user_top_5 = []
        for row in rows[:5]:
            try:
                user_top_5.append({
                    "a": row.get('Artist_A', '').strip(),
                    "b": row.get('Artist_B', '').strip(),
                    "c": int(row.get('CoOccurrenceCount', 0))
                })
            except ValueError:
                continue

        gt_top_5 = []
        for row in gt_pairs[:5]:
            gt_top_5.append({
                "a": row.get('Artist_A', '').strip(),
                "b": row.get('Artist_B', '').strip(),
                "c": int(row.get('Count', 0))
            })

        # Compare sets of (A, B, Count) for robustness against tie-breaking sort order differences
        # Although the spec said sort by Count Desc, A Asc, so order should be deterministic.
        
        # Let's do direct index comparison for strictness on sorting
        matches = 0
        for i in range(min(len(user_top_5), len(gt_top_5))):
            u = user_top_5[i]
            g = gt_top_5[i]
            
            # Allow minor differences in count (unlikely in SQLite but possible if DB version differs slightly)
            # Relaxed check: A and B match, count is close
            if u['a'] == g['a'] and u['b'] == g['b'] and abs(u['c'] - g['c']) <= 1:
                matches += 1
        
        if matches >= 5:
            score += 30
            feedback.append("✅ Data Accuracy: Top 5 pairs match ground truth exactly.")
        elif matches >= 3:
            score += 15
            feedback.append(f"⚠️ Data Accuracy: {matches}/5 top pairs match ground truth.")
        else:
            feedback.append(f"❌ Data Accuracy: Only {matches}/5 top pairs match. Check your JOIN logic.")
            # Add debug info to feedback
            if len(user_top_5) > 0:
                feedback.append(f"   User Top 1: {user_top_5[0]}")
            if len(gt_top_5) > 0:
                feedback.append(f"   Expected Top 1: {gt_top_5[0]}")

    except Exception as e:
        feedback.append(f"❌ Error validating CSV content: {e}")
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }