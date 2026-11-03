"""Short-lived renderer; never imported by the control process."""
import argparse
import json
import sys


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("path")
    parser.add_argument("--page", type=int, default=1)
    parser.add_argument("--width", type=int, default=1200)
    args = parser.parse_args()
    import pymupdf
    with pymupdf.open(args.path) as doc:
        if not 1 <= doc.page_count <= 10000: raise ValueError("不支持的 PDF 页数")
        index = max(0, min(args.page-1, doc.page_count-1))
        output = b""
        if args.width:
            page = doc[index]
            scale = min(max(200, min(1600, args.width))/max(page.rect.width, 1), 2400/max(page.rect.height, 1))
            output = page.get_pixmap(matrix=pymupdf.Matrix(scale, scale), alpha=False).tobytes("png")
        sys.stdout.buffer.write(json.dumps({"page_count": doc.page_count, "page_index": index+1}).encode()+b"\n"+output)


if __name__ == "__main__": main()
