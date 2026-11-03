import pymupdf
doc = pymupdf.open(); page = doc.new_page()
page.insert_text((72, 72), "c3 test", fontsize=12)
pix = page.get_pixmap(matrix=pymupdf.Matrix(640/595, 640/595), alpha=False)
pix.save(r"D:\student\翻译\p0-frozen-fa97b2e6f9\docs\verification\native-desktop\p0-delivery-20261103-c72fd7361c\runs\recorder-matrix\entry-run\cases\c3-real640.png")
