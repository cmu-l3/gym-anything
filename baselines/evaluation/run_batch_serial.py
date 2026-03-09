import os
import sys
import argparse
import requests
import time

parser = argparse.ArgumentParser()
parser.add_argument("--osw", action="store_true")
parser.add_argument("--nc", action="store_true")
parser.add_argument("--model", type=str, required=False, default="mPLUG/GUI-Owl-32B")
parser.add_argument("--agent", type=str, required=False, default="OwlAgent")
parser.add_argument("--exp_name", type=str, required=False, default="owl-gui-normal-highres-all")
parser.add_argument("--use_cache", action="store_true")
parser.add_argument('--test_only', action="store_true")
parser.add_argument('--train_only', action="store_true")
parser.add_argument('--temperature', type=float, required=False, default=1.0)
parser.add_argument('--repeat', type=int, required=False, default=1)
parser.add_argument('--env_dir', type=str, required=False, default="benchmarks/environments/gimp_env_all_fast")
parser.add_argument('--max_steps', type=int, required=False, default=50)
args = parser.parse_args()

IS_OSW = args.osw
IS_NC = args.nc
MODEL = args.model
EXP_NAME = args.exp_name
AGENT = args.agent
USE_CACHE = args.use_cache
TEST_ONLY = args.test_only
REPEAT = args.repeat
TRAIN_ONLY = args.train_only
TEMPERATURE = args.temperature
assert not (TEST_ONLY and TRAIN_ONLY), "Cannot set both test_only and train_only"
MAX_STEPS = args.max_steps

all_tasks = ["flood_fill", "brightness_contrast", "object_erase", "border_add", "drop_shadow", "rotate_90_clockwise", "border_addition", "threshold_convert", "select_fill", "desaturate", "layer_duplicate", "canvas_expand", "rotate_90_cw", "brush_drawing", "layer_opacity", "image_rotation", "color_invert", "sharpen_filter", "saturation_enhance", "auto_levels", "rect_select_delete", "gradient_fill", "pattern_fill", "ellipse_fill", "clone_duplicate", "scale_image", "grayscale_convert", "fuzzy_delete", "emboss_filter", "image_export", "invert_colors", "rectangle_fill", "rotate_90cw", "ellipse_delete", "brightness_adjust", "gaussian_blur", "bucket_fill", "vertical_mirror", "paintbrush_drawing", "color_sample", "selection_stroke", "rotate_90", "new_image", "canvas_resize"]

all_tasks = ['add_border', 'add_drop_shadow', 'add_layer_mask', 'add_noise', 'auto_levels', 'auto_normalize', 'auto_stretch_contrast', 'auto_white_balance', 'autocrop', 'autocrop_content', 'autocrop_image', 'blend_mode', 'blend_mode_multiply', 'border_add', 'border_addition', 'border_frame', 'border_stroke', 'brightness_adjust', 'brightness_contrast', 'brush_drawing', 'bucket_fill', 'canvas_expand', 'canvas_expansion', 'canvas_extend', 'canvas_resize', 'cartoon', 'checkerboard', 'circle_fill', 'circular_fill', 'clone_duplicate', 'clone_stamp', 'color_balance', 'color_enhance', 'color_invert', 'color_sample', 'color_temperature', 'color_to_alpha', 'colorize', 'contrast_adjust', 'crop_to_selection', 'cubism_effect', 'desaturate', 'desaturate_bw', 'desaturate_grayscale', 'despeckle', 'dilate', 'draw_line', 'drop_shadow', 'duplicate_layer', 'edge_detect', 'ellipse_delete', 'ellipse_fill', 'emboss', 'emboss_effect', 'emboss_filter', 'eraser_transparency', 'export_jpeg', 'feather_selection', 'flatten_image', 'flood_fill', 'fuzzy_delete', 'fuzzy_select_fill', 'gaussian_blur', 'gradient_fill', 'grayscale_convert', 'grayscale_mode', 'hue_rotation', 'hue_shift', 'image_export', 'image_rotation', 'increase_saturation', 'indexed_color', 'invert_colors', 'layer_duplicate', 'layer_offset', 'layer_opacity', 'lens_flare', 'levels_adjust', 'merge_down', 'motion_blur', 'neon_edges', 'new_image', 'new_layer', 'newsprint', 'noise_reduce', 'object_erase', 'offset_image', 'offset_wrap', 'oilify', 'paintbrush_drawing', 'paintbrush_stroke', 'partial_erase', 'paste_as_new_layer', 'pattern_fill', 'pixelate', 'pixelate_effect', 'pixelate_mosaic', 'pixelize', 'plasma_render', 'posterize', 'print_resolution', 'rect_fill', 'rect_select_delete', 'rect_select_fill', 'rectangle_clear', 'rectangle_fill', 'rectangle_stroke', 'remove_background', 'rename_layer', 'render_grid', 'rgb_noise', 'ripple', 'ripple_effect', 'rotate_180', 'rotate_45', 'rotate_90', 'rotate_90_ccw', 'rotate_90_clockwise', 'rotate_90_cw', 'rotate_90cw', 'rotate_clockwise', 'round_corners', 'rounded_corners', 'saturation_boost', 'saturation_enhance', 'saturation_increase', 'scale_50_percent', 'scale_by_percentage', 'scale_image', 'scale_to_width', 'select_fill', 'selection_stroke', 'sepia_tone', 'shadows_highlights', 'sharpen', 'sharpen_details', 'sharpen_filter', 'sharpen_unsharp', 'shear_horizontal', 'soft_glow', 'softglow', 'solarize', 'solid_noise', 'square_crop', 'threshold', 'threshold_binary', 'threshold_bw', 'threshold_convert', 'threshold_effect', 'tile_seamless', 'unsharp_mask', 'vertical_mirror', 'vignette', 'wind_effect']

if IS_OSW:
#     osw_add_layer_square   osw_green_background_fill  osw_remove_background    osw_undo_steps_100
# osw_brightness_reduce  osw_hide_docks             osw_resize_layer_512     osw_vignette_filter_open
# osw_contrast_increase  osw_horizontal_mirror      osw_saturation_increase
# osw_export_rename      osw_open_vignette          osw_theme_light
# osw_green_background   osw_palette_convert        osw_triangle_center
    all_tasks = ["osw_add_layer_square", "osw_green_background_fill", "osw_remove_background", "osw_undo_steps_100", "osw_brightness_reduce", "osw_hide_docks", "osw_resize_layer_512", "osw_vignette_filter_open", "osw_contrast_increase", "osw_horizontal_mirror", "osw_saturation_increase", "osw_export_rename", "osw_open_vignette", "osw_theme_light", "osw_green_background", "osw_palette_convert", "osw_triangle_center"]
    ENV_DIR = "benchmarks/environments/gimp_env_osw"
elif IS_NC:
    # ['auto_white_balance', 'vignette', 'layer_opacity', 'layer_offset', 'plasma_render', 'offset_image', 'render_grid', 'color_balance', 'dilate', 'tile_seamless', 'newsprint', 'scale_image', 'offset_wrap', 'cartoon']
    all_tasks = ['auto_white_balance', 'vignette', 'layer_opacity', 'layer_offset', 'plasma_render', 'offset_image', 'render_grid', 'color_balance', 'dilate', 'tile_seamless', 'newsprint', 'scale_image', 'offset_wrap', 'cartoon']
    ENV_DIR = "benchmarks/environments/gimp_env_all_fast"
else:
    if args.env_dir:
        ENV_DIR = args.env_dir
    else:   
        ENV_DIR = "benchmarks/environments/gimp_env_all_fast"

if TEST_ONLY or TRAIN_ONLY:
    all_tasks_test = ['object_erase', 'threshold_binary', 'emboss_effect', 'rectangle_stroke', 'color_balance', 'rect_fill', 'scale_to_width', 'ripple', 'saturation_enhance', 'circle_fill', 'grayscale_mode', 'solid_noise', 'sharpen_filter', 'sharpen_unsharp', 'blend_mode', 'add_drop_shadow', 'invert_colors', 'print_resolution', 'scale_image', 'select_fill', 'flood_fill', 'ellipse_fill', 'vignette', 'duplicate_layer', 'border_add', 'dilate', 'auto_normalize', 'border_addition', 'threshold_bw', 'cartoon', 'saturation_boost', 'layer_opacity', 'auto_white_balance', 'edge_detect', 'color_enhance', 'render_grid', 'newsprint', 'increase_saturation', 'emboss', 'square_crop', 'add_border', 'vertical_mirror', 'paste_as_new_layer', 'tile_seamless', 'offset_image', 'offset_wrap', 'layer_offset', 'threshold_effect', 'plasma_render', 'fuzzy_select_fill']
    if TEST_ONLY:
        all_tasks = all_tasks_test
    else:
        all_tasks = list(set(all_tasks) - set(all_tasks_test))


# all_tasks = ["brush_drawing", "clone_duplicate", "ellipse_fill", "grayscale_convert", "rotate_90_cw", "sharpen_filter", "rectangle_fill"]
import numpy as np
np.random.shuffle(all_tasks)

for repeat in range(REPEAT):
    for task_file in all_tasks:
        print('Starting task: ', task_file)
        command = (
            f"python -m baselines.evaluation.run_single --env_dir {ENV_DIR} --task {task_file} "
            f"--agent '{AGENT}' --agent_args "
            f"\"{{\\\"model\\\":\\\"{MODEL}\\\", \\\"exp_name\\\":\\\"{EXP_NAME}\\\", "
            f"\\\"task_name\\\": \\\"{task_file}\\\", \\\"temperature\\\": {TEMPERATURE}}}\" "
            f"--steps {MAX_STEPS} {'--use_cache --cache_level pre_start' if USE_CACHE else ''}"
        )
        print(command)
        os.system(command)

        # Make a curl request to localhost:4243/v1, if not available keep exponential backoff sleeping for 1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024 seconds
        # if 'claude' in MODEL:  
        #     continue
        # for i in range(15):
        #     try:
        #         response = requests.get("http://localhost:4243/v1")
        #         break
        #     except requests.exceptions.RequestException as e:
        #         print(f'Retrying Attempt {i} for localhost:4243/v1', f'Sleeping for {2**i} seconds')
        #         time.sleep(2**i)
        #     if i == 14: # 15 attempts
        #         raise Exception("Failed to connect to localhost:4243/v1 after 15 attempts")
