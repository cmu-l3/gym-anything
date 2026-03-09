from baselines.agents.qwen3vl_memory_agent import Qwen3VLMemoryAgent


class Qwen3VLMemoryAgentCustomSys(Qwen3VLMemoryAgent):
    """
    Qwen3VL Memory agent with custom system prompt appended.

    Inherits all functionality from Qwen3VLMemoryAgent but allows appending
    custom instructions (e.g., actionable insights) to the system prompt.

    Usage:
        agent_args = {
            'model': 'qwen3-vl',
            'system_prompt_append': 'Your custom instructions here...',
            ...
        }
    """

    def __init__(self, *args, **kwargs):
        # Call parent constructor to initialize everything
        super().__init__(*args, **kwargs)

        # Extract the custom system prompt append from agent_args
        self.system_prompt_append = self.agent_args.get('system_prompt_append', '')

    def get_system_prompt(self):
        """Get the parent system prompt and append custom instructions."""
        # Get the base system prompt from parent
        system_prompt = super().get_system_prompt()

        # Append custom instructions if provided
        if self.system_prompt_append:
            system_prompt += "\n\n## Important Points to follow for each step:\n" + self.system_prompt_append
            print('System prompt appended with: ', self.system_prompt_append)
        return system_prompt
