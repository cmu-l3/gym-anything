#!/usr/bin/env python3
"""
Interactive test script for odoo_scheduling_env.
Run with: python3 benchmarks/environments/odoo_scheduling_env/dev/test_env.py
"""
import sys
import os
import time

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))))

import gym_anything
from gym_anything.runners.vnc_utils import VNCConnection

ENV_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EVIDENCE_DIR = os.path.join(ENV_DIR, "evidence")


def screenshot(vnc_port, path):
    vnc = VNCConnection("localhost", vnc_port, password="password")
    vnc.connect()
    data = vnc.capture_screenshot()
    with open(path, "wb") as f:
        f.write(data)
    print(f"Screenshot: {path}")


def ssh_run(ssh, cmd, timeout=30):
    _, stdout, stderr = ssh.exec_command(cmd, timeout=timeout)
    out = stdout.read().decode().strip()
    err = stderr.read().decode().strip()
    return out, err


def main():
    print("=== Odoo Scheduling Env — Fresh Test ===")
    print("Resetting from post_start cache (runs pre_task: Firefox + login + Calendar)...")

    env = gym_anything.api.from_config(ENV_DIR, task_id="create_meeting")
    obs = env.reset(seed=42, use_cache=True, cache_level="post_start", use_savevm=True)
    print("Reset complete (pre_task ran: Firefox launched, logged in, navigated to Calendar).")

    vnc_port = env._runner.vnc_port
    ssh_port = env._runner.ssh_port
    print(f"VNC: {vnc_port}, SSH: {ssh_port}")

    import paramiko
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect('localhost', port=ssh_port, username='ga', password='password123',
                look_for_keys=False)

    print("\n--- Docker containers ---")
    out, _ = ssh_run(ssh, "sudo docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'")
    print(out)

    print("\n--- Odoo health ---")
    out, _ = ssh_run(ssh, "curl -sf http://localhost:8069/web/health && echo 'OK' || echo 'FAIL'")
    print(out)

    print("\n--- Firefox running? ---")
    out, _ = ssh_run(ssh, "pgrep firefox 2>/dev/null | wc -l")
    print(f"Firefox processes: {out}")
    assert int(out.strip()) >= 1, "FAIL: Firefox should be running after pre_task!"
    print("PASS: Firefox is running after pre_task")

    print("\n--- Window title ---")
    out, _ = ssh_run(ssh, "DISPLAY=:1 xdotool getactivewindow getwindowname 2>/dev/null || echo N/A")
    print(f"Title: {out}")
    assert "Meetings" in out or "Calendar" in out or "Odoo" in out, \
        f"FAIL: Expected Odoo Calendar window, got: {out}"
    print("PASS: Odoo Calendar window is active")

    print("\n--- Calendar events ---")
    out, _ = ssh_run(ssh, """python3 -c "
import xmlrpc.client
url='http://localhost:8069'; db='odoo_scheduling'
c=xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
uid=c.authenticate(db,'admin','admin',{})
m=xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')
evts=m.execute_kw(db,uid,'admin','calendar.event','search_read',[[]], {'fields':['name','start'],'limit':25})
print(f'Total events: {len(evts)}')
for e in evts: print(f'  {e[\"id\"]}: {e[\"name\"]}')
" """)
    print(out)

    print("\n--- Alice Johnson events ---")
    out, _ = ssh_run(ssh, """python3 -c "
import xmlrpc.client
url='http://localhost:8069'; db='odoo_scheduling'
c=xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
uid=c.authenticate(db,'admin','admin',{})
m=xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')
alice=m.execute_kw(db,uid,'admin','res.partner','search',[[['name','=','Alice Johnson']]])
if alice:
    evts=m.execute_kw(db,uid,'admin','calendar.event','search_read',
        [[['partner_ids','in',alice]]], {'fields':['name'],'limit':20})
    print(f'Alice events: {len(evts)}')
    for e in evts: print(f'  {e[\"name\"]}')
else:
    print('Alice not found')
" """)
    print(out)

    # Screenshot of task start state
    time.sleep(3)
    screenshot(vnc_port, os.path.join(EVIDENCE_DIR, "screenshot_task_start_firefox.png"))
    print("Task-start screenshot saved (should show Firefox with Odoo Calendar/Meetings)")

    ssh.close()
    print("\n=== Test complete ===")
    return env, vnc_port, ssh_port


if __name__ == "__main__":
    env, vnc_port, ssh_port = main()
    print(f"\nEnv running: VNC={vnc_port}, SSH={ssh_port}")
    input("Press Enter to close...")
    env.close()
