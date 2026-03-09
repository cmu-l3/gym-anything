#!/usr/bin/env python3
"""
Example showing how to create user accounts using the Python API and convenience methods.
"""

import gym_anything
from gym_anything.specs import UserAccount, UserPermissions

# Example 1: Using convenience methods
admin_user = UserAccount.admin_user("admin", "admin123")
dev_user = UserAccount.developer_user("developer", "dev123") 
guest_user = UserAccount.guest_user("guest", "guest123")
service_user = UserAccount.service_user("backup_service")

print("Created users using convenience methods:")
print(f"Admin: {admin_user.name} (sudo: {admin_user.permissions.sudo})")
print(f"Developer: {dev_user.name} (groups: {dev_user.permissions.groups})")
print(f"Guest: {guest_user.name} (max_processes: {guest_user.permissions.max_processes})")
print(f"Service: {service_user.name} (system: {service_user.permissions.system_user})")

# Example 2: Custom user configuration
custom_user = UserAccount(
    name="researcher",
    password="research123",
    uid=2000,
    role="researcher",
    permissions=UserPermissions(
        sudo=True,
        sudo_nopasswd=False,
        groups=["docker", "audio", "video", "research"],
        shell="/bin/zsh",  # Different shell
        max_processes=200,
        max_memory="2G",
        env_vars={
            "RESEARCH_MODE": "active",
            "DATA_PATH": "/data/research",
            "JUPYTER_CONFIG_DIR": "/home/researcher/.jupyter"
        }
    )
)

print(f"\nCustom user: {custom_user.name}")
print(f"  Shell: {custom_user.permissions.shell}")
print(f"  Memory limit: {custom_user.permissions.max_memory}")
print(f"  Environment vars: {list(custom_user.permissions.env_vars.keys())}")

# Example 3: Programmatically create environment config
config = {
    "id": "research.environment@1.0",
    "base": "ubuntu-gnome",
    "user_accounts": [
        # Convert UserAccount objects to dict format
        {
            "name": admin_user.name,
            "password": admin_user.password,
            "uid": admin_user.uid,
            "role": admin_user.role,
            "permissions": {
                "sudo": admin_user.permissions.sudo,
                "sudo_nopasswd": admin_user.permissions.sudo_nopasswd,
                "groups": admin_user.permissions.groups,
                "shell": admin_user.permissions.shell,
            }
        },
        {
            "name": custom_user.name,
            "password": custom_user.password,  
            "uid": custom_user.uid,
            "role": custom_user.role,
            "permissions": {
                "sudo": custom_user.permissions.sudo,
                "sudo_nopasswd": custom_user.permissions.sudo_nopasswd,
                "groups": custom_user.permissions.groups,
                "shell": custom_user.permissions.shell,
                "max_processes": custom_user.permissions.max_processes,
                "max_memory": custom_user.permissions.max_memory,
                "env_vars": custom_user.permissions.env_vars,
            }
        }
    ],
    "vnc": {"enable": True, "host_port": 5940}
}

print(f"\nGenerated config with {len(config['user_accounts'])} users")
print("Ready to create environment with:")
print(f"  - {config['user_accounts'][0]['name']} (admin)")
print(f"  - {config['user_accounts'][1]['name']} (researcher)")

# To actually run this environment:
# env_spec = gym_anything.specs.EnvSpec.from_dict(config)
# env = gym_anything.GymAnythingEnv(env_spec)
# env.reset()
