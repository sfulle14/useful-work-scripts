import argparse
import logging
import sys
from pathlib import Path
from typing import List, Optional

from PIL import Image, ImageOps, ImageDraw, ImageFont

IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".bmp", ".gif", ".webp"}
TIFF_EXTS = {".tif", ".tiff"}
DOCUMENT_EXTS = {".txt", ".docx"}
SUPPORTED_COMPRESSIONS = {"none": None, "lzw": "tiff_lzw", "deflate": "tiff_deflate", "packbits": "packbits"}


def is_image_file(path: Path) -> bool:
    suffix = path.suffix.lower()
    if suffix in TIFF_EXTS:
        return False
    if suffix in IMAGE_EXTS:
        return True
    # Fallback: try opening with Pillow to detect images without standard ext
    try:
        with Image.open(path):
            return True
    except Exception:
        return False


def build_output_path(src: Path, output_root: Optional[Path]) -> Path:
    # Always replace the existing extension with .tif (don't append)
    tif_name = src.stem + ".tif"
    if output_root:
        rel = src.relative_to(src.anchor if src.anchor else src.parents[-1])
        # Mirror folder structure under output_root, preserving folders, replacing filename ext
        return (output_root / rel.parent / tif_name)
    # In-place next to original, replacing filename ext
    return src.with_name(tif_name)


def convert_single_image(img: Image.Image, dest: Path, compression: Optional[str], preserve_alpha: bool) -> None:
    # Apply EXIF-based orientation correction for JPEGs and others
    try:
        img = ImageOps.exif_transpose(img)
    except Exception:
        pass

    mode = img.mode
    if mode in ("P", "LA"):
        img = img.convert("RGBA" if preserve_alpha else "RGB")
    elif mode == "L" and preserve_alpha:
        # Grayscale, no alpha to preserve
        pass
    elif mode == "RGBA" and not preserve_alpha:
        # Composite over white background to drop alpha
        background = Image.new("RGB", img.size, (255, 255, 255))
        background.paste(img, mask=img.split()[3])
        img = background
    elif mode not in ("RGB", "L", "RGBA"):
        img = img.convert("RGB")

    dest.parent.mkdir(parents=True, exist_ok=True)
    save_kwargs = {"format": "TIFF"}
    if compression is not None:
        save_kwargs["compression"] = compression

    # Try to carry EXIF if present; Pillow support for EXIF in TIFF varies
    exif = img.info.get("exif")
    if exif:
        save_kwargs["exif"] = exif

    img.save(dest, **save_kwargs)


def _load_font(font_path: Optional[str], font_size: int) -> ImageFont.ImageFont:
    try:
        if font_path:
            return ImageFont.truetype(font_path, font_size)
    except Exception:
        logging.warning("Failed to load font at %s, falling back to default", font_path)
    return ImageFont.load_default()


def _wrap_text_to_lines(text: str, draw: ImageDraw.ImageDraw, font: ImageFont.ImageFont, max_width: int) -> List[str]:
    lines: List[str] = []
    for paragraph in text.splitlines():
        if not paragraph:
            lines.append("")
            continue
        words = paragraph.split()
        current = ""
        for word in words:
            test = word if not current else current + " " + word
            bbox = draw.textbbox((0, 0), test, font=font)
            width = bbox[2] - bbox[0]
            if width <= max_width:
                current = test
            else:
                if current:
                    lines.append(current)
                current = word
        if current:
            lines.append(current)
    return lines


def render_text_to_tiff_single_page(text: str, dest: Path, compression: Optional[str], dpi: int, page_width: int, page_height: int, margin: int, font_path: Optional[str], font_size: int) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    font = _load_font(font_path, font_size)
    # Temporary draw to measure text
    temp_img = Image.new("RGB", (page_width, max(100, page_height)), (255, 255, 255))
    temp_draw = ImageDraw.Draw(temp_img)

    # Estimate line height from font metrics
    try:
        ascent, descent = font.getmetrics()
        line_height = ascent + descent + 4
    except Exception:
        bbox = temp_draw.textbbox((0, 0), "Ag", font=font)
        line_height = (bbox[3] - bbox[1]) + 4

    max_text_width = page_width - 2 * margin
    lines = _wrap_text_to_lines(text, temp_draw, font, max_text_width)

    # Compute required height to fit all lines on a single page
    required_height = margin * 2 + max(1, len(lines)) * line_height
    height = max(page_height, required_height)

    img = Image.new("RGB", (page_width, height), (255, 255, 255))
    draw = ImageDraw.Draw(img)
    y = margin
    for ln in lines:
        draw.text((margin, y), ln, fill=(0, 0, 0), font=font)
        y += line_height

    save_kwargs = {"format": "TIFF", "dpi": (dpi, dpi)}
    if compression is not None:
        save_kwargs["compression"] = compression

    img.save(dest, **save_kwargs)


def convert_gif_multipage(src: Path, dest: Path, compression: Optional[str], preserve_alpha: bool) -> None:
    frames: List[Image.Image] = []
    with Image.open(src) as img:
        try:
            frame_count = img.n_frames
        except Exception:
            frame_count = 1
        for i in range(frame_count):
            try:
                img.seek(i)
                frame = ImageOps.exif_transpose(img)
                mode = frame.mode
                if mode in ("P", "LA"):
                    frame = frame.convert("RGBA" if preserve_alpha else "RGB")
                elif mode == "RGBA" and not preserve_alpha:
                    background = Image.new("RGB", frame.size, (255, 255, 255))
                    background.paste(frame, mask=frame.split()[3])
                    frame = background
                elif mode not in ("RGB", "L", "RGBA"):
                    frame = frame.convert("RGB")
                frames.append(frame.copy())
            except Exception:
                # If a frame fails, skip it
                continue

    if not frames:
        raise RuntimeError(f"No frames extracted from {src}")

    dest.parent.mkdir(parents=True, exist_ok=True)
    save_kwargs = {"format": "TIFF", "save_all": True}
    if compression is not None:
        save_kwargs["compression"] = compression
    first, rest = frames[0], frames[1:]
    first.save(dest, append_images=rest, **save_kwargs)


def process_file(src: Path, output_root: Optional[Path], overwrite: bool, delete_original: bool, compression_name: str, preserve_alpha: bool, multipage_gif: bool, dry_run: bool, dpi: int, page_width: int, page_height: int, margin: int, font_path: Optional[str], font_size: int) -> bool:
    # Returns True if converted, False if skipped
    dest = build_output_path(src, output_root)
    if dest.exists() and not overwrite:
        logging.debug("Skip existing: %s", dest)
        return False

    if dry_run:
        logging.info("Would convert: %s -> %s", src, dest)
        return False

    try:
        suffix = src.suffix.lower()
        compression = SUPPORTED_COMPRESSIONS.get(compression_name)
        if suffix in DOCUMENT_EXTS:
            if suffix == ".txt":
                try:
                    text = src.read_text(encoding="utf-8", errors="replace")
                except Exception:
                    text = src.read_text(errors="replace")
                render_text_to_tiff_single_page(text, dest, compression, dpi, page_width, page_height, margin, font_path, font_size)
            elif suffix == ".docx":
                try:
                    from docx import Document  # type: ignore
                except Exception as e:
                    raise RuntimeError("python-docx not installed; cannot convert DOCX") from e
                doc = Document(str(src))
                paragraphs = [p.text for p in doc.paragraphs]
                text = "\n".join(paragraphs)
                render_text_to_tiff_single_page(text, dest, compression, dpi, page_width, page_height, margin, font_path, font_size)
        elif suffix == ".gif" and multipage_gif:
            convert_gif_multipage(src, dest, compression, preserve_alpha)
        else:
            with Image.open(src) as img:
                convert_single_image(img, dest, compression, preserve_alpha)
        logging.info("Converted: %s -> %s", src, dest)
        if delete_original:
            try:
                src.unlink()
                logging.debug("Deleted original: %s", src)
            except Exception as e:
                logging.warning("Failed to delete original %s: %s", src, e)
        return True
    except Exception as e:
        logging.error("Failed to convert %s: %s", src, e)
        return False


