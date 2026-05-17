# Expert Console

A single-user web app that lets a domain expert nudge the existing
`creation_audit` and `propose_and_amplify` pipelines for Gym-Anything /
CUA-World.

The expert never edits files. They:

1. Pick a software (and optionally a task).
2. Inspect a curated view — task description, scripts, data files, audit
   verdict, evidence docs, plus a live VNC into the running env.
3. Send a short message routed to **either** the creator or the audit agent.
4. Optionally pin that message into memory (general vs software-specific) or
   propose a checklist amendment.
5. See the memory diff. Push to GitHub or hand to Discord for community
   review (planned).

The actual work is done by the **same** drivers as the automated pipeline —
`extras/research/software_as_env/creation_audit/method.py` and
`extras/research/task_generation/propose_and_amplify/method.py` — invoked as
subprocesses with the expert's note appended to a dedicated
`expert_feedback.md` memory file that both pipelines' prompts read.

## Quickstart

```bash
gym-anything-extras research expert_console serve
```

Prerequisites: `claude` on `PATH`, `OPENAI_API_KEY` (for summarization), and
the dependencies installed by the `[expert_console]` extra in `pyproject.toml`.
The server fails loud if anything is missing.

## Layout

```
extras/research/expert_console/
├── PROGRESS.md           # running build log
├── README.md             # this file
├── launch/
│   └── method.py         # `... expert_console serve` entry point
├── server/
│   ├── app.py            # FastAPI factory
│   ├── main.py           # uvicorn entry
│   ├── config.py         # settings
│   ├── db.py             # SQLAlchemy + SQLite
│   ├── models.py         # ORM models
│   ├── api/              # FastAPI routers
│   ├── services/         # inspection, summarize, memory, dispatch, vnc
│   └── schemas/          # pydantic models
├── frontend/             # Next.js + Tailwind + shadcn/ui
├── state/                # SQLite db + JSONL session log
└── tests/
    ├── backend/          # pytest
    └── e2e/              # Playwright + screenshot baselines
```

## See also

- `PROGRESS.md` — what's built and what's next
- `../software_as_env/creation_audit/` — the pipeline this console drives
- `../task_generation/propose_and_amplify/` — the other pipeline
