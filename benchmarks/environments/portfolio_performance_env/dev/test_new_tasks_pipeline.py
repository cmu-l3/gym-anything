#!/usr/bin/env python3
"""
Pipeline simulation for the 5 new Portfolio Performance tasks.

Tests each verifier with:
1. Do-nothing (file_modified=False) → expect score=0
2. Partial completion (one subtask done) → expect partial score
3. Full completion → expect high score

No VM required — uses mock copy_from_env to inject pre-built result JSONs.
"""

import json
import os
import sys
import tempfile
import shutil
import time

# Make sure the task verifiers are importable
TASK_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "tasks")
EVIDENCE_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "evidence")
os.makedirs(EVIDENCE_DIR, exist_ok=True)

results_summary = {}


def make_copy_from_env(result_dict):
    """Factory: returns a copy_from_env function that writes result_dict to dest."""
    def copy_fn(src_path, dest_path):
        with open(dest_path, "w") as f:
            json.dump(result_dict, f, indent=2)
    return copy_fn


def run_verifier(task_name, verifier_fn_name, result_dict, task_info=None):
    """Run a verifier function with a mocked copy_from_env."""
    task_path = os.path.join(TASK_DIR, task_name)
    if task_path not in sys.path:
        sys.path.insert(0, task_path)

    # Import the verifier module
    import importlib.util
    spec = importlib.util.spec_from_file_location(
        f"verifier_{task_name}",
        os.path.join(task_path, "verifier.py")
    )
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)

    # Get the verifier function
    fn = getattr(mod, verifier_fn_name)

    env_info = {"copy_from_env": make_copy_from_env(result_dict)}
    if task_info is None:
        # Load from task.json
        with open(os.path.join(task_path, "task.json")) as f:
            task_json = json.load(f)
        task_info = task_json

    result = fn(traj=[], env_info=env_info, task_info=task_info)
    return result


# ============================================================
# TASK 1: reconcile_brokerage_statement
# ============================================================
print("\n" + "=" * 60)
print("TASK 1: reconcile_brokerage_statement")
print("=" * 60)

TASK = "reconcile_brokerage_statement"
FN = "verify_reconcile_brokerage_statement"

# Do-nothing scenario
do_nothing = {
    "portfolio_found": True, "file_modified": False,
    "initial_portfolio_txns": 2, "initial_account_txns": 1,
    "total_portfolio_txns": 2, "total_account_txns": 1,
    "new_portfolio_txns": 0, "new_account_txns": 0,
    "googl_buy_found": False, "googl_buy_shares": 0, "googl_buy_amount": 0.0,
    "aapl_sell_found": False, "aapl_sell_shares": 0, "aapl_sell_amount": 0.0,
    "new_deposit_found": False, "new_deposit_amount": 0.0,
    "all_new_portfolio_txns": []
}
r = run_verifier(TASK, FN, do_nothing)
print(f"Do-nothing:  score={r['score']}, passed={r['passed']}")
assert r['score'] == 0 and not r['passed'], f"FAIL: expected score=0, got {r['score']}"

# Partial (GOOGL BUY only)
partial = {
    "portfolio_found": True, "file_modified": True,
    "initial_portfolio_txns": 2, "initial_account_txns": 1,
    "total_portfolio_txns": 3, "total_account_txns": 1,
    "new_portfolio_txns": 1, "new_account_txns": 0,
    "googl_buy_found": True, "googl_buy_shares": 15.0, "googl_buy_amount": 2122.35, "googl_buy_date": "2024-03-08T00:00",
    "aapl_sell_found": False, "aapl_sell_shares": 0, "aapl_sell_amount": 0.0,
    "new_deposit_found": False, "new_deposit_amount": 0.0,
    "all_new_portfolio_txns": [{"type": "BUY", "sec_ticker": "GOOGL"}]
}
r = run_verifier(TASK, FN, partial)
print(f"Partial:     score={r['score']}, passed={r['passed']}")
assert 15 <= r['score'] <= 65, f"FAIL: expected partial score, got {r['score']}"

