#!/usr/bin/env python3
import json
import logging
import os
import tempfile
import csv
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_query_output(filepath):
    try:
        with open(filepath, 'r', encoding='utf-8', errors='replace') as f:
            content = f.read()
    except Exception as e:
        return {"success": False, "errors": [str(e)]}
        
    # Strip terminal escape sequences just in case of shell prompt leakage
    ansi_escape = re.compile(r'\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])')
    content = ansi_escape.sub('', content)
        
    # Check for underlying Oracle errors
    ora_errors = re.findall(r'ORA-\d+.*', content)
    if ora_errors:
        return {"success": False, "errors": ora_errors}
        
    lines = [line.strip() for line in content.split('\n')]
    header_idx = -1
    for i in range(len(lines)-1, -1, -1):
        if 'EMPLOYEE_NAME' in lines[i].upper():
            header_idx = i
            break
            
    if header_idx == -1:
        return {"success": True, "rows": [], "headers": []}
        
    csv_reader = csv.reader(lines[header_idx:])
    rows = list(csv_reader)
    if not rows:
        return {"success": True, "rows": [], "headers": []}
        
    headers = [h.strip().upper() for h in rows[0]]
    data_rows = []
    
    for r in rows[1:]:
        if not r or len(r) != len(headers):
            continue
        if r[0].strip().upper() == headers[0]:
            continue
        if r[0].startswith('SQL>') or 'rows selected' in r[0]:
            continue
        data_rows.append(dict(zip(headers, r)))
        
    return {"success": True, "headers": headers, "rows": data_rows}

def check_sql_syntax(filepath):
    try:
        with open(filepath, 'r', encoding='utf-8', errors='replace') as f:
            content = f.read().upper()
    except Exception:
        return False, []
        
    keywords = ['DENSE_RANK', 'OVER', 'PARTITION BY', 'AVG', 'JOIN']
    found = [k for k in keywords if k in content]
    return len(found) >= 3, found

def check_departments(rows):
    valid_depts = {'FINANCE', 'IT', 'PURCHASING', 'SALES', 'SHIPPING'}
    found_depts = set()
    invalid_depts = set()
    for r in rows:
        dept = r.get('DEPARTMENT_NAME', '').strip().upper()
        if dept:
            found_depts.add(dept)
            if dept not in valid_depts:
                invalid_depts.add(dept)
    return found_depts, invalid_depts

def check_anchors(rows):
    rank_pass_count = 0
    avg_pass_count = 0
    for r in rows:
        dept = r.get('DEPARTMENT_NAME', '').strip().upper()
        rank = str(r.get('DEPT_SALARY_RANK', '')).strip()
        name = r.get('EMPLOYEE_NAME', '').strip().upper()
        sal = str(r.get('SALARY', '')).strip()
        avg_sal = str(r.get('DEPT_AVG_SALARY', '')).strip()
        
        if dept == 'FINANCE' and rank == '1':
            if name == 'NANCY GREENBERG' and sal == '12008':
                rank_pass_count += 1
            try:
                if abs(float(avg_sal) - 8601.33) < 2.0:
                    avg_pass_count += 1
            except ValueError:
                pass
                
        if dept == 'IT' and rank == '1':
            if name == 'ALEXANDER HUNOLD' and sal == '9000':
                rank_pass_count += 1
            try:
                if abs(float(avg_sal) - 5760.0) < 2.0:
                    avg_pass_count += 1
            except ValueError:
                pass
                
    return rank_pass_count >= 2, avg_pass_count >= 2

def check_ordering(rows):
    if not rows:
        return False
    is_ordered = True
    prev_dept = None
    prev_rank = -1
    for r in rows:
        dept = r.get('DEPARTMENT_NAME', '').strip().upper()
        try:
            rank = int(r.get('DEPT_SALARY_RANK', '').strip())
        except ValueError:
            continue
            
        if prev_dept is not None:
            if dept < prev_dept:
                is_ordered = False
                break
            elif dept == prev_dept:
                if rank < prev_rank:
                    is_ordered = False
                    break
        prev_dept = dept
        prev_rank = rank
    return is_ordered

def check_manager(rows):
    has_managers = False
    for r in rows:
        mgr = r.get('MANAGER_NAME', '').strip().upper()
        if mgr and mgr != 'NO MANAGER' and mgr != 'NULL':
            has_managers = True
            break
    return has_managers

def _check_gui_usage(gui_evidence):
    if not gui_evidence:
        return False, 0.0, "No GUI evidence"
    signals = 0
    details = []
    if gui_evidence.get('mru_connection_count', 0) > 0:
        signals += 1
        details.append(f"MRU:{gui_evidence['mru_connection_count']}")
    if gui_evidence.get('sqldev_oracle_sessions', 0) > 0:
        signals += 1
        details.append(f"sessions:{gui_evidence['sqldev_oracle_sessions']}")
    if gui_evidence.get('window_title_changed', False):
        signals += 1
        details.append("title_changed")
    gui_used = signals >= 2
    return gui_used, min(signals / 2, 1.0), "; ".join(details) or "No signals"

