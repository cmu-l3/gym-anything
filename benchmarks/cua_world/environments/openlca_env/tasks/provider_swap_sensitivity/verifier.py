#!/usr/bin/env python3
"""
Verifier for Provider Swap Sensitivity task.

Scoring Breakdown (100 pts):
- (10 pts) Database Imported: DB size > 15MB
- (10 pts) LCIA Methods Imported: Impact categories > 0
- (15 pts) Product System Created: PS count > 0
- (10 pts) System Linked: Process links > 10 (proves not empty)
- (10 pts) CSV File Exists: created during task & > 50 bytes
- (15 pts) CSV Content: Contains 2 distinct electricity provider names
- (15 pts) CSV Content: Contains 2 distinct GWP values
- (10 pts) Sensitivity Demonstrated: The GWP values are different
- (5 pts)  VLM: Verified provider selection dialog or graph modification

Pass Threshold: 60 pts
"""

import json
import os
import tempfile
import logging
import base64
import re

logger = logging.getLogger(__name__)

# ── VLM Prompts ─────────────────────────────────────────────────────────────

TRAJECTORY_PROMPT = """You are verifying an openLCA task where the agent must swap an electricity provider in a product system.

Look for these key stages in the screenshots:
1. Product System Graph/Editor: A view showing process boxes connected by lines.
2. Link Modification: A dialog or menu where the agent selects a "Provider" for an input (specifically looking for electricity/power inputs).
3. Calculation: Running the LCIA calculation (progress bar or calculation setup dialog).
4. Results Comparison: Viewing results or saving a CSV.

Assess:
- GRAPH_VISIBLE: Was the product system graph visible?
- PROVIDER_SWAP_ATTEMPTED: Did you see a "Provider" column, link editor, or "Search providers" dialog?
- CALCULATION_RUN: Was a calculation performed?

Return JSON:
{
    "graph_visible": true/false,
    "provider_swap_attempted": true/false,
    "calculation_run": true/false,
    "confidence": "low"/"medium"/"high"
}
"""

# ── Verification Logic ──────────────────────────────────────────────────────

def verify_provider_swap_sensitivity(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Load Result JSON
    temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp.name)
        with open(temp.name) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp.name):
            os.unlink(temp.name)

    score = 0
    feedback = []
    
    # 1. Database & Methods (20 pts)
    if result.get('db_found') and result.get('db_size_mb', 0) > 15:
        score += 10
        feedback.append("Database imported successfully")
    
    if result.get('impact_category_count', 0) > 0:
        score += 10
        feedback.append("LCIA methods imported")
        
    # 2. Product System Structure (25 pts)
    ps_count = int(result.get('product_system_count', 0))
    link_count = int(result.get('process_link_count', 0))
    
    if ps_count > 0:
        score += 15
        feedback.append(f"Product system created (count: {ps_count})")
    
    if link_count > 10:
        score += 10
        feedback.append(f"System is populated with links (count: {link_count})")
    elif link_count > 0:
        score += 5
        feedback.append("System has minimal links")
        
    # 3. CSV File Check (10 pts)
    csv_exists = result.get('csv_exists')
    csv_created = result.get('csv_created_during_task')
    csv_size = result.get('csv_size', 0)
    
    if csv_exists and csv_created and csv_size > 50:
        score += 10
        feedback.append("CSV file created during task")
    elif csv_exists:
        feedback.append("CSV file exists but timestamp check failed or file empty")
        
    # 4. CSV Content Analysis (40 pts)
    content_b64 = result.get('csv_content_base64', "")
    valid_comparison = False
    
    if content_b64:
        try:
            content = base64.b64decode(content_b64).decode('utf-8', errors='ignore')
            
            # Look for numbers (GWP values)
            numbers = re.findall(r'[0-9]+\.[0-9]+', content)
            float_vals = [float(n) for n in numbers]
            
            # Look for provider keywords (electricity related)
            # e.g., "grid", "mix", "US", "WECC", "coal", "gas", "hydro", "solar"
            elec_keywords = re.findall(r'(?i)(grid|mix|US|WECC|RFC|SERC|coal|gas|hydro|solar|wind|nuclear|cogen)', content)
            unique_keywords = set(k.lower() for k in elec_keywords)
            
            # Score: 2 distinct GWP values (15 pts)
            unique_floats = sorted(list(set(float_vals)))
            if len(unique_floats) >= 2:
                score += 15
                feedback.append(f"Found distinct GWP values: {unique_floats[:2]}")
                
                # Score: Values are different (Sensitivity shown) (10 pts)
                # Check absolute difference
                if abs(unique_floats[0] - unique_floats[1]) > 1e-6:
                    score += 10
                    feedback.append("Sensitivity confirmed (values differ)")
                    valid_comparison = True
            elif len(unique_floats) == 1:
                feedback.append("Found only one unique numeric value (no sensitivity shown)")
                
            # Score: 2 distinct provider names (15 pts)
            if len(unique_keywords) >= 2:
                score += 15
                feedback.append(f"Found distinct provider keywords: {list(unique_keywords)}")
            elif len(unique_keywords) == 1:
                score += 5
                feedback.append("Found one provider type")
                
        except Exception as e:
            feedback.append(f"Error parsing CSV content: {e}")

    # 5. VLM Verification (5 pts)
    # Only run if we haven't maxed out score yet
    if score < 100:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        frames = sample_trajectory_frames(traj, n=4)
        vlm_res = query_vlm(images=frames, prompt=TRAJECTORY_PROMPT)
        
        if vlm_res and vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            if parsed.get('provider_swap_attempted') or parsed.get('graph_visible'):
                score += 5
                feedback.append("VLM confirmed workflow steps")

    # Final tally
    passed = (score >= 60) and valid_comparison
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback)
    }