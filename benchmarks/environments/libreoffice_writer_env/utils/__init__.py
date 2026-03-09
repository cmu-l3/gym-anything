"""LibreOffice Writer verification utilities for gym-anything tasks."""

from .writer_verification_utils import (
    copy_and_parse_document,
    cleanup_verification_temp,
    get_document_text,
    get_paragraph_styles,
    check_heading_styles,
    detect_toc_present,
    check_text_formatting,
    check_paragraph_alignment,
    count_headings_by_level,
    check_hanging_indent,
    check_hanging_indent_count,
    has_italicized_text,
    count_paragraphs_with_italics,
    check_mail_merge_output,
    check_no_raw_placeholders,
    verify_page_breaks,
    check_apa_citation_format,
    check_alphabetical_order,
    extract_citation_paragraphs,
    vlm_verify_screenshot,
)
