#!/usr/bin/env python3
"""
Verifier for aggregate_analytics_report@1

Strategy:
1. Fetch the agent's output file (`~/analytics_report.txt`) and the ground truth JSONs (generated during setup).
2. Parse the text report looking for the key data points from the ground truth.
   - Since the report format is free-text, we use fuzzy/regex matching:
   - "Find 'Italy' in text, then look for '4.5' nearby"
3. Score based on how many correct data points are found.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_analytics_report(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # 1. Setup temporary directory for artifacts
    with tempfile.TemporaryDirectory() as temp_dir:
        report_path = os.path.join(temp_dir, "agent_report.txt")
        gt_dir = os.path.join(temp_dir, "ground_truth")
        os.makedirs(gt_dir, exist_ok=True)
        
        # 2. Copy files from environment
        try:
            # Copy Agent Report
            copy_from_env("/home/ga/analytics_report.txt", report_path)
            
            # Copy Ground Truth files
            gt_files = ["nationality.json", "hotel_stars.json", "luxury_hotels.json", "restaurants.json", "orders.json"]
            for f in gt_files:
                copy_from_env(f"/tmp/ground_truth/{f}", os.path.join(gt_dir, f))
                
            # Copy result metadata
            copy_from_env("/tmp/task_result.json", os.path.join(temp_dir, "task_result.json"))
            with open(os.path.join(temp_dir, "task_result.json")) as f:
                task_meta = json.load(f)
                
        except Exception as e:
            # If report is missing, copy might fail
            if "agent_report.txt" in str(e) or not os.path.exists(report_path):
                return {"passed": False, "score": 0, "feedback": "Report file '/home/ga/analytics_report.txt' not found."}
            logger.error(f"Copy error: {e}")
            return {"passed": False, "score": 0, "feedback": f"Error retrieving files: {str(e)}"}

        # 3. Basic Validation (Anti-Gaming)
        if not task_meta.get("created_during_task", False):
            return {"passed": False, "score": 0, "feedback": "The report file was not created/modified during the task window."}
        
        if task_meta.get("report_size", 0) < 50:
            return {"passed": False, "score": 0, "feedback": "The report file is too empty to contain valid analysis."}

        # Read Report Content
        with open(report_path, "r", errors="ignore") as f:
            report_text = f.read()

        score = 0
        feedback = []
        
        # --- CHECK 1: Nationality Distribution (20 pts) ---
        # Logic: For each GT entry (e.g., American: 5), check if "American" appears, and "5" appears within proximity.
        try:
            with open(os.path.join(gt_dir, "nationality.json")) as f:
                gt_data = json.load(f).get("result", [])
            
            hits = 0
            for item in gt_data:
                nat = item.get("Nationality", "Unknown")
                count = item.get("cnt", 0)
                # Regex: Look for Nationality, then within 50 chars look for the count (or vice versa)
                # Simple check: both exist in the text? (Weak)
                # Better: both exist in text
                if re.search(rf"{re.escape(nat)}", report_text, re.IGNORECASE) and \
                   re.search(rf"\b{count}\b", report_text):
                    hits += 1
            
            if hits >= min(len(gt_data), 3): # If at least 3 correct pairs found (or all if <3)
                score += 20
                feedback.append(f"✓ Nationality section correct ({hits} matches)")
            elif hits > 0:
                score += 10
                feedback.append(f"⚠ Nationality section partial ({hits} matches)")
            else:
                feedback.append("✗ Nationality data missing")
        except Exception as e:
            feedback.append(f"Error checking nationality: {e}")

        # --- CHECK 2: Hotel Stars (20 pts) ---
        try:
            with open(os.path.join(gt_dir, "hotel_stars.json")) as f:
                gt_data = json.load(f).get("result", [])
            
            hits = 0
            for item in gt_data:
                country = item.get("Country", "")
                avg = item.get("avg_stars", 0)
                # Match integer part or float with 1 decimal
                # e.g. if avg is 4.5, match "4.5". If 4.0, match "4" or "4.0"
                target = f"{avg:.1f}"
                if re.search(rf"{re.escape(country)}", report_text, re.IGNORECASE) and \
                   (re.search(rf"{re.escape(target)}", report_text) or re.search(rf"\b{int(avg)}\b", report_text)):
                    hits += 1
            
            if hits >= min(len(gt_data), 3):
                score += 20
                feedback.append(f"✓ Hotel stars correct ({hits} matches)")
            elif hits > 0:
                score += 10
                feedback.append(f"⚠ Hotel stars partial ({hits} matches)")
            else:
                feedback.append("✗ Hotel star data missing")
        except: pass

        # --- CHECK 3: 5-Star Hotels (20 pts) ---
        try:
            with open(os.path.join(gt_dir, "luxury_hotels.json")) as f:
                gt_data = json.load(f).get("result", [])
            
            hits = 0
            for item in gt_data:
                name = item.get("Name", "")
                # Just check if the hotel name appears in the report
                if name and re.search(rf"{re.escape(name)}", report_text, re.IGNORECASE):
                    hits += 1
            
            if hits >= len(gt_data): # All must be present
                score += 20
                feedback.append(f"✓ All {hits} 5-star hotels listed")
            elif hits > 0:
                score += int(20 * (hits / len(gt_data)))
                feedback.append(f"⚠ Some 5-star hotels missing ({hits}/{len(gt_data)} found)")
            else:
                feedback.append("✗ No 5-star hotels found")
        except: pass

        # --- CHECK 4: Restaurants (20 pts) ---
        try:
            with open(os.path.join(gt_dir, "restaurants.json")) as f:
                gt_data = json.load(f).get("result", [])
            
            hits = 0
            for item in gt_data:
                country = item.get("Country", "")
                cnt = item.get("cnt", 0)
                if re.search(rf"{re.escape(country)}", report_text, re.IGNORECASE) and \
                   re.search(rf"\b{cnt}\b", report_text):
                    hits += 1
            
            if hits >= min(len(gt_data), 3):
                score += 20
                feedback.append(f"✓ Restaurant counts correct ({hits} matches)")
            elif hits > 0:
                score += 10
                feedback.append("⚠ Restaurant counts partial")
            else:
                feedback.append("✗ Restaurant counts missing")
        except: pass

        # --- CHECK 5: Order Revenue (20 pts) ---
        try:
            with open(os.path.join(gt_dir, "orders.json")) as f:
                gt_data = json.load(f).get("result", [])
            
            hits = 0
            for item in gt_data:
                status = item.get("Status", "")
                rev = item.get("revenue", 0)
                # Revenue is a float, match integer part mainly or rough formatting
                rev_int = int(rev)
                if re.search(rf"{re.escape(status)}", report_text, re.IGNORECASE) and \
                   re.search(rf"{rev_int}", report_text):
                    hits += 1
            
            if hits >= min(len(gt_data), 2):
                score += 20
                feedback.append("✓ Revenue data correct")
            elif hits > 0:
                score += 10
                feedback.append("⚠ Revenue data partial")
            else:
                feedback.append("✗ Revenue data missing")
        except: pass

        return {
            "passed": score >= 60,
            "score": score,
            "feedback": "; ".join(feedback)
        }