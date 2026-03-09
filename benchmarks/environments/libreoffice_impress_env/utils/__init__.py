"""
LibreOffice Impress verification utilities package
"""

from .impress_verification_utils import (
    parse_odp_file,
    parse_pptx_file,
    get_slide_count,
    get_slide_text_content,
    get_slide_title,
    get_slide_bullets,
    check_slide_has_images,
    check_slide_has_chart,
    check_slide_has_shapes,
    check_slide_has_animations,
    verify_slide_transition,
    get_slide_shapes,
    setup_verification_environment,
    cleanup_verification_environment,
    copy_and_parse_presentation,
    verify_text_on_slide,
    count_shapes_on_slide,
    get_presentation_metadata,
)

__all__ = [
    'parse_odp_file',
    'parse_pptx_file',
    'get_slide_count',
    'get_slide_text_content',
    'get_slide_title',
    'get_slide_bullets',
    'check_slide_has_images',
    'check_slide_has_chart',
    'check_slide_has_shapes',
    'check_slide_has_animations',
    'verify_slide_transition',
    'get_slide_shapes',
    'setup_verification_environment',
    'cleanup_verification_environment',
    'copy_and_parse_presentation',
    'verify_text_on_slide',
    'count_shapes_on_slide',
    'get_presentation_metadata',
]
