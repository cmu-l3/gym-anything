# Simple User Setup

Demonstrates how to create user accounts using the gym-anything Python API.

## Files

- `env.json` — environment spec using the `ubuntu-gnome` preset with a developer user account
- `example_with_python_api.py` — Python script showing `UserAccount` convenience constructors and custom user configuration

## Usage

```bash
# Run the API example (no container needed — just demonstrates the data model)
python example_with_python_api.py
```

To actually launch the environment:

```python
from gym_anything import from_config

env = from_config("examples/tutorials/simple_user_setup")
obs = env.reset()
# The developer user is provisioned inside the container
env.close()
```
