#!/usr/bin/env python3
import os
import json
import gzip
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_pdf_memory_profiling(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_pdf_name = metadata.get('target_pdf_name', 'Heavy_Scientific_Report.pdf')

    feedback_parts = []
    score = 0
    max_score = 100

    # Extract task_result.json
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    task_start = result.get('task_start', 0)
    baseline_info = result.get('baseline', {})
    peak_info = result.get('peak', {})
    
    # 1. Check if files exist and created during task (20 + 20 pts)
    baseline_exists = baseline_info.get('exists', False)
    peak_exists = peak_info.get('exists', False)
    
    baseline_valid = False
    peak_valid = False
    
    if baseline_exists:
        if baseline_info.get('mtime', 0) >= task_start:
            score += 20
            feedback_parts.append("Baseline report created")
            baseline_valid = True
        else:
            feedback_parts.append("Baseline report existed before task")
    else:
        feedback_parts.append("Baseline report NOT found")
        
    if peak_exists:
        if peak_info.get('mtime', 0) >= task_start:
            score += 20
            feedback_parts.append("Peak report created")
            peak_valid = True
        else:
            feedback_parts.append("Peak report existed before task")
    else:
        feedback_parts.append("Peak report NOT found")
        
    # Helper to parse and analyze Firefox memory JSON files safely
    def analyze_memory_report(remote_path):
        temp_gz = tempfile.NamedTemporaryFile(delete=False, suffix='.json.gz')
        try:
            copy_from_env(remote_path, temp_gz.name)
            if not os.path.exists(temp_gz.name) or os.path.getsize(temp_gz.name) == 0:
                return {"valid": False, "error": "Empty file", "has_pdf": False, "raw_size": 0}
            
            # Agent might have saved it as uncompressed json despite the extension
            try:
                with gzip.open(temp_gz.name, 'rt', encoding='utf-8') as f:
                    content = f.read()
            except OSError:
                with open(temp_gz.name, 'r', encoding='utf-8') as f:
                    content = f.read()

            data = json.loads(content)
                
            is_valid_schema = 'hasDetailedSubreports' in data and 'reports' in data
            has_pdf = target_pdf_name in content
            
            return {
                "valid": is_valid_schema,
                "has_pdf": has_pdf,
                "raw_size": len(content),
                "error": None
            }
        except Exception as e:
            return {"valid": False, "error": str(e), "has_pdf": False, "raw_size": 0}
        finally:
            if os.path.exists(temp_gz.name):
                os.unlink(temp_gz.name)

    baseline_analysis = {"valid": False}
    peak_analysis = {"valid": False}

    if baseline_valid:
        baseline_analysis = analyze_memory_report("/home/ga/Documents/memory_baseline.json.gz")
        
    if peak_valid:
        peak_analysis = analyze_memory_report("/home/ga/Documents/memory_peak.json.gz")

    # 2. Schema Validation (20 pts)
    if baseline_analysis.get('valid') and peak_analysis.get('valid'):
        score += 20
        feedback_parts.append("Valid Firefox memory JSON schemas")
    elif baseline_analysis.get('valid') or peak_analysis.get('valid'):
        score += 10
        feedback_parts.append("Partial JSON schema validation")
    else:
        if baseline_valid or peak_valid:
            feedback_parts.append("Files are not valid Firefox memory reports")

    # 3. PDF Content Reference Validation (20 pts)
    if baseline_analysis.get('has_pdf') and peak_analysis.get('has_pdf'):
        score += 20
        feedback_parts.append(f"Target PDF '{target_pdf_name}' found in both memory trees")
    elif baseline_analysis.get('has_pdf') or peak_analysis.get('has_pdf'):
        score += 10
        feedback_parts.append(f"Target PDF found in one memory tree")
    else:
        if baseline_analysis.get('valid'):
            feedback_parts.append("Target PDF NOT found in memory trees")

    # 4. Anti-gaming Distinct Chronological Snapshots Check (20 pts)
    if baseline_valid and peak_valid and baseline_analysis.get('valid') and peak_analysis.get('valid'):
        # Check they aren't exactly the same content copy-pasted
        if baseline_analysis.get('raw_size') != peak_analysis.get('raw_size'):
            score += 20
            feedback_parts.append("Snapshots are distinct")
        else:
            feedback_parts.append("Baseline and peak snapshots are identical (failed anti-gaming check)")

    # 5. VLM verification check (Supplementary Evidence)
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        
        prompt = "Look at these screenshots of a user interacting with Firefox. Did they open a PDF document and did they access the 'about:memory' page?"
        vlm_result = query_vlm(images=frames + [final], prompt=prompt)
        
        if vlm_result and isinstance(vlm_result, dict) and "yes" in str(vlm_result.get('response', '')).lower():
            logger.info("VLM verified workflow trajectory successfully.")
    except Exception as e:
        logger.warning(f"VLM verification skipped or failed: {e}")

    # Determine pass threshold
    key_criteria_met = baseline_valid and peak_valid and baseline_analysis.get('valid') and peak_analysis.get('valid')
    passed = score >= 80 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }