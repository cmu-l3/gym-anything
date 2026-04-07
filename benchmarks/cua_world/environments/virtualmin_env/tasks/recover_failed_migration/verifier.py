"""
Verifier stub for recover_failed_migration.

Full programmatic verification is deferred to the VLM checklist verifier.
This stub returns a pass so the VLM evaluator score is used as the real signal.
"""


def verify_recover_failed_migration(traj, env_info, task_info):
    """Stub verifier — VLM evaluation is external."""
    return {
        "passed": True,
        "score": 100,
        "feedback": "Stub verifier — VLM evaluation is external",
    }