# Full completion
full = {
    "portfolio_found": True, "file_modified": True,
    "initial_portfolio_txns": 2, "initial_account_txns": 1,
    "total_portfolio_txns": 4, "total_account_txns": 2,
    "new_portfolio_txns": 2, "new_account_txns": 1,
    "googl_buy_found": True, "googl_buy_shares": 15.0, "googl_buy_amount": 2122.35, "googl_buy_date": "2024-03-08T00:00",
    "aapl_sell_found": True, "aapl_sell_shares": 3.0, "aapl_sell_amount": 566.55, "aapl_sell_date": "2024-03-20T00:00",
    "new_deposit_found": True, "new_deposit_amount": 15000.0, "new_deposit_date": "2024-03-01T00:00",
    "all_new_portfolio_txns": [
        {"type": "BUY", "sec_ticker": "GOOGL"},
        {"type": "SELL", "sec_ticker": "AAPL"}
    ]
}
r_full = run_verifier(TASK, FN, full)
print(f"Full:        score={r_full['score']}, passed={r_full['passed']}")
assert r_full['score'] >= 65 and r_full['passed'], f"FAIL: expected pass, got score={r_full['score']}"

partial_score_1 = run_verifier(TASK, FN, partial)['score']
results_summary[TASK] = {
    "task_id": "reconcile_brokerage_statement@1",
    "do_nothing_score": 0, "do_nothing_passed": False,
    "partial_score": partial_score_1,
    "full_pipeline_score": r_full['score'],
    "full_pipeline_passed": r_full['passed'],
    "notes": "Pipeline test: simulated GOOGL BUY + AAPL SELL + $15k deposit added to pre-seeded portfolio."
}
print(f"PASS: do-nothing=0, partial={results_summary[TASK]['partial_score']}, full={r_full['score']}")


# ============================================================
# TASK 2: record_quarterly_dividends
# ============================================================
print("\n" + "=" * 60)
print("TASK 2: record_quarterly_dividends")
print("=" * 60)

TASK = "record_quarterly_dividends"
FN = "verify_record_quarterly_dividends"

do_nothing = {
    "portfolio_found": True, "file_modified": False,
    "total_dividend_count": 0, "new_dividend_count": 0,
    "aapl_dividend_found": False, "aapl_dividend_amount": 0.0,
    "aapl_dividend_date": "", "aapl_linked_to_security": False,
    "msft_dividend_found": False, "msft_dividend_amount": 0.0,
    "msft_dividend_date": "", "msft_linked_to_security": False
}
r = run_verifier(TASK, FN, do_nothing)
print(f"Do-nothing:  score={r['score']}, passed={r['passed']}")
assert r['score'] == 0 and not r['passed'], f"FAIL: expected score=0, got {r['score']}"

# Partial: AAPL dividend only
partial = {
    "portfolio_found": True, "file_modified": True,
    "total_dividend_count": 1, "new_dividend_count": 1,
    "aapl_dividend_found": True, "aapl_dividend_amount": 36.00,
    "aapl_dividend_date": "2024-02-15T00:00", "aapl_linked_to_security": True,
    "msft_dividend_found": False, "msft_dividend_amount": 0.0,
    "msft_dividend_date": "", "msft_linked_to_security": False
}
r = run_verifier(TASK, FN, partial)
print(f"Partial:     score={r['score']}, passed={r['passed']}")
assert 15 <= r['score'] <= 75, f"FAIL: expected partial score, got {r['score']}"

