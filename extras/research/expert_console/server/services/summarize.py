"""Summarization service — turns scripts and JSON into plain English
for non-CS domain experts.

Uses OpenAI's GPT-5.4 with reasoning effort `medium`. Caches by
content hash on disk so repeat reads of the same artifact are free.

Fail loud: API errors propagate as `SummarizationError`. There is no
fallback summary — the API endpoint that calls this surfaces the
error to the frontend so the expert sees what went wrong.
"""

from __future__ import annotations

import enum
import hashlib
import json
import logging
import os
import time
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Protocol

from ..config import Settings


logger = logging.getLogger("expert_console.summarize")


# ----------------------------------------------------------------------
# Result types
# ----------------------------------------------------------------------


class SummaryKind(str, enum.Enum):
    """Drives which prompt template runs."""

    SCRIPT = "script"
    VERIFIER = "verifier"
    TASK_SPEC = "task_spec"
    ENV_SPEC = "env_spec"
    AUDIT = "audit"
    VLM_CHECKLIST = "vlm_checklist"
    EVIDENCE = "evidence"
    DATA = "data"
    GENERIC = "generic"


@dataclass
class SummaryResult:
    summary: str
    bullets: list[str]
    cached: bool
    model: str
    reasoning_effort: str

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


class SummarizationError(RuntimeError):
    """Summarization failed — surface to the caller. No fallback."""


# ----------------------------------------------------------------------
# Backend protocol
# ----------------------------------------------------------------------


class OpenAIBackend(Protocol):
    """The narrow surface we need from `openai`. Tests inject a stub."""

    def respond(
        self,
        *,
        model: str,
        reasoning_effort: str,
        system: str,
        user: str,
        timeout: float,
    ) -> str:
        ...


class _RealOpenAIBackend:
    def __init__(self) -> None:
        api_key = os.environ.get("OPENAI_API_KEY")
        if not api_key:
            raise SummarizationError(
                "OPENAI_API_KEY is not set. The summarization service "
                "requires it. Export the key and restart."
            )
        from openai import OpenAI

        self._client = OpenAI(api_key=api_key)

    def respond(
        self,
        *,
        model: str,
        reasoning_effort: str,
        system: str,
        user: str,
        timeout: float,
    ) -> str:
        try:
            response = self._client.responses.create(
                model=model,
                reasoning={"effort": reasoning_effort},
                input=[
                    {"role": "system", "content": system},
                    {"role": "user", "content": user},
                ],
                timeout=timeout,
            )
        except Exception as exc:  # pragma: no cover (real network path)
            raise SummarizationError(
                f"OpenAI Responses API call failed: {exc}"
            ) from exc
        text = getattr(response, "output_text", None)
        if not text:
            raise SummarizationError(
                f"OpenAI Responses API returned no output_text. "
                f"response={response!r}"
            )
        return text


# ----------------------------------------------------------------------
# Prompt templates
# ----------------------------------------------------------------------


_SYSTEM_PROMPT = """You are a technical writer translating low-level
artifacts (shell scripts, Python verifiers, JSON specs, audit reports)
into plain English for a domain expert who is NOT a software engineer.

The expert is using a console to review computer-use environments
built for AI agents in fields like medicine, education, engineering,
and law. **Data quality is their primary concern** — they need to
know exactly what data the environment uses, where it came from, how
big it is, and whether it's realistic for the domain.

Hard rules:
- Lead with a one-paragraph plain-English summary. **If the artifact
  references data, the data is the headline of the summary** — what
  it is, where it came from, scale.
- Then give 3-7 short bullet points covering the concrete things
  the artifact does. **At least one bullet must be a "Data" bullet
  whenever the artifact touches any data** (datasets, fixtures, seed
  records, downloads, CSV files, database rows, image corpora, etc).
  In the Data bullet, name explicitly:
    * what kind of data (e.g. "patient records", "stock-trade ticks",
      "satellite scenes", "legal filings")
    * the source — verbatim URL or named dataset (e.g.
      "https://nces.ed.gov/programs/digest/2023/", "SEC EDGAR
      10-K filings", "Synthea v3.2.0 1k-patient sample")
    * format / size if discoverable (e.g. "CSV, 52,708 rows", "FITS,
      ~120 MB", "JSONL, 8.4M entries")
    * whether it appears real vs synthetic / demo / placeholder.
  If the data source is unclear, vague, or appears synthetic, **say
  that explicitly** — domain experts care about this above everything.
- Never invent details. If the artifact references external data,
  name the source as it appears in the artifact, verbatim.
- If the artifact appears buggy, incomplete, or contains placeholders,
  flag it explicitly in one of the bullets.
- Respond as a JSON object with exactly the keys `summary` (string)
  and `bullets` (array of short strings, ideally <= 22 words each).
"""


