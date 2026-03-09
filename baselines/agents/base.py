from typing import Tuple, Dict, Any, List

class BaseAgent:


    def __init__(self, *args, **kwargs):
        """
            Make sure to initialize the following variables:
            - model: The model name to be used for the agent.
            - done:  Whether the agent has completed all its actions and is done.
            - step_idx: The current step_idx since it won't be provided by the agent loop
        """
        raise NotImplementedError

    def init(self, task_description : str, display_resolution : Tuple[int, int], save_path : str):
        """
            task_description: The task description, that the agent needs to complete.
            display_resolution: The resolution of the display. display_resolution is a tuple of (width, height).
            save_path: The path where the agent will save the artifacts.
        """
        raise NotImplementedError

    def step(self, obs : Dict[str, Any], action_outputs : List[Dict[str, Any]]):
        """
            obs: The observation from the environment.
            action_outputs: The action outputs from the previous step.
        """
        raise NotImplementedError
    
    def finish(self, *args, **kwargs):
        """
            Store the trajectory in the relevant folder.
        """
        raise NotImplementedError