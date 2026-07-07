"""Harbor (laude-institute/harbor) integration.

Modules:

* ``environment`` — ``GymAnythingEnvironment``, Harbor's BaseEnvironment on
  top of the gym-anything runner stack (the ``--env`` fast path).
* ``compile`` — compile benchmark tasks into Harbor task directories
  (dual-shape: stock docker and the custom backend).
* ``container`` — the in-container runtime docker-shaped tasks boot
  (entrypoint ``serve`` + the ``finalize`` CLI ``tests/test.sh`` calls).
  Must not import ``harbor``.
* ``agent`` — ``CuaWorldAgent``, runs a reference agent loop with a driver
  per environment shape and records ATIF trajectories.

The re-exports below keep Harbor's ``module:Class`` import paths short::

    --env gym_anything.integrations.harbor:GymAnythingEnvironment
    --agent-import-path gym_anything.integrations.harbor:CuaWorldAgent

``environment`` and ``agent`` import the ``harbor`` package, so the
re-exports resolve lazily (PEP 562): importing this package or its
harbor-free modules (``compile``, ``container``) never requires harbor.
"""

__all__ = ["CuaWorldAgent", "GymAnythingEnvironment"]

_LAZY = {
    "CuaWorldAgent": "agent",
    "GymAnythingEnvironment": "environment",
}


def __getattr__(name: str):
    module_name = _LAZY.get(name)
    if module_name is None:
        raise AttributeError(f"module {__name__!r} has no attribute {name!r}")
    from importlib import import_module

    return getattr(import_module(f".{module_name}", __name__), name)