_KIND_PROMPTS: dict[SummaryKind, str] = {
    SummaryKind.SCRIPT: (
        "This artifact is a shell or Python script that installs or "
        "configures software inside a computer-use environment. "
        "Lead the summary with the **data** the script handles — what "
        "data sources it pulls from (URLs / dataset names), what it "
        "seeds into the application, and the scale (record counts, file "
        "sizes, byte sizes). Then cover services started and notable "
        "configuration. Domain experts read this to verify the env uses "
        "real, production-realistic data — flag explicitly if you see "
        "`np.random`, `fake.*`, hardcoded Python lists, single-row "
        "fixtures, or anything that looks like demo / placeholder data."
    ),
    SummaryKind.VERIFIER: (
        "This artifact is a verifier — a Python function that decides "
        "whether an AI agent successfully completed a task. Explain "
        "in plain English which conditions the verifier checks, what "
        "files or database entries it inspects, and how scoring works. "
        "Call out any data the verifier reads (file paths, query "
        "results, downloaded artifacts) and whether the comparison "
        "values look real or hardcoded."
    ),
    SummaryKind.TASK_SPEC: (
        "This artifact is a task.json — the specification of a single "
        "task an AI agent must complete inside an environment. "
        "Explain in plain English what the agent is asked to do, the "
        "starting state guarantees, the timeout/step budget, and how "
        "success is judged. **If the task description references data "
        "(names, IDs, datasets), state where that data comes from — "
        "is it real public data, is it Odoo/LMS demo data, or is it "
        "fabricated?** Domain experts read this to verify realism."
    ),
    SummaryKind.ENV_SPEC: (
        "This artifact is an env.json — the specification of a "
        "computer-use environment that wraps a real software "
        "application. Explain in plain English what software the "
        "environment hosts, what runner/base image it uses, what "
        "resources it requests, and what hooks run at startup. Mention "
        "any data fixtures mounted into the env (look at the `mounts` "
        "block) and what dataset(s) those represent if discoverable."
    ),
    SummaryKind.AUDIT: (
        "This artifact is an automated audit report on a computer-use "
        "environment built by an AI agent. Explain in plain English "
        "what the auditor found — what passed, what failed, and what "
        "the critical issues are. Be specific about findings."
    ),
    SummaryKind.VLM_CHECKLIST: (
        "This artifact is a VLM checklist used to verify whether an "
        "AI agent completed a task correctly. Explain in plain English "
        "what each checklist item asks the verifier to confirm, what "
        "the integrity guards are, and what privileged information "
        "the verifier has access to."
    ),
    SummaryKind.EVIDENCE: (
        "This artifact is an evidence file captured while building a "
        "computer-use environment. Explain in plain English what it "
        "shows or claims, and how reliable it appears to be."
    ),
    SummaryKind.DATA: (
        "This artifact is a data file used by a computer-use "
        "environment. The expert is reviewing the env's data-quality "
        "specifically, so be precise: "
        "  (1) state what the data IS (e.g. 'patient demographics + "
        "ICD-10 codes', 'historical S&P 600 ticker close prices', "
        "'EU Common European Crawl extract'); "
        "  (2) state where it came from — verbatim citation from any "
        "header, README, comment, or schema (URL, DOI, paper, regulatory "
        "filing); "
        "  (3) state scale — rows / records / sample size / byte size; "
        "  (4) say plainly whether it looks **real** (a recognisable "
        "public dataset) or **synthetic / generated / placeholder** "
        "(hand-coded values, faker output, np.random, single-row "
        "fixtures). Domain experts care about (4) above all else."
    ),
    SummaryKind.GENERIC: (
        "Explain this artifact in plain English for a domain expert."
    ),
}


def kind_from_artifact(
    name: str, role: str | None, kind_hint: str | None
) -> SummaryKind:
    """Map an inspection-service Artifact to a summarization kind."""
    role = role or ""
    if role == "verifier":
        return SummaryKind.VERIFIER
    if role == "vlm_checklist":
        return SummaryKind.VLM_CHECKLIST
    if role == "task_spec":
        return SummaryKind.TASK_SPEC
    if role == "env_spec":
        return SummaryKind.ENV_SPEC
    if role == "evidence":
        return SummaryKind.EVIDENCE
    if role == "data":
        return SummaryKind.DATA
    if role in {"install_script", "setup_script", "task_setup", "task_export", "script"}:
        return SummaryKind.SCRIPT
    if name.lower().startswith("audit_") and name.lower().endswith(".md"):
        return SummaryKind.AUDIT
    if kind_hint == "shell" or kind_hint == "python":
        return SummaryKind.SCRIPT
    return SummaryKind.GENERIC


# ----------------------------------------------------------------------
# Service
# ----------------------------------------------------------------------


