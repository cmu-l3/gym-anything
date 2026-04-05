from agents.shared.llm_clients import parse_qwen3vl_response, call_gemini_with_retry
from agents.agents.qwen3vl import Qwen3VLAgent
from PIL import Image
import json
import os
import base64
import numpy as np


# python -m agents.evaluation.run_single --env_dir benchmarks/cua_world/environments/gimp_env_all_fast --task saturation_increase --agent 'ClaudeDatabricksAgent' --agent_args "{\"model\":\"databricks/claude-4-5-sonnet\", \"exp_name\":\"claude-4-5-sonnet\", \"task_name\": \"saturation_increase\"}"

class CustomJSONEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, np.bool_):
            return bool(obj)
        # Let the base class default method raise the TypeError for other unhandled types
        return json.JSONEncoder.default(self, obj)


class GeminiQwen3Agent(Qwen3VLAgent):
    """
    Gemini agent using the Qwen-style multimodal prompting loop.
    Maintains a history-based prompting approach with image preprocessing.
    """
    
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)

    def process_image(self, image_path, resize_to=None):
        image = Image.open(image_path)
        if resize_to is not None:
            image = image.resize((resize_to[0], resize_to[1]))
        processed_path = f"{self.save_folder_custom}/observation_{self.step_idx}.png"
        image.save(processed_path, format="PNG")
        with open(processed_path, "rb") as handle:
            processed_bytes = handle.read()
        return base64.b64encode(processed_bytes).decode("utf-8")

    def step(self, obs, action_outputs):
        """
        Execute one agent step.
        
        Args:
            obs: Current observation from environment
            action_outputs: List of outputs from previous actions (not used for Qwen3VL agent)
        
        Returns:
            List of action groups to execute
        """
        # Save current observation
        self.save_observation(obs)
        self.step_idx += 1
        
        # Process image
        processed_image_b64 = self.process_image(obs['screen']['path'], resize_to = (self.display_resolution[0], self.display_resolution[1]))
        self.screenshots.append(processed_image_b64)
        
        # Build messages
        messages = self.build_messages(processed_image_b64)

        messages[0]['cache_control'] = {"type": "ephemeral"}

        # Save messages for debugging
        try:
            message_file_path = os.path.join(
                self.save_folder_custom, f"messages_step_{self.step_idx}.json"
            )
            with open(message_file_path, "w") as f:
                json.dump(messages, f, indent=2)
        except Exception as e:
            if self.verbose:
                print(f"Failed to save messages: {e}")
        self.save_messages(messages)
        # Call LLM
        print(f"Calling LLM with temperature: {self.temperature}")
        response = call_gemini_with_retry(
            messages, 
            self.model, 
            self.temperature, 
            self.top_p,
            self.top_k,
            # self.max_tokens
        )
        
        
        # Store response for history
        self.responses.append(response)
        
        # Parse response using existing parse_owl_response function
        parsed_response = parse_qwen3vl_response(response, scale_dims = True, scale_dims_ratio = (self.display_resolution[0]/1000, self.display_resolution[1]/1000))
        
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
