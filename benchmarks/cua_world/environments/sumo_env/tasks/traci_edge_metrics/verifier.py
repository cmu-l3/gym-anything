#!/usr/bin/env python3
import json
import os
import tempfile
import logging
import csv

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_traci_edge_metrics(traj, env_info, task_info):
    """
    Verify the Traci monitoring script and its generated output CSV.
    Uses multiple independent signals: script content checks and output data validation.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    script_path = metadata.get('script_path', '/home/ga/SUMO_Output/traci_monitor.py')
    csv_path = metadata.get('csv_path', '/home/ga/SUMO_Output/edge_metrics.csv')
    required_columns = set(metadata.get('required_columns', ['sim_time', 'edge_id', 'vehicle_count', 'mean_speed', 'travel_time']))
    
    score = 0
    feedback_parts = []
    
    # 1. Read task_result.json
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read export results: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    # Check anti-gaming
    if not result.get('script_created_during_task', False):
        feedback_parts.append("Script not created during task")
    if not result.get('csv_created_during_task', False):
        feedback_parts.append("CSV not created during task")
        
    # 2. Check Script
    if result.get('script_exists', False) and result.get('valid_python', False):
        score += 10
        feedback_parts.append("Valid Python script exists")
        
        # Download and inspect script
        temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.py')
        try:
            copy_from_env(script_path, temp_script.name)
            with open(temp_script.name, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()
                
            has_import = 'import traci' in content or 'from traci' in content
            has_start = 'traci.start' in content
            has_step = 'traci.simulationStep' in content
            has_close = 'traci.close' in content
            
            api_score = 0
            if has_import and has_start and has_step and has_close:
                api_score += 10
                feedback_parts.append("TraCI lifecycle methods found")
                
            edge_calls = 0
            if 'getLastStepVehicleNumber' in content: edge_calls += 1
            if 'getLastStepMeanSpeed' in content: edge_calls += 1
            if 'getTraveltime' in content: edge_calls += 1
            
            if edge_calls >= 2:
                api_score += 5
                feedback_parts.append("Edge metric API calls found")
            score += api_score
        except Exception as e:
            logger.error(f"Failed to inspect script: {e}")
        finally:
            if os.path.exists(temp_script.name):
                os.unlink(temp_script.name)
    else:
        feedback_parts.append("Script missing or invalid")
        
    # 3. Check CSV
    if result.get('csv_exists', False):
        score += 10
        feedback_parts.append("CSV file exists")
        
        temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
        try:
            copy_from_env(csv_path, temp_csv.name)
            
            with open(temp_csv.name, 'r', encoding='utf-8', errors='ignore') as f:
                # Basic check for empty file
                f.seek(0, 2)
                if f.tell() == 0:
                    feedback_parts.append("CSV is empty")
                    raise ValueError("Empty CSV")
                f.seek(0)
                
                reader = csv.reader(f)
                try:
                    header = next(reader)
                except StopIteration:
                    feedback_parts.append("CSV has no header")
                    raise ValueError("No header")
                
                header_cleaned = [h.strip() for h in header]
                if required_columns.issubset(set(header_cleaned)):
                    score += 10
                    feedback_parts.append("CSV has correct schema")
                else:
                    feedback_parts.append(f"Missing columns: {required_columns - set(header_cleaned)}")
                    
                # Find column indices safely
                idx_time = header_cleaned.index('sim_time') if 'sim_time' in header_cleaned else -1
                idx_edge = header_cleaned.index('edge_id') if 'edge_id' in header_cleaned else -1
                idx_vc = header_cleaned.index('vehicle_count') if 'vehicle_count' in header_cleaned else -1
                idx_speed = header_cleaned.index('mean_speed') if 'mean_speed' in header_cleaned else -1
                idx_tt = header_cleaned.index('travel_time') if 'travel_time' in header_cleaned else -1
                
                sim_times = set()
                edge_ids = set()
                
                valid_counts = True
                valid_speeds = True
                valid_tts = True
                has_non_zero_count = False
                has_non_zero_speed = False
                
                row_count = 0
                
                for row in reader:
                    if not row:
                        continue
                        
                    row_count += 1
                    try:
                        if idx_time != -1 and len(row) > idx_time:
                            sim_times.add(float(row[idx_time]))
                            
                        if idx_edge != -1 and len(row) > idx_edge:
                            edge_ids.add(row[idx_edge].strip())
                        
                        if idx_vc != -1 and len(row) > idx_vc:
                            vc = float(row[idx_vc])
                            if vc < 0: valid_counts = False
                            if vc > 0: has_non_zero_count = True
                        else:
                            valid_counts = False
                            
                        if idx_speed != -1 and len(row) > idx_speed:
                            speed = float(row[idx_speed])
                            if speed < 0 or speed > 50: valid_speeds = False
                            if speed > 0: has_non_zero_speed = True
                        else:
                            valid_speeds = False
                            
                        if idx_tt != -1 and len(row) > idx_tt:
                            tt = float(row[idx_tt])
                            if tt < 0 or tt > 3600: valid_tts = False
                        else:
                            valid_tts = False
                            
                    except ValueError:
                        # Skip rows with parsing errors silently 
                        pass
                
                if row_count >= 100:
                    score += 6
                    feedback_parts.append(f"Sufficient rows ({row_count})")
                    
                if len(sim_times) >= 6 and (max(sim_times) - min(sim_times)) >= 250:
                    score += 10
                    feedback_parts.append(f"Good temporal coverage ({len(sim_times)} steps)")
                    
                if len(edge_ids) >= 20:
                    score += 10
                    feedback_parts.append(f"Good spatial coverage ({len(edge_ids)} edges)")
                    
                if valid_counts and has_non_zero_count:
                    score += 8
                    feedback_parts.append("Vehicle counts plausible")
                    
                if valid_speeds and has_non_zero_speed:
                    score += 8
                    feedback_parts.append("Speeds plausible")
                    
                if valid_tts:
                    score += 8
                    feedback_parts.append("Travel times plausible")
                    
                if result.get('csv_created_during_task', False):
                    score += 5
                    
        except Exception as e:
            logger.error(f"Failed to inspect CSV: {e}")
        finally:
            if os.path.exists(temp_csv.name):
                os.unlink(temp_csv.name)
    else:
        feedback_parts.append("CSV file missing")

    passed = score >= 65 and result.get('csv_exists', False) and result.get('csv_created_during_task', False)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }