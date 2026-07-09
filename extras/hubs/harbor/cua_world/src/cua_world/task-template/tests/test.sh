#!/bin/bash
# Grades the episode via the in-container gym-anything runtime: runs the
# task's real pipeline (post_task export hook + verifier.py) against the
# guest VM and writes /logs/verifier/reward.json for Harbor's Verifier.
# On the gym-anything custom backend this script is not executed: the
# backend intercepts the invocation and runs the same pipeline host-side.
exec python -m gym_anything.integrations.harbor.container finalize \
  --reward-path /logs/verifier/reward.json \
  --verifier-path /logs/verifier/verifier.json
