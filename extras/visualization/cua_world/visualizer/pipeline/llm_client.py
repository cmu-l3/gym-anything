"""Thin OpenAI client wrapper used by the visualizer pipeline.

Loads OPENAI_API_KEY from .env at the repo root if not already in the
environment. Exposes:

    structured_chat(model, messages, schema, *, reasoning_effort) -> dict
    embed(model, inputs) -> list[list[float]]

Both retry on transient errors (rate-limit, 5xx, network) with bounded backoff.
"""

from __future__ import annotations

import json
import logging
import os
import random
import time
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence

logger = logging.getLogger(__name__)

_ENV_LOADED = False


def _load_env_once() -> None:
    global _ENV_LOADED
    if _ENV_LOADED:
        return
    if os.environ.get("OPENAI_API_KEY"):
        _ENV_LOADED = True
        return
    try:
        from dotenv import load_dotenv
    except ImportError:
        load_dotenv = None  # type: ignore[assignment]
    here = Path(__file__).resolve()
    for ancestor in here.parents:
        candidate = ancestor / ".env"
        if candidate.is_file():
            if load_dotenv is not None:
                load_dotenv(candidate)
            else:
                # Manual minimal parse so we don't hard-require python-dotenv.
                for line in candidate.read_text(encoding="utf-8").splitlines():
                    line = line.strip()
                    if not line or line.startswith("#") or "=" not in line:
                        continue
                    k, v = line.split("=", 1)
                    os.environ.setdefault(k.strip(), v.strip().strip("'\""))
            break
    _ENV_LOADED = True


def _client():
    _load_env_once()
    from openai import OpenAI  # imported lazily so test envs don't need it
    if not os.environ.get("OPENAI_API_KEY"):
        raise RuntimeError("OPENAI_API_KEY is not set (looked in env and .env)")
    return OpenAI()


_TRANSIENT_PHRASES = (
    "rate limit",
    "rate_limit",
    "timeout",
    "temporarily",
    "overloaded",
    "503",
    "502",
    "504",
    "connection",
    "internal server error",
    "server_error",
)


def _is_transient(exc: BaseException) -> bool:
    msg = str(exc).lower()
    return any(p in msg for p in _TRANSIENT_PHRASES)


def _retry(call, *, attempts: int = 6, base: float = 1.0, cap: float = 30.0):
    last: Optional[BaseException] = None
    for i in range(attempts):
        try:
            return call()
        except Exception as exc:  # noqa: BLE001
            last = exc
            if not _is_transient(exc) and i >= 1:
                # Non-transient: try once more then propagate.
                raise
            sleep_for = min(cap, base * (2 ** i)) + random.random()
            logger.warning("transient error (%s); retrying in %.1fs (%d/%d)", exc, sleep_for, i + 1, attempts)
            time.sleep(sleep_for)
    assert last is not None
    raise last


def structured_chat(
    *,
    model: str,
    messages: Sequence[Dict[str, str]],
    schema: Dict[str, Any],
    schema_name: str,
    reasoning_effort: Optional[str] = None,
    timeout: float = 120.0,
) -> Dict[str, Any]:
    """Run a chat completion with strict JSON schema output. Returns parsed dict."""
    client = _client()

    def _call():
        kwargs: Dict[str, Any] = {
            "model": model,
            "messages": list(messages),
            "response_format": {
                "type": "json_schema",
                "json_schema": {
                    "name": schema_name,
                    "schema": schema,
                    "strict": True,
                },
            },
            "timeout": timeout,
        }
        if reasoning_effort:
            kwargs["reasoning_effort"] = reasoning_effort
        return client.chat.completions.create(**kwargs)

    resp = _retry(_call)
    msg = resp.choices[0].message
    if getattr(msg, "refusal", None):
        raise RuntimeError(f"model refused: {msg.refusal}")
    content = msg.content
    if content is None:
        raise RuntimeError("model returned no content")
    return json.loads(content)


def embed(*, model: str, inputs: Sequence[str], timeout: float = 60.0) -> List[List[float]]:
    """Embed a batch of strings. Returns list of float lists in the same order."""
    if not inputs:
        return []
    client = _client()

    def _call():
        return client.embeddings.create(model=model, input=list(inputs), timeout=timeout)

    resp = _retry(_call)
    return [item.embedding for item in resp.data]
