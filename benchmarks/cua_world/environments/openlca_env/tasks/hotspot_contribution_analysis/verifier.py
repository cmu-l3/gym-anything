#!/usr/bin/env python3
import json
import os
import tempfile
import logging
import csv
import re

logger = logging.getLogger(__name__)

def verify_hotspot_analysis(traj, env_info, task_info):
    """
    Verify the Hotspot Contribution Analysis task.
    
    Scoring Breakdown (100 pts total):
    1. Infrastructure & Setup (20 pts)
       - Database imported (>50 processes) (10 pts)
       - LCIA methods imported (>0 categories) (10 pts)
       
    2. Core Task Execution (30 pts)
       - Product System created (>=1) (15 pts)
       - Hotspot Report CSV exists & created during task (15 pts)
       
    3. Content Accuracy (30 pts)
       - CSV contains data (rows > 3) (10 pts)
       - CSV/Summary references relevant keywords (natural gas, electricity) (10 pts)
       - Summary file exists and lists contributors (10 pts)
       
    4. VLM Verification (20 pts)
       - Trajectory shows correct workflow (Import -> System -> Calc -> Results)
       
    Pass Threshold: 60 points
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # --- 1. Retrieve Result JSON ---
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback = []
    
    # Extract metrics
    db_metrics = result.get('database_state', {})
    report_file = result.get('report_file', {})
    summary_file = result.get('summary_file', {})
    
    # --- 2. Programmatic Verification ---
    
    # Criterion: Database Imported (10 pts)
    # Real USLCI has hundreds of processes. We check for > 50 to allow for partial/test imports but exclude empty DBs.
    proc_count = db_metrics.get('process_count', 0)
    if proc_count > 50:
        score += 10
        feedback.append(f"Database successfully imported ({proc_count} processes).")
    elif proc_count > 0:
        score += 5
        feedback.append(f"Database has some processes ({proc_count}), but fewer than expected for USLCI.")
    else:
        feedback.append("No processes found in database.")

    # Criterion: LCIA Methods Imported (10 pts)
    impact_count = db_metrics.get('impact_category_count', 0)
    if impact_count > 0:
        score += 10
        feedback.append(f"LCIA methods present ({impact_count} categories).")
    else:
        feedback.append("No LCIA methods/impact categories found.")

    # Criterion: Product System Created (15 pts)
    sys_count = db_metrics.get('product_system_count', 0)
    if sys_count >= 1:
        score += 15
        feedback.append(f"Product System created ({sys_count} found).")
    else:
        feedback.append("No Product System created.")

    # Criterion: Report CSV Exists & Valid (15 pts)
    report_exists = report_file.get('exists', False)
    report_fresh = report_file.get('created_during_task', False)
    report_size = report_file.get('size', 0)
    
    if report_exists and report_fresh and report_size > 50:
        score += 15
        feedback.append("Hotspot report CSV created successfully.")
        
        # --- Content Check for CSV (part of Content Accuracy) ---
        # We need to copy the actual CSV file to verify content
        temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
        try:
            copy_from_env(report_file['path'], temp_csv.name)
            with open(temp_csv.name, 'r', errors='ignore') as f:
                content = f.read()
                
            # Check row count (header + data)
            lines = [l for l in content.splitlines() if l.strip()]
            if len(lines) >= 3:
                score += 10
                feedback.append("Report CSV contains data rows.")
            else:
                feedback.append("Report CSV appears empty or missing data.")
                
            # Check keywords in CSV
            keywords = ["gas", "electricity", "power", "combustion", "extraction", "transport"]
            if any(k in content.lower() for k in keywords):
                score += 5  # Part of 10 pts for keywords
                feedback.append("Report contains relevant process keywords.")
            
            # Check for numeric values (basic check)
            if re.search(r'[0-9]+\.[0-9]+', content):
                 # Implicitly good, confirming data
                 pass
                 
        except Exception as e:
            feedback.append(f"Could not verify CSV content: {e}")
        finally:
            if os.path.exists(temp_csv.name):
                os.unlink(temp_csv.name)
    else:
        feedback.append("Hotspot report CSV missing, empty, or not created during task.")

    # Criterion: Summary File (15 pts split)
    summary_exists = summary_file.get('exists', False)
    if summary_exists and summary_file.get('size', 0) > 20:
        score += 10
        feedback.append("Summary text file created.")
        
        # Check summary content
        temp_txt = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env(summary_file['path'], temp_txt.name)
            with open(temp_txt.name, 'r', errors='ignore') as f:
                txt_content = f.read().lower()
                
            # Check for impact category mention
            if any(w in txt_content for w in ["gwp", "global warming", "climate", "co2"]):
                score += 5  # Remaining keyword points
                feedback.append("Summary mentions Global Warming/GWP.")
        except:
            pass
        finally:
            if os.path.exists(temp_txt.name):
                os.unlink(temp_txt.name)
    else:
        feedback.append("Summary file missing or empty.")

    # --- 3. VLM Verification (20 pts) ---
    # Using the gym_anything.vlm interface provided in context
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    
    # 1. Trajectory Analysis
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        prompt = """
        Analyze these screenshots of a user performing a Life Cycle Assessment (LCA) hotspot analysis.
        Look for the following stages:
        1. Importing data (wizards, file dialogs)
        2. Creating a Product System (graph view of connected boxes)
        3. Running a Calculation (dialog with 'Calculate' button, loading bars)
        4. Viewing Results (tables with 'Impact Analysis', 'Process Contributions', or charts)
        
        Does the visual history show a progression through these steps?
        Answer JSON: {"steps_seen": ["list"], "workflow_complete": bool}
        """
        
        try:
            vlm_res = query_vlm(prompt=prompt, images=frames)
            if vlm_res and vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('workflow_complete', False) or len(parsed.get('steps_seen', [])) >= 3:
                    score += 20
                    feedback.append("VLM confirms complete LCA workflow.")
                elif len(parsed.get('steps_seen', [])) >= 1:
                    score += 10
                    feedback.append("VLM sees partial workflow.")
                else:
                    feedback.append("VLM did not observe clear LCA workflow steps.")
            else:
                # Fallback if VLM fails: award points if programmatic checks are strong
                if score >= 50:
                    score += 10
                    feedback.append("VLM query failed, awarding partial credit based on file evidence.")
        except Exception:
            # Fallback
            if score >= 50:
                score += 10
    else:
        feedback.append("No trajectory frames available for VLM.")

    # Final Score Calculation
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback)
    }