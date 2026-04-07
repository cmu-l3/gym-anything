#!/usr/bin/env python3
"""
Verifier for Debug Distributed Payment System task.

Checks whether the agent fixed the five injected bugs:
1. Float arithmetic -> Decimal in payment_processor.py
2. Inverted FX rate in currency_converter.py
3. Missing MAX_TRANSACTION_LIMIT check in transaction_validator.py
4. Reversed debit/credit for liability accounts in ledger.py
5. Case-sensitive idempotency key comparison in idempotency.py

Each bug fix is worth 20 points (total 100, pass threshold 60).
"""

import sys
import os
import json
import re
import logging
import tempfile
import shutil

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_payment_system(traj, env_info, task_info):
    """
    Verify that the agent found and fixed all five payment-system bugs.

    Returns:
        dict: {"passed": bool, "score": int, "feedback": str}
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_dir = tempfile.mkdtemp(prefix='payment_verify_')

    try:
        result_src = "/tmp/payment_system_result.json"
        local_result = os.path.join(temp_dir, "payment_system_result.json")

        try:
            copy_from_env(result_src, local_result)
        except Exception as e:
            logger.error(f"Failed to copy result file: {e}")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Could not access result file: {str(e)}"
            }

        if not os.path.exists(local_result) or os.path.getsize(local_result) == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Result file not found or empty"
            }

        with open(local_result, 'r') as f:
            file_contents = json.load(f)

        score = 0
        feedback = []

        # ── Bug 1: Decimal precision (payment_processor.py) ──────────
        pp_content = file_contents.get("services/payment_processor.py", "")
        if pp_content.startswith("ERROR"):
            feedback.append("[-] payment_processor.py: file could not be read")
        else:
            uses_decimal = (
                'Decimal' in pp_content
                or 'decimal.Decimal' in pp_content
            )
            still_uses_float = (
                'float(transaction' in pp_content
                or re.search(r'float\s*\(\s*transaction', pp_content)
                or 'float(amount' in pp_content
            )
            if uses_decimal and not still_uses_float:
                score += 20
                feedback.append("[+] payment_processor.py: Decimal precision fix applied (20/20)")
            elif uses_decimal and still_uses_float:
                score += 10
                feedback.append("[~] payment_processor.py: Decimal imported but float() still used (10/20)")
            else:
                feedback.append("[-] payment_processor.py: still uses float arithmetic for money (0/20)")

        # ── Bug 2: Inverse FX rate (currency_converter.py) ───────────
        cc_content = file_contents.get("services/currency_converter.py", "")
        if cc_content.startswith("ERROR"):
            feedback.append("[-] currency_converter.py: file could not be read")
        else:
            # Look at the inverse branch: should contain division, not multiplication
            # We search for the pattern after the inverse_key branch
            inverse_branch = ""
            lines = cc_content.split('\n')
            in_inverse = False
            for line in lines:
                if 'inverse_key' in line and 'in self.RATES' in line:
                    in_inverse = True
                    continue
                if in_inverse:
                    inverse_branch += line + '\n'
                    if 'return' in line:
                        break

            has_division = bool(re.search(r'(amount\s*/\s*rate|1\s*/\s*rate|1/rate|/\s*rate)', inverse_branch))
            has_multiply_bug = bool(re.search(r'amount\s*\*\s*rate', inverse_branch))

            if has_division and not has_multiply_bug:
                score += 20
                feedback.append("[+] currency_converter.py: inverse FX rate fixed (20/20)")
            elif has_division:
                score += 10
                feedback.append("[~] currency_converter.py: division present but multiply also remains (10/20)")
            else:
                feedback.append("[-] currency_converter.py: still multiplies by rate on inverse conversion (0/20)")

        # ── Bug 3: Amount limit validation (transaction_validator.py) ─
        tv_content = file_contents.get("services/transaction_validator.py", "")
        if tv_content.startswith("ERROR"):
            feedback.append("[-] transaction_validator.py: file could not be read")
        else:
            has_limit_check = bool(
                re.search(r'MAX_TRANSACTION_LIMIT', tv_content)
                and (
                    re.search(r'amount\s*(>|>=)\s*MAX_TRANSACTION_LIMIT', tv_content)
                    or re.search(r'amount\s*>\s*1000000', tv_content)
                    or re.search(r'MAX_TRANSACTION_LIMIT\s*(<|<=)\s*amount', tv_content)
                    or re.search(r'amount\s*<=\s*MAX_TRANSACTION_LIMIT', tv_content)
                    or re.search(r'not.*amount\s*<=\s*MAX_TRANSACTION_LIMIT', tv_content)
                )
            )
            has_type_or_negative_fix = bool(
                re.search(r'(isinstance|type\(|int\(|float\(|try|except|<=\s*0|<\s*0|not.*>\s*0)', tv_content)
            )
            if has_limit_check:
                score += 20
                feedback.append("[+] transaction_validator.py: MAX_TRANSACTION_LIMIT check added (20/20)")
            else:
                feedback.append("[-] transaction_validator.py: missing MAX_TRANSACTION_LIMIT enforcement (0/20)")

        # ── Bug 4: Account-type-aware ledger (ledger.py) ──────────────
        lg_content = file_contents.get("services/ledger.py", "")
        if lg_content.startswith("ERROR"):
            feedback.append("[-] ledger.py: file could not be read")
        else:
            # Strip comments before checking to avoid false positives on BUG markers
            lg_code_lines = [l for l in lg_content.split('\n') if not l.strip().startswith('#')]
            lg_code = '\n'.join(lg_code_lines)
            # The fix should include conditional logic distinguishing liability from asset
            has_account_type_branch = bool(
                re.search(r"(account_type|entry\.account_type)\s*==\s*['\"]liability['\"]", lg_code)
                or re.search(r"['\"]liability['\"]\s*(==|in)", lg_code)
                or re.search(r"if\s+.*['\"]liability['\"]", lg_code, re.IGNORECASE)
            )
            if has_account_type_branch:
                score += 20
                feedback.append("[+] ledger.py: account-type-aware debit/credit logic added (20/20)")
            else:
                feedback.append("[-] ledger.py: debit/credit logic still ignores account type (0/20)")

        # ── Bug 5: Case-insensitive idempotency (idempotency.py) ─────
        id_content = file_contents.get("services/idempotency.py", "")
        if id_content.startswith("ERROR"):
            feedback.append("[-] idempotency.py: file could not be read")
        else:
            has_case_normalize = bool(
                re.search(r'\.(lower|casefold|upper)\s*\(\s*\)', id_content)
            )
            if has_case_normalize:
                score += 20
                feedback.append("[+] idempotency.py: case-insensitive key comparison applied (20/20)")
            else:
                feedback.append("[-] idempotency.py: key comparison is still case-sensitive (0/20)")

        # ── Final result ──────────────────────────────────────────────
        passed = score >= 60
        feedback.append(f"\nTotal score: {score}/100 ({'PASS' if passed else 'FAIL'}, threshold 60)")

        return {
            "passed": passed,
            "score": score,
            "feedback": "\n".join(feedback)
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)
