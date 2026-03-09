# Evidence Documentation

This folder contains evidence from actual agent task runs.

## Purpose

Evidence files here are generated from real agent executions to demonstrate:
1. Task start states are correct
2. Verifiers correctly detect success/failure
3. The environment works as designed

## Structure

```
evidence/
├── create_blog_post/     # Evidence from create_blog_post task runs
│   ├── initial.png       # Screenshot at task start
│   ├── final.png         # Screenshot at task end
│   └── result.json       # Verification result
├── edit_page/            # Evidence from edit_page task runs
│   └── ...
├── create_user/          # Evidence from create_user task runs
│   └── ...
└── README.md             # This file
```

## How Evidence is Generated

Evidence is captured automatically during task execution:
1. `setup_task.sh` captures initial state
2. Agent performs task actions
3. `export_result.sh` captures final state and verification data
4. Verifier produces result.json with pass/fail and score

## Current Status

Evidence files will be populated from successful agent runs. Check `artifacts/` folder for raw episode data from all runs (including failures).

## Related Folders

- `../docs/example_workflow_docs/` - Staged screenshots showing expected workflow (for documentation only)
- `artifacts/` - Raw episode data from actual agent runs
