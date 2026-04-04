#!/usr/bin/env python3
"""
Verifier for chinook_schema_documentation task.
Scores based on:
1. DBeaver Connection created (10 pts)
2. DDL SQL file content (25 pts)
3. Relationship CSV content (25 pts)
4. Table Statistics CSV content (40 pts)
"""

import json
import logging
import os
import tempfile
import csv
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_chinook_schema_documentation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata and ground truth
    metadata = task_info.get('metadata', {})
    expected_tables = set(metadata.get('expected_tables', []))
    ground_truth_counts = metadata.get('ground_truth_row_counts', {})

    # Load basic result JSON
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        os.unlink(temp_result.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}

    score = 0
    feedback = []

    # --- Criterion 1: Connection (10 pts) ---
    if result.get('connection_found') and result.get('connection_correct_path'):
        score += 10
        feedback.append("DBeaver connection 'Chinook' verified.")
    elif result.get('connection_found'):
        score += 5
        feedback.append("Connection 'Chinook' found but path might be wrong.")
    else:
        feedback.append("Connection 'Chinook' NOT found in DBeaver config.")

    # --- Criterion 2: DDL Export (25 pts) ---
    if result.get('ddl_exists') and result.get('ddl_size') > 500:
        try:
            temp_ddl = tempfile.NamedTemporaryFile(delete=False, suffix='.sql')
            copy_from_env("/tmp/agent_ddl.sql", temp_ddl.name)
            with open(temp_ddl.name, 'r', errors='ignore') as f:
                ddl_content = f.read()
            os.unlink(temp_ddl.name)

            # Check for CREATE TABLE statements
            tables_found = 0
            for tbl in expected_tables:
                # Regex to match CREATE TABLE [If NOT EXISTS] "Table" or Table
                if re.search(f"CREATE\\s+TABLE.*[\"\\s]{tbl}[\"\\s(]", ddl_content, re.IGNORECASE):
                    tables_found += 1
            
            if tables_found >= len(expected_tables):
                score += 25
                feedback.append(f"DDL export looks complete ({tables_found}/{len(expected_tables)} tables).")
            elif tables_found > 0:
                partial = int((tables_found / len(expected_tables)) * 25)
                score += partial
                feedback.append(f"DDL export partial: found {tables_found}/{len(expected_tables)} tables.")
            else:
                feedback.append("DDL export file exists but no valid CREATE TABLE statements found.")
        except Exception as e:
            feedback.append(f"Error verifying DDL content: {e}")
    else:
        feedback.append("DDL export file missing or empty.")

    # --- Criterion 3: Relationships CSV (25 pts) ---
    if result.get('rel_exists') and result.get('rel_size') > 50:
        try:
            temp_rel = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
            copy_from_env("/tmp/agent_rel.csv", temp_rel.name)
            
            valid_rels = 0
            required_rels = 5 # arbitrary threshold for partial credit, there are ~11
            
            with open(temp_rel.name, 'r', errors='ignore') as f:
                reader = csv.DictReader(f)
                headers = [h.lower() for h in reader.fieldnames or []]
                
                # Check headers loosely
                if 'childtable' in headers and 'parenttable' in headers:
                    for row in reader:
                        # Normalize keys
                        row_norm = {k.lower(): v for k, v in row.items()}
                        child = row_norm.get('childtable', '').lower()
                        parent = row_norm.get('parenttable', '').lower()
                        
                        # Check a few known relationships
                        if child == 'tracks' and parent == 'albums': valid_rels += 1
                        elif child == 'invoices' and parent == 'customers': valid_rels += 1
                        elif child == 'invoice_items' and parent == 'invoices': valid_rels += 1
                        elif child == 'playlist_track' and parent == 'playlists': valid_rels += 1
                        elif child == 'tracks' and parent == 'genres': valid_rels += 1
            
            os.unlink(temp_rel.name)

            if valid_rels >= 3:
                score += 25
                feedback.append(f"Relationships CSV verified with {valid_rels} valid key pairs.")
            elif valid_rels > 0:
                score += 10
                feedback.append(f"Relationships CSV has only {valid_rels} valid pairs.")
            else:
                feedback.append("Relationships CSV format correct but no known FKs matched.")

        except Exception as e:
            feedback.append(f"Error verifying relationships CSV: {e}")
    else:
        feedback.append("Relationships CSV missing.")

    # --- Criterion 4: Table Stats CSV (40 pts) ---
    if result.get('stats_exists') and result.get('stats_size') > 50:
        try:
            temp_stats = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
            copy_from_env("/tmp/agent_stats.csv", temp_stats.name)
            
            matches = 0
            with open(temp_stats.name, 'r', errors='ignore') as f:
                reader = csv.DictReader(f)
                # find row count column
                headers = reader.fieldnames or []
                row_col = next((h for h in headers if 'row' in h.lower() and 'count' in h.lower()), None)
                table_col = next((h for h in headers if 'table' in h.lower()), None)

                if row_col and table_col:
                    for row in reader:
                        tbl = row[table_col].lower().strip()
                        try:
                            cnt = int(row[row_col])
                            # Check against ground truth
                            if tbl in ground_truth_counts and ground_truth_counts[tbl] == cnt:
                                matches += 1
                        except ValueError:
                            pass
            
            os.unlink(temp_stats.name)

            total_tables = len(ground_truth_counts)
            if matches >= total_tables:
                score += 40
                feedback.append(f"Table stats perfect: {matches}/{total_tables} row counts match.")
            elif matches > 0:
                partial = int((matches / total_tables) * 40)
                score += partial
                feedback.append(f"Table stats partial: {matches}/{total_tables} row counts match.")
            else:
                feedback.append("Table stats CSV exists but no row counts matched ground truth.")

        except Exception as e:
            feedback.append(f"Error verifying stats CSV: {e}")
    else:
        feedback.append("Table stats CSV missing.")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback)
    }