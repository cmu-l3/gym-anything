from agents.agents.base import BaseAgent
from agents.shared.llm_clients import call_llm, smart_resize, parse_qwen3vl_response
from agents.agents.kimi import KimiAzureAgent
from PIL import Image
import json
import os
import copy
from io import BytesIO
import base64
import numpy as np


class CustomJSONEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, np.bool_):
            return bool(obj)
        # Let the base class default method raise the TypeError for other unhandled types
        return json.JSONEncoder.default(self, obj)


class KimiDistillAgent(KimiAzureAgent):
    """
    Kimi Azure agent with prompt aligned to osworld implementation.
    Uses relative coordinate scaling (1000x1000 grid) and osworld-matching action enum.
    """

    def __init__(self, *args, **kwargs):
        self.agent_args = kwargs.get('agent_args', {})
        self.model = self.agent_args.get('model', 'Kimi-K2.5')
        # TODO: Fix this confusion
        self.decoding_params = self.agent_args.get('decoding_params', {})
        # self.temperature = self.decoding_params.get('temperature', 1.0)
        print('Agent args are: ', self.agent_args, 'and temperature is: ', self.agent_args.get('temperature', 1.0))
        self.temperature = self.agent_args.get('temperature', 1.0)

        self.top_p = self.decoding_params.get('top_p', 0.95)
        self.top_k = self.decoding_params.get('top_k', 20)
        self.max_tokens = self.decoding_params.get('max_tokens', 1500)
        self.history_n = self.agent_args.get('history_n', 1)
        self.history_n = 1

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
        processed_image_b64, processed_path = self.process_image(obs['screen']['path'])
        self.screenshots.append(processed_image_b64)

        # Store mapping for efficient message saving
        self.b64_to_path[processed_image_b64] = processed_path

        # Build messages
        messages = self.build_messages(processed_image_b64)


        # Save messages with file paths instead of base64
        self.save_messages(messages)

        # Call LLM
        print(f"Calling LLM with temperature: {self.temperature}")
        # response = call_kimi_azure(
        #     messages,
        #     self.model,
        #     self.temperature,
        #     self.top_p,
        #     self.top_k,
        #     # self.max_tokens
        # )
        response = call_llm(
            messages,
            self.model,
            self.temperature,
            self.top_p,
            self.top_k,
            self.max_tokens
        )


        # Store response for history
        self.responses.append(response)

        # Parse response using existing parse_qwen3vl_response function
        parsed_response = parse_qwen3vl_response(response, scale_dims=True, scale_dims_ratio=(1920, 1080))

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
