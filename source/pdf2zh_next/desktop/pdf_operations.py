"""BabelDOC 0.6.2 PDF process targets, with a lightweight import boundary.

Same PyMuPDF operations, arguments and exit contract as pdf_creater.py (AGPL).
Moving only the spawn targets avoids importing layout/ML in PDF save children.
The locked optional patch selects these targets only in native workers.
"""
import logging
import os
import pymupdf

logger=logging.getLogger(__name__)


def subset_fonts_process(pdf_path,output_path):
    try:
        pdf=pymupdf.open(pdf_path)
        pdf.subset_fonts(fallback=False)
        pdf.save(output_path)
        os._exit(0)
    except Exception as e:
        logger.error(f"Error in font subsetting subprocess: {e}")
        os._exit(1)


def save_pdf_clean_process(pdf_path,output_path,garbage=1,deflate=True,clean=True,deflate_fonts=True,linear=False):
    try:
        pdf=pymupdf.open(pdf_path)
        pdf.save(output_path,garbage=garbage,deflate=deflate,clean=clean,deflate_fonts=deflate_fonts,linear=linear)
        os._exit(0)
    except Exception as e:
        logger.error(f"Error in save PDF with clean=True subprocess: {e}")
        os._exit(1)
