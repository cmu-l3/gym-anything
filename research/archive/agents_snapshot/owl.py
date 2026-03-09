from agents.base import BaseAgent
from agent_utils import get_prompt, pil_to_base64, call_llm, parse_owl_response
from PIL import Image
import json
import os
import time


class OwlAgent(BaseAgent):
    """
    GUI-Owl agent using open-source vision-language models.
    Maintains a history-based prompting approach.
    """
    
    def __init__(self, *args, **kwargs):
        self.agent_args = kwargs.get('agent_args', {})
        self.model = self.agent_args.get('model', 'mPLUG/GUI-Owl-32B')
        self.decoding_params = self.agent_args.get('decoding_params', {})
        self.temperature = self.decoding_params.get('temperature', 0.6)
        self.top_p = self.decoding_params.get('top_p', 0.9)
        
        # Setup custom save folder
        self.exp_name = self.agent_args.get('exp_name', 'exp')
        self.setup_custom_logger()
        
        # Agent state
        self.done = False
        self.step_idx = -1
        
        # History for prompting (list of step conclusions)
        self.history = []
        
        # Store all responses for final dump
        self.all_model_responses = []
        self.all_parsed_responses = []
        
        self.debug = kwargs.get('debug', False)
        self.verbose = kwargs.get('verbose', False)
    
    def setup_custom_logger(self):
        """Setup custom save folder for agent artifacts."""
        task_name = self.agent_args.get('task_name', 'task')
        self.save_folder_custom = f'all_runs/{self.exp_name}/{self.model}/{task_name}'
        for run_number in range(0, 100):
            if os.path.exists(f'{self.save_folder_custom}/run_{run_number}'):
                continue
            self.save_folder_custom = f'{self.save_folder_custom}/run_{run_number}'
            break
        os.makedirs(self.save_folder_custom, exist_ok=False)
    
    def save_observation(self, img):
        """Save the current observation screenshot."""
        profile_start_time = time.time()
        img.save(
            f'{self.save_folder_custom}/observation_{self.step_idx}.png'
        )
        print(f'[owl.py] Profiling time for save_observation: {time.time() - profile_start_time}')
    
    def init(self, task_description, display_resolution, save_path):
        """Initialize agent with task description and environment details."""
        self.task_description = task_description
        self.display_resolution = display_resolution
        self.save_path = save_path
    
    def step(self, obs, action_outputs):
        """
        Execute one agent step.
        
        Args:
            obs: Current observation from environment
            action_outputs: List of outputs from previous actions (not used for Owl agent)
        
        Returns:
            List of action groups to execute
        """
        image = Image.open(obs['screen']['path'])
        # Save current observation
        self.save_observation(image)

        profile_start_time = time.time()
        self.step_idx += 1
        
        # Build messages with history
        messages = get_prompt(self.task_description, self.history)
        
        # Add current screenshot to messages
        messages[-1]['content'].append({
            "type": "text", 
            "text": "Current screenshot:\n"
        })
        
        # Load and encode image
        encoded_string = pil_to_base64(image)
        messages[-1]['content'].append({
            "type": "image_url", 
            "image_url": {"url": f"data:image/png;base64,{encoded_string}"}
        })
        profile_build_messages_time = time.time()
        print(f'[owl.py] Profiling time for build_messages: {profile_build_messages_time - profile_start_time}')
        
        # Call LLM
        response = call_llm(messages, self.model, self.temperature, self.top_p)

        profile_call_llm_time = time.time()
        print(f'[owl.py] Profiling time for call_llm: {profile_call_llm_time - profile_build_messages_time}')
        if self.debug: breakpoint()
        
        # Parse response
        parsed_response = parse_owl_response(response)
        profile_parse_owl_response_time = time.time()
        print(f'[owl.py] Profiling time for parse_owl_response: {profile_parse_owl_response_time - profile_call_llm_time}')
        # Store responses for later dumping
        self.all_model_responses.append(response)
        self.all_parsed_responses.append(parsed_response)
        
        # Extract actions and metadata
        actions = parsed_response['actions']
        metadata = parsed_response['metadata']
        
        # Update history with conclusion
        self.history.append(f"Step {self.step_idx + 1}: {metadata['conclusion']}")
        print(f'[owl.py] Profiling time for update_history: {time.time() - profile_parse_owl_response_time}')
        if self.verbose:
            print(f"Step {self.step_idx + 1}:")
            print(f"  Thought: {metadata['thought']}")
            print(f"  Conclusion: {metadata['conclusion']}")
            print(f"  Action Type: {metadata['action_type']}")
            print(f"  Actions: {actions}")
        
        # Check if terminal
        if metadata['is_terminal']:
            self.done = True
            # Return empty actions - loop.py will handle marking as done
            # Note: parse_owl_response returns empty actions for terminate
            return [{
                'tool_id': f'owl_step_{self.step_idx}',
                'actions': actions,  # Empty list from parse_owl_response
                'metadata': metadata
            }]
        
        # Check if wait action
        if metadata['wait_time'] is not None:
            # parse_owl_response returns empty actions for wait
            # Convert to the old format that loop.py expects
            return [{
                'tool_id': f'owl_step_{self.step_idx}',
                'actions': [{'action': 'wait', 'time': metadata['wait_time']}],
                'metadata': metadata
            }]
        
        # Regular actions (mouse, keyboard, etc.)
        return [{
            'tool_id': f'owl_step_{self.step_idx}',
            'actions': actions,
            'metadata': metadata
        }]
    
    def finish(self, *args, **kwargs):
        """Save all agent artifacts."""
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
            json.dump(info, open(f'{self.save_folder_custom}/info.json', 'w'), indent=4)
