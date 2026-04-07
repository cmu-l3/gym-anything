#!/usr/bin/env python3
"""Stub verifier for bio201_outcomes_assessment_migration.

Actual verification is done externally via VLM checklist evaluators.

This task requires the agent to complete an outcomes-based assessment migration
for BIO201 by reading a migration plan wiki page and bringing the course into
compliance. The migration involves:

  1. Enabling Learning Mastery Gradebook feature flags
  2. Creating/correcting 3 learning outcomes (one missing, one wrong mastery)
  3. Building a 4-criterion rubric aligned to outcomes
  4. Attaching the rubric for grading to 2 assignments
  5. Fixing assignment group weights (3 wrong values)
  6. Moving a miscategorized assignment
  7. Correcting the late submission policy (deduction + floor)
  8. Fixing a module prerequisite (Week 4 should require Week 3, not Week 2)
"""


def verify_bio201_outcomes_assessment_migration(traj, env_info, task_info):
    """Stub verifier — real verification is done via external VLM evaluation."""
    return {
        "passed": True,
        "score": 100,
        "feedback": "Stub verifier — VLM evaluation is external",
    }
