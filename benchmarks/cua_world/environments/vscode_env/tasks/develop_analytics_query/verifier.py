#!/usr/bin/env python3
"""
Verifier for Develop Analytics Query task
"""

import sys
import os
import logging
import tempfile
import shutil
import sqlite3
import pandas as pd
import time

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_analytics_query(traj, env_info, task_info):
    """
    Verify that the agent correctly developed the analytics SQL query.
    
    Checks:
    1. File query_solution.sql exists
    2. Query is valid SQL and executable
    3. Query includes documentation comments
    4. Query uses proper structure (JOINs, GROUP BY)
    5. Query results match expected output exactly
    6. Query is performant
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    temp_dir = tempfile.mkdtemp(prefix='sql_verify_')
    
    try:
        # Copy files exported by export_result.sh
        query_file_local = os.path.join(temp_dir, "query_solution.sql")
        db_file_local = os.path.join(temp_dir, "sales.db")
        expected_csv_local = os.path.join(temp_dir, "expected_output.csv")
        
        try:
            copy_from_env("/tmp/query_solution.sql", query_file_local)
            copy_from_env("/tmp/sales.db", db_file_local)
            copy_from_env("/tmp/expected_output.csv", expected_csv_local)
        except Exception as e:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ Failed to copy verification files: {str(e)}"
            }
        
        feedback_parts = []
        reward = 0.0
        metadata = {}
        
        # Step 1: Check query file exists and is not placeholder
        if not os.path.exists(query_file_local):
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ query_solution.sql not found in workspace"
            }
        
        with open(query_file_local, 'r', encoding='utf-8', errors='ignore') as f:
            query_content = f.read()
        
        if query_content.strip() == "NOT_FOUND" or len(query_content.strip()) < 50:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ query_solution.sql is empty or too short (possibly incomplete)"
            }
        
        feedback_parts.append("✅ Query file exists and is non-trivial")
        reward += 0.1
        metadata['query_length'] = len(query_content)
        
        # Step 2: Check for documentation (SQL comments)
        comment_lines = [
            line for line in query_content.split('\n') 
            if line.strip().startswith('--') and len(line.strip()) > 3
        ]
        has_documentation = len(comment_lines) >= 2
        
        if has_documentation:
            feedback_parts.append(f"✅ Query includes {len(comment_lines)} documentation comments")
            reward += 0.1
        else:
            feedback_parts.append("⚠️ Query lacks sufficient documentation comments (expected at least 2)")
            metadata['missing_documentation'] = True
        
        # Step 3: Check query structure (should use JOINs, GROUP BY, window functions)
        query_upper = query_content.upper()
        
        has_joins = 'JOIN' in query_upper
        has_group_by = 'GROUP BY' in query_upper
        has_window_fn = 'RANK()' in query_upper or 'ROW_NUMBER()' in query_upper or 'OVER' in query_upper
        has_where = 'WHERE' in query_upper
        
        structure_score = 0
        if has_joins:
            feedback_parts.append("✅ Query uses JOIN operations")
            structure_score += 1
        else:
            feedback_parts.append("⚠️ Query might not properly join tables")
            metadata['missing_joins'] = True
        
        if has_group_by:
            feedback_parts.append("✅ Query includes aggregation (GROUP BY)")
            structure_score += 1
        else:
            feedback_parts.append("⚠️ Query might be missing GROUP BY for aggregation")
        
        if has_window_fn:
            feedback_parts.append("✅ Query uses window functions for ranking")
            structure_score += 1
        else:
            feedback_parts.append("⚠️ Query might be missing window functions (RANK/ROW_NUMBER)")
        
        if structure_score >= 2:
            reward += 0.1
        
        # Step 4: Check database exists
        if not os.path.exists(db_file_local):
            return {
                "passed": False,
                "score": reward,
                "feedback": " | ".join(feedback_parts) + " | ❌ Database file not found"
            }
        
        if not os.path.exists(expected_csv_local):
            return {
                "passed": False,
                "score": reward,
                "feedback": " | ".join(feedback_parts) + " | ❌ Expected output file not found"
            }
        
        # Step 5: Execute query and validate results
        try:
            conn = sqlite3.connect(db_file_local)
            
            # Execute the agent's query
            try:
                result_df = pd.read_sql_query(query_content, conn)
            except Exception as sql_err:
                conn.close()
                return {
                    "passed": False,
                    "score": reward,
                    "feedback": " | ".join(feedback_parts) + f" | ❌ SQL execution error: {str(sql_err)[:100]}"
                }
            
            feedback_parts.append("✅ Query executes without errors")
            reward += 0.15
            
            # Load expected output
            try:
                expected_df = pd.read_csv(expected_csv_local)
            except Exception as e:
                conn.close()
                return {
                    "passed": False,
                    "score": reward,
                    "feedback": " | ".join(feedback_parts) + f" | ❌ Could not load expected output: {str(e)}"
                }
            
            # Check column structure
            expected_cols = set(expected_df.columns.str.lower())
            actual_cols = set(result_df.columns.str.lower())
            
            if expected_cols != actual_cols:
                missing = expected_cols - actual_cols
                extra = actual_cols - expected_cols
                msg_parts = []
                if missing:
                    msg_parts.append(f"Missing columns: {missing}")
                if extra:
                    msg_parts.append(f"Extra columns: {extra}")
                conn.close()
                return {
                    "passed": False,
                    "score": reward,
                    "feedback": " | ".join(feedback_parts) + " | ❌ Column mismatch. " + ", ".join(msg_parts)
                }
            
            # Normalize column names to lowercase for comparison
            result_df.columns = result_df.columns.str.lower()
            expected_df.columns = expected_df.columns.str.lower()
            
            feedback_parts.append("✅ Query returns correct columns")
            reward += 0.15
            
            # Check row count
            if len(result_df) != len(expected_df):
                conn.close()
                return {
                    "passed": False,
                    "score": reward,
                    "feedback": " | ".join(feedback_parts) + f" | ❌ Row count mismatch. Expected {len(expected_df)}, got {len(result_df)}"
                }
            
            feedback_parts.append(f"✅ Query returns correct number of rows ({len(result_df)})")
            reward += 0.15
            
            # Sort both dataframes for comparison (in case order is slightly different)
            sort_cols = ['region', 'rank'] if 'rank' in result_df.columns else ['region']
            result_sorted = result_df.sort_values(by=sort_cols).reset_index(drop=True)
            expected_sorted = expected_df.sort_values(by=sort_cols).reset_index(drop=True)
            
            # Compare values with tolerance for floating point
            numeric_cols = result_sorted.select_dtypes(include=['float64', 'int64', 'float32', 'int32']).columns
            string_cols = result_sorted.select_dtypes(include=['object']).columns
            
            # Check numeric columns with tolerance
            numeric_match = True
            for col in numeric_cols:
                # Convert to float for comparison
                result_vals = pd.to_numeric(result_sorted[col], errors='coerce')
                expected_vals = pd.to_numeric(expected_sorted[col], errors='coerce')
                
                # Check if all values are close (within 0.01 tolerance)
                if not (abs(result_vals - expected_vals) < 0.01).all():
                    numeric_match = False
                    # Find first mismatch for debugging
                    mismatch_idx = (abs(result_vals - expected_vals) >= 0.01).idxmax()
                    conn.close()
                    return {
                        "passed": False,
                        "score": reward,
                        "feedback": " | ".join(feedback_parts) + f" | ❌ Numeric values in column '{col}' don't match. Row {mismatch_idx}: expected {expected_vals[mismatch_idx]}, got {result_vals[mismatch_idx]}"
                    }
            
            # Check string columns (case-insensitive)
            string_match = True
            for col in string_cols:
                result_str = result_sorted[col].astype(str).str.strip().str.lower()
                expected_str = expected_sorted[col].astype(str).str.strip().str.lower()
                
                if not (result_str == expected_str).all():
                    string_match = False
                    # Find first mismatch
                    mismatch_idx = (result_str != expected_str).idxmax()
                    conn.close()
                    return {
                        "passed": False,
                        "score": reward,
                        "feedback": " | ".join(feedback_parts) + f" | ❌ String values in column '{col}' don't match. Row {mismatch_idx}: expected '{expected_str[mismatch_idx]}', got '{result_str[mismatch_idx]}'"
                    }
            
            feedback_parts.append("✅ Query results match expected output exactly")
            reward += 0.3
            
            # Step 6: Check query performance
            start_time = time.time()
            pd.read_sql_query(query_content, conn)
            elapsed = time.time() - start_time
            
            metadata['query_execution_time'] = elapsed
            
            if elapsed < 0.5:
                feedback_parts.append(f"✅ Query is performant ({elapsed:.3f}s)")
                reward += 0.1
            elif elapsed < 2.0:
                feedback_parts.append(f"⚠️ Query is acceptable but could be faster ({elapsed:.3f}s)")
                reward += 0.05
            else:
                feedback_parts.append(f"⚠️ Query is slow ({elapsed:.3f}s) - consider optimization")
            
            conn.close()
            
            # Success!
            reward = 1.0  # Override to ensure perfect score on complete success
            success_msg = " | ".join(feedback_parts)
            success_msg += " | 🎉 Task completed successfully!"
            
            return {
                "passed": True,
                "score": 100,
                "feedback": success_msg,
                "metadata": metadata
            }
            
        except sqlite3.Error as e:
            return {
                "passed": False,
                "score": reward,
                "feedback": " | ".join(feedback_parts) + f" | ❌ SQL execution error: {str(e)[:200]}"
            }
        except Exception as e:
            logger.error(f"Unexpected error during query execution: {e}", exc_info=True)
            return {
                "passed": False,
                "score": reward,
                "feedback": " | ".join(feedback_parts) + f" | ❌ Unexpected error: {str(e)[:200]}"
            }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification system error: {str(e)}"
        }
    finally:
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)
