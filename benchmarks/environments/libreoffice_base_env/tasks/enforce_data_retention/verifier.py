#!/usr/bin/env python3
"""
Verifier for enforce_data_retention task.

Verification Strategy:
1. Ground Truth Calculation:
   - Uses the original Chinook SQLite database to determine exactly which
     Invoice IDs should have been deleted vs. preserved.
   - Logic: (Date < 2011-01-01) AND NOT (Contains 'Classical' Tracks).

2. Agent Output Analysis:
   - Extracts the internal 'database/script' file from the agent's ODB (Zip archive).
   - Parses the HSQLDB SQL script to find all remaining 'INSERT INTO "Invoice"' statements.
   - Compares the set of remaining IDs against the expected set.

3. Integrity Checks:
   - Verifies no orphans exist in InvoiceLine table.
   - Verifies unrelated tables (Customer) were not deleted.
"""

import json
import os
import sqlite3
import zipfile
import tempfile
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_data_retention(traj, env_info, task_info):
    """
    Verify that the agent correctly purged old data while respecting the legal hold.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # Paths in container
    agent_odb_path = metadata.get('database_path', '/home/ga/chinook.odb')
    reference_sqlite_path = metadata.get('reference_sqlite_path', '/opt/libreoffice_base_samples/Chinook_Sqlite.sqlite')
    
    # Constants
    CUTOFF_DATE = "2011-01-01"
    PROTECTED_GENRE = "Classical"

    # Temporary directory for verification artifacts
    with tempfile.TemporaryDirectory() as temp_dir:
        local_sqlite = os.path.join(temp_dir, "Chinook_Sqlite.sqlite")
        local_odb = os.path.join(temp_dir, "agent.odb")
        local_result_json = os.path.join(temp_dir, "task_result.json")

        # 1. Fetch files from environment
        try:
            copy_from_env(agent_odb_path, local_odb)
            copy_from_env(reference_sqlite_path, local_sqlite)
            copy_from_env("/tmp/task_result.json", local_result_json)
            
            with open(local_result_json, 'r') as f:
                task_result = json.load(f)
        except Exception as e:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": f"Failed to retrieve task files: {str(e)}",
                "details": {"error": str(e)}
            }

        if not task_result.get('odb_modified', False):
            return {
                "passed": False,
                "score": 0,
                "feedback": "Database file was not modified. No changes were saved.",
                "details": {"odb_modified": False}
            }

        # 2. Calculate Ground Truth Sets using SQLite
        try:
            conn = sqlite3.connect(local_sqlite)
            cursor = conn.cursor()
            
            # A. Get all invoice IDs and dates
            cursor.execute("SELECT InvoiceId, InvoiceDate FROM Invoice")
            all_invoices = {row[0]: row[1] for row in cursor.fetchall()}
            
            # B. Get IDs of invoices containing 'Classical' tracks
            # Join: InvoiceLine -> Track -> Genre
            query_protected = """
                SELECT DISTINCT i.InvoiceId 
                FROM Invoice i
                JOIN InvoiceLine il ON i.InvoiceId = il.InvoiceId
                JOIN Track t ON il.TrackId = t.TrackId
                JOIN Genre g ON t.GenreId = g.GenreId
                WHERE g.Name = ?
            """
            cursor.execute(query_protected, (PROTECTED_GENRE,))
            protected_ids_set = {row[0] for row in cursor.fetchall()}
            
            conn.close()
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Ground truth calculation failed: {str(e)}"}

        # Define expected sets
        expected_ids = set()
        target_deletion_ids = set()
        
        # Categorize every invoice
        count_pre_2011_total = 0
        count_pre_2011_protected = 0
        count_post_2011 = 0

        for inv_id, inv_date in all_invoices.items():
            # Date format in SQLite is YYYY-MM-DD HH:MM:SS, just compare string prefix
            is_old = inv_date < CUTOFF_DATE
            is_protected = inv_id in protected_ids_set
            
            if is_old:
                count_pre_2011_total += 1
                if is_protected:
                    # Old but protected -> KEEP
                    expected_ids.add(inv_id)
                    count_pre_2011_protected += 1
                else:
                    # Old and not protected -> DELETE
                    target_deletion_ids.add(inv_id)
            else:
                # Newer invoice -> KEEP
                expected_ids.add(inv_id)
                count_post_2011 += 1

        logger.info(f"Ground Truth: Total={len(all_invoices)}, Keep={len(expected_ids)}, Delete={len(target_deletion_ids)}")
        logger.info(f"Breakdown: OldTotal={count_pre_2011_total}, OldProtected={count_pre_2011_protected}, Recent={count_post_2011}")

        # 3. Parse Agent's ODB File
        agent_invoice_ids = set()
        agent_invoiceline_ids = set() # Store (InvoiceId) referenced in lines
        customer_count = 0
        
        try:
            with zipfile.ZipFile(local_odb, 'r') as z:
                # HSQLDB stores data in 'database/script'
                with z.open('database/script') as f:
                    script_content = f.read().decode('utf-8', errors='ignore')
                    
                    for line in script_content.splitlines():
                        if line.startswith('INSERT INTO "Invoice"'):
                            # Format: INSERT INTO "Invoice" VALUES(1,1,'2009-01-01 00:00:00.0',...)
                            match = re.search(r'VALUES\((\d+),', line)
                            if match:
                                agent_invoice_ids.add(int(match.group(1)))
                        
                        elif line.startswith('INSERT INTO "InvoiceLine"'):
                            # InvoiceLine typically: VALUES(LineId, InvoiceId, TrackId...)
                            # We need the 2nd value (InvoiceId)
                            # Regex to capture second number: VALUES(123, 456, ...)
                            match = re.search(r'VALUES\(\d+,\s*(\d+)', line)
                            if match:
                                agent_invoiceline_ids.add(int(match.group(1)))
                                
                        elif line.startswith('INSERT INTO "Customer"'):
                            customer_count += 1
                            
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to parse ODB file: {str(e)}"}

        # 4. Score Calculation
        score = 0
        feedback_lines = []

        # A. Target Deletion (40 pts)
        # Did agent delete the ones that SHOULD be deleted?
        deleted_targets = target_deletion_ids - agent_invoice_ids # IDs in target set NOT in agent set
        deletion_rate = len(deleted_targets) / len(target_deletion_ids) if target_deletion_ids else 1.0
        
        score_deletion = int(deletion_rate * 40)
        score += score_deletion
        feedback_lines.append(f"Target Deletion: {len(deleted_targets)}/{len(target_deletion_ids)} removed ({int(deletion_rate*100)}%)")

        # B. Legal Hold Preservation (30 pts)
        # Did agent keep the old ones that were protected?
        # Intersection of agent IDs and old-protected IDs
        protected_kept = agent_invoice_ids.intersection(expected_ids) & {i for i in all_invoices if i in protected_ids_set and all_invoices[i] < CUTOFF_DATE}
        total_protected_old = count_pre_2011_protected
        
        preservation_rate = len(protected_kept) / total_protected_old if total_protected_old else 1.0
        score_preservation = int(preservation_rate * 30)
        score += score_preservation
        feedback_lines.append(f"Legal Hold Preservation: {len(protected_kept)}/{total_protected_old} kept ({int(preservation_rate*100)}%)")

        # C. Recent Data Preservation (10 pts)
        # Did agent keep the invoices >= 2011?
        recent_kept_count = 0
        recent_total_count = 0
        for i in expected_ids:
            if all_invoices[i] >= CUTOFF_DATE:
                recent_total_count += 1
                if i in agent_invoice_ids:
                    recent_kept_count += 1
        
        recent_rate = recent_kept_count / recent_total_count if recent_total_count else 1.0
        score_recent = int(recent_rate * 10)
        score += score_recent
        if recent_rate < 1.0:
            feedback_lines.append(f"Recent Data: {recent_kept_count}/{recent_total_count} kept (Some recent data was wrongly deleted)")
        else:
            feedback_lines.append("Recent Data: All preserved")

        # D. Integrity Check (10 pts)
        # Are there InvoiceLines pointing to non-existent invoices?
        orphans = {i_id for i_id in agent_invoiceline_ids if i_id not in agent_invoice_ids}
        if not orphans:
            score += 10
            feedback_lines.append("Integrity: No orphaned invoice lines")
        else:
            feedback_lines.append(f"Integrity: Found {len(orphans)} orphaned invoice lines (Constraint violation)")

        # E. Collateral Damage (10 pts)
        # Did they delete customers?
        if customer_count == 59: # Original count
            score += 10
            feedback_lines.append("Collateral: Customer table intact")
        else:
            feedback_lines.append(f"Collateral: Customer table modified (Count: {customer_count}, Expected: 59)")

        # Final Evaluation
        passed = (score >= 70) and (deletion_rate > 0.9) and (preservation_rate > 0.9)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_lines),
            "details": {
                "deleted_targets": len(deleted_targets),
                "target_total": len(target_deletion_ids),
                "protected_kept": len(protected_kept),
                "protected_total": total_protected_old,
                "recent_kept": recent_kept_count,
                "recent_total": recent_total_count,
                "orphans": len(orphans),
                "customer_count": customer_count
            }
        }