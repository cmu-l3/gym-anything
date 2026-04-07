#!/usr/bin/env python3
"""Offline mock tests for all 5 new oracle_sql_developer_env verifiers.

Tests do-nothing, partial, and full completion scenarios per task_creation_notes/13.
"""
import importlib.util
import json
import os
import tempfile
import sys

def load_verifier(task_name):
    """Load a verifier module from its file path."""
    path = os.path.join(os.path.dirname(__file__), task_name, 'verifier.py')
    spec = importlib.util.spec_from_file_location('verifier', path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod

def make_env(result_data):
    """Create env_info with mocked copy_from_env."""
    def copy_from_env(src, dst):
        with open(dst, 'w', encoding='utf-8') as f:
            json.dump(result_data, f)
    return {'copy_from_env': copy_from_env}

def make_env_missing():
    """Simulate result file not existing."""
    def copy_from_env(src, dst):
        raise FileNotFoundError(f"No such file: {src}")
    return {'copy_from_env': copy_from_env}

PASSED = 0
FAILED = 0

def check(condition, msg):
    global PASSED, FAILED
    if condition:
        PASSED += 1
        print(f"  PASS: {msg}")
    else:
        FAILED += 1
        print(f"  FAIL: {msg}")

# ==============================================================================
# Task 1: fiscal_period_close_reconciliation
# ==============================================================================
print("\n=== fiscal_period_close_reconciliation ===")
mod = load_verifier('fiscal_period_close_reconciliation')
task_info = {'metadata': {'result_file': '/tmp/fiscal_close_result.json'}}

# Do-nothing: file missing
r = mod.verify_fiscal_period_close_reconciliation([], make_env_missing(), task_info)
check(r['passed'] is False, f"Missing file -> passed=False (score={r['score']})")
check(r['score'] == 0, f"Missing file -> score=0 (got {r['score']})")

# Do-nothing: all errors remain (realistic: 1 unbalanced, 1 dup group, IC uneliminated)
r = mod.verify_fiscal_period_close_reconciliation([], make_env({
    'unbalanced_je_fixed': False, 'remaining_unbalanced_count': 1,
    'duplicate_je_removed': False, 'remaining_duplicate_count': 1,
    'intercompany_eliminated': False, 'pending_ic_eliminations': 3,
    'capex_reclassified': False, 'ppe_has_entry': 0,
    'trial_balance_mv_exists': False, 'trial_balance_mv_alt_exists': 0,
    'trial_balance_balances': False, 'rollup_used': False,
    'consolidated_vw_exists': False,
    'csv_exists': False, 'csv_size': 0, 'csv_has_categories': False,
    'gui_evidence': {}
}), task_info)
check(r['passed'] is False, f"Do-nothing -> passed=False (score={r['score']})")
check(r['score'] == 0, f"Do-nothing -> score=0 (got {r['score']})")

# Partial: 2 errors fixed, no views
r = mod.verify_fiscal_period_close_reconciliation([], make_env({
    'unbalanced_je_fixed': True, 'remaining_unbalanced_count': 0,
    'duplicate_je_removed': True, 'remaining_duplicate_count': 0,
    'intercompany_eliminated': False, 'pending_ic_eliminations': 1,
    'capex_reclassified': False, 'ppe_has_entry': 0,
    'trial_balance_mv_exists': False, 'trial_balance_mv_alt_exists': 0,
    'trial_balance_balances': False, 'rollup_used': False,
    'consolidated_vw_exists': False,
    'csv_exists': False, 'csv_size': 0, 'csv_has_categories': False,
    'gui_evidence': {'mru_connection_count': 1, 'sqldev_oracle_sessions': 1, 'sql_history_count': 5}
}), task_info)
check(r['passed'] is False, f"Partial (2 errors fixed) -> passed=False (score={r['score']})")
check(r['score'] > 0, f"Partial -> score>0 (got {r['score']})")

# Full completion
r = mod.verify_fiscal_period_close_reconciliation([], make_env({
    'unbalanced_je_fixed': True, 'remaining_unbalanced_count': 0,
    'duplicate_je_removed': True, 'remaining_duplicate_count': 0,
    'intercompany_eliminated': True, 'pending_ic_eliminations': 0,
    'capex_reclassified': True, 'ppe_has_entry': 1,
    'trial_balance_mv_exists': True, 'trial_balance_mv_alt_exists': 0,
    'trial_balance_balances': True, 'rollup_used': True,
    'consolidated_vw_exists': True,
    'csv_exists': True, 'csv_size': 5000, 'csv_has_categories': True,
    'gui_evidence': {'mru_connection_count': 2, 'sqldev_oracle_sessions': 3, 'sql_history_count': 15}
}), task_info)
check(r['passed'] is True, f"Full completion -> passed=True (score={r['score']})")
check(r['score'] >= 70, f"Full completion -> score>=70 (got {r['score']})")

# ==============================================================================
# Task 2: energy_portfolio_milestone_tracker
# ==============================================================================
print("\n=== energy_portfolio_milestone_tracker ===")
mod = load_verifier('energy_portfolio_milestone_tracker')
task_info = {'metadata': {'result_file': '/tmp/energy_portfolio_result.json'}}

# Do-nothing: file missing
r = mod.verify_energy_portfolio_milestone_tracker([], make_env_missing(), task_info)
check(r['passed'] is False, f"Missing file -> passed=False (score={r['score']})")

# Do-nothing: all violations remain (realistic: alerts table pre-exists but empty)
r = mod.verify_energy_portfolio_milestone_tracker([], make_env({
    'milestones_fixed_count': 0, 'total_remaining_violations': 8,
    'shepherds_flat_fixed': False, 'alta_wind_fixed': False,
    'roscoe_fixed': False, 'horse_hollow_fixed': False,
    'hierarchy_vw_exists': False, 'connect_by_used': False,
    'pivot_vw_exists': False, 'pivot_used': False,
    'scheduler_job_exists': False, 'overdue_proc_exists': False,
    'alerts_table_exists': True, 'alert_count': 0,
    'constraint_exists': False,
    'gui_evidence': {}
}), task_info)
check(r['passed'] is False, f"Do-nothing -> passed=False (score={r['score']})")
check(r['score'] == 0, f"Do-nothing -> score=0 (got {r['score']})")

# Partial: 2 projects fixed, hierarchy view done
r = mod.verify_energy_portfolio_milestone_tracker([], make_env({
    'milestones_fixed_count': 2, 'total_remaining_violations': 4,
    'shepherds_flat_fixed': True, 'alta_wind_fixed': True,
    'roscoe_fixed': False, 'horse_hollow_fixed': False,
    'hierarchy_vw_exists': True, 'connect_by_used': True,
    'pivot_vw_exists': False, 'pivot_used': False,
    'scheduler_job_exists': False, 'overdue_proc_exists': False,
    'alerts_table_exists': False, 'alert_count': 0,
    'constraint_exists': False,
    'gui_evidence': {'mru_connection_count': 1, 'sqldev_oracle_sessions': 1, 'sql_history_count': 5}
}), task_info)
check(r['passed'] is False, f"Partial (2 fixed) -> passed=False (score={r['score']})")
check(r['score'] > 0, f"Partial -> score>0 (got {r['score']})")

# Full completion
r = mod.verify_energy_portfolio_milestone_tracker([], make_env({
    'milestones_fixed_count': 4, 'total_remaining_violations': 0,
    'shepherds_flat_fixed': True, 'alta_wind_fixed': True,
    'roscoe_fixed': True, 'horse_hollow_fixed': True,
    'hierarchy_vw_exists': True, 'connect_by_used': True,
    'pivot_vw_exists': True, 'pivot_used': True,
    'scheduler_job_exists': True, 'overdue_proc_exists': True,
    'alerts_table_exists': True, 'alert_count': 3,
    'constraint_exists': True,
    'gui_evidence': {'mru_connection_count': 2, 'sqldev_oracle_sessions': 3, 'sql_history_count': 15}
}), task_info)
check(r['passed'] is True, f"Full completion -> passed=True (score={r['score']})")
check(r['score'] >= 70, f"Full completion -> score>=70 (got {r['score']})")

# ==============================================================================
# Task 3: multi_tenant_data_isolation
# ==============================================================================
print("\n=== multi_tenant_data_isolation ===")
mod = load_verifier('multi_tenant_data_isolation')
task_info = {'metadata': {'result_file': '/tmp/multi_tenant_result.json'}}

# Do-nothing: file missing
r = mod.verify_multi_tenant_data_isolation([], make_env_missing(), task_info)
check(r['passed'] is False, f"Missing file -> passed=False (score={r['score']})")

# Do-nothing: all flaws remain (SECURITY_AUDIT_LOG not pre-created after fix)
r = mod.verify_multi_tenant_data_isolation([], make_env({
    'policy_function_fixed': False, 'policy_function_valid': 1,
    'financial_policy_exists': False, 'total_vpd_policies': 1,
    'context_default_fixed': False, 'still_has_zero_default': True,
    'audit_log_table_exists': False, 'violation_vw_exists': False,
    'audit_proc_exists': False,
    'tenant1_customer_isolated': False, 'tenant2_customer_isolated': False,
    'tenant3_customer_isolated': False, 'tenant1_financial_isolated': False,
    'gui_evidence': {}
}), task_info)
check(r['passed'] is False, f"Do-nothing -> passed=False (score={r['score']})")
check(r['score'] == 0, f"Do-nothing -> score=0 (got {r['score']})")

# Partial: policy function fixed, but others not
r = mod.verify_multi_tenant_data_isolation([], make_env({
    'policy_function_fixed': True, 'policy_function_valid': 1,
    'financial_policy_exists': False, 'total_vpd_policies': 1,
    'context_default_fixed': False, 'still_has_zero_default': True,
    'audit_log_table_exists': False, 'violation_vw_exists': False,
    'audit_proc_exists': False,
    'tenant1_customer_isolated': True, 'tenant2_customer_isolated': True,
    'tenant3_customer_isolated': True, 'tenant1_financial_isolated': False,
    'gui_evidence': {'mru_connection_count': 1, 'sqldev_oracle_sessions': 1, 'sql_history_count': 5}
}), task_info)
check(r['passed'] is False, f"Partial (1 flaw fixed) -> passed=False (score={r['score']})")
check(r['score'] > 0, f"Partial -> score>0 (got {r['score']})")

# Full completion
r = mod.verify_multi_tenant_data_isolation([], make_env({
    'policy_function_fixed': True, 'policy_function_valid': 1,
    'financial_policy_exists': True, 'total_vpd_policies': 3,
    'context_default_fixed': True, 'still_has_zero_default': False,
    'audit_log_table_exists': True, 'violation_vw_exists': True,
    'audit_proc_exists': True,
    'tenant1_customer_isolated': True, 'tenant2_customer_isolated': True,
    'tenant3_customer_isolated': True, 'tenant1_financial_isolated': True,
    'gui_evidence': {'mru_connection_count': 2, 'sqldev_oracle_sessions': 3, 'sql_history_count': 15}
}), task_info)
check(r['passed'] is True, f"Full completion -> passed=True (score={r['score']})")
check(r['score'] >= 70, f"Full completion -> score>=70 (got {r['score']})")

# ==============================================================================
# Task 4: insurance_claims_fraud_detection
# ==============================================================================
print("\n=== insurance_claims_fraud_detection ===")
mod = load_verifier('insurance_claims_fraud_detection')
task_info = {'metadata': {'result_file': '/tmp/claims_fraud_result.json'}}

# Do-nothing: file missing
r = mod.verify_insurance_claims_fraud_detection([], make_env_missing(), task_info)
check(r['passed'] is False, f"Missing file -> passed=False (score={r['score']})")

# Do-nothing: nothing created (FRAUD_FLAGS not pre-created after fix)
r = mod.verify_insurance_claims_fraud_detection([], make_env({
    'package_exists': False, 'package_body_valid': False,
    'benford_function_exists': False, 'pipelined_used': False,
    'outlier_function_exists': False, 'duplicate_proc_exists': False,
    'upcoding_proc_exists': False,
    'fraud_flags_table_exists': False, 'fraud_flags_count': 0,
    'benford_flags': 0, 'outlier_flags': 0, 'duplicate_flags': 0,
    'upcoding_flags': 0, 'temporal_flags': 0,
    'fraud_summary_mv_exists': False, 'object_type_count': 0,
    'csv_exists': False, 'csv_size': 0, 'csv_has_flag_types': False,
    'gui_evidence': {}
}), task_info)
check(r['passed'] is False, f"Do-nothing -> passed=False (score={r['score']})")
check(r['score'] == 0, f"Do-nothing -> score=0 (got {r['score']})")

# Partial: package exists but no flags populated
r = mod.verify_insurance_claims_fraud_detection([], make_env({
    'package_exists': True, 'package_body_valid': True,
    'benford_function_exists': True, 'pipelined_used': True,
    'outlier_function_exists': True, 'duplicate_proc_exists': True,
    'upcoding_proc_exists': True,
    'fraud_flags_table_exists': True, 'fraud_flags_count': 0,
    'benford_flags': 0, 'outlier_flags': 0, 'duplicate_flags': 0,
    'upcoding_flags': 0, 'temporal_flags': 0,
    'fraud_summary_mv_exists': False, 'object_type_count': 2,
    'csv_exists': False, 'csv_size': 0, 'csv_has_flag_types': False,
    'gui_evidence': {'mru_connection_count': 1, 'sqldev_oracle_sessions': 1, 'sql_history_count': 5}
}), task_info)
check(r['passed'] is False, f"Partial (pkg exists, no flags) -> passed=False (score={r['score']})")
check(r['score'] > 0, f"Partial -> score>0 (got {r['score']})")

# Full completion
r = mod.verify_insurance_claims_fraud_detection([], make_env({
    'package_exists': True, 'package_body_valid': True,
    'benford_function_exists': True, 'pipelined_used': True,
    'outlier_function_exists': True, 'duplicate_proc_exists': True,
    'upcoding_proc_exists': True,
    'fraud_flags_table_exists': True, 'fraud_flags_count': 80,
    'benford_flags': 3, 'outlier_flags': 15, 'duplicate_flags': 24,
    'upcoding_flags': 20, 'temporal_flags': 15,
    'fraud_summary_mv_exists': True, 'object_type_count': 2,
    'csv_exists': True, 'csv_size': 2000, 'csv_has_flag_types': True,
    'gui_evidence': {'mru_connection_count': 2, 'sqldev_oracle_sessions': 3, 'sql_history_count': 15}
}), task_info)
check(r['passed'] is True, f"Full completion -> passed=True (score={r['score']})")
check(r['score'] >= 70, f"Full completion -> score>=70 (got {r['score']})")

# ==============================================================================
# Task 5: supply_chain_inventory_rebalance
# ==============================================================================
print("\n=== supply_chain_inventory_rebalance ===")
mod = load_verifier('supply_chain_inventory_rebalance')
task_info = {'metadata': {'result_file': '/tmp/supply_chain_result.json'}}

# Do-nothing: file missing
r = mod.verify_supply_chain_inventory_rebalance([], make_env_missing(), task_info)
check(r['passed'] is False, f"Missing file -> passed=False (score={r['score']})")

# Do-nothing: all errors remain (realistic: alerts table pre-exists but empty)
r = mod.verify_supply_chain_inventory_rebalance([], make_env({
    'demand_analysis_exists': False, 'demand_analysis_rows': 0,
    'window_functions_used': False,
    'zero_reorder_fixed': False, 'remaining_zero_reorder': 12,
    'excessive_safety_fixed': False, 'remaining_excessive_safety': 8,
    'zero_leadtime_fixed': False, 'remaining_zero_leadtime': 5,
    'inventory_forecast_exists': False, 'model_clause_used': False,
    'rebalance_vw_exists': False, 'json_used': False,
    'scheduler_job_exists': False, 'stockout_proc_exists': False,
    'alerts_table_exists': True, 'alert_count': 0,
    'eoq_used': False,
    'gui_evidence': {}
}), task_info)
check(r['passed'] is False, f"Do-nothing -> passed=False (score={r['score']})")
check(r['score'] == 0, f"Do-nothing -> score=0 (got {r['score']})")

# Partial: errors fixed but no forecast view
r = mod.verify_supply_chain_inventory_rebalance([], make_env({
    'demand_analysis_exists': True, 'demand_analysis_rows': 125,
    'window_functions_used': True,
    'zero_reorder_fixed': True, 'remaining_zero_reorder': 0,
    'excessive_safety_fixed': True, 'remaining_excessive_safety': 0,
    'zero_leadtime_fixed': True, 'remaining_zero_leadtime': 0,
    'inventory_forecast_exists': False, 'model_clause_used': False,
    'rebalance_vw_exists': False, 'json_used': False,
    'scheduler_job_exists': False, 'stockout_proc_exists': False,
    'alerts_table_exists': False, 'alert_count': 0,
    'eoq_used': True,
    'gui_evidence': {'mru_connection_count': 1, 'sqldev_oracle_sessions': 1, 'sql_history_count': 5}
}), task_info)
check(r['passed'] is False, f"Partial (errors fixed, no forecast) -> passed=False (score={r['score']})")
check(r['score'] > 0, f"Partial -> score>0 (got {r['score']})")

# Full completion
r = mod.verify_supply_chain_inventory_rebalance([], make_env({
    'demand_analysis_exists': True, 'demand_analysis_rows': 6500,
    'window_functions_used': True,
    'zero_reorder_fixed': True, 'remaining_zero_reorder': 0,
    'excessive_safety_fixed': True, 'remaining_excessive_safety': 0,
    'zero_leadtime_fixed': True, 'remaining_zero_leadtime': 0,
    'inventory_forecast_exists': True, 'model_clause_used': True,
    'rebalance_vw_exists': True, 'json_used': True,
    'scheduler_job_exists': True, 'stockout_proc_exists': True,
    'alerts_table_exists': True, 'alert_count': 5,
    'eoq_used': True,
    'gui_evidence': {'mru_connection_count': 2, 'sqldev_oracle_sessions': 3, 'sql_history_count': 15}
}), task_info)
check(r['passed'] is True, f"Full completion -> passed=True (score={r['score']})")
check(r['score'] >= 70, f"Full completion -> score>=70 (got {r['score']})")

# ==============================================================================
# Summary
# ==============================================================================
print(f"\n{'='*60}")
print(f"RESULTS: {PASSED} passed, {FAILED} failed out of {PASSED+FAILED} checks")
if FAILED > 0:
    print("SOME TESTS FAILED!")
    sys.exit(1)
else:
    print("ALL TESTS PASSED!")
    sys.exit(0)