# Full
full = {
    "portfolio_found": True, "file_modified": True,
    "total_dividend_count": 2, "new_dividend_count": 2,
    "aapl_dividend_found": True, "aapl_dividend_amount": 36.00,
    "aapl_dividend_date": "2024-02-15T00:00", "aapl_linked_to_security": True,
    "msft_dividend_found": True, "msft_dividend_amount": 56.25,
    "msft_dividend_date": "2024-03-14T00:00", "msft_linked_to_security": True
}
r_full = run_verifier(TASK, FN, full)
print(f"Full:        score={r_full['score']}, passed={r_full['passed']}")
assert r_full['score'] >= 65 and r_full['passed'], f"FAIL: expected pass, got score={r_full['score']}"

results_summary[TASK] = {
    "task_id": "record_quarterly_dividends@1",
    "do_nothing_score": 0, "do_nothing_passed": False,
    "partial_score": run_verifier(TASK, FN, partial)['score'],
    "full_pipeline_score": r_full['score'],
    "full_pipeline_passed": r_full['passed'],
    "notes": "Pipeline test: simulated AAPL $36.00 dividend (Feb 15) + MSFT $56.25 dividend (Mar 14), both linked to securities."
}
print(f"PASS: do-nothing=0, partial={results_summary[TASK]['partial_score']}, full={r_full['score']}")


# ============================================================
# TASK 3: correct_erroneous_transactions
# ============================================================
print("\n" + "=" * 60)
print("TASK 3: correct_erroneous_transactions")
print("=" * 60)

TASK = "correct_erroneous_transactions"
FN = "verify_correct_erroneous_transactions"

do_nothing = {
    "portfolio_found": True, "file_modified": False,
    "aapl_buy_found": True, "aapl_buy_amount": 4500.0, "aapl_buy_shares": 10.0,
    "aapl_buy_date": "2024-01-05T00:00", "aapl_amount_corrected": False,
    "msft_buy_found": True, "msft_buy_amount": 19536.50, "msft_buy_shares": 50.0,
    "msft_buy_date": "2024-01-16T00:00", "msft_shares_corrected": False,
    "all_portfolio_txns": []
}
r = run_verifier(TASK, FN, do_nothing)
print(f"Do-nothing:  score={r['score']}, passed={r['passed']}")
assert r['score'] == 0 and not r['passed'], f"FAIL: expected score=0, got {r['score']}"

# Partial: AAPL corrected but MSFT not
partial = {
    "portfolio_found": True, "file_modified": True,
    "aapl_buy_found": True, "aapl_buy_amount": 1811.80, "aapl_buy_shares": 10.0,
    "aapl_buy_date": "2024-01-05T00:00", "aapl_amount_corrected": True,
    "msft_buy_found": True, "msft_buy_amount": 19536.50, "msft_buy_shares": 50.0,
    "msft_buy_date": "2024-01-16T00:00", "msft_shares_corrected": False,
    "all_portfolio_txns": []
}
r = run_verifier(TASK, FN, partial)
print(f"Partial:     score={r['score']}, passed={r['passed']}")
assert 20 <= r['score'] <= 75, f"FAIL: expected partial score, got {r['score']}"

# Full
full = {
    "portfolio_found": True, "file_modified": True,
    "aapl_buy_found": True, "aapl_buy_amount": 1811.80, "aapl_buy_shares": 10.0,
    "aapl_buy_date": "2024-01-05T00:00", "aapl_amount_corrected": True,
    "msft_buy_found": True, "msft_buy_amount": 1953.65, "msft_buy_shares": 5.0,
    "msft_buy_date": "2024-01-16T00:00", "msft_shares_corrected": True,
    "all_portfolio_txns": []
}
r_full = run_verifier(TASK, FN, full)
print(f"Full:        score={r_full['score']}, passed={r_full['passed']}")
assert r_full['score'] >= 70 and r_full['passed'], f"FAIL: expected pass, got score={r_full['score']}"

results_summary[TASK] = {
    "task_id": "correct_erroneous_transactions@1",
    "do_nothing_score": 0, "do_nothing_passed": False,
    "partial_score": run_verifier(TASK, FN, partial)['score'],
    "full_pipeline_score": r_full['score'],
    "full_pipeline_passed": r_full['passed'],
    "notes": ("Pipeline test: Error 1=AAPL amount $4,500→$1,811.80; "
              "Error 2=MSFT shares 50→5. Both corrected in full scenario.")
}
print(f"PASS: do-nothing=0, partial={results_summary[TASK]['partial_score']}, full={r_full['score']}")


# ============================================================
# TASK 4: add_security_with_price_history
# ============================================================
print("\n" + "=" * 60)
print("TASK 4: add_security_with_price_history")
print("=" * 60)

TASK = "add_security_with_price_history"
FN = "verify_add_security_with_price_history"

do_nothing = {
    "portfolio_found": True, "file_modified": False,
    "initial_sec_count": 2, "initial_txn_count": 2,
    "current_sec_count": 2, "current_txn_count": 2,
    "googl_security_found": False, "googl_name": "", "googl_ticker": "",
    "googl_isin": "", "googl_currency": "", "googl_price_count": 0,
    "googl_buy_found": False, "googl_buy_date": "",
    "googl_buy_shares": 0.0, "googl_buy_amount": 0.0,
    "all_securities": []
}
r = run_verifier(TASK, FN, do_nothing)
print(f"Do-nothing:  score={r['score']}, passed={r['passed']}")
assert r['score'] == 0 and not r['passed'], f"FAIL: expected score=0, got {r['score']}"

# Partial: GOOGL added with ticker+ISIN, prices imported, but no BUY
partial = {
    "portfolio_found": True, "file_modified": True,
    "initial_sec_count": 2, "initial_txn_count": 2,
    "current_sec_count": 3, "current_txn_count": 2,
    "googl_security_found": True, "googl_name": "Alphabet Inc.",
    "googl_ticker": "GOOGL", "googl_isin": "US02079K3059",
    "googl_currency": "USD", "googl_price_count": 30,
    "googl_buy_found": False, "googl_buy_date": "",
    "googl_buy_shares": 0.0, "googl_buy_amount": 0.0,
    "all_securities": []
}
r = run_verifier(TASK, FN, partial)
print(f"Partial:     score={r['score']}, passed={r['passed']}")
assert 30 <= r['score'] <= 70, f"FAIL: expected partial score, got {r['score']}"

# Full
full = {
    "portfolio_found": True, "file_modified": True,
    "initial_sec_count": 2, "initial_txn_count": 2,
    "current_sec_count": 3, "current_txn_count": 3,
    "googl_security_found": True, "googl_name": "Alphabet Inc.",
    "googl_ticker": "GOOGL", "googl_isin": "US02079K3059",
    "googl_currency": "USD", "googl_price_count": 30,
    "googl_buy_found": True, "googl_buy_date": "2024-02-01T00:00",
    "googl_buy_shares": 20.0, "googl_buy_amount": 2829.80,
    "all_securities": []
}
r_full = run_verifier(TASK, FN, full)
print(f"Full:        score={r_full['score']}, passed={r_full['passed']}")
assert r_full['score'] >= 65 and r_full['passed'], f"FAIL: expected pass, got score={r_full['score']}"

results_summary[TASK] = {
    "task_id": "add_security_with_price_history@1",
    "do_nothing_score": 0, "do_nothing_passed": False,
    "partial_score": run_verifier(TASK, FN, partial)['score'],
    "full_pipeline_score": r_full['score'],
    "full_pipeline_passed": r_full['passed'],
    "notes": ("Pipeline test: simulated Alphabet Inc. (GOOGL, US02079K3059) added with 30 prices, "
              "BUY 20 shares @ $141.49 on 2024-02-01.")
}
print(f"PASS: do-nothing=0, partial={results_summary[TASK]['partial_score']}, full={r_full['score']}")


# ============================================================
# TASK 5: export_securities_transactions
# ============================================================
print("\n" + "=" * 60)
print("TASK 5: export_securities_transactions")
print("=" * 60)

