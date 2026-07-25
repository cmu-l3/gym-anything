#!/bin/bash
set -euo pipefail

# A real VM boot starts with an empty tmpfs at /run. Modal filesystem
# checkpoints otherwise preserve stale PID files and per-application mount
# namespaces there, which cannot be re-entered after the old VM has stopped.
mount -t tmpfs -o mode=0755,nosuid,nodev tmpfs /run

# acpid.path continuously retriggers when systemd runs in a PID/mount namespace:
# /etc/acpi/events is non-empty, while acpid.service is skipped because nested
# systemd detects container virtualization. ACPI is not usable in a Modal VM
# Sandbox guest namespace, so keep all three activation units masked.
ln -sfn /dev/null /etc/systemd/system/acpid.path
ln -sfn /dev/null /etc/systemd/system/acpid.service
ln -sfn /dev/null /etc/systemd/system/acpid.socket

exec /sbin/init
