#!/usr/bin/env python3
"""
Verifier for active_telemetry_sqlite_export task.

Validates the agent's ability to pull continuous telemetry, invoke commands,
and correctly write SQLite structures mirroring the real-world COSMOS output.

Scoring breakdown (100 pts total):
  10pts  Export metadata JSON readable
   5pts  SQLite Database file exists on Desktop
   5pts  Database was newly created this session
  20pts  System Authenticity: `cmd_acpt_cnt` increased (agent actively commanded)
  15pts  Schema Validation (Correct columns and types)
  15pts  Record Volume (>= 10 rows inserted)
  10pts  Data Sanity (Values are populated and float temperatures are valid)
  10pts  Chronological Order (Timestamps continuously scale upward)
  10pts  DB Authenticity Check (Database telemetry shows `COLLECTS` increments)

Pass Threshold: 65 points AND Actual System Command Execution.
"""

import json
import os
import sqlite3
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_active_telemetry_sqlite_export(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if copy_from_env is None:
        return {'passed': False, 'score': 0, 'feedback': 'copy_from_env not available'}

    meta = task_info.get('metadata', {})
    result_file = meta.get('result_file', '/tmp/active_telemetry_sqlite_export_result.json')
    output_db = meta.get('output_db', '/home/ga/Desktop/telemetry_archive.db')

    score = 0
    feedback = []

    # ── 1. Read metadata exported from container ──────────────────────────────
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            tmp_name = tmp.name
        copy_from_env(result_file, tmp_name)
        with open(tmp_name, 'r') as f:
            export_meta = json.load(f)
        score += 10
        feedback.append('Export metadata readable (+10)')
    except Exception as e:
        feedback.append(f'Export metadata not found: {e}')
        return {'passed': False, 'score': 0, 'feedback': '; '.join(feedback)}
    finally:
        if os.path.exists(tmp_name): 
            os.unlink(tmp_name)

    file_exists = export_meta.get('file_exists', False)
    file_is_new = export_meta.get('file_is_new', False)
    initial_cmd = int(export_meta.get('initial_cmd_count', 0))
    current_cmd = int(export_meta.get('current_cmd_count', 0))

    if not file_exists:
        feedback.append('SQLite DB not found on Desktop')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}
    
    score += 5
    feedback.append('DB file exists (+5)')

    if not file_is_new:
        feedback.append('DB file predates task start (No content credit awarded for stale DBs)')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}

    score += 5
    feedback.append('DB file created this session (+5)')

    # ── 2. System Authenticity (Command sent check) ───────────────────────────
    command_executed = current_cmd > initial_cmd
    if command_executed:
        score += 20
        feedback.append(f'COSMOS API confirms command sent (count: {initial_cmd} → {current_cmd}) (+20)')
    else:
        feedback.append('COSMOS API shows NO new commands sent. Task requires active commanding.')

    # ── 3. Inspect the SQLite Database ────────────────────────────────────────
    try:
        with tempfile.NamedTemporaryFile(suffix='.db', delete=False) as tmp:
            db_tmp_name = tmp.name
        copy_from_env(output_db, db_tmp_name)
        
        # Check size to ensure it's not totally empty/corrupt
        if os.path.getsize(db_tmp_name) == 0:
            feedback.append("DB file is 0 bytes.")
            return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}
            
        conn = sqlite3.connect(db_tmp_name)
        cursor = conn.cursor()
        
        # Check schema
        cursor.execute("PRAGMA table_info(telemetry_archive)")
        columns = cursor.fetchall()
        
        if not columns:
            feedback.append("Table 'telemetry_archive' not found or has no columns")
            return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}
            
        col_types = {row[1].lower(): row[2].upper() for row in columns}
        expected_cols = {
            'id': 'INTEGER', 'timestamp': 'TEXT', 'temp1': 'REAL',
            'temp2': 'REAL', 'temp3': 'REAL', 'temp4': 'REAL', 'collects': 'INTEGER'
        }
        
        schema_ok = True
        for cname, ctype in expected_cols.items():
            if cname not in col_types:
                schema_ok = False
                feedback.append(f"Missing required column: {cname}")
        
        if schema_ok and len(col_types) == 7:
            score += 15
            feedback.append('Schema perfectly matches specification (+15)')
        elif schema_ok:
            score += 10
            feedback.append('Schema has correct columns but includes extra columns (+10)')
            
        # Check row count
        cursor.execute("SELECT * FROM telemetry_archive ORDER BY id ASC")
        rows = cursor.fetchall()
        
        if len(rows) >= 10:
            score += 15
            feedback.append(f'Table contains {len(rows)} rows (Expected >= 10) (+15)')
        else:
            feedback.append(f'Table contains {len(rows)} rows (Expected >= 10)')
            
        if len(rows) > 0:
            # Map index by column name
            col_idx = {row[1].lower(): idx for idx, row in enumerate(columns)}
            
            sanity_passed = True
            chronology_passed = True
            prev_time = None
            collects_vals = []
            
            for r in rows:
                try:
                    # Sanity check temperatures (Simulator typically floats bounded well above 0)
                    for t_name in ['temp1', 'temp2', 'temp3', 'temp4']:
                        t_val = r[col_idx[t_name]]
                        if t_val is None or float(t_val) <= 0:
                            sanity_passed = False
                    
                    # Sanity check chronological timestamps
                    ts_str = str(r[col_idx['timestamp']])
                    if 'T' not in ts_str and '-' not in ts_str and ':' not in ts_str:
                        sanity_passed = False # Loosely verify format shape
                        
                    if prev_time and ts_str < prev_time:
                        chronology_passed = False
                    prev_time = ts_str
                        
                    # Accumulate COLLECTS to verify mid-process increments
                    c_val = r[col_idx['collects']]
                    if c_val is not None:
                        collects_vals.append(int(c_val))
                        
                except Exception as e:
                    sanity_passed = False
                    logger.error(f"Row iteration error: {e}")
                    
            if sanity_passed:
                score += 10
                feedback.append('Data sanity & types verified (+10)')
            else:
                feedback.append('Data sanity checks failed (Found invalid floats, nulls, or bad timestamps)')
                
            if chronology_passed and prev_time is not None:
                score += 10
                feedback.append('Timestamps correctly sequenced chronologically (+10)')
                
            # DB Authenticity Check
            if collects_vals and max(collects_vals) > min(collects_vals):
                score += 10
                feedback.append(f'DB telemetry confirms COLLECT counter increased mid-sequence ({min(collects_vals)} -> {max(collects_vals)}) (+10)')
            else:
                feedback.append('DB records do NOT show an increase in the COLLECTS counter.')
                
        conn.close()
    except Exception as e:
        feedback.append(f"Database extraction error: {e}")
    finally:
        if os.path.exists(db_tmp_name): 
            os.unlink(db_tmp_name)

    passed = score >= 65 and command_executed

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }