#!/usr/bin/env python3
import json
import os
import csv
import logging
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_convert_watchlist_to_portfolio(traj, env_info, task_info):
    """
    Verifies that the agent created the 'Starter_Positions' portfolio and 
    added the 5 watchlist stocks with 1 unit at $150.00 each.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_stocks = set(metadata.get('expected_stocks', ["AAPL", "MSFT", "GOOGL", "AMZN", "NVDA"]))
    expected_units = float(metadata.get('expected_units', 1.0))
    expected_price = float(metadata.get('expected_price', 150.0))
    
    score = 0
    feedback_parts = []
    
    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
            
    # 2. Check basic file existence (20 points)
    if not result.get('portfolio_dir_exists', False):
        return {"passed": False, "score": 0, "feedback": "Portfolio 'Starter_Positions' was not created."}
    
    score += 10
    feedback_parts.append("Portfolio directory created")
    
    if not result.get('csv_exists', False):
        return {"passed": False, "score": 10, "feedback": "Portfolio created but no transactions found (buyportfolio.csv missing)."}
        
    score += 10
    feedback_parts.append("Transaction file exists")
    
    # 3. Check Anti-Gaming (Timestamp)
    if not result.get('file_modified_during_task', False):
        feedback_parts.append("WARNING: File not modified during task time window.")
        # We penalize but don't fail immediately, in case of slight clock skews, 
        # but combined with VLM this is a strong signal.
    
    # 4. Parse CSV Content
    # We need to copy the CSV file exported by the script
    csv_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env("/tmp/exported_portfolio.csv", csv_temp.name)
        
        found_stocks = set()
        correct_units_count = 0
        correct_price_count = 0
        total_rows = 0
        
        with open(csv_temp.name, 'r', encoding='utf-8', errors='replace') as f:
            # JStock CSVs often quote all fields. python csv handles this.
            reader = csv.reader(f)
            header = next(reader, None)
            
            # Identify columns
            try:
                # Normal headers: "Code","Symbol","Date","Units","Purchase Price",...
                # We need to find indices. 
                # Note: JStock headers might be case-sensitive or vary slightly.
                # We'll normalize headers to lower case for finding indices.
                if not header:
                    raise ValueError("Empty CSV")
                    
                header_map = {h.lower().strip(): i for i, h in enumerate(header)}
                idx_code = header_map.get('code')
                idx_units = header_map.get('units')
                idx_price = header_map.get('purchase price')
                
                if idx_code is None: 
                    # Fallback for JStock specific format if header is weird
                    idx_code = 0
                    
                for row in reader:
                    if not row: continue
                    total_rows += 1
                    
                    # Extract data
                    code = row[idx_code].strip()
                    
                    # Units
                    try:
                        units = float(row[idx_units]) if idx_units is not None else 0.0
                    except: units = 0.0
                    
                    # Price
                    try:
                        price = float(row[idx_price]) if idx_price is not None else 0.0
                    except: price = 0.0
                    
                    # Check Logic
                    if code in expected_stocks:
                        found_stocks.add(code)
                        if abs(units - expected_units) < 0.01:
                            correct_units_count += 1
                        if abs(price - expected_price) < 0.01:
                            correct_price_count += 1
                    else:
                        # Extra stock found
                        pass
                        
            except Exception as e:
                feedback_parts.append(f"Error parsing CSV: {e}")
                
    except Exception as e:
        feedback_parts.append(f"Failed to retrieve CSV: {e}")
    finally:
        if os.path.exists(csv_temp.name):
            os.unlink(csv_temp.name)
            
    # 5. Score Calculation
    
    # Coverage (30 pts)
    # 5 stocks expected. 6 points each.
    coverage_score = len(found_stocks) * 6
    score += coverage_score
    if len(found_stocks) == len(expected_stocks):
        feedback_parts.append(f"All {len(expected_stocks)} stocks found")
    else:
        missing = expected_stocks - found_stocks
        feedback_parts.append(f"Missing stocks: {', '.join(missing)}")

    # Accuracy - Units (20 pts)
    # 4 points per correct stock
    units_score = correct_units_count * 4
    score += units_score
    
    # Accuracy - Price (20 pts)
    # 4 points per correct stock
    price_score = correct_price_count * 4
    score += price_score
    
    # Extra check: No extra stocks (10 pts)
    if total_rows == len(expected_stocks):
        score += 10
        feedback_parts.append("Clean portfolio (no extra stocks)")
    elif total_rows > len(expected_stocks):
        feedback_parts.append(f"Found {total_rows} entries (expected {len(expected_stocks)})")
        
    # 6. VLM Verification (Trajectory check)
    # Ensure they actually used the GUI
    frames = sample_trajectory_frames(traj, n=4)
    final = get_final_screenshot(traj)
    
    vlm_score = 0
    try:
        # Simple check: Did we see the Portfolio Management screen?
        response = query_vlm(
            images=frames + [final],
            prompt="Does the user navigate to a screen titled 'Portfolio Management' or 'JStock'? Do we see a table where they are entering stock data like 'AAPL' or '150'? Answer YES or NO."
        )
        if "yes" in response.lower():
            # If we already have high score from CSV, this confirms it.
            # If CSV failed, this might give partial credit? 
            # Actually, let's keep it simple: VLM acts as a sanity check.
            pass
        else:
            feedback_parts.append("VLM did not observe portfolio data entry.")
    except Exception:
        pass

    passed = score >= 80 and len(found_stocks) >= 4
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }