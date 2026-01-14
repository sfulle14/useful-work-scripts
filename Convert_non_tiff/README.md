# Folder Image & Document to TIFF Converter

A small Python tool to recursively scan a folder and convert all non-TIFF images and documents (TXT/DOCX) to TIFF, preserving folder structure.

## Features
- Recursively scans subfolders
- Skips `.tif`/`.tiff` files automatically
- Converts common image formats (`jpg`, `jpeg`, `png`, `bmp`, `gif`, `webp`)
- Converts `.txt` and `.docx` by rendering text into single-page TIFFs (page height expands to fit content)
- Optional multi-page conversion for animated GIFs (`--multipage-gif`)
- Choose TIFF compression (`none`, `lzw`, `deflate`, `packbits`); default `lzw`
- Preserve alpha channel (`--preserve-alpha`) or composite onto white (images)
- In-place conversion or mirror structure under an output directory
- Optional overwrite of existing `.tif` files and deletion of originals

## Quick Start

### 1) Install dependencies
```bash
pip install -r requirements.txt
```

### 2) Show help
```bash
python tools/convert_to_tiff.py --help
```

### Bash-only converter (Git Bash/WSL)
```bash
bash tools/convert_to_tiff.sh --help
```

### 3) Convert in-place (writes `.tif` next to originals)
```bash
python tools/convert_to_tiff.py "F:\\Catalis\\MontCo" --log-level INFO
```

Or via Bash-only:
```bash
bash tools/convert_to_tiff.sh "/mnt/f/Catalis/MontCo" --log-level INFO
```

### 4) Mirror into an output folder
```bash
python tools/convert_to_tiff.py "F:\\Catalis\\MontCo" --output "F:\\Catalis\\MontCo_TIFF" --log-level INFO
```

Or via Bash-only:
```bash
bash tools/convert_to_tiff.sh "/mnt/f/Catalis/MontCo" --output "/mnt/f/Catalis/MontCo_TIFF" --log-level INFO
```

### Requirements for Bash-only flow
- ImageMagick (`magick` or `convert`) for all conversions
- LibreOffice (`soffice`) for DOCX → PDF (then stitched into a single tall TIFF)

### Bash-only options
- `--overwrite`, `--delete-original`, `--compression lzw|zip|packbits|none`
- `--dpi`, `--page-width`, `--page-height`, `--margin`, `--font`, `--font-size`, `--dry-run`

Notes:
- GIFs are converted using the first frame, resulting in a single-page TIFF.
- TXT renders to a single-page TIFF whose height expands to fit the text.
- DOCX is converted via LibreOffice to PDF, then pages are vertically appended into a single TIFF.

### Common options
- `--overwrite`: Overwrite existing `.tif` outputs
- `--delete-original`: Delete originals after successful conversion
- `--compression lzw|deflate|packbits|none`: Choose TIFF compression
- `--preserve-alpha`: Keep transparency where possible (RGBA TIFF) for images
- `--multipage-gif`: Convert animated GIFs to multi-page TIFF
- `--dry-run`: Show planned conversions without writing files
- `--dpi`: DPI for text pages (default: 300)
- `--page-width` / `--page-height`: Page pixel size for text rendering (default: 2550x3300 ~ 8.5x11" @300DPI). For TXT/DOCX, height grows to fit all text on one page.
- `--margin`: Text margin in pixels (default: 150)
- `--font-path`: Optional TTF font path (e.g., `C:\\Windows\\Fonts\\Consola.ttf`)
- `--font-size`: Font size for text/docx (default: 20)

## Notes
- HEIC/HEIF is not supported by Pillow by default; such files will be skipped unless you add appropriate plugins.
- Multi-page TIFFs are created for GIFs (when `--multipage-gif`) and for long TXT/DOCX content automatically.
- DOCX conversion extracts text only; complex formatting and embedded images are not rendered.
- EXIF orientation is applied on load; EXIF metadata may not be fully preserved when saving as TIFF.
