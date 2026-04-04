#!/usr/bin/env python3
"""
Verifier for Chinook RFM Analysis Task.
Calculates ground truth RFM values from the database and compares against agent's CSV.
"""

import json
import sqlite3
import base64
import pandas as pd
import io
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

DB_PATH = "/home/ga/Documents/databases/chinook.db"
REF_DATE = datetime(2014, 1, 1)

def calculate_ground_truth():
    """Calculates expected RFM values from the raw database."""
    try:
        conn = sqlite3.connect(DB_PATH)
        
        # Get raw data
        query = """
        SELECT 
            c.CustomerId,
            MAX(i.InvoiceDate) as LastDate,
            COUNT(i.InvoiceId) as Frequency,
            SUM(i.Total) as Monetary
        FROM customers c
        LEFT JOIN invoices i ON c.CustomerId = i.CustomerId
        GROUP BY c.CustomerId
        """
        df = pd.read_sql_query(query, conn)
        conn.close()
        
        # Calculate Recency
        # SQLite dates are strings. Convert to datetime.
        # Assuming InvoiceDate format YYYY-MM-DD ...
        df['LastDate'] = pd.to_datetime(df['LastDate'])
        df['Recency'] = (REF_DATE - df['LastDate']).dt.days.round().astype(int)
        
        # Handle customers with no invoices (if any, though Chinook usually has data for all)
        df['Frequency'] = df['Frequency'].fillna(0).astype(int)
        df['Monetary'] = df['Monetary'].fillna(0.0)
        
        # Segment Logic
        def get_segment(row):
            if row['Monetary'] > 40.00:
                return 'VIP'
            elif row['Frequency'] >= 5:
                return 'Loyal'
            elif row['Recency'] > 365:
                return 'Churn Risk'
            else:
                return 'Standard'
                
        df['Segment'] = df.apply(get_segment, axis=1)
        
        return df.set_index('CustomerId')
        
    except Exception as e:
        logger.error(f"Failed to calculate ground truth: {e}")
        return None

def verify_chinook_rfm_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # Load Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/rfm_task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # 1. Check CSV Existence (10 pts)
    if not result.get('csv_exists'):
        return {"passed": False, "score": 0, "feedback": "RFM CSV file not found."}
    
    score += 10
    feedback.append("CSV file exists.")

    # 2. Check if created during task (5 pts)
    if result.get('csv_created_during_task'):
        score += 5
    else:
        feedback.append("Warning: CSV file timestamp is old.")

    # 3. Parse and Verify CSV Content (60 pts)
    try:
        csv_content = base64.b64decode(result.get('csv_content_b64', '')).decode('utf-8')
        df_agent = pd.read_csv(io.StringIO(csv_content))
        
        # Standardize columns
        df_agent.columns = [c.strip() for c in df_agent.columns]
        
        # Check required columns
        req_cols = ['CustomerId', 'Recency', 'Frequency', 'Monetary', 'Segment']
        missing_cols = [c for c in req_cols if c not in df_agent.columns]
        
        if missing_cols:
            feedback.append(f"Missing columns: {missing_cols}")
        else:
            score += 10 # Structure correct
            
            # Load Ground Truth
            df_truth = calculate_ground_truth()
            
            if df_truth is not None:
                # Merge for comparison
                # Ensure CustomerId is compatible (int)
                try:
                    df_agent['CustomerId'] = df_agent['CustomerId'].astype(int)
                    df_agent = df_agent.set_index('CustomerId')
                    
                    # Verify Row Count
                    if len(df_agent) == len(df_truth):
                        score += 5
                    else:
                        feedback.append(f"Row count mismatch: Agent {len(df_agent)} vs Truth {len(df_truth)}")
                    
                    # Compare Metrics
                    # Allow slight tolerance for float (Monetary) and Integer (Recency +/- 1 day for timezone issues)
                    
                    # Monetary (20 pts)
                    mon_diff = (df_agent['Monetary'] - df_truth['Monetary']).abs()
                    valid_mon = mon_diff < 0.05
                    mon_score = (valid_mon.sum() / len(df_truth)) * 20
                    score += mon_score
                    if mon_score < 15:
                        feedback.append(f"Monetary calculation issues. Accuracy: {valid_mon.mean():.1%}")

                    # Frequency (10 pts)
                    freq_diff = (df_agent['Frequency'] - df_truth['Frequency']).abs()
                    valid_freq = freq_diff == 0
                    freq_score = (valid_freq.sum() / len(df_truth)) * 10
                    score += freq_score
                    
                    # Recency (10 pts)
                    # Allow +/- 1 day difference
                    rec_diff = (df_agent['Recency'] - df_truth['Recency']).abs()
                    valid_rec = rec_diff <= 1
                    rec_score = (valid_rec.sum() / len(df_truth)) * 10
                    score += rec_score
                    if rec_score < 8:
                        feedback.append(f"Recency calculation issues. Accuracy: {valid_rec.mean():.1%}")
                    
                    # Segments (15 pts)
                    # Case-insensitive comparison
                    agent_seg = df_agent['Segment'].str.lower().str.strip()
                    truth_seg = df_truth['Segment'].str.lower().str.strip()
                    valid_seg = agent_seg == truth_seg
                    seg_score = (valid_seg.sum() / len(df_truth)) * 15
                    score += seg_score
                    if seg_score < 12:
                        feedback.append(f"Segmentation logic issues. Accuracy: {valid_seg.mean():.1%}")
                        
                except Exception as e:
                    feedback.append(f"Error comparing data: {e}")
            else:
                feedback.append("Could not calculate ground truth for comparison.")
                
    except Exception as e:
        feedback.append(f"Failed to parse CSV: {e}")

    # 4. Check SQL Script (5 pts)
    if result.get('sql_exists'):
        score += 5
        sql_content = base64.b64decode(result.get('sql_content_b64', '')).decode('utf-8', errors='ignore').lower()
        if 'case' in sql_content and 'when' in sql_content:
             # Bonus for using CASE statement which is likely required for segmentation
             pass
    else:
        feedback.append("SQL script not found.")

    # 5. Check DB Object (10 pts)
    if result.get('db_object_exists'):
        score += 10
        feedback.append(f"Database object '{result.get('db_object_type')}' created.")
    else:
        feedback.append("Customer RFM table/view not found in database.")

    return {
        "passed": score >= 70,
        "score": round(score),
        "feedback": " ".join(feedback)
    }