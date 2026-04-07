#!/usr/bin/env python3
import json
import pandas as pd
import datetime
import os
import tempfile
import io

def verify_reseller_order_sessionization(traj, env_info, task_info):
    """
    Verifies the Reseller Order Sessionization task.
    
    Strategy:
    1. Checks if Schema, Table, Proc, and Index exist.
    2. Calculates Ground Truth sessions using Python (pandas) from raw source data.
    3. Compares Agent's 7-day run (initial state) against Ground Truth.
    4. Compares Agent's 21-day run (dynamic test) against Ground Truth.
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # 1. Load Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback = []

    # ----------------------------------------------------------------
    # Scoring: Object Existence (30 pts)
    # ----------------------------------------------------------------
    objs = result_data.get('objects', {})
    
    if objs.get('schema_exists'):
        score += 5
        feedback.append("Schema 'Logistics' created.")
    else:
        feedback.append("Missing schema 'Logistics'.")

    if objs.get('table_exists'):
        score += 10
        feedback.append("Table 'ResellerRestockingSessions' created.")
    else:
        feedback.append("Missing table 'ResellerRestockingSessions'.")

    if objs.get('proc_exists'):
        score += 10
        feedback.append("Stored Procedure 'usp_GenerateRestockingSessions' created.")
    else:
        feedback.append("Missing stored procedure.")

    if objs.get('index_exists'):
        score += 5
        feedback.append("Index 'IX_ResellerSessions_CustomerID' created.")
    else:
        feedback.append("Missing non-clustered index.")

    # ----------------------------------------------------------------
    # Scoring: Column Structure (10 pts)
    # ----------------------------------------------------------------
    cols = result_data.get('columns', [])
    col_names = [c['COLUMN_NAME'].lower() for c in cols] if cols else []
    required = ['sessionid', 'customerid', 'sessionstartdate', 'sessionenddate', 'ordercount', 'totalsessionvalue', 'gapused']
    
    missing_cols = [r for r in required if r not in col_names]
    if not missing_cols and objs.get('table_exists'):
        score += 10
        feedback.append("Table structure correct.")
    elif objs.get('table_exists'):
        feedback.append(f"Table missing columns: {', '.join(missing_cols)}")

    # ----------------------------------------------------------------
    # Helper: Calculate Ground Truth
    # ----------------------------------------------------------------
    def calculate_ground_truth(source_csv_path, gap_days):
        # Load Raw Data
        temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix=".csv")
        try:
            copy_from_env(source_csv_path, temp_csv.name)
            # SQL output might have headers or not depending on tool, script uses mssql-tools raw
            # Assuming standard CSV format or whitespace separated. The script used mssql_query_raw which might output ugly formatting.
            # Let's robustly parse.
            with open(temp_csv.name, 'r') as f:
                content = f.read()
            
            # Basic parsing if format is messy (sqlcmd default output)
            # Lines often look like:
            # CustomerID,OrderDate,TotalDue
            # 1,2011-05-31,234.22
            # ------
            # We assume the export script produced a clean enough CSV or we clean it.
            # If standard comma separated:
            df = pd.read_csv(io.StringIO(content), sep=r'[\s,]+', engine='python', header=None, names=['CustomerID', 'OrderDate', 'TotalDue'])
            
            # Clean headers if they exist in row 0
            if isinstance(df.iloc[0]['CustomerID'], str) and 'CustomerID' in df.iloc[0]['CustomerID']:
                df = df.iloc[1:]
            
            # Drop separator lines (---)
            df = df[~df['CustomerID'].astype(str).str.contains('-')]
            
            df['OrderDate'] = pd.to_datetime(df['OrderDate'])
            df['TotalDue'] = pd.to_numeric(df['TotalDue'])
            df['CustomerID'] = pd.to_numeric(df['CustomerID'])
            
        except Exception as e:
            return None, f"Error parsing source data: {e}"
        finally:
            if os.path.exists(temp_csv.name):
                os.unlink(temp_csv.name)

        # Logic: Sessionization
        # Sort by Customer, Date
        df = df.sort_values(['CustomerID', 'OrderDate'])
        
        # Calculate lag
        df['PrevDate'] = df.groupby('CustomerID')['OrderDate'].shift(1)
        df['Diff'] = (df['OrderDate'] - df['PrevDate']).dt.days
        
        # New session if diff > gap or it's the first record
        df['NewSession'] = (df['Diff'] > gap_days) | df['Diff'].isna()
        
        # Assign Session IDs (cumulative sum of NewSession flag per customer)
        df['SessionID'] = df.groupby('CustomerID')['NewSession'].cumsum()
        
        # Aggregate
        sessions = df.groupby(['CustomerID', 'SessionID']).agg(
            SessionStartDate=('OrderDate', 'min'),
            SessionEndDate=('OrderDate', 'max'),
            OrderCount=('OrderDate', 'count'),
            TotalSessionValue=('TotalDue', 'sum')
        ).reset_index()
        
        return sessions, None

    # ----------------------------------------------------------------
    # Scoring: Data Validation (60 pts)
    # ----------------------------------------------------------------
    
    # We need the source data to calculate truth
    gt_7day, err = calculate_ground_truth(result_data.get('raw_source_path'), 7)
    
    if gt_7day is None:
        feedback.append(f"Could not calculate ground truth: {err}")
    else:
        # Validate 7-Day (Initial Run) - 30 pts
        # Load Agent Data
        agent_7day_path = result_data.get('agent_7day_path')
        try:
            temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix=".csv")
            copy_from_env(agent_7day_path, temp_csv.name)
            # Parse agent csv
            with open(temp_csv.name, 'r') as f:
                content = f.read()
            df_agent = pd.read_csv(io.StringIO(content), sep=r'[\s,]+', engine='python', header=None)
            # Clean up potentially messy sqlcmd output
            if len(df_agent.columns) >= 5:
                # Expecting: CustomerID, Start, End, Count, Total, Gap
                # Filter out headers/dashes
                df_agent = df_agent[pd.to_numeric(df_agent.iloc[:,0], errors='coerce').notnull()]
            
            agent_row_count = len(df_agent)
            gt_row_count = len(gt_7day)
            
            # Compare counts (allow small variance for data version diffs, but AdventureWorks is static)
            if abs(agent_row_count - gt_row_count) <= 5:
                score += 15
                feedback.append(f"7-Day Analysis: Row count matches ground truth ({agent_row_count}).")
            else:
                feedback.append(f"7-Day Analysis: Row count mismatch. Expected ~{gt_row_count}, got {agent_row_count}.")

            # Compare a specific metric (Total Value Sum) to ensure not just empty rows
            # Column 4 is TotalSessionValue (index 4)
            agent_total = pd.to_numeric(df_agent.iloc[:,4]).sum()
            gt_total = gt_7day['TotalSessionValue'].sum()
            
            if abs(agent_total - gt_total) < 1000: # Allow rounding diffs
                score += 15
                feedback.append("7-Day Analysis: Total value aggregation matches.")
            else:
                feedback.append(f"7-Day Analysis: Value aggregation mismatch. Expected {gt_total:.2f}, got {agent_total:.2f}.")

        except Exception as e:
            feedback.append(f"Error validating 7-day results: {e}")
        finally:
            if os.path.exists(temp_csv.name):
                os.unlink(temp_csv.name)

        # Validate 21-Day (Dynamic Check) - 30 pts
        if result_data.get('dynamic_test_run'):
            gt_21day, _ = calculate_ground_truth(result_data.get('raw_source_path'), 21)
            
            agent_21day_path = result_data.get('agent_21day_path')
            try:
                temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix=".csv")
                copy_from_env(agent_21day_path, temp_csv.name)
                with open(temp_csv.name, 'r') as f:
                    content = f.read()
                df_agent_21 = pd.read_csv(io.StringIO(content), sep=r'[\s,]+', engine='python', header=None)
                df_agent_21 = df_agent_21[pd.to_numeric(df_agent_21.iloc[:,0], errors='coerce').notnull()]
                
                agent_row_count_21 = len(df_agent_21)
                gt_row_count_21 = len(gt_21day)
                
                if abs(agent_row_count_21 - gt_row_count_21) <= 5:
                    score += 15
                    feedback.append(f"21-Day Analysis (Dynamic): Row count matches ground truth ({agent_row_count_21}).")
                else:
                    feedback.append(f"21-Day Analysis: Row count mismatch. Expected ~{gt_row_count_21}, got {agent_row_count_21}.")
                
                # Verify fewer sessions than 7 days (Logic check)
                if agent_row_count_21 < len(df_agent): # Compare to 7-day count
                    score += 15
                    feedback.append("Dynamic Logic Verified: 21-day gap produced fewer sessions than 7-day gap.")
                else:
                    feedback.append("Dynamic Logic Fail: 21-day gap did not reduce session count.")
                    
            except Exception as e:
                feedback.append(f"Error validating 21-day results: {e}")
            finally:
                if os.path.exists(temp_csv.name):
                    os.unlink(temp_csv.name)
        else:
            feedback.append("Dynamic Test Failed: Stored procedure did not execute successfully with @MaxGapDays=21.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }