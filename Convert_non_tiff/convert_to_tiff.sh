#!/usr/bin/env bash
set -euo pipefail

# Pure Bash converter using ImageMagick and LibreOffice (for DOCX -> PDF),
# with optional IrfanView CLI for image conversions.
# - Recursively scans a source folder
# - Converts non-TIFF images to single-page TIFF (uses first frame of GIF)
# - Converts TXT and DOCX to single-page TIFF (DOCX via PDF -> vertical append -> single tall page)
# - If IrfanView is available and preferred, uses it for image conversions; default output is in-place

log() { echo "[convert_to_tiff.sh] $*"; }
err() { echo "[convert_to_tiff.sh] ERROR: $*" 1>&2; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Detect ImageMagick (magick for IM7, convert for IM6)
find_imagemagick() {
  if command -v magick >/dev/null 2>&1; then
    echo "magick"
    return 0
  fi
  if command -v convert >/dev/null 2>&1; then
    echo "convert"
    return 0
  fi
  return 1
}

IM_BIN="$(find_imagemagick || true)"
if [ -z "${IM_BIN:-}" ]; then
  err "ImageMagick not found. Install ImageMagick and ensure 'magick' or 'convert' is on PATH."
  exit 1
fi

have_soffice=false
if command -v soffice >/dev/null 2>&1; then
  have_soffice=true
fi

# Detect IrfanView (64-bit)
find_irfanview() {
  local candidates=(
    i_view64.exe
    "/c/Program Files/IrfanView/i_view64.exe"
    "/c/Program Files (x86)/IrfanView/i_view64.exe"
    "C:/Program Files/IrfanView/i_view64.exe"
    "C:/Program Files (x86)/IrfanView/i_view64.exe"
  )
  for p in "${candidates[@]}"; do
    if command -v "$p" >/dev/null 2>&1; then echo "$p"; return 0; fi
    if [ -f "$p" ]; then echo "$p"; return 0; fi
  done
  return 1
}
IR_BIN="$(find_irfanview || true)"

usage() {
  cat <<USAGE
Usage: bash tools/convert_to_tiff.sh SOURCE [options]

Options:
  --output DIR           Mirror folder structure under DIR; default: next to original
  --overwrite            Overwrite existing .tif files
  --delete-original      Delete source files after successful conversion
  --compression C        TIFF compression: lzw (default) | zip | packbits | none
  --dpi N                DPI for text/PDF rendering (default: 300)
  --page-width W         Page width (pixels) for text (default: 2550 ~ 8.5in @300DPI)
  --page-height H        Minimum page height (pixels) for text (default: 3300)
  --margin M             Margin (pixels) around text (default: 150)
  --font PATH            Optional TTF font path (e.g., /mnt/c/Windows/Fonts/consola.ttf)
  --font-size N          Font size for TXT/DOCX (default: 20)
  --irfanview PATH       Explicit path to i_view64.exe (IrfanView)
  --prefer-irfanview     Prefer IrfanView for image conversions when available
  --dry-run              Show planned actions without writing files
  -h, --help             Show this help

Notes:
  - Requires ImageMagick. DOCX conversion requires LibreOffice ('soffice').
  - Produces single-page TIFFs. GIFs use the first frame.
USAGE
}

# Defaults
OUTPUT_DIR=""
OVERWRITE=false
DELETE_ORIGINAL=false
COMPRESSION="lzw"   # maps to ImageMagick: LZW|Zip|PackBits|None
DPI=300
PAGE_WIDTH=2550
PAGE_HEIGHT=3300
MARGIN=150
FONT_PATH=""
FONT_SIZE=20
DRY_RUN=false
PREFER_IRFV=false

# Parse args
if [ $# -lt 1 ]; then
  usage; exit 2
fi

SOURCE=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --output) OUTPUT_DIR="$2"; shift 2 ;;
    --overwrite) OVERWRITE=true; shift ;;
    --delete-original) DELETE_ORIGINAL=true; shift ;;
    --compression) COMPRESSION="$2"; shift 2 ;;
    --dpi) DPI="$2"; shift 2 ;;
    --page-width) PAGE_WIDTH="$2"; shift 2 ;;
    --page-height) PAGE_HEIGHT="$2"; shift 2 ;;
    --margin) MARGIN="$2"; shift 2 ;;
    --font) FONT_PATH="$2"; shift 2 ;;
    --font-size) FONT_SIZE="$2"; shift 2 ;;
    --irfanview) IR_BIN="$2"; shift 2 ;;
    --prefer-irfanview) PREFER_IRFV=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --*) err "Unknown option: $1"; usage; exit 2 ;;
    *) SOURCE="$1"; shift ;;
  esac
done

if [ -z "$SOURCE" ]; then
  err "SOURCE folder is required"; usage; exit 2
fi

if [ ! -d "$SOURCE" ]; then
  err "SOURCE is not a directory: $SOURCE"; exit 2
fi

# Normalize compression
case "$COMPRESSION" in
  lzw|LZW) COMP_ARG="LZW" ;;
  zip|ZIP|Zip) COMP_ARG="Zip" ;;
  packbits|PackBits|PACKBITS) COMP_ARG="PackBits" ;;
  none|None|NONE) COMP_ARG="None" ;;
  *) err "Unsupported compression: $COMPRESSION"; exit 2 ;;
esac

ensure_parent_dir() { mkdir -p "$(dirname "$1")"; }

build_dest_path() {
  local src="$1"; local dest_root="$2"
  local rel
  if [ -n "$dest_root" ]; then
    rel="${src#$SOURCE}"        # remove SOURCE prefix
    # if src is absolute and not matching, fallback to basename
    if [ "$rel" = "$src" ]; then rel="$(basename "$src")"; fi
    echo "$dest_root/$rel" | sed 's/\\.[^.]*$/.tif/'
  else
    echo "$src" | sed 's/\\.[^.]*$/.tif/'
  fi
}

is_tiff() {
  case "${1,,}" in
    *.tif|*.tiff) return 0 ;;
    *) return 1 ;;
  esac
}

is_image_non_tiff() {
  case "${1,,}" in
    *.jpg|*.jpeg|*.png|*.bmp|*.gif|*.webp) return 0 ;;
    *) return 1 ;;
  esac
}

is_document() {
  case "${1,,}" in
    *.txt|*.docx) return 0 ;;
    *) return 1 ;;
  esac
}

# Convert POSIX path to Windows path for IrfanView, if cygpath is available
to_winpath() {
  local p="$1"
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$p"
  else
    echo "$p"
  fi
}

convert_image_single_page() {
  local src="$1"; local dest="$2"
  if [ -n "$IR_BIN" ] && [ "$PREFER_IRFV" = true ]; then
    local wsrc="$(to_winpath "$src")"; local wdst="$(to_winpath "$dest")"
    # IrfanView uses last saved TIFF options for compression; ensure desired settings in GUI if needed
    "$IR_BIN" "$wsrc" /silent /convert="$wdst"
  else
    local args=("-auto-orient")
    # Flatten transparency onto white to avoid alpha in TIFF
    args+=("-background" "white" "-alpha" "remove" "-alpha" "off" "-flatten")
    args+=("-compress" "$COMP_ARG")
    "$IM_BIN" "$src" "${args[@]}" "$dest"
  fi
}

convert_gif_first_frame() {
  local src="$1"; local dest="$2"
  if [ -n "$IR_BIN" ] && [ "$PREFER_IRFV" = true ]; then
    local wsrc="$(to_winpath "$src")"; local wdst="$(to_winpath "$dest")"
    "$IR_BIN" "$wsrc" /silent /convert="$wdst"
  else
    local frame="${src}[0]"
    local args=("-auto-orient" "-background" "white" "-alpha" "remove" "-alpha" "off" "-flatten" "-compress" "$COMP_ARG")
    "$IM_BIN" "$frame" "${args[@]}" "$dest"
  fi
}

convert_txt_single_page() {
  local src="$1"; local dest="$2"
  # Render text with fixed width and variable height, add margin via border
  local args=("-background" "white" "-fill" "black" "-size" "${PAGE_WIDTH}x"
              "-gravity" "northwest" "-compress" "$COMP_ARG")
  if [ -n "$FONT_PATH" ]; then
    args+=("-font" "$FONT_PATH")
  fi
  args+=("-pointsize" "$FONT_SIZE" "caption:@$src" "-bordercolor" "white" "-border" "${MARGIN}x${MARGIN}" "-density" "$DPI")
  "$IM_BIN" "${args[@]}" "$dest"
}

convert_docx_single_page() {
  local src="$1"; local dest="$2"
  if [ "$have_soffice" != true ]; then
    err "LibreOffice ('soffice') not found; cannot convert DOCX."
    return 1
  fi
  local tmpdir; tmpdir="$(mktemp -d)"
  local base; base="$(basename "$src" .docx)"
  local pdf="$tmpdir/$base.pdf"
  soffice --headless --convert-to pdf --outdir "$tmpdir" "$src" >/dev/null 2>&1 || { err "Failed to convert DOCX to PDF: $src"; rm -rf "$tmpdir"; return 1; }
  if [ ! -f "$pdf" ]; then err "PDF not produced: $pdf"; rm -rf "$tmpdir"; return 1; fi
  # Rasterize PDF pages and append vertically into single tall page
  "$IM_BIN" -density "$DPI" "$pdf" -alpha remove -append -compress "$COMP_ARG" "$dest"
  rm -rf "$tmpdir"
}

process_one() {
  local src="$1"
  local dest; dest="$(build_dest_path "$src" "$OUTPUT_DIR")"
  ensure_parent_dir "$dest"
  if [ -f "$dest" ] && [ "$OVERWRITE" != true ]; then
    log "Skip existing: $dest"
    return 0
  fi
  if [ "$DRY_RUN" = true ]; then
    log "Would convert: $src -> $dest"
    return 0
  fi
  if is_tiff "$src"; then
    return 0
  elif is_image_non_tiff "$src"; then
    case "${src,,}" in
      *.gif) convert_gif_first_frame "$src" "$dest" ;;
      *)     convert_image_single_page "$src" "$dest" ;;
    esac
  elif is_document "$src"; then
    case "${src,,}" in
      *.txt)  convert_txt_single_page "$src" "$dest" ;;
      *.docx) convert_docx_single_page "$src" "$dest" ;;
    esac
  else
    return 0
  fi
  log "Converted: $src -> $dest"
  if [ "$DELETE_ORIGINAL" = true ]; then
    rm -f "$src" || err "Failed to delete original: $src"
  fi
}

# Walk the source tree
while IFS= read -r -d '' file; do
  process_one "$file"
done < <(find "$SOURCE" -type f -print0)

log "Done"
