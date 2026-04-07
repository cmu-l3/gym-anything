"""
Verifier stub for PRL Computational Model Fitting task.
Actual verification is performed externally via VLM checklist verifier.
"""


def verify_prl_computational_model_fitting(trajectory, env_info, task_info):
    """
    Stub verifier — returns passed.

    The VLM checklist verifier evaluates:
    - Whether PRL-999 was excluded using data-driven criteria
    - Whether single-rate RW model was fitted via grid search for all 14 valid participants
    - Whether dual-rate RW model was fitted via grid search for all 14 valid participants
    - Whether AIC model comparison was performed correctly
    - Whether output JSON has correct structure with per-participant parameters
    - Whether group_summary contains mean parameters and model preference counts
    """
    return {"passed": True, "score": 1.0}
