#!/usr/bin/env python3
"""
Verifier for the migrate_express_to_typescript task.

Validates:
1. tsconfig.json exists and is configured strictly (10 pts)
2. All 11 .js files in src/ have been renamed to .ts (15 pts)
3. Compilation succeeds: `npx tsc --noEmit` exits with 0 (25 pts)
4. TypeScript Interfaces for Book and User are defined (15 pts)
5. `any` usage is minimal (<= 2 instances) (10 pts)
6. package.json contains required typescript dependencies (10 pts)
7. Core logic preservation and type signature presence (15 pts)

Total: 100 points. Pass threshold: 60.
"""

import sys
import os
import json
import re
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_migration(traj, env_info, task_info):
    """
    Verify the TypeScript migration.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_dir = tempfile.mkdtemp(prefix='ts_migrate_verify_')
    
    try:
        result_src = "/tmp/migration_result.json"
        local_result = os.path.join(temp_dir, "migration_result.json")
        
        try:
            copy_from_env(result_src, local_result)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not access result file: {str(e)}"}
            
        if not os.path.exists(local_result) or os.path.getsize(local_result) == 0:
            return {"passed": False, "score": 0, "feedback": "Result file not found or empty"}
            
        with open(local_result, 'r') as f:
            data = json.load(f)

        score = 0
        feedback = []
        
        # ── 1. Check tsconfig.json (10 pts) ──────────────────────────────────
        tsconfig_content = data.get("tsconfig_json")
        if not tsconfig_content or "ERROR" in tsconfig_content:
            feedback.append("[-] tsconfig.json is missing")
        else:
            # Check for strict mode and esModuleInterop
            has_strict = re.search(r'"strict"\s*:\s*true', tsconfig_content)
            has_interop = re.search(r'"esModuleInterop"\s*:\s*true', tsconfig_content)
            
            if has_strict and has_interop:
                score += 10
                feedback.append("[+] tsconfig.json has strict and esModuleInterop enabled (10/10)")
            elif has_strict:
                score += 5
                feedback.append("[~] tsconfig.json is strict, but missing esModuleInterop (5/10)")
            else:
                feedback.append("[-] tsconfig.json exists but is not strictly configured (0/10)")

        # ── 2. Check File Conversions (15 pts) ───────────────────────────────
        js_count = data.get("js_file_count", -1)
        ts_count = data.get("ts_file_count", 0)
        
        if js_count == 0 and ts_count >= 11:
            score += 15
            feedback.append(f"[+] All .js files migrated ({ts_count} .ts files) (15/15)")
        elif js_count == 0 and ts_count > 0:
            score += 10
            feedback.append(f"[~] No .js files, but only {ts_count} .ts files found (expected ~11) (10/15)")
        elif js_count > 0 and ts_count > 0:
            score += 5
            feedback.append(f"[-] Partial migration: {js_count} .js files remain, {ts_count} .ts files (5/15)")
        else:
            feedback.append(f"[-] Migration failed: {js_count} .js files, {ts_count} .ts files (0/15)")

        # ── 3. Check Compilation (25 pts) ────────────────────────────────────
        tsc_exit_code = data.get("tsc_exit_code", -1)
        tsc_output = data.get("tsc_output", "")
        
        if tsc_exit_code == 0:
            score += 25
            feedback.append("[+] TypeScript compilation succeeded with zero errors (25/25)")
        elif tsc_exit_code != -1:
            # Count errors roughly by "error TS"
            error_count = tsc_output.count("error TS")
            if error_count < 5:
                score += 10
                feedback.append(f"[~] TypeScript compiled with a few errors ({error_count} found) (10/25)")
            else:
                feedback.append(f"[-] TypeScript compilation failed with many errors ({error_count} found) (0/25)")
        else:
            feedback.append("[-] TypeScript compilation did not execute successfully (0/25)")

        # Gather all TS source content for static analysis
        source_files = data.get("source_files", {})
        all_ts_content = ""
        modified_files = 0
        for path, info in source_files.items():
            all_ts_content += "\n" + info.get("content", "")
            if info.get("modified_during_task", False):
                modified_files += 1

        # Anti-gaming: Ensure files were actually modified during task
        if modified_files == 0 and ts_count > 0:
            feedback.append("[!] WARNING: TS files were not modified during this task. Possible gaming.")
            return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

        # ── 4. Interface Definitions (15 pts) ────────────────────────────────
        has_book_interface = re.search(r'interface\s+Book\b|type\s+Book\s*=', all_ts_content)
        has_user_interface = re.search(r'interface\s+User\b|type\s+User\s*=', all_ts_content)
        
        if has_book_interface and has_user_interface:
            score += 15
            feedback.append("[+] Explicit Book and User interfaces defined (15/15)")
        elif has_book_interface or has_user_interface:
            score += 7
            feedback.append("[~] Only one of the expected interfaces defined (7/15)")
        else:
            feedback.append("[-] Required model interfaces (Book, User) missing (0/15)")

        # ── 5. Minimal Any Usage (10 pts) ────────────────────────────────────
        # Regex looks for `: any` or `as any` or `<any>`
        any_matches = re.findall(r'(?::\s*any\b|\b[aA]s\s+any\b|<\s*any\s*>)', all_ts_content)
        any_count = len(any_matches)
        
        if any_count <= 2:
            score += 10
            feedback.append(f"[+] Minimal `any` usage detected (count: {any_count}) (10/10)")
        elif any_count <= 5:
            score += 5
            feedback.append(f"[~] Moderate `any` usage detected (count: {any_count}) (5/10)")
        else:
            feedback.append(f"[-] Excessive `any` usage detected (count: {any_count}) (0/10)")

        # ── 6. package.json Updates (10 pts) ─────────────────────────────────
        pkg_content = data.get("package_json", "")
        if "typescript" in pkg_content and "@types/express" in pkg_content:
            score += 10
            feedback.append("[+] package.json contains required TypeScript dependencies (10/10)")
        elif "typescript" in pkg_content:
            score += 5
            feedback.append("[~] package.json has typescript, but missing some @types (5/10)")
        else:
            feedback.append("[-] package.json missing typescript dependency (0/10)")

        # ── 7. Explicit Typings & Core Logic Preservation (15 pts) ───────────
        # Ensure we didn't just delete all the code.
        # Original logic has 'books.push', 'uuidv4', 'jwt.verify'
        has_core_logic = 'books.push' in all_ts_content and 'jwt.verify' in all_ts_content
        
        # Look for explicit express typings (Request, Response, NextFunction)
        has_express_types = re.search(r':\s*Request\b|:\s*Response\b|:\s*NextFunction\b', all_ts_content)
        
        if has_core_logic and has_express_types:
            score += 15
            feedback.append("[+] Core business logic preserved and Express handler types added (15/15)")
        elif has_core_logic:
            score += 7
            feedback.append("[~] Core business logic preserved, but Express types missing (7/15)")
        else:
            feedback.append("[-] Core business logic appears to be missing or deleted (0/15)")

        pass_threshold = task_info.get("metadata", {}).get("pass_threshold", 60)
        passed = score >= pass_threshold
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback)
        }
        
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)