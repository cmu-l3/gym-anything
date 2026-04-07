#!/usr/bin/env python3
# Stub verifier for build_court_docket_system task.
# Actual verification is done externally via VLM checklist evaluators.
#
# The VLM checklist should verify:
#
# 1. DIRECTORY & FILES (10 pts):
#    - docket_manager/ directory created under Talon user dir
#    - Contains docket_manager.py, case_types.talon-list, docket.talon
#
# 2. PYTHON MODULE STRUCTURE (20 pts):
#    - docket_manager.py imports from talon (Module, Context, actions, app)
#    - Defines mod = Module() and ctx = Context()
#    - Registers user.docket_cases list via mod.list()
#    - Has @mod.action_class with four action methods:
#      docket_lookup, docket_by_judge, docket_continue, docket_summary
#
# 3. CSV DATA PROCESSING (20 pts):
#    - Reads court_docket.csv using csv module
#    - Builds dynamic list from case numbers (hyphens stripped as keys)
#    - Loads/parses the next_hearing datetime field for sorting
#
# 4. DOCKET_BY_JUDGE OUTPUT (20 pts):
#    - Filters cases by judge last name (case-insensitive partial match)
#    - Groups filtered cases by courtroom
#    - Sorts each group by next_hearing time
#    - Writes formatted docket sheet to Documents/docket_<judge>_<YYYYMMDD>.txt
#    - Output includes header, per-courtroom sections, and total case count
#
# 5. DOCKET_CONTINUE LOGIC (15 pts):
#    - Finds case by case_number in CSV data
#    - Updates next_hearing to new_date
#    - Sets status to "Continued"
#    - Re-sorts all cases by next_hearing
#    - Overwrites the CSV file preserving structure
#    - Refreshes the dynamic user.docket_cases list
#
# 6. TALON-LIST FILE (5 pts):
#    - case_types.talon-list has correct list: user.case_types header
#    - Contains all 8 mappings: felony/FL, misdemeanor/MS, civil/CV,
#      family/FM, traffic/TR, juvenile/JV, probation violation/PV,
#      restraining order/RO
#
# 7. TALON VOICE COMMANDS (10 pts):
#    - docket.talon has four voice commands:
#      pull case <user.docket_cases>
#      docket for judge <user.text>
#      continue case <user.docket_cases> to <user.text>
#      docket summary
#    - Commands correctly invoke the corresponding user.docket_* actions


def verify_build_court_docket_system(traj, env_info, task_info):
    """Stub verifier - VLM evaluation is external."""
    return {
        "passed": True,
        "score": 100,
        "feedback": "Stub verifier - VLM checklist evaluation is external"
    }
