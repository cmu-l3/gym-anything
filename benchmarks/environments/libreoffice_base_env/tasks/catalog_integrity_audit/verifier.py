#!/usr/bin/env python3
"""
Verifier for Catalog Integrity Audit task.
Parses the LibreOffice Base ODB (HSQLDB script) to verify SQL audit tables.
"""

import json
import os
import zipfile
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_catalog_integrity_audit(traj, env_info, task_info):
    """
    Verify that the agent correctly identified data integrity issues by creating
    and populating specific audit tables in the ODB file.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    max_score = 100
    feedback_parts = []
    
    # Files to retrieve
    files_to_copy = {
        "/tmp/task_result.json": "result.json",
        "/tmp/submitted_chinook.odb": "chinook.odb",
        "/tmp/ground_truth.json": "ground_truth.json"
    }
    
    temp_dir = tempfile.mkdtemp()
    local_files = {}
    
    try:
        # Copy files
        for remote, local in files_to_copy.items():
            local_path = os.path.join(temp_dir, local)
            try:
                copy_from_env(remote, local_path)
                local_files[local] = local_path
            except Exception as e:
                logger.warning(f"Failed to copy {remote}: {e}")

        # Load JSON data
        if "result.json" not in local_files:
            return {"passed": False, "score": 0, "feedback": "Task result file not found"}
            
        with open(local_files["result.json"], 'r') as f:
            task_result = json.load(f)

        if "ground_truth.json" not in local_files:
            return {"passed": False, "score": 0, "feedback": "Ground truth data missing"}
            
        with open(local_files["ground_truth.json"], 'r') as f:
            ground_truth = json.load(f)

        # Basic Check: File modification
        if not task_result.get("odb_modified", False):
            return {"passed": False, "score": 0, "feedback": "Database file was not saved/modified."}
        score += 5

        # Check ODB content
        if "chinook.odb" not in local_files:
             return {"passed": False, "score": score, "feedback": "Database file not found."}

        # Unzip ODB and read database/script
        script_content = ""
        try:
            with zipfile.ZipFile(local_files["chinook.odb"], 'r') as zf:
                if "database/script" in zf.namelist():
                    script_content = zf.read("database/script").decode('utf-8', errors='ignore')
                else:
                    return {"passed": False, "score": score, "feedback": "Invalid ODB: missing database/script"}
        except zipfile.BadZipFile:
             return {"passed": False, "score": score, "feedback": "Corrupt ODB file."}

        # Helper to parse INSERT statements for a table
        # HSQLDB syntax: INSERT INTO "TableName" VALUES(val1,val2,...)
        def get_table_data(table_name):
            pattern = fr'INSERT INTO "{table_name}" VALUES\((.*?)\)'
            matches = re.findall(pattern, script_content)
            rows = []
            for m in matches:
                # Basic CSV parsing (handling quotes roughly)
                # This is a simplification; for complex strings verification might need robust parser
                # But for IDs (ints) it's safe.
                rows.append(m)
            return rows
        
        def table_exists(table_name):
            return f'CREATE TABLE "{table_name}"' in script_content or f'CREATE TABLE PUBLIC."{table_name}"' in script_content

        # --- Verify AuditOrphanArtists ---
        expected_orphans = ground_truth.get('AuditOrphanArtists', [])
        if table_exists('AuditOrphanArtists'):
            score += 5
            data = get_table_data('AuditOrphanArtists')
            if len(data) == len(expected_orphans):
                # Verify at least one ID matches to ensure it's not just random rows
                # Picking first expected ID to check
                if expected_orphans and str(expected_orphans[0]['ArtistId']) in str(data):
                    score += 15
                    feedback_parts.append("AuditOrphanArtists: OK")
                elif not expected_orphans and len(data) == 0:
                    score += 15
                    feedback_parts.append("AuditOrphanArtists: OK (Empty)")
                else:
                    score += 5 # Partial for correct count
                    feedback_parts.append("AuditOrphanArtists: Correct count, data mismatch")
            else:
                feedback_parts.append(f"AuditOrphanArtists: Count mismatch (Found {len(data)}, Expected {len(expected_orphans)})")
        else:
            feedback_parts.append("AuditOrphanArtists: Table missing")

        # --- Verify AuditEmptyAlbums ---
        expected_empty = ground_truth.get('AuditEmptyAlbums', [])
        if table_exists('AuditEmptyAlbums'):
            score += 5
            data = get_table_data('AuditEmptyAlbums')
            if len(data) == len(expected_empty):
                score += 10
                feedback_parts.append("AuditEmptyAlbums: OK")
            else:
                feedback_parts.append(f"AuditEmptyAlbums: Count mismatch ({len(data)} vs {len(expected_empty)})")
        else:
            feedback_parts.append("AuditEmptyAlbums: Table missing")

        # --- Verify AuditUnusedGenres ---
        expected_genres = ground_truth.get('AuditUnusedGenres', [])
        if table_exists('AuditUnusedGenres'):
            score += 5
            data = get_table_data('AuditUnusedGenres')
            if len(data) == len(expected_genres):
                score += 10
                feedback_parts.append("AuditUnusedGenres: OK")
            else:
                feedback_parts.append(f"AuditUnusedGenres: Count mismatch ({len(data)} vs {len(expected_genres)})")
        else:
            feedback_parts.append("AuditUnusedGenres: Table missing")

        # --- Verify AuditInactiveCustomers ---
        expected_inactive = ground_truth.get('AuditInactiveCustomers', [])
        if table_exists('AuditInactiveCustomers'):
            score += 5
            data = get_table_data('AuditInactiveCustomers')
            if len(data) == len(expected_inactive):
                score += 15
                feedback_parts.append("AuditInactiveCustomers: OK")
            else:
                feedback_parts.append(f"AuditInactiveCustomers: Count mismatch ({len(data)} vs {len(expected_inactive)})")
        else:
            feedback_parts.append("AuditInactiveCustomers: Table missing")

        # --- Verify CatalogAuditSummary ---
        if table_exists('CatalogAuditSummary'):
            score += 5
            data = get_table_data('CatalogAuditSummary')
            # Expect 4 rows
            if len(data) == 4:
                score += 5
                # Verify content loosely (finding counts in the strings)
                c_artists = ground_truth['Count_OrphanArtists']
                c_albums = ground_truth['Count_EmptyAlbums']
                c_genres = ground_truth['Count_UnusedGenres']
                c_customers = ground_truth['Count_InactiveCustomers']
                
                # Check if these numbers appear in the summary inserts
                # We simply check if the number is present in the set of insert values
                all_inserts = " ".join(data)
                
                # Note: This is a loose check. Agent could swap rows.
                # But getting the exact numbers right usually implies correctness here.
                matches = 0
                if str(c_artists) in all_inserts: matches += 1
                if str(c_albums) in all_inserts: matches += 1
                if str(c_genres) in all_inserts: matches += 1
                if str(c_customers) in all_inserts: matches += 1
                
                if matches == 4:
                    score += 15 # 10 for correct counts + 5 for consistency
                    feedback_parts.append("CatalogAuditSummary: Data Correct")
                else:
                    feedback_parts.append(f"CatalogAuditSummary: Data Mismatch (Found {matches}/4 expected counts)")
            else:
                feedback_parts.append(f"CatalogAuditSummary: Incorrect row count ({len(data)})")
        else:
            feedback_parts.append("CatalogAuditSummary: Table missing")

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": score, "feedback": f"Error during verification: {str(e)}"}
    finally:
        # Cleanup
        import shutil
        shutil.rmtree(temp_dir, ignore_errors=True)

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }