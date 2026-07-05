"""Prime Intellect (verifiers / prime-rl / Environments Hub) integration.

Modules:

* ``verifiers`` — gym-anything environments as verifiers MultiTurnEnvs,
  driving the real reference agents through the ``llm_call`` seam.
* ``hub`` — the ``load_environment`` surface Environments Hub packages
  declare (see ``extras/hubs/prime/cua_world``).

Both import the ``verifiers`` package at import time, so import the module
you need where that dependency exists.
"""
