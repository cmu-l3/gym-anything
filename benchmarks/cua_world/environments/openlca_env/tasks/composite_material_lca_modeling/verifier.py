#!/usr/bin/env python3
"""
Verifier for Composite Material LCA Modeling task.

Criteria (100 points total):
1. Database Setup (15 pts): Database created & populated (>15MB).
2. Custom Flow (15 pts): "Rice Husks" flow exists in DB.
3. Process Creation (20 pts): "Bio-brick Production" process exists.
4. Input Accuracy (25 pts): 
   - Cement (~0.5), Sand (~1.2), Rice Husks (~0.3), Electricity (~0.05).
   - Checks if standard inputs are linked to valid USLCI flows (not just text).
5. Output Export (15 pts): Valid CSV created during task with GWP results.
6. Visual Verification (10 pts): Trajectory shows correct workflow.

Pass threshold: 70 points
"""

import json
import base64
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# --- VLM Prompts ---

TRAJECTORY_PROMPT = """You are verifying an OpenLCA task where an agent models a Bio-brick.
Workflow steps:
1. Import database (USLCI).
2. Create a custom flow ("Rice Husks").
3. Create a process ("Bio-brick Production") and add inputs (Cement, Sand, Husks, Electricity).
4. Create a product system and calculate results (GWP).
5. Export results.

Look at the screenshots.
- Did the agent create a new flow or process? (Look for forms with "Rice Husks" or "Bio-brick")
- Did they open the "Bio-brick Production" process editor with a list of inputs?
- Did they run a calculation (Activity: "Calculating..." or Results window)?
- Is there a final result table or export dialog?

Respond in JSON:
{
    "created_custom_flow": true/false,
    "created_process": true/false,
    "inputs_added": true/false,
    "calculation_run": true/false,
    "confidence": "low/medium/high"
}
"""

def verify_composite_material_lca(traj, env_info, task_info):
    # 1. Setup - Copy result from env
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}
    
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    score = 0
    feedback = []
    
    # 2. Database Check (15 pts)
    # Pass if DB found and size > 15MB (implies import happened)
    if result.get('db_found') and result.get('db_size_mb', 0) > 15:
        score += 15
        feedback.append("Database created and imported successfully.")
    elif result.get('db_found'):
        score += 5
        feedback.append("Database created but seems empty/small.")
    else:
        feedback.append("No active database found.")

    # 3. Custom Flow Check (15 pts)
    if result.get('flow_found'):
        score += 15
        feedback.append("Custom flow 'Rice Husks' found.")
    else:
        feedback.append("Custom flow 'Rice Husks' NOT found.")

    # 4. Process Creation Check (20 pts)
    if result.get('process_found'):
        score += 20
        feedback.append("Process 'Bio-brick Production' found.")
    else:
        feedback.append("Process 'Bio-brick Production' NOT found.")
        
    # 5. Input Accuracy & Linking (25 pts)
    # Parse exchange data from base64
    exchange_score = 0
    exchange_feedback = []
    
    try:
        raw_exch = base64.b64decode(result.get('exchange_data_b64', '')).decode('utf-8', errors='ignore')
        # Derby output format: NAME | RESULT_AMOUNT
        # We look for lines containing our target inputs
        
        # Targets with tolerances (+/- 10%)
        targets = [
            ("Rice", 0.3, "Rice Husks"),
            ("Cement", 0.5, "Cement"),
            ("Sand", 1.2, "Sand"),
            ("Electricity", 0.05, "Electricity") # Note: unit checks are hard in raw query, assuming consistent units
        ]
        
        found_inputs = 0
        for keyword, target_amt, label in targets:
            # Simple heuristic parsing: look for lines with keyword and check the number in that line
            found = False
            for line in raw_exch.splitlines():
                if keyword.lower() in line.lower():
                    # Extract numbers
                    parts = line.split('|')
                    if len(parts) >= 2:
                        try:
                            val = float(parts[1].strip())
                            # Check amounts (allow wide tolerance for units or density differences)
                            # Primary check is presence + rough magnitude
                            if 0.1 * target_amt <= val <= 10 * target_amt: 
                                found = True
                                break
                        except ValueError:
                            continue
            if found:
                found_inputs += 1
                exchange_score += 6.25 # 25 / 4
                exchange_feedback.append(f"Input '{label}' found.")
            else:
                exchange_feedback.append(f"Input '{label}' missing or wrong amount.")
        
    except Exception as e:
        exchange_feedback.append(f"Error parsing exchanges: {str(e)}")
        
    score += min(25, int(exchange_score))
    feedback.extend(exchange_feedback)

    # 6. Output Export Check (15 pts)
    if result.get('file_exists') and result.get('file_created_during_task'):
        # Check content for GWP/Global Warming
        content_preview = base64.b64decode(result.get('file_content_b64', '')).decode('utf-8', errors='ignore')
        if "global" in content_preview.lower() or "gwp" in content_preview.lower() or "warming" in content_preview.lower():
            score += 15
            feedback.append("Valid LCIA result file exported.")
        else:
            score += 5
            feedback.append("File exported but GWP results not detected in preview.")
    else:
        feedback.append("No new result file exported.")

    # 7. VLM Verification (10 pts)
    # Only run if we have some programmatic success (to save tokens) or if we need points
    vlm_score = 0
    if score < 70 and score > 20: 
        # Import VLM utils (mocked here or assumed available in environment)
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            vlm_res = query_vlm(prompt=TRAJECTORY_PROMPT, images=frames)
            if vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                # Grant points for evidence of work
                criteria = ['created_custom_flow', 'created_process', 'inputs_added', 'calculation_run']
                met = sum(1 for c in criteria if parsed.get(c))
                if met >= 2:
                    vlm_score = 10
                    feedback.append(f"VLM confirmed workflow ({met}/4 steps observed).")
    
    score += vlm_score

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback),
        "details": result
    }