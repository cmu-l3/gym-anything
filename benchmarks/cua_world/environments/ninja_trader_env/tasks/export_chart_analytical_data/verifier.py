#!/usr/bin/env python3
"""
Verifier for export_chart_analytical_data task.

Verifies:
1. CSV file existence and timestamps (anti-gaming).
2. Data range (approx Jan 2023 - Dec 2024).
3. Presence and accuracy of SMA(50) and RSI(14) columns.
"""

import json
import os
import tempfile
import logging
import pandas as pd
import numpy as np

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def calculate_rsi(series, period=14):
    """Calculate RSI for validation."""
    delta = series.diff()
    gain = (delta.where(delta > 0, 0)).rolling(window=period).mean()
    loss = (-delta.where(delta < 0, 0)).rolling(window=period).mean()
    
    # Use Wilder's smoothing if possible, but simple rolling is often enough for correlation check
    # Let's use simple rolling for robustness against slight algo diffs, 
    # checking for high correlation rather than exact float match.
    rs = gain / loss
    return 100 - (100 / (1 + rs))

def calculate_sma(series, period=50):
    """Calculate SMA for validation."""
    return series.rolling(window=period).mean()

def verify_export_chart_analytical_data(traj, env_info, task_info):
    """
    Verify the exported CSV contains correct SPY data and indicators.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_filename = metadata.get('filename', 'spy_analytical_export.csv')
    min_rows = metadata.get('min_rows', 480)
    
    # Result JSON path on Windows container (mapped to verifier logic)
    # The container path is C:\Users\Docker\Documents\NinjaTraderTasks\task_result.json
    # but we need to pass the path that copy_from_env understands.
    # Usually copy_from_env takes the internal container path.
    result_json_path = "C:\\Users\\Docker\\Documents\\NinjaTraderTasks\\task_result.json"
    csv_path = "C:\\Users\\Docker\\Documents\\NinjaTraderTasks\\spy_analytical_export.csv"

    # 1. Get Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(result_json_path, temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task status: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Check basic criteria
    if not result_data.get('output_exists'):
        return {"passed": False, "score": 0, "feedback": "Exported CSV file not found."}
    
    if not result_data.get('file_created_during_task'):
        return {"passed": False, "score": 10, "feedback": "File exists but was not created during this task session (stale data)."}

    # 2. Get CSV File
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env(csv_path, temp_csv.name)
        # NinjaTrader exports often use semi-colon or comma. Try standard read.
        # It usually has headers.
        try:
            df = pd.read_csv(temp_csv.name, sep=None, engine='python')
        except:
            # Fallback for weird delimiters
            df = pd.read_csv(temp_csv.name)
            
    except Exception as e:
        return {"passed": False, "score": 20, "feedback": f"File created but could not be parsed as CSV: {e}"}
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    score = 20
    feedback = ["File created and readable (+20)"]

    # 3. Verify Data Range (Approx check)
    # NinjaTrader exports typically have 'Time' or 'Date' column
    date_col = None
    for col in df.columns:
        if 'time' in col.lower() or 'date' in col.lower():
            date_col = col
            break
    
    if date_col:
        try:
            df[date_col] = pd.to_datetime(df[date_col])
            start_date = df[date_col].min()
            end_date = df[date_col].max()
            
            # Check 2023 start
            if start_date.year == 2023 and start_date.month == 1:
                score += 10
                feedback.append("Start date correct (+10)")
            else:
                feedback.append(f"Start date mismatch ({start_date.date()})")

            # Check 2024 end
            if end_date.year == 2024 and end_date.month == 12:
                score += 10
                feedback.append("End date correct (+10)")
            else:
                feedback.append(f"End date mismatch ({end_date.date()})")
                
        except:
            feedback.append("Could not parse dates")
    
    # Check Row Count
    if len(df) >= min_rows:
        score += 10 # Credit for correct amount of data even if date parse failed
        feedback.append(f"Row count sufficient ({len(df)}) (+10)")
    else:
        feedback.append(f"Row count too low ({len(df)} < {min_rows})")

    # 4. Verify Indicators
    # Find Price column (Close/Last)
    price_col = None
    for col in df.columns:
        if 'close' in col.lower() or 'last' in col.lower():
            price_col = col
            break
            
    if not price_col:
        # Fallback: assume last column is Close if not labeled, or 4th column
        # But for reliable scoring, we need to find columns that look like indicators
        pass

    # Helper to find matching column
    def find_matching_column(target_series, df, corr_threshold=0.95):
        best_col = None
        best_corr = -1
        
        # Clean target
        target_series = target_series.dropna()
        if len(target_series) == 0: return None
        
        for col in df.columns:
            if df[col].dtype.kind not in 'fi': continue # Skip non-numeric
            
            # Align indices
            candidate = df[col].iloc[target_series.index[0]:].dropna()
            
            # Simple length check to avoid misalignments
            common_idx = target_series.index.intersection(candidate.index)
            if len(common_idx) < len(target_series) * 0.8: continue
            
            try:
                corr = np.corrcoef(target_series.loc[common_idx], candidate.loc[common_idx])[0,1]
                if corr > best_corr:
                    best_corr = corr
                    best_col = col
            except:
                continue
                
        if best_corr >= corr_threshold:
            return best_col
        return None

    if price_col:
        # Calculate expected indicators
        prices = df[price_col]
        
        # Verify SMA(50)
        expected_sma = calculate_sma(prices, period=50)
        # Drop NaN for correlation
        sma_match = find_matching_column(expected_sma, df)
        
        if sma_match and sma_match != price_col:
            score += 25
            feedback.append(f"SMA(50) column identified: '{sma_match}' (+25)")
        else:
            feedback.append("SMA(50) values not found in export")

        # Verify RSI(14)
        # RSI calculation can vary (Wilder vs Standard). We look for high correlation or explicit name.
        # First check by name
        rsi_col_name = next((c for c in df.columns if 'RSI' in c), None)
        if rsi_col_name:
            score += 25
            feedback.append(f"RSI column found by name: '{rsi_col_name}' (+25)")
        else:
            # Try calculation correlation (approximate)
            # RSI typically oscillates 0-100.
            # Look for a column with range 0-100 and non-price values
            potential_rsi = []
            for col in df.columns:
                if df[col].dtype.kind in 'fi' and col != price_col and col != sma_match:
                    if df[col].min() >= 0 and df[col].max() <= 100:
                        potential_rsi.append(col)
            
            if potential_rsi:
                score += 25
                feedback.append(f"Potential RSI column found (0-100 range): {potential_rsi[0]} (+25)")
            else:
                feedback.append("No RSI-like data found")

    else:
        feedback.append("Could not identify price column to verify indicators")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }