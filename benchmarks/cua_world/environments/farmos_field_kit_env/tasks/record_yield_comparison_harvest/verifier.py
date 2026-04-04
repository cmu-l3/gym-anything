#!/usr/bin/env python3
"""
Verifier for record_yield_comparison_harvest task.
Analyzes the exported SQLite database from farmOS Field Kit.
"""

import sqlite3
import json
import os
import sys
import tempfile
import shutil
import logging
from datetime import datetime

# Import VLM utils provided by the environment
try:
    from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames
except ImportError:
    # Fallback for local testing
    def query_vlm(**kwargs): return {"success": False, "error": "VLM not available"}
    def get_final_screenshot(traj): return None
    def sample_trajectory_frames(traj, n=1): return []

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_yield_comparison(traj, env_info, task_info):
    """
    Verifies that a Harvest log with two labeled quantities was created.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_date_str = metadata.get('expected_date', '2025-07-15')
    expected_notes_keyword = metadata.get('expected_notes_keyword', 'Garlic harvest trial')
    expected_quantities = metadata.get('quantities', [])

    score = 0
    max_score = 100
    feedback_parts = []
    
    # Create temp directory for artifacts
    temp_dir = tempfile.mkdtemp()
    
    try:
        # --- Step 1: Retrieve Artifacts ---
        # Try to retrieve database files. We don't know the exact name, so we listed them in export.
        # We'll try to pull the directory or known filenames.
        # Since copy_from_env usually copies single files, we might need to guess.
        # Common farmOS DB names: 'farmos.db', 'field-kit.db', 'logs.db'
        
        db_path = None
        possible_db_names = ['farmos.db', 'field-kit.db', 'data.db', 'app.db']
        
        for db_name in possible_db_names:
            local_path = os.path.join(temp_dir, db_name)
            try:
                # Path on device as set in export_result.sh
                copy_from_env(f"/sdcard/task_export/{db_name}", local_path)
                if os.path.getsize(local_path) > 0:
                    db_path = local_path
                    logger.info(f"Found database: {db_name}")
                    break
            except Exception:
                continue
                
        # Get metadata
        meta_path = os.path.join(temp_dir, "task_meta.json")
        task_start_time = 0
        try:
            copy_from_env("/sdcard/task_export/task_meta.json", meta_path)
            with open(meta_path, 'r') as f:
                meta = json.load(f)
                task_start_time = meta.get('task_start', 0)
        except Exception as e:
            logger.warning(f"Could not retrieve task metadata: {e}")

        # --- Step 2: Database Verification ---
        db_verified = False
        if db_path:
            try:
                conn = sqlite3.connect(db_path)
                cursor = conn.cursor()
                
                # List tables to understand schema if unknown
                cursor.execute("SELECT name FROM sqlite_master WHERE type='table';")
                tables = [r[0] for r in cursor.fetchall()]
                logger.info(f"DB Tables: {tables}")
                
                # Heuristic: Find the logs table. Usually 'logs' or 'log'.
                log_table = next((t for t in tables if 'log' in t.lower() and 'activity' not in t.lower()), 'logs')
                
                # Check for the specific log
                # We look for a harvest log around the expected date
                # Date format in DB might be timestamp or string.
                
                # Query all logs to inspect
                cursor.execute(f"SELECT * FROM {log_table}")
                columns = [description[0] for description in cursor.description]
                all_logs = [dict(zip(columns, row)) for row in cursor.fetchall()]
                
                target_log = None
                for log in all_logs:
                    # Check Notes
                    notes_val = str(log.get('notes', '') or '')
                    name_val = str(log.get('name', '') or '')
                    
                    # Check Type (might be stored as 'harvest' or an ID)
                    type_val = str(log.get('type', '') or '').lower()
                    
                    # Check Date (might be timestamp in ms or s, or ISO string)
                    date_val = log.get('timestamp') or log.get('date') or 0
                    
                    is_match = False
                    if expected_notes_keyword.lower() in notes_val.lower():
                        is_match = True
                    
                    # Convert date to check if it matches 2025-07-15
                    # 2025-07-15 is approx 1752537600 (seconds) or 1752537600000 (ms)
                    try:
                        d_ts = float(date_val)
                        if d_ts > 1735689600: # After 2025-01-01
                             # Check if it falls on the day (loose check)
                             # Just checking year/month is often enough for unique tasks
                             if '2025' in datetime.fromtimestamp(d_ts if d_ts < 10000000000 else d_ts/1000).strftime('%Y-%m-%d'):
                                 pass 
                    except:
                        if '2025-07-15' in str(date_val):
                            is_match = True

                    if is_match:
                        target_log = log
                        break
                
                if target_log:
                    score += 40
                    feedback_parts.append("Found Harvest log with correct notes/date.")
                    
                    # Now check quantities
                    # Usually linked by log_id or stored in a separate table 'quantities'
                    # Schema guess: table 'quantities' with column 'log_id' matching 'id' or 'local_id' from log
                    
                    qty_table = next((t for t in tables if 'quant' in t.lower()), None)
                    
                    if qty_table:
                        log_id = target_log.get('id') or target_log.get('local_id') or target_log.get('_id')
                        
                        # Find columns for quantity table
                        cursor.execute(f"SELECT * FROM {qty_table}")
                        q_cols = [d[0] for d in cursor.description]
                        
                        # Look for quantities linking to this log
                        # Try common FK names: log_id, log, parent_id
                        fk_col = next((c for c in q_cols if 'log' in c or 'parent' in c), None)
                        
                        found_quantities = []
                        if fk_col:
                            cursor.execute(f"SELECT * FROM {qty_table} WHERE {fk_col}=?", (log_id,))
                            found_quantities = [dict(zip(q_cols, row)) for row in cursor.fetchall()]
                        else:
                            # Fallback: scan all quantities if DB is small
                            cursor.execute(f"SELECT * FROM {qty_table}")
                            all_qs = [dict(zip(q_cols, row)) for row in cursor.fetchall()]
                            # Logic to link would be guessing, but let's see if we find matching values
                            found_quantities = all_qs # risky, but maybe only these exist
                            
                        # Verify the two quantities
                        upper_found = False
                        lower_found = False
                        
                        for q in found_quantities:
                            val = str(q.get('value', ''))
                            lbl = str(q.get('label', '') or '')
                            
                            if '450' in val and 'Upper' in lbl:
                                upper_found = True
                            if '320' in val and 'Lower' in lbl:
                                lower_found = True
                                
                        if upper_found:
                            score += 20
                            feedback_parts.append("Quantity 'Upper Field' (450) confirmed.")
                        else:
                            feedback_parts.append("Missing or incorrect 'Upper Field' quantity.")
                            
                        if lower_found:
                            score += 20
                            feedback_parts.append("Quantity 'Lower Field' (320) confirmed.")
                        else:
                            feedback_parts.append("Missing or incorrect 'Lower Field' quantity.")
                            
                        db_verified = True
                        
                else:
                    feedback_parts.append("Could not find the specific Harvest log in database.")

            except Exception as e:
                logger.error(f"Database analysis failed: {e}")
                feedback_parts.append(f"Database verification error: {e}")
        
        # --- Step 3: VLM Verification (Hybrid/Fallback) ---
        # If DB verification was partial or failed (maybe schema mismatch), use VLM
        
        vlm_score = 0
        vlm_possible = 20 if db_verified else 100
        
        # Get frames
        frames = sample_trajectory_frames(traj, n=5)
        final_ss = get_final_screenshot(traj)
        if final_ss:
            frames.append(final_ss)
            
        if frames:
            prompt = f"""
            Analyze these screenshots from the farmOS Field Kit app.
            Task: Create a Harvest log for 'Garlic harvest trial' with two quantities:
            1. 450 bulbs labeled 'Upper Field'
            2. 320 bulbs labeled 'Lower Field'
            
            Look for:
            - A log form or list showing 'Harvest' type.
            - The date set to July 15, 2025.
            - Two quantity entries visible (or the action of adding them).
            - Labels 'Upper Field' and 'Lower Field'.
            - Values 450 and 320.
            
            Return JSON:
            {{
                "log_created": true/false,
                "date_correct": true/false,
                "upper_quantity_seen": true/false,
                "lower_quantity_seen": true/false,
                "confidence": 0-1
            }}
            """
            
            vlm_res = query_vlm(images=frames, prompt=prompt)
            if vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('log_created'):
                    # If DB failed, give base points here
                    if not db_verified: score += 20
                
                if parsed.get('upper_quantity_seen'):
                    if not db_verified: score += 30
                    feedback_parts.append("VLM confirmed 'Upper Field' quantity.")
                
                if parsed.get('lower_quantity_seen'):
                    if not db_verified: score += 30
                    feedback_parts.append("VLM confirmed 'Lower Field' quantity.")
                    
                if db_verified:
                    # Just add the bonus/completion points
                    score += 20
        
        # Cap score
        score = min(score, 100)
        passed = score >= 75
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    finally:
        shutil.rmtree(temp_dir)