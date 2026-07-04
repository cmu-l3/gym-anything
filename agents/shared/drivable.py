"""Drivable-agent capability marker.

An agent that mixes this in declares that an external loop which OWNS the
model call (e.g. a prime-rl trainer sampling the policy itself) can drive its
real ``step()`` verbatim. The contract is:

  * ``step()`` routes its model call through ``self.llm_call`` (see
    ``BaseAgent.llm_call``) instead of calling a client directly, and makes
    exactly one such call per step.
  * The messages passed to ``self.llm_call`` are OpenAI chat format.

The external loop injects its own ``llm_call`` and runs the unmodified agent,
so the driven harness and the local harness are the same code by construction
(``gym_anything.integrations.verifiers`` is the loop that does this).

Provider-native agents (Anthropic/Google/Azure native tools) do not mix this
in: their model call cannot be served over an OpenAI policy endpoint.
"""

from __future__ import annotations


class DrivableAgentMixin:
    """Marks an agent as drivable through the ``llm_call`` seam."""

    driven = True


__all__ = ["DrivableAgentMixin"]
