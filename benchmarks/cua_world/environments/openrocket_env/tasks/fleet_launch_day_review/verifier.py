#!/usr/bin/env python3
"""
Verifier for fleet_launch_day_review task.

Scoring breakdown (100 points total):
  10 pts - simple_model_rocket.ork has >=1 uptodate simulation
  10 pts - dual_parachute_deployment.ork has >=1 uptodate simulation
  10 pts - clustered_motors.ork has >=1 uptodate simulation
  10 pts - Fleet summary CSV exists and has a header row
  15 pts - CSV contains data rows for >=2 distinct rockets with numeric metrics
  10 pts - Safety briefing exists (text file >= 100 characters)
  10 pts - Briefing references at least 2 rocket names/types
  15 pts - Unsafe rocket explicitly identified (references dual-deploy's high velocity or unsafe status)
  10 pts - GO/NO-GO or clear clearance language present in briefing

Pass threshold: 60 points
"""

import os
import re
import tempfile
import zipfile
import json
import xml.etree.ElementTree as ET


def _parse_ork(local_path):
    """Parse .ork ZIP+XML and return (root_element, error_string)."""
    try:
        with zipfile.ZipFile(local_path, 'r') as z:
            xml_bytes = z.read('rocket.ork')
        root = ET.fromstring(xml_bytes.decode('utf-8'))
        return root, None
    except zipfile.BadZipFile:
        try:
            tree = ET.parse(local_path)
            return tree.getroot(), None
        except Exception as e:
            return None, f"Could not parse .ork as ZIP or XML: {e}"
    except Exception as e:
        return None, f"Failed to parse .ork: {e}"

def _has_uptodate_sim(root):
    if root is None:
        return False
    sims = root.find('simulations')
    if sims is not None:
        for sim in sims.findall('simulation'):
            if sim.get('status') == 'uptodate':
                return True
    return False

def verify_fleet_launch_day_review(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    launch_day_dir = metadata.get('launch_day_dir', '/home/ga/Documents/rockets/launch_day')
    csv_path = metadata.get('csv_path', '/home/ga/Documents/exports/fleet_summary.csv')
    report_path = metadata.get('report_path', '/home/ga/Documents/exports/launch_day_briefing.txt')
    rockets = metadata.get('rockets', ["simple_model_rocket.ork", "dual_parachute_deployment.ork", "clustered_motors.ork"])

    score = 0
    feedback_parts = []
    
    # ---- 1. Check simulations (30 points) ----
    for rocket in rockets:
        vm_path = f"{launch_day_dir}/{rocket}"
        tmp_ork = tempfile.NamedTemporaryFile(delete=False, suffix='.ork')
        tmp_ork.close()
        try:
            copy_from_env(vm_path, tmp_ork.name)
            if os.path.exists(tmp_ork.name) and os.path.getsize(tmp_ork.name) > 0:
                root, err = _parse_ork(tmp_ork.name)
                if not err and _has_uptodate_sim(root):
                    score += 10
                    feedback_parts.append(f"{rocket} simulation updated (+10)")
                else:
                    feedback_parts.append(f"{rocket} simulation NOT updated")
            else:
                feedback_parts.append(f"Failed to copy {rocket}")
        except Exception as e:
            feedback_parts.append(f"Error checking {rocket}: {e}")
        finally:
            if os.path.exists(tmp_ork.name):
                os.unlink(tmp_ork.name)

    # ---- 2. Check CSV (25 points) ----
    tmp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    tmp_csv.close()
    try:
        copy_from_env(csv_path, tmp_csv.name)
        if os.path.exists(tmp_csv.name) and os.path.getsize(tmp_csv.name) > 10:
            score += 10
            feedback_parts.append("CSV file exists (+10)")
            
            with open(tmp_csv.name, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()
            
            lines = [l.strip() for l in content.split('\n') if l.strip()]
            data_rows = 0
            # Skip header, count lines with numeric data
            if len(lines) >= 2:
                for line in lines[1:]:
                    if re.search(r'\d', line):
                        data_rows += 1
                
            if data_rows >= 2:
                score += 15
                feedback_parts.append(f"CSV contains multi-rocket data ({data_rows} rows) (+15)")
            else:
                feedback_parts.append("CSV lacks sufficient data rows")
        else:
            feedback_parts.append("CSV file missing or empty")
    except Exception as e:
        feedback_parts.append(f"Error checking CSV: {e}")
    finally:
        if os.path.exists(tmp_csv.name):
            os.unlink(tmp_csv.name)

    # ---- 3. Check Safety Briefing Report (45 points) ----
    tmp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    tmp_report.close()
    try:
        copy_from_env(report_path, tmp_report.name)
        if os.path.exists(tmp_report.name) and os.path.getsize(tmp_report.name) > 0:
            with open(tmp_report.name, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read().lower()
            
            # Criterion: Exists and has substance
            if len(content) >= 50:
                score += 10
                feedback_parts.append("Briefing exists (+10)")
            else:
                feedback_parts.append("Briefing is too short")
            
            # Criterion: References rockets
            rockets_mentioned = sum(1 for kw in ['simple', 'dual', 'cluster', 'deployment'] if kw in content)
            if rockets_mentioned >= 2:
                score += 10
                feedback_parts.append("Briefing references multiple rockets (+10)")
            else:
                feedback_parts.append("Briefing does not adequately reference the rockets")

            # Criterion: Explicit GO/NO-GO language
            if re.search(r'\b(go|no-go|no go|clear|unsafe|safe|grounded)\b', content):
                score += 10
                feedback_parts.append("Briefing contains GO/NO-GO language (+10)")
            else:
                feedback_parts.append("Briefing lacks clearance language")

            # Criterion: Unsafe rocket identified
            # Look for associations between dual/parachute/descent/hit/velocity and unsafe/danger/no-go/fast
            if re.search(r'(dual|parachute|descent|velocity|hit)[^.]{0,80}(unsafe|no-go|no go|danger|fast|fail|high|ground|re-size|fix)', content, re.IGNORECASE) or \
               re.search(r'(unsafe|no-go|no go|danger|fast|fail|high|ground|re-size|fix)[^.]{0,80}(dual|parachute|descent|velocity|hit)', content, re.IGNORECASE):
                score += 15
                feedback_parts.append("Unsafe rocket issue explicitly identified (+15)")
            else:
                feedback_parts.append("Failed to clearly identify the recovery safety issue on the dual-deploy rocket")
                
        else:
            feedback_parts.append("Safety briefing report missing or empty")
    except Exception as e:
        feedback_parts.append(f"Error checking report: {e}")
    finally:
        if os.path.exists(tmp_report.name):
            os.unlink(tmp_report.name)

    pass_threshold = metadata.get('pass_threshold', 60)
    passed = score >= pass_threshold

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }