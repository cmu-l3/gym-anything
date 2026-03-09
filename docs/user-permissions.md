# User Permissions

Gym-Anything has a `user_accounts` model in `EnvSpec`, and the supported behavior is runner-dependent.

## Current Reality

The spec supports:

- multiple users
- role labels
- group membership
- sudo flags
- home-directory settings
- per-user limits
- environment variables

The release-facing contract is documented in [Compatibility Checklist](compatibility.md).

## Runtime Fields

Recognized user fields:

- `name`
- `password`
- `uid`
- `gid`
- `role`
- `permissions`

Recognized permission fields:

- `sudo`
- `sudo_nopasswd`
- `shell`
- `groups`
- `primary_group`
- `home_dir`
- `home_permissions`
- `create_home`
- `login_shell`
- `system_user`
- `network_access`
- `max_processes`
- `max_memory`
- `env_vars`

## Example

```json
{
  "user_accounts": [
    {
      "name": "ga",
      "password": "password123",
      "role": "developer",
      "permissions": {
        "sudo": true,
        "sudo_nopasswd": true,
        "groups": ["sudo", "audio", "video", "input"],
        "shell": "/bin/bash",
        "env_vars": {
          "DISPLAY": ":1"
        }
      }
    }
  ]
}
```

## Convenience Constructors

The Python dataclasses provide:

- `UserAccount.admin_user(...)`
- `UserAccount.developer_user(...)`
- `UserAccount.guest_user(...)`
- `UserAccount.service_user(...)`

These are useful when constructing env specs programmatically.

## Recommendation

If your benchmark depends on real user creation semantics, verify it on the exact runner you intend to use and check the runner mode in [Compatibility Checklist](compatibility.md). Do not assume the presence of `user_accounts` in JSON is enough.
