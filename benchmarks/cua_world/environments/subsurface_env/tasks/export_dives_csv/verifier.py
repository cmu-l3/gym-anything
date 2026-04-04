#!/usr/bin/env python3
"""Verifier for export_dives_csv task.

Checks that /home/ga/Documents/dive_log.csv exists and contains valid dive data.
"""

import os
import csv
import tempfile


def verify_export_dives_csv(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    tmp.close()
    try:
        try:
            copy_from_env('/home/ga/Documents/dive_log.csv', tmp.name)
        except FileNotFoundError:
            return {"passed": False, "score": 0,
                    "feedback": "dive_log.csv not found — file was not exported"}
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not read dive_log.csv: {e}"}

        file_size = os.path.getsize(tmp.name)
        if file_size == 0:
            return {"passed": False, "score": 0, "feedback": "dive_log.csv is empty"}

        # Parse CSV and count rows
        try:
            with open(tmp.name, encoding='utf-8', errors='replace') as f:
                reader = csv.reader(f)
                rows = list(reader)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"dive_log.csv is not valid CSV: {e}"}

        if len(rows) < 2:
            return {"passed": False, "score": 30,
                    "feedback": f"dive_log.csv has only {len(rows)} rows (need header + data)"}

        header = [h.strip().lower() for h in rows[0]]
        data_rows = [r for r in rows[1:] if any(cell.strip() for cell in r)]

        # Check for expected columns
        has_date = any('date' in h for h in header)
        has_depth = any('depth' in h for h in header)

        score = 0
        if data_rows:
            score += 50
        if has_date and has_depth:
            score += 30
        if len(data_rows) >= 8:
            score += 20

        if score >= 80:
            return {
                "passed": True,
                "score": score,
                "feedback": (f"dive_log.csv exported with {len(data_rows)} dive records, "
                             f"{len(header)} columns. File size: {file_size} bytes.")
            }
        else:
            return {
                "passed": False,
                "score": score,
                "feedback": (f"dive_log.csv exists with {len(data_rows)} rows but "
                             f"missing expected columns (date={has_date}, depth={has_depth})")
            }
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)