class SummarizationService:
    def __init__(
        self,
        settings: Settings,
        backend: OpenAIBackend | None = None,
        preferences: "PreferencesService | None" = None,
    ) -> None:
        self.settings = settings
        self.cache_dir = settings.state_dir / "summaries"
        self.cache_dir.mkdir(parents=True, exist_ok=True)
        self._backend: OpenAIBackend | None = backend
        self._preferences = preferences

    @property
    def model(self) -> str:
        return self._current().summarize_model

    @property
    def reasoning_effort(self) -> str:
        return self._current().summarize_reasoning_effort

    @property
    def timeout(self) -> int:
        return self._current().summarize_timeout_sec

    def _current(self):
        if self._preferences is None:
            # Lazy import keeps the module independent of preferences in
            # tests that don't bind a service.
            from .preferences import PreferencesService

            self._preferences = PreferencesService(self.settings)
        return self._preferences.get()

    @property
    def backend(self) -> OpenAIBackend:
        if self._backend is None:
            self._backend = _RealOpenAIBackend()
        return self._backend

    # ------------------------------------------------------------------
    # Public
    # ------------------------------------------------------------------

    def summarize_text(
        self,
        *,
        content: str,
        kind: SummaryKind,
        artifact_label: str,
        force: bool = False,
    ) -> SummaryResult:
        if not content.strip():
            raise SummarizationError(
                f"Cannot summarize empty artifact: {artifact_label}"
            )
        key = self._cache_key(content=content, kind=kind, label=artifact_label)
        cache_path = self.cache_dir / f"{key}.json"
        if not force and cache_path.is_file():
            try:
                raw = json.loads(cache_path.read_text(encoding="utf-8"))
                return SummaryResult(
                    summary=raw["summary"],
                    bullets=list(raw["bullets"]),
                    cached=True,
                    model=raw.get("model", self.model),
                    reasoning_effort=raw.get("reasoning_effort", self.reasoning_effort),
                )
            except (OSError, json.JSONDecodeError, KeyError) as exc:
                raise SummarizationError(
                    f"Corrupt summary cache at {cache_path}: {exc}"
                ) from exc

        user_prompt = self._build_user_prompt(
            kind=kind, label=artifact_label, content=content
        )
        started = time.time()
        raw_text = self.backend.respond(
            model=self.model,
            reasoning_effort=self.reasoning_effort,
            system=_SYSTEM_PROMPT,
            user=user_prompt,
            timeout=float(self.timeout),
        )
        elapsed = time.time() - started
        logger.info(
            "summarize kind=%s label=%s took=%.2fs", kind.value, artifact_label, elapsed
        )

        summary, bullets = self._parse_response(raw_text)
        result = SummaryResult(
            summary=summary,
            bullets=bullets,
            cached=False,
            model=self.model,
            reasoning_effort=self.reasoning_effort,
        )
        self._write_cache(cache_path, result, raw_text=raw_text)
        return result

    # ------------------------------------------------------------------
    # Internals
    # ------------------------------------------------------------------

    def _build_user_prompt(
        self, *, kind: SummaryKind, label: str, content: str
    ) -> str:
        kind_instruction = _KIND_PROMPTS[kind]
        return (
            f"Artifact label: {label}\n"
            f"Artifact kind: {kind.value}\n\n"
            f"{kind_instruction}\n\n"
            f"Respond with a JSON object: "
            f'{{"summary": "...", "bullets": ["...", "..."]}}\n\n'
            f"Artifact content (verbatim, may be truncated):\n"
            f"---\n{content}\n---"
        )

    def _parse_response(self, text: str) -> tuple[str, list[str]]:
        cleaned = text.strip()
        # Some reasoning models wrap JSON in ```json fences — strip them.
        if cleaned.startswith("```"):
            cleaned = cleaned.split("\n", 1)[1] if "\n" in cleaned else cleaned[3:]
            if cleaned.rstrip().endswith("```"):
                cleaned = cleaned.rstrip()[:-3]
        try:
            data = json.loads(cleaned)
        except json.JSONDecodeError as exc:
            raise SummarizationError(
                f"Summarizer did not return valid JSON. Got: {text!r}"
            ) from exc
        summary = data.get("summary")
        bullets = data.get("bullets")
        if not isinstance(summary, str) or not summary.strip():
            raise SummarizationError(
                f"Summarizer JSON missing 'summary' string: {data!r}"
            )
        if not isinstance(bullets, list) or not all(isinstance(b, str) for b in bullets):
            raise SummarizationError(
                f"Summarizer JSON missing 'bullets' list of strings: {data!r}"
            )
        return summary.strip(), [b.strip() for b in bullets if b.strip()]

    def _cache_key(
        self, *, content: str, kind: SummaryKind, label: str
    ) -> str:
        h = hashlib.sha256()
        h.update(self.model.encode("utf-8"))
        h.update(b"\x00")
        h.update(self.reasoning_effort.encode("utf-8"))
        h.update(b"\x00")
        h.update(kind.value.encode("utf-8"))
        h.update(b"\x00")
        h.update(label.encode("utf-8"))
        h.update(b"\x00")
        h.update(content.encode("utf-8", errors="replace"))
        return h.hexdigest()

    def _write_cache(
        self, path: Path, result: SummaryResult, *, raw_text: str
    ) -> None:
        payload = {
            "summary": result.summary,
            "bullets": result.bullets,
            "model": result.model,
            "reasoning_effort": result.reasoning_effort,
            "raw": raw_text,
            "created_at": time.time(),
        }
        tmp = path.with_suffix(".tmp")
        tmp.write_text(json.dumps(payload, indent=2), encoding="utf-8")
        tmp.replace(path)


__all__ = [
    "SummarizationService",
    "SummarizationError",
    "SummaryKind",
    "SummaryResult",
    "OpenAIBackend",
    "kind_from_artifact",
]