def verify_write_analytical_query(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []

    # Criterion: Check SQL file exists (5 points)
    if result.get('sql_exists') and result.get('sql_size', 0) > 20:
        score += 5
        feedback_parts.append("SQL script saved (5/5)")
    else:
        feedback_parts.append("SQL script not saved or too small (0/5)")

    # Criterion: Check SQL syntax (10 points)
    temp_sql = tempfile.NamedTemporaryFile(delete=False, suffix='.sql')
    try:
        copy_from_env("/tmp/user_script.sql", temp_sql.name)
        has_analytics, keywords = check_sql_syntax(temp_sql.name)
        if has_analytics:
            score += 10
            feedback_parts.append(f"Analytical syntax used: {','.join(keywords)} (10/10)")
        elif keywords:
            score += 5
            feedback_parts.append(f"Partial analytical syntax used: {','.join(keywords)} (5/10)")
        else:
            feedback_parts.append("No analytical syntax found (0/10)")
    except Exception:
        feedback_parts.append("Failed to check SQL syntax (0/10)")
    finally:
        if os.path.exists(temp_sql.name):
            os.unlink(temp_sql.name)

    # Output execution and verification
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env("/tmp/query_output.csv", temp_csv.name)
        parsed = parse_query_output(temp_csv.name)
    except Exception:
        parsed = {"success": False, "errors": ["Failed to copy or read query output"]}
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    if not parsed["success"]:
        feedback_parts.append(f"Execution failed: {parsed.get('errors', ['Unknown'])[0]} (0/15)")
        rows = []
    else:
        score += 15
        feedback_parts.append("Script executed without errors (15/15)")
        rows = parsed.get("rows", [])
        
        if not rows:
            feedback_parts.append("Query returned 0 rows (0/15)")
        else:
            # Criterion: Correct row count (15 pts)
            if len(rows) == 96:
                score += 15
                feedback_parts.append("Correct row count: 96 (15/15)")
            elif 90 <= len(rows) <= 100:
                score += 10
                feedback_parts.append(f"Approximate row count: {len(rows)} (10/15)")
            else:
                feedback_parts.append(f"Incorrect row count: {len(rows)} (0/15)")
                
            # Criterion: Correct department filtering (10 pts)
            found_depts, invalid_depts = check_departments(rows)
            if found_depts and not invalid_depts:
                score += 10
                feedback_parts.append("Correct department filtering (10/10)")
            elif invalid_depts:
                feedback_parts.append(f"Found invalid departments: {list(invalid_depts)[:2]} (0/10)")
                
            # Criterion: Rank and Average checks (10 pts each)
            rank_pass, avg_pass = check_anchors(rows)
            if rank_pass:
                score += 10
                feedback_parts.append("Salary rank values correct (10/10)")
            else:
                feedback_parts.append("Salary rank values incorrect (0/10)")
                
            if avg_pass:
                score += 10
                feedback_parts.append("Department average calculations correct (10/10)")
            else:
                feedback_parts.append("Department average calculations incorrect (0/10)")
                
            # Criterion: Manager details (5 pts)
            if check_manager(rows):
                score += 5
                feedback_parts.append("Manager names populated correctly (5/5)")
            else:
                feedback_parts.append("Manager names missing/incorrect (0/5)")
                
            # Criterion: Valid Sorting/Ordering (5 pts)
            if check_ordering(rows):
                score += 5
                feedback_parts.append("Results ordered correctly (5/5)")
            else:
                feedback_parts.append("Results not ordered correctly (0/5)")

    # Criterion: Check CSV export (10 pts)
    if result.get('csv_exists') and result.get('csv_size', 0) > 100:
        temp_export = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
        try:
            copy_from_env("/tmp/user_export.csv", temp_export.name)
            with open(temp_export.name, 'r', encoding='utf-8', errors='replace') as f:
                export_content = f.read().upper()
                if 'NANCY' in export_content or 'GREENBERG' in export_content or 'FINANCE' in export_content:
                    score += 10
                    feedback_parts.append("CSV export valid and contains expected data (10/10)")
                else:
                    score += 5
                    feedback_parts.append("CSV export exists but data not recognized (5/10)")
        except Exception:
            score += 5
            feedback_parts.append("CSV export exists but could not be verified (5/10)")
        finally:
            if os.path.exists(temp_export.name):
                os.unlink(temp_export.name)
    else:
        feedback_parts.append("CSV export missing or empty (0/10)")

    # Criterion: GUI Evidence (5 pts)
    gui_evidence = result.get('gui_evidence', {})
    gui_used, gui_frac, gui_msg = _check_gui_usage(gui_evidence)
    if gui_used:
        score += 5
        feedback_parts.append(f"GUI usage detected [{gui_msg}] (5/5)")
    else:
        feedback_parts.append(f"Insufficient GUI usage [{gui_msg}] (0/5)")

    passed = score >= 60 and result.get('sql_exists') and parsed.get('success', False) and len(rows) > 0

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }