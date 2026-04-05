from agents.agents.base import BaseAgent
from agents.shared.prompts import CLAUDE_SYSTEM_PROMPT, CLAUDE_SYSTEM_PROMPT_CAREFUL
from agents.shared.llm_clients import call_claude, claude_parse_tool_result
from agents.shared.message_cache import add_cache_blocks
from PIL import Image
import base64
from pathlib import Path
import pickle
import logging
import os
from glob import glob
from io import BytesIO
class ClaudeAgent(BaseAgent):


    def setup_custom_logger(self):
        task_name = self.agent_args.get('task_name', 'task')
        self.save_folder_custom = f'all_runs/{self.exp_name}/{self.model}/{task_name}'
        for run_number in range(0, 100):
            if os.path.exists(f'{self.save_folder_custom}/run_{run_number}'):
                continue
            self.save_folder_custom = f'{self.save_folder_custom}/run_{run_number}'
            break
        os.makedirs(self.save_folder_custom, exist_ok=False)

    def save_observation(self, observation):
        Image.open(observation['screen']['path']).save(f'{self.save_folder_custom}/observation_{self.step_idx}.png')

    def __init__(self, *args, **kwargs):
        self.agent_args = kwargs.get('agent_args', {})
        self.model = self.agent_args.get('model', 'claude-sonnet-4-20250514')
        self.decoding_params = self.agent_args.get('decoding_params', {})

        self.exp_name = self.agent_args.get('exp_name', 'exp')
        self.setup_custom_logger()

        self.messages = []
        system_prompt_type = self.agent_args.get('system_prompt_type', 'CLAUDE_SYSTEM_PROMPT')
        self.system_prompt = eval(system_prompt_type)

        self.done = False
        self.step_idx = -1

        self.debug = kwargs.get('debug', False)
        self.verbose = kwargs.get('verbose', False)


    def init(self, task_description, display_resolution, save_path):
        self.task_description = task_description
        self.display_resolution = display_resolution
        self.save_path = save_path
        self.messages.append({"content": self.task_description, "role": "user"})


    def step(self, obs, action_outputs):

        self.save_observation(obs)

        self.step_idx += 1
        if len(action_outputs)>0:
            converted_action_outputs = self._convert_action_outputs(action_outputs)
            self.messages.append({"content": converted_action_outputs, "role": "user"})
        self.messages = add_cache_blocks(self.messages)
        response = call_claude(self.messages, self.model, self.decoding_params.get('temperature', 1.0), self.decoding_params.get('top_p', 0.95), self.decoding_params.get('thinking_budget', 8192), self.system_prompt)
        response_content = response.content
        self.messages.append({'role': 'assistant', 'content': response_content})
        actions = self._get_actions_from_response(response_content)
        if len(actions) == 0:
            self.done = True

        return actions
    
    def finish(self, *args, **kwargs):
        # TODO: Store the trajectory in the relevant folder.
        pickle.dump(self.messages, open(f'{self.save_path}/messages.pkl', 'wb'))
        pickle.dump(self.messages, open(f'{self.save_folder_custom}/messages.pkl', 'wb'))

        if 'info' in kwargs:
            info = kwargs['info']
            pickle.dump(info, open(f'{self.save_folder_custom}/info.pkl', 'wb'))

    def _get_actions_from_response(self, response_content):
        all_actions = []
        for block in response_content:
            if block.type == "thinking":
                if self.verbose:
                    print(f"Thinking: {block.thinking}")
            elif block.type == "text":
                if self.verbose:
                    print(f"Response: {block.text}")
            elif block.type == "tool_use":
                # Now, we need to parse the tool call, and create corresponding observations.
                tool_id = block.id
                action_json = block.input
                try:
                    actions = claude_parse_tool_result(action_json)
                    if len(actions) == 1 and 'action' in actions[0] and actions[0]['action'] == 'terminate':
                        self.done = True
                        continue
                    # Make sure that stop/wait logic is properly handled
                    all_actions.append({
                        'tool_id': tool_id,
                        'actions': actions
                    })
                    if self.verbose:
                        print(f"Actions: {actions} ; Tool ID: {tool_id}")
                except Exception as e:
                    self.done = True
                    print(f"Exception in claude parse tool result {e}")
                    return []
        return all_actions
    
    def _get_screenshot_tool_content(self, action_output):
        """Generate tool content for screenshot actions."""
        from PIL import Image
        
        # Load the image from the path
        image = Image.open(action_output['output'])
        
        # Resize to 1280x720
        image = image.resize((1280, 720))
        
        # Convert to base64
        buffered = BytesIO()
        image.save(buffered, format="PNG")
        encoded_string = base64.b64encode(buffered.getvalue()).decode()
        return {
            "type": "tool_result",
            "content": [
                {
                    "type": "text",
                    "text": "Here is the screenshot",
                },
                {
                    'type': 'image',
                    'source': {
                        'type': 'base64',
                        'media_type': 'image/png',
                        'data': encoded_string,
                    },
                }
            ],
            'tool_use_id': action_output['tool_id'],
            'is_error': False, # TODO: Ideally we should have this set correctly
        }
    
    def _get_other_tool_content(self, action_output):
        """Generate tool content for non-screenshot actions."""
        return {
            "type": "tool_result",
            "content": [
                {
                    "type": "text",
                    "text": "Executed the action",
                },
            ],
            'tool_use_id': action_output['tool_id'],
            'is_error': False, # TODO: Ideally we should have this set correctly
        }
    
    def _get_tool_content_from_output(self, action_output):
        """Get tool content from action output based on action type."""
        if action_output['action'] == 'screenshot':
            return self._get_screenshot_tool_content(action_output)
        else:
            return self._get_other_tool_content(action_output)
    
    def _convert_action_outputs(self, action_outputs):
        """Convert action outputs to tool call content."""
        tool_call_content = []
        for action_output in action_outputs:
            tool_content = self._get_tool_content_from_output(action_output)
            tool_call_content.append(tool_content)
        return tool_call_content