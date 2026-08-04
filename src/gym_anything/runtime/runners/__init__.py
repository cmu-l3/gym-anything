"""Runner implementations (parties).

Importing this package must stay cheap and platform-neutral: core imports it
for the registry and the ``BaseRunner`` contract, while party implementation
modules carry platform-specific dependencies (``fcntl`` on Unix, vendor
SDKs). Classes therefore resolve lazily (PEP 562) — importing core never
loads a party implementation, on any OS.
"""

from .base import BaseRunner

_LAZY_CLASSES = {
    "DockerRunner": ".docker",
    "LocalRunner": ".local",
    "QemuApptainerRunner": ".qemu_apptainer",
    "QemuNativeRunner": ".qemu_native",
    "ApptainerDirectRunner": ".apptainer_direct",
    "AVDApptainerRunner": ".avd_apptainer",
    "AVDNativeRunner": ".avd_native",
    "AVFRunner": ".avf",
    "UseComputerRunner": ".use_computer",
    "ModalNativeRunner": ".modal_native",
}

__all__ = ["BaseRunner", *_LAZY_CLASSES]


def __getattr__(name):
    if name in _LAZY_CLASSES:
        from importlib import import_module

        return getattr(import_module(_LAZY_CLASSES[name], __name__), name)
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")
