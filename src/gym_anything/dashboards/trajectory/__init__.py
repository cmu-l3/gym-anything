"""Trajectory inspection dashboard for Gym-Anything run artifacts."""


def create_app(*args, **kwargs):
    from .app import create_app as _create_app

    return _create_app(*args, **kwargs)


def main(argv=None):
    from .app import main as _main

    return _main(argv)


__all__ = ["create_app", "main"]
