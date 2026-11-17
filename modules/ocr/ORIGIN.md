# OCR module

Text extraction for every file people upload, photos and scans included: Apache Tika with Tesseract, in the official
image, on the internal network only. The OCR languages come from `ALICE_OCR_LANGUAGES` (for example `fra+eng`).

| Part | Source | License |
|---|---|---|
| Server | [Apache Tika](https://github.com/apache/tika) 4.2.0, image `apache/tika:4.2.0-full` pinned by digest | Apache-2.0 |
| OCR | [Tesseract](https://github.com/tesseract-ocr/tesseract) with its language data | Apache-2.0 |

Measured on the reference machine: a photo of a receipt in 0.4 s, about 1 GB of memory. Without the French model,
capital letters lose their accents ("MARCHE" instead of "MARCHÉ").
