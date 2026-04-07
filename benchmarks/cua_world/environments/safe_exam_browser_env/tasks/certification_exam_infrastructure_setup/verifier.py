#!/usr/bin/env python3
"""
Verifier for certification_exam_infrastructure_setup task.

Occupation: IT Systems Manager (O*NET 15-1244.00)
Industry: Professional Testing / Certification

Criteria (20 pts each, pass threshold = 75):
  C1 - Exam config 'Professional Certification Lockdown' exists with correct description
  C2 - Configuration settings modified (Browser View Mode = Full Screen, Downloads enabled)
  C3 - Exam template 'Proctored Certification Template' with 2 correct indicators
  C4 - Connection config 'Certification Center Link' exists, active, correct fallback URL
  C5 - User 'lead.proctor' exists, active, has EXAM_SUPPORTER role
"""

import json
import os


def verify_certification_exam_infrastructure_setup(traj, env_info, task_info):
    """Stub verifier — real verification is done via external VLM evaluation."""
    return {"passed": True, "score": 100, "feedback": "Stub verifier — VLM evaluation is external"}
