#!/usr/bin/env python3
import json
import os
import base64
import pandas as pd
import io
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_identify_overbank_flow(traj, env_info, task_info):
    """
    Verify the Identify Overbank Flow task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON
    import tempfile
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Check if files exist (Basic Requirements)
    if not result.get('script_exists', False):
        feedback_parts.append("Python script not found.")
    else:
        score += 5
    
    if not result.get('csv_exists', False):
        feedback_parts.append("CSV output not found.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
    
    score += 10  # CSV exists
    
    if not result.get('summary_exists', False):
        feedback_parts.append("Summary text file not found.")
    else:
        score += 10
        
    # 2. Validate Ground Truth Generation
    gt = result.get('ground_truth', {})
    if not gt.get('success', False):
        return {"passed": False, "score": score, "feedback": f"Internal verification error: {gt.get('error')}"}
        
    gt_rows = gt.get('rows', [])
    gt_summary = gt.get('summary', {})
    gt_df = pd.DataFrame(gt_rows)
    
    # 3. Analyze Agent CSV
    agent_csv_b64 = result.get('agent_csv_b64', "")
    if not agent_csv_b64:
        return {"passed": False, "score": score, "feedback": "CSV file is empty."}
        
    try:
        agent_csv_str = base64.b64decode(agent_csv_b64).decode('utf-8')
        agent_df = pd.read_csv(io.StringIO(agent_csv_str))
        
        # Check Columns
        required_cols = {'River_Station', 'Min_Bank_Elev_ft', 'Max_WSE_ft', 'Overtopped', 'First_Overtop_Index', 'Max_Overtop_Depth_ft'}
        if not required_cols.issubset(set(agent_df.columns)):
            missing = required_cols - set(agent_df.columns)
            feedback_parts.append(f"Missing columns: {missing}")
        else:
            score += 10 # Columns Correct
            
            # Check Row Count
            if len(agent_df) == len(gt_df):
                score += 10
            else:
                feedback_parts.append(f"Row count mismatch: Agent {len(agent_df)}, Truth {len(gt_df)}")
            
            # Merge for comparison
            # Ensure River_Station is string/object for merge
            agent_df['River_Station'] = agent_df['River_Station'].astype(str)
            gt_df['River_Station'] = gt_df['River_Station'].astype(str)
            
            merged = pd.merge(agent_df, gt_df, on='River_Station', suffixes=('_agent', '_gt'))
            
            # Calculate accuracy metrics
            # Bank Elevation (within 0.5 ft)
            bank_diff = abs(merged['Min_Bank_Elev_ft_agent'] - merged['Min_Bank_Elev_ft_gt'])
            bank_acc = (bank_diff <= 0.5).mean()
            if bank_acc >= 0.8: score += 15
            else: feedback_parts.append(f"Bank elevation accuracy low ({bank_acc:.1%})")
            
            # Max WSE (within 0.1 ft)
            wse_diff = abs(merged['Max_WSE_ft_agent'] - merged['Max_WSE_ft_gt'])
            wse_acc = (wse_diff <= 0.1).mean()
            if wse_acc >= 0.8: score += 15
            else: feedback_parts.append(f"WSE accuracy low ({wse_acc:.1%})")
            
            # Overtopping Classification
            # normalize Yes/No case
            merged['Overtopped_agent'] = merged['Overtopped_agent'].astype(str).str.lower()
            merged['Overtopped_gt'] = merged['Overtopped_gt'].astype(str).str.lower()
            cls_acc = (merged['Overtopped_agent'] == merged['Overtopped_gt']).mean()
            if cls_acc >= 0.9: score += 15
            else: feedback_parts.append(f"Overtopping classification accuracy low ({cls_acc:.1%})")
            
            # Depth Accuracy (for overtopped only)
            overtopped_mask = merged['Overtopped_gt'] == 'yes'
            if overtopped_mask.any():
                depth_diff = abs(merged.loc[overtopped_mask, 'Max_Overtop_Depth_ft_agent'] - merged.loc[overtopped_mask, 'Max_Overtop_Depth_ft_gt'])
                depth_acc = (depth_diff <= 0.5).mean()
                if depth_acc >= 0.8: score += 10
                else: feedback_parts.append(f"Depth calculation accuracy low ({depth_acc:.1%})")
            else:
                score += 10 # No overtopping to check
                
    except Exception as e:
        feedback_parts.append(f"Failed to parse Agent CSV: {str(e)}")
        
    # 4. Check Summary File
    agent_summary_b64 = result.get('agent_summary_b64', "")
    if agent_summary_b64:
        try:
            summary_text = base64.b64decode(agent_summary_b64).decode('utf-8')
            # Check for key numbers
            if str(gt_summary['total_xs']) in summary_text: score += 2
            if str(gt_summary['overtopped_count']) in summary_text: score += 4
            if str(gt_summary['max_depth_rs']) in summary_text: score += 4
        except:
            pass
            
    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) if feedback_parts else "Task completed successfully."
    }