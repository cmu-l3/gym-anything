#!/usr/bin/env python3
import json
import os
import tempfile
import csv
import io
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_portfolio_asset_allocation(traj, env_info, task_info):
    """
    Verifies:
    1. KO added to portfolio with correct details (from CSV).
    2. Agent created a screenshot file.
    3. Screenshot shows a Pie Chart with KO/Coca-Cola visible (VLM).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    metadata = task_info.get('metadata', {})
    expected_symbol = metadata.get('expected_symbol', 'KO')
    expected_units = metadata.get('expected_units', 200.0)
    expected_price = metadata.get('expected_price', 60.0)
    
    score = 0
    feedback = []
    
    # 1. Load Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
            
    # 2. CSV Verification (Portfolio Content)
    portfolio_csv_str = result.get('portfolio_content')
    ko_found = False
    details_correct = False
    
    if portfolio_csv_str:
        try:
            # Parse CSV
            f_io = io.StringIO(portfolio_csv_str)
            reader = csv.DictReader(f_io)
            for row in reader:
                # Check for Symbol (Col 1 is 'Code', Col 2 is 'Symbol')
                code = row.get('Code', '')
                symbol_name = row.get('Symbol', '')
                
                if code == expected_symbol or expected_symbol in symbol_name:
                    ko_found = True
                    feedback.append(f"Found stock: {code}")
                    
                    # Verify details
                    try:
                        units = float(row.get('Units', 0))
                        price = float(row.get('Purchase Price', 0))
                        
                        units_ok = abs(units - expected_units) < 0.1
                        price_ok = abs(price - expected_price) < 0.1
                        
                        if units_ok and price_ok:
                            details_correct = True
                            feedback.append(f"Transaction details correct: {units} units @ ${price}")
                        else:
                            feedback.append(f"Transaction mismatch: Found {units} @ ${price}, expected {expected_units} @ ${expected_price}")
                    except ValueError:
                        feedback.append("Error parsing numeric values in CSV")
                    break
        except Exception as e:
            feedback.append(f"CSV parsing error: {e}")
    else:
        feedback.append("Portfolio CSV not found")

    if ko_found:
        score += 30
    if details_correct:
        score += 20

    # 3. Screenshot File Verification
    screenshot_created = result.get('screenshot_created_during_task', False)
    screenshot_path_in_container = result.get('screenshot_path')
    
    if screenshot_created:
        score += 20
        feedback.append("Screenshot file created successfully")
    else:
        feedback.append("Screenshot file missing or not created during task")

    # 4. VLM Verification (Visual Content)
    vlm_score = 0
    vlm_feedback = ""
    
    # We check the AGENT'S screenshot if it exists, otherwise fall back to trajectory/final
    images_to_check = []
    temp_img = None
    
    if screenshot_created and screenshot_path_in_container:
        try:
            temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
            copy_from_env(screenshot_path_in_container, temp_img.name)
            images_to_check.append(temp_img.name)
            feedback.append("Analyzing agent's screenshot...")
        except Exception as e:
            feedback.append(f"Could not copy agent screenshot: {e}")
    
    # If agent didn't make a screenshot, check their screen (final state)
    if not images_to_check:
        try:
            final_ss = get_final_screenshot(traj)
            if final_ss:
                images_to_check.append(final_ss)
                feedback.append("Analyzing final screen state...")
        except:
            pass

    if images_to_check:
        try:
            prompt = (
                "The user is asked to view a Portfolio Distribution Pie Chart in JStock. "
                "Does this image show a Pie Chart? "
                "Can you see a slice or legend entry for 'KO', 'Coca-Cola', or 'Coca'? "
                "Answer 'YES' if a pie chart is visible with the new stock, otherwise explain."
            )
            vlm_resp = query_vlm(images=images_to_check, prompt=prompt).strip()
            
            if "YES" in vlm_resp.upper():
                vlm_score = 30
                vlm_feedback = "VLM confirmed Pie Chart with Coca-Cola is visible."
            else:
                vlm_feedback = f"VLM did not verify chart: {vlm_resp}"
        except Exception as e:
            vlm_feedback = f"VLM error: {e}"
        finally:
            if temp_img and os.path.exists(temp_img.name):
                os.unlink(temp_img.name)
    else:
        vlm_feedback = "No images available for VLM verification."

    score += vlm_score
    feedback.append(vlm_feedback)
    
    passed = (score >= 70) and ko_found and details_correct
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }