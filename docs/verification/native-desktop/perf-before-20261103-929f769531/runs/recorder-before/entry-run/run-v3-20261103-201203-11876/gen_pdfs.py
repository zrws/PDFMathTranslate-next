import sys
import pymupdf
base = sys.argv[1]
doc = pymupdf.open()
for i in range(20):
    page = doc.new_page()
    page.insert_text((72, 72), f"Sample Document Page {i+1}", fontsize=16)
    for line in range(12):
        page.insert_text((72, 110 + line * 22),
            f"Paragraph {line+1} on page {i+1}: the quick brown fox jumps over the lazy dog.",
            fontsize=11)
doc.save(base + r"\p0-sample-20p.pdf")
doc.close()
doc = pymupdf.open()
page = doc.new_page()
page.insert_text((72, 72), "Baseline Translation Test Page", fontsize=16)
body = ("This one-page document is generated locally for offline measurement. "
        "It is not uploaded anywhere.")
page.insert_textbox(pymupdf.Rect(72, 100, 520, 400), body, fontsize=11)
doc.save(base + r"\p0-sample-1p.pdf")
doc.close()
print("pdfs-generated")
