from agents.agents.base import BaseAgent
from agents.agents.image_pipeline import ImagePipelineMixin
from agents.shared.drivable import DrivableAgentMixin
from agents.shared.llm_clients import parse_qwen3vl_response
from PIL import Image
import json
import os
import copy
import time
import numpy as np


class CustomJSONEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, np.bool_):
            return bool(obj)
        # Let the base class default method raise the TypeError for other unhandled types
        return json.JSONEncoder.default(self, obj)


class Qwen3VLAgent(ImagePipelineMixin, DrivableAgentMixin, BaseAgent):
    """
    Qwen3VL agent using Qwen vision-language models via OpenAI-compatible API.
    Maintains a history-based prompting approach with image preprocessing.
    """
    
    def __init__(self, *args, **kwargs):
        self.agent_args = kwargs.get('agent_args', {})
        self.model = self.agent_args.get('model', 'qwen3-vl')
        # TODO: Fix this confusion
        self.decoding_params = self.agent_args.get('decoding_params', {})
        # self.temperature = self.decoding_params.get('temperature', 1.0)
        self.temperature = self.agent_args.get('temperature', 1.0)

        self.top_p = self.decoding_params.get('top_p', 0.95)
        self.top_k = self.decoding_params.get('top_k', 20)
        self.max_tokens = self.decoding_params.get('max_tokens', 1500)
        self.history_n = self.agent_args.get('history_n', 1)
        
        # Setup custom save folder
        self.exp_name = self.agent_args.get('exp_name', 'exp')
        self.setup_custom_logger()
        
        # Agent state
        self.done = False
        self.step_idx = -1
        
        # History for prompting (previous actions descriptions)
        self.history = []
        
        # Store processed screenshots and responses for multi-turn conversation
        self.screenshots = []
        self.responses = []
        
        # Store all responses for final dump
        self.all_model_responses = []
        self.all_parsed_responses = []

        # Mapping from base64 to file path for efficient message saving
        self.b64_to_path = {}

        self.debug = kwargs.get('debug', False)
        self.verbose = kwargs.get('verbose', False)
        self._init_image_pipeline()
    
    def setup_custom_logger(self):
        """Setup custom save folder for agent artifacts."""
        task_name = self.agent_args.get('task_name', 'task')
        self.save_folder_custom = f'all_runs/{self.exp_name}/{self.model}/{task_name}'
        for run_number in range(0, 1000):
            if os.path.exists(f'{self.save_folder_custom}/run_{run_number}'):
                continue
            self.save_folder_custom = f'{self.save_folder_custom}/run_{run_number}'
            break
        os.makedirs(self.save_folder_custom, exist_ok=False)
    
    def save_observation(self, observation):
        """Save the current observation screenshot."""
        Image.open(observation['screen']['path']).save(
            f'{self.save_folder_custom}/observation_{self.step_idx}.png'
        )

    def save_messages(self, messages):
        """Save the messages to a file with base64 replaced by file paths."""
        messages_to_save = copy.deepcopy(messages)

        # Replace base64 data with file paths
        for msg in messages_to_save:
            if msg.get('role') != 'user' or not isinstance(msg.get('content'), list):
                continue
            for content in msg['content']:
                if content.get('type') != 'image_url':
                    continue
                image_url = content.get('image_url')
                if image_url is None:
                    image_uuid = content.get('uuid')
                    if image_uuid in self.uuid_to_path:
                        content['image_url'] = {
                            "url": self.uuid_to_path[image_uuid],
                            "cached": True,
                        }
                    continue
                url = image_url.get('url', '') if isinstance(image_url, dict) else ''
                if 'base64,' in url:
                    b64 = url.split('base64,')[1]
                    if b64 in self.b64_to_path:
                        content['image_url']['url'] = self.b64_to_path[b64]

        with open(f'{self.save_folder_custom}/messages_step_{self.step_idx}.json', 'w') as f:
            json.dump(messages_to_save, f, indent=2)
    
    def init(self, task_description, display_resolution, save_path):
        """Initialize agent with task description and environment details."""
        self.task_description = task_description
        self.display_resolution = display_resolution
        self.save_path = save_path
    
    def build_messages(self, current_screenshot_b64):
        """
        Build the messages list for LLM call, including history if available.
        """
        # System prompt
        system_prompt = self.get_system_prompt()
        
        # Instruction prompt
        current_step = self.step_idx + 1
        history_start_idx = max(0, current_step - self.history_n)
        
        previous_actions = []
        # for i in range(history_start_idx, len(self.history)):
        for i in range(history_start_idx):
            previous_actions.append(f"Step {i+1}: {self.history[i]}")
        previous_actions_str = (
            "\n".join(previous_actions) if previous_actions else "None"
        )
        if self.verbose:
            print('Len of previous actions: ', len(previous_actions))
        
        instruction_prompt = f"""Please generate the next move according to the UI screenshot, instruction and previous actions.

Instruction: {self.task_description}

Previous actions:
{previous_actions_str}"""
        
        messages = [
            {
                "role": "system",
                "content": [
                    {"type": "text", "text": system_prompt},
                ],
            }
        ]
        
        # Add conversation history if available
        history_len = min(self.history_n, len(self.responses))
        if history_len > 0:
            history_responses = self.responses[-history_len:]
            history_screenshots = self.screenshots[-history_len - 1:-1]
            history_uuids = self.screenshot_uuids[-history_len - 1:-1]
            
            for idx in range(history_len):
                if idx < len(history_screenshots):
                    screenshot_b64 = history_screenshots[idx]
                    screenshot_uuid = history_uuids[idx] if idx < len(history_uuids) else None
                    if idx == 0:
                        # First turn includes the instruction
                        messages.append({
                            "role": "user",
                            "content": [
                                self._image_content(
                                    screenshot_b64,
                                    include_bytes=False,
                                    image_uuid=screenshot_uuid,
                                ),
                                {"type": "text", "text": instruction_prompt},
                            ],
                        })
                    else:
                        # Subsequent turns only include screenshot
                        messages.append({
                            "role": "user",
                            "content": [
                                self._image_content(
                                    screenshot_b64,
                                    include_bytes=False,
                                    image_uuid=screenshot_uuid,
                                )
                            ],
                        })
                
                # Add assistant response
                messages.append({
                    "role": "assistant",
                    "content": [
                        {"type": "text", "text": f"{history_responses[idx]}"},
                    ],
                })
            
            # Add current screenshot
            messages.append({
                "role": "user",
                "content": [
                    self._image_content(
                        current_screenshot_b64,
                        include_bytes=True,
                        image_uuid=self.screenshot_uuids[-1] if self.screenshot_uuids else None,
                    ),
                    # {"type": "text", "text": instruction_prompt},
                ],
            })
        else:
            # First turn
            messages.append({
                "role": "user",
                "content": [
                    self._image_content(
                        current_screenshot_b64,
                        include_bytes=True,
                        image_uuid=self.screenshot_uuids[-1] if self.screenshot_uuids else None,
                    ),
                    {"type": "text", "text": instruction_prompt},
                ],
            })
        
        return messages
    
    def get_system_prompt(self):
        """Get the system prompt for Qwen3VL (single source: agents/shared/qwen_computer_use.py)."""
        from agents.shared.qwen_computer_use import qwen_system_prompt

        return qwen_system_prompt(tuple(self.display_resolution))

    def step(self, obs, action_outputs):
        """
        Execute one agent step.
        
        Args:
            obs: Current observation from environment
            action_outputs: List of outputs from previous actions (not used for Qwen3VL agent)
        
        Returns:
            List of action groups to execute
        """
        self.step_idx += 1

        # Process image and save to disk (also saves as observation)
        step_timing = {}
        step_start = time.perf_counter()

        t0 = time.perf_counter()
        processed_image_b64, processed_path = self.process_image(obs['screen'])
        step_timing["process_observation_ms"] = (time.perf_counter() - t0) * 1000.0
        self._remember_screenshot(processed_image_b64)

        # Store mapping for efficient message saving
        self.b64_to_path[processed_image_b64] = processed_path
        
        # Build messages
        t0 = time.perf_counter()
        messages = self.build_messages(processed_image_b64)
        step_timing["build_messages_ms"] = (time.perf_counter() - t0) * 1000.0


        # Save messages with file paths instead of base64
        t0 = time.perf_counter()
        self.save_messages(messages)
        step_timing["save_messages_ms"] = (time.perf_counter() - t0) * 1000.0

        # Call LLM
        if self.verbose:
            print(f"Calling LLM with temperature: {self.temperature}")
        t0 = time.perf_counter()
        response = self.llm_call(
            messages,
            self.model,
            self.temperature,
            self.top_p,
            self.top_k,
            # self.max_tokens
        )
        step_timing["llm_call_ms"] = (time.perf_counter() - t0) * 1000.0
        
        
        # Store response for history
        self.responses.append(response)
        
        # Parse response using existing parse_owl_response function
        t0 = time.perf_counter()
        parsed_response = parse_qwen3vl_response(response)
        step_timing["parse_response_ms"] = (time.perf_counter() - t0) * 1000.0
        
        t0 = time.perf_counter()
        # Store responses for later dumping
        self.all_model_responses.append(response)
        self.all_parsed_responses.append(parsed_response)
        
        # Extract actions and metadata
        actions = parsed_response['actions']
        metadata = parsed_response['metadata']
        
        # Update history with conclusion
        self.history.append(metadata['conclusion'])
        
        if self.verbose:
            print(f"Step {self.step_idx + 1}:")
            print(f"  Thought: {metadata['thought']}")
            print(f"  Conclusion: {metadata['conclusion']}")
            print(f"  Action Type: {metadata['action_type']}")
            print(f"  Actions: {actions}")
        step_timing["postprocess_ms"] = (time.perf_counter() - t0) * 1000.0
        step_timing["total_ms"] = (time.perf_counter() - step_start) * 1000.0
        step_timing["llm_response_chars"] = len(response or "")
        step_timing["actions_count"] = len(actions)
        self.last_step_timing = step_timing
        
        # Check if terminal
        if metadata['is_terminal']:
            self.done = True
            return [{
                'tool_id': f'qwen3vl_step_{self.step_idx}',
                'actions': actions,  # Empty list from parse_owl_response
                'metadata': metadata
            }]
        
        # Check if wait action
        if metadata['wait_time'] is not None:
            return [{
                'tool_id': f'qwen3vl_step_{self.step_idx}',
                'actions': [{'action': 'wait', 'time': metadata['wait_time']}],
                'metadata': metadata
            }]
        
        # Regular actions (mouse, keyboard, etc.)
        return [{
            'tool_id': f'qwen3vl_step_{self.step_idx}',
            'actions': actions,
            'metadata': metadata
        }]
    
    def finish(self, *args, **kwargs):
        """Save all agent artifacts."""
        self._wait_for_image_saves()

        # Save responses as JSON
        json.dump(
            {
                'model_responses': self.all_model_responses, 
                'parsed_responses': self.all_parsed_responses
            }, 
            open(f'{self.save_path}/responses.json', 'w'), 
            indent=4
        )
        
        json.dump(
            self.all_parsed_responses, 
            open(f'{self.save_path}/parsed_responses.json', 'w'), 
            indent=4
        )
        
        # Also save to custom folder
        json.dump(
            {
                'model_responses': self.all_model_responses, 
                'parsed_responses': self.all_parsed_responses,
                'history': self.history
            }, 
            open(f'{self.save_folder_custom}/responses.json', 'w'), 
            indent=4
        )
        
        json.dump(
            self.all_parsed_responses, 
            open(f'{self.save_folder_custom}/parsed_responses.json', 'w'), 
            indent=4
        )
        
        # Save info if provided
        if 'info' in kwargs:
            info = kwargs['info']
            try:
                json.dump(info, open(f'{self.save_folder_custom}/info.json', 'w'), indent=4)
            except Exception as e:
                json.dump(info, open(f'{self.save_folder_custom}/info.json', 'w'), indent=4, cls=CustomJSONEncoder)