TASK = "export_securities_transactions"
FN = "verify_export_securities_transactions"

do_nothing = {
    "csv_exists": False,
    "csv_path": "",
    "file_created_after_start": False,
    "row_count": 0, "data_row_count": 0,
    "has_header": False, "column_count": 0,
    "has_aapl": False, "has_msft": False,
    "has_buy_transactions": False, "has_sell_transactions": False,
    "sample_rows": [], "parse_error": "CSV not found"
}
r = run_verifier(TASK, FN, do_nothing)
print(f"Do-nothing:  score={r['score']}, passed={r['passed']}")
assert r['score'] == 0 and not r['passed'], f"FAIL: expected score=0, got {r['score']}"

# Partial: CSV exists but only has AAPL (not MSFT)
partial = {
    "csv_exists": True,
    "csv_path": "/home/ga/Documents/PortfolioData/portfolio_trades.csv",
    "file_created_after_start": True,
    "row_count": 4, "data_row_count": 3,
    "has_header": True, "column_count": 6,
    "has_aapl": True, "has_msft": False,
    "has_buy_transactions": True, "has_sell_transactions": True,
    "sample_rows": [], "parse_error": ""
}
r = run_verifier(TASK, FN, partial)
print(f"Partial:     score={r['score']}, passed={r['passed']}")
assert 30 <= r['score'] <= 80, f"FAIL: expected partial score, got {r['score']}"

# Full
full = {
    "csv_exists": True,
    "csv_path": "/home/ga/Documents/PortfolioData/portfolio_trades.csv",
    "file_created_after_start": True,
    "row_count": 7, "data_row_count": 6,
    "has_header": True, "column_count": 7,
    "has_aapl": True, "has_msft": True,
    "has_buy_transactions": True, "has_sell_transactions": True,
    "sample_rows": [], "parse_error": ""
}
r_full = run_verifier(TASK, FN, full)
print(f"Full:        score={r_full['score']}, passed={r_full['passed']}")
assert r_full['score'] >= 60 and r_full['passed'], f"FAIL: expected pass, got score={r_full['score']}"

results_summary[TASK] = {
    "task_id": "export_securities_transactions@1",
    "do_nothing_score": 0, "do_nothing_passed": False,
    "partial_score": run_verifier(TASK, FN, partial)['score'],
    "full_pipeline_score": r_full['score'],
    "full_pipeline_passed": r_full['passed'],
    "notes": ("Pipeline test: simulated portfolio_trades.csv with 6 data rows "
              "(3 AAPL + 3 MSFT buy/sell transactions), 7 columns.")
}
print(f"PASS: do-nothing=0, partial={results_summary[TASK]['partial_score']}, full={r_full['score']}")


# ============================================================
# Save evidence JSON files
# ============================================================
print("\n" + "=" * 60)
print("SAVING EVIDENCE")
print("=" * 60)

for task_name, summary in results_summary.items():
    evidence = {
        "task": task_name,
        "test_date": time.strftime("%Y-%m-%d"),
        "methodology": "Pipeline simulation: verifier.py run with mock copy_from_env against manually-crafted result JSONs",
        "pipeline_results": {
            "do_nothing": {"score": summary["do_nothing_score"], "passed": summary["do_nothing_passed"]},
            "partial": {"score": summary["partial_score"]},
            "full": {"score": summary["full_pipeline_score"], "passed": summary["full_pipeline_passed"]}
        },
        "notes": summary["notes"]
    }
    path = os.path.join(EVIDENCE_DIR, f"{task_name}_evidence.json")
    with open(path, "w") as f:
        json.dump(evidence, f, indent=2)
    print(f"  Saved: {path}")

print("\n" + "=" * 60)
print("ALL PIPELINE TESTS PASSED")
print("=" * 60)
for task, data in results_summary.items():
    print(f"  {task}: do_nothing=0, full={data['full_pipeline_score']}/100 (pass={data['full_pipeline_passed']})")