def scan_and_convert(root: Path, output_root: Optional[Path], overwrite: bool, delete_original: bool, compression_name: str, preserve_alpha: bool, multipage_gif: bool, dry_run: bool, dpi: int, page_width: int, page_height: int, margin: int, font_path: Optional[str], font_size: int) -> None:
    total = 0
    converted = 0
    skipped = 0
    for path in root.rglob("*"):
        if not path.is_file():
            continue
        suffix = path.suffix.lower()
        if suffix in TIFF_EXTS:
            continue
        is_image = is_image_file(path)
        is_document = suffix in DOCUMENT_EXTS
        if not (is_image or is_document):
            continue
        total += 1
        if process_file(path, output_root, overwrite, delete_original, compression_name, preserve_alpha, multipage_gif, dry_run, dpi, page_width, page_height, margin, font_path, font_size):
            converted += 1
        else:
            skipped += 1
    logging.info("Done. Total images: %d, converted: %d, skipped: %d", total, converted, skipped)


def parse_args(argv: Optional[List[str]] = None) -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Recursively convert non-TIFF images and TXT/DOCX to TIFF.")
    p.add_argument("source", type=str, help="Source folder to scan recursively")
    p.add_argument("--output", type=str, default=None, help="Optional output root; mirrors structure under this folder. If omitted, saves next to original.")
    p.add_argument("--overwrite", action="store_true", help="Overwrite existing .tif files if present.")
    p.add_argument("--delete-original", action="store_true", help="Delete original files after successful conversion.")
    p.add_argument("--compression", choices=list(SUPPORTED_COMPRESSIONS.keys()), default="lzw", help="TIFF compression to use.")
    p.add_argument("--preserve-alpha", action="store_true", help="Preserve alpha channel where possible (RGBA TIFF). Without this, alpha is composited over white.")
    p.add_argument("--multipage-gif", action="store_true", help="Convert animated GIFs to multi-page TIFF. Without this, only the first frame is saved.")
    p.add_argument("--dry-run", action="store_true", help="Show what would be converted without writing files.")
    p.add_argument("--dpi", type=int, default=300, help="DPI for text-based TIFF pages (default: 300).")
    p.add_argument("--page-width", type=int, default=2550, help="Page width in pixels for text rendering (default: 2550 ~ 8.5in @300DPI).")
    p.add_argument("--page-height", type=int, default=3300, help="Page height in pixels for text rendering (default: 3300 ~ 11in @300DPI).")
    p.add_argument("--margin", type=int, default=150, help="Margin in pixels around text (default: 150).")
    p.add_argument("--font-path", type=str, default=None, help="Optional TTF font path for text/docx rendering.")
    p.add_argument("--font-size", type=int, default=20, help="Font size for text/docx rendering (default: 20).")
    p.add_argument("--log-level", choices=["DEBUG", "INFO", "WARNING", "ERROR"], default="INFO")
    return p.parse_args(argv)


def main(argv: Optional[List[str]] = None) -> int:
    args = parse_args(argv)
    logging.basicConfig(level=getattr(logging, args.log_level), format="%(levelname)s: %(message)s")

    src_root = Path(args.source)
    if not src_root.exists() or not src_root.is_dir():
        logging.error("Source folder does not exist or is not a directory: %s", src_root)
        return 2

    output_root = Path(args.output) if args.output else None
    if output_root:
        output_root.mkdir(parents=True, exist_ok=True)

    scan_and_convert(
        root=src_root,
        output_root=output_root,
        overwrite=args.overwrite,
        delete_original=args.delete_original,
        compression_name=args.compression,
        preserve_alpha=args.preserve_alpha,
        multipage_gif=args.multipage_gif,
        dry_run=args.dry_run,
        dpi=args.dpi,
        page_width=args.page_width,
        page_height=args.page_height,
        margin=args.margin,
        font_path=args.font_path,
        font_size=args.font_size,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
