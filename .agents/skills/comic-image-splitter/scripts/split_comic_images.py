#!/usr/bin/env python3
"""缩短漫画近白边缘与横向纯色间隔并均衡切割长图，保持原格式与页序。"""

from __future__ import annotations

import argparse
import ctypes
import hashlib
import json
import math
import os
import re
import shutil
import sys
import tempfile
import uuid
from collections import Counter
from dataclasses import dataclass, replace
from pathlib import Path

try:
    import cv2
    import numpy as np
    from PIL import Image, JpegImagePlugin
except ImportError as error:  # pragma: no cover - dependency guard
    raise SystemExit(
        "需要安装 OpenCV、Pillow 和 NumPy：python -m pip install opencv-python pillow numpy"
    ) from error


SUPPORTED_FORMATS = {
    ".jpg": "JPEG",
    ".jpeg": "JPEG",
    ".png": "PNG",
    ".webp": "WEBP",
}
MANIFEST_NAME = ".comic-image-splitter.json"
GROUPED_NAME = re.compile(r"^\d+-\d+$")
BLANK_BACKUP_SUBDIR = "blank_pages"
GUTTER_SAMPLE_WIDTH = 320
GUTTER_WHITE_THRESHOLD = 250
GUTTER_COLOR_TOLERANCE = 8
GUTTER_EDGE_COLOR_TOLERANCE = 32
GUTTER_MIN_RUN_WIDTH_RATIO = 0.03
GUTTER_SEARCH_RATIO = 0.15
GUTTER_RETAINED_HEIGHT_MIN = 48
GUTTER_RETAINED_HEIGHT_RATIO = 0.10
GUTTER_RETAINED_HEIGHT_MAX = 160
LOW_INK_CANDIDATE_COUNT = 24
LOW_INK_ROW_SMOOTHING = 7
MIN_SEGMENT_RATIO = 0.75
EDGE_TRIM_WHITE_THRESHOLD = 250
EDGE_TRIM_MAX_NONWHITE_RATIO = 0.002
EDGE_TRIM_MIN_MARGIN_RATIO = 0.02
EDGE_TRIM_SAFETY_PADDING_RATIO = 0.009
EDGE_TRIM_SAMPLE_WIDTH = 1000
BLANK_PAGE_MIN_CHANNEL_VALUE = 250
TEXT_COMPONENT_THRESHOLD = 170
TEXT_COMPONENT_MAX_WIDTH = 180
TEXT_COMPONENT_MAX_HEIGHT = 160
TEXT_COMPONENT_MAX_AREA = 6000
TEXT_COMPONENT_PADDING_RATIO = 0.03
TEXT_COMPONENT_MIN_BACKGROUND_RATIO = 0.52
WEBP_QUALITY = 85
WEBP_QUALITY_MIN_WIDTH = 1280


@dataclass(frozen=True)
class SourceImage:
    """一张输入图片及其基本属性。"""

    path: Path
    width: int
    height: int
    image_format: str
    mode: str
    quantization: dict[int, list[int]] | None
    jpeg_subsampling: int | None
    info: dict[str, object]


@dataclass(frozen=True)
class ImagePlan:
    """一张输入图对应的分段边界。"""

    source: SourceImage
    boundaries: tuple[int, ...]
    gutter_boundaries: tuple[int, ...] = ()
    low_ink_boundaries: tuple[int, ...] = ()
    crop_top: int = 0
    crop_bottom: int | None = None
    text_protected_intervals: tuple[tuple[int, int], ...] = ()
    source_spans: tuple[tuple[int, int], ...] = ()
    is_blank_white: bool = False

    @property
    def effective_bottom(self) -> int:
        return self.source.height if self.crop_bottom is None else self.crop_bottom

    @property
    def effective_height(self) -> int:
        if self.source_spans:
            return sum(bottom - top for top, bottom in self.source_spans)
        return self.effective_bottom - self.crop_top

    @property
    def trimmed(self) -> bool:
        return self.effective_height < self.source.height

    @property
    def piece_count(self) -> int:
        return 0 if self.is_blank_white else len(self.boundaries) + 1

    @property
    def cuts(self) -> tuple[int, ...]:
        if self.is_blank_white:
            return ()
        return (0, *self.boundaries, self.effective_height)


@dataclass(frozen=True)
class OutputPart:
    """一张输出切片。"""

    plan: ImagePlan
    page_index: int
    segment_index: int
    top: int
    bottom: int
    filename: str

    @property
    def expected_size(self) -> tuple[int, int]:
        return self.plan.source.width, self.bottom - self.top


@dataclass
class ChapterJob:
    """一个章节的已校验来源、预览计划与替换范围。"""

    directory: Path
    backup_dir: Path
    blank_backup_dir: Path
    sources: list[SourceImage]
    plans: list[ImagePlan]
    parts: list[OutputPart]
    skipped: list[tuple[str, str]]
    previous_outputs: list[Path]
    records: dict[str, dict]
    source_hashes: dict[str, str]
    previous_hashes: dict[str, str]
    manifest_bytes: bytes | None


def parse_args() -> argparse.Namespace:
    """解析筛选、递归及明确授权的写入参数。"""
    parser = argparse.ArgumentParser(
        description="缩短纵向近白留白并均衡切割 JPG/PNG/WebP 漫画图片。"
    )
    parser.add_argument(
        "--input-dir",
        required=True,
        type=Path,
        help="必须显式指定图片目录；默认只处理顶层，递归时每章独立处理。",
    )
    parser.add_argument("--max-width", type=int, help="只处理宽度不超过此值的图片（包含边界）。")
    parser.add_argument("--exclude-webp", action="store_true", help="跳过 WebP，保留原文件。")
    parser.add_argument("--recursive", action="store_true", help="自动处理子目录，每章独立编号。")
    parser.add_argument("--resplit", action="store_true", help="从已校验的原图备份重新处理，验证新结果后替换旧切片。")
    parser.add_argument(
        "--reference-width",
        type=int,
        default=2160,
        help="用于计算等效高度的参考宽度，默认 2160。",
    )
    parser.add_argument(
        "--min-equivalent-height",
        type=int,
        default=3000,
        help="分段后每段的目标最小等效高度，默认 3000。",
    )
    parser.add_argument(
        "--max-equivalent-height",
        type=int,
        default=5000,
        help="每段在参考宽度下的最大等效高度，默认 5000。",
    )
    parser.add_argument(
        "--start-index",
        type=int,
        default=1,
        help="原始页序号起点，默认 1；分段序号从 0 开始。",
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="实际写入切片并将原图备份到系统下载目录；未指定时只预览。",
    )
    parser.add_argument(
        "--backup-dir",
        type=Path,
        help="单章备份目录；递归时作为备份根目录，按章节相对路径分别存放。",
    )
    parser.add_argument(
        "--keep-blank-pages",
        action="store_true",
        help="保留纯白或近白空白页；默认跳过空白页并在执行时备份原图。",
    )
    parser.add_argument(
        "--preview-limit",
        type=int,
        default=20,
        help="预览中最多列出多少张待切图片，默认 20。",
    )
    args = parser.parse_args()
    if (
        args.reference_width <= 0
        or args.min_equivalent_height <= 0
        or args.max_equivalent_height <= 0
    ):
        parser.error("参考宽度与等效高度范围必须大于 0。")
    if args.min_equivalent_height >= args.max_equivalent_height:
        parser.error("等效高度下限必须小于上限。")
    if args.start_index < 0:
        parser.error("起始编号不能小于 0。")
    if args.preview_limit < 0:
        parser.error("预览条数不能小于 0。")
    if args.max_width is not None and args.max_width <= 0:
        parser.error("宽度筛选上限必须大于 0。")
    if (args.max_width is not None or args.exclude_webp) and args.start_index != 1:
        parser.error("筛选模式保留原始页号，不能同时指定其他 --start-index。")
    return args


def get_downloads_directory() -> Path:
    """获取系统配置的下载目录。"""
    if os.name == "nt":
        from ctypes import wintypes

        class Guid(ctypes.Structure):
            """Windows GUID 结构。"""

            _fields_ = [
                ("data", ctypes.c_ubyte * 16),
            ]

        folder_id = Guid.from_buffer_copy(
            uuid.UUID("374de290-123f-4565-9164-39c4925e467b").bytes_le
        )
        path_pointer = wintypes.LPWSTR()
        shell32 = ctypes.WinDLL("shell32", use_last_error=True)
        shell32.SHGetKnownFolderPath.argtypes = [
            ctypes.POINTER(Guid),
            wintypes.DWORD,
            wintypes.HANDLE,
            ctypes.POINTER(wintypes.LPWSTR),
        ]
        shell32.SHGetKnownFolderPath.restype = ctypes.c_long
        result = shell32.SHGetKnownFolderPath(
            ctypes.byref(folder_id), 0, None, ctypes.byref(path_pointer)
        )
        if result != 0:
            raise OSError(result, "无法获取 Windows 系统下载目录")
        try:
            downloads = Path(path_pointer.value)
        finally:
            ctypes.WinDLL("ole32").CoTaskMemFree(path_pointer)
    else:
        downloads = Path.home() / "Downloads"
        config_path = Path.home() / ".config" / "user-dirs.dirs"
        if config_path.is_file():
            try:
                for line in config_path.read_text(encoding="utf-8").splitlines():
                    match = re.match(r'XDG_DOWNLOAD_DIR="(.*)"$', line.strip())
                    if match:
                        configured = match.group(1).replace("$HOME", str(Path.home()))
                        downloads = Path(configured).expanduser()
                        break
            except OSError:
                pass

    if not downloads.is_dir():
        raise ValueError(f"系统下载目录不存在：{downloads}")
    return downloads.resolve()


def safe_path_component(value: str) -> str:
    """清理目录名中的跨平台非法字符。"""
    cleaned = re.sub(r'[<>:"/\\|?*\x00-\x1f]', "_", value).strip(" .")
    return cleaned or "comic"


def blank_archive_chapter_name(chapter: Path) -> str:
    """生成稳定且可读的空白页归档章节子目录名。"""
    resolved = chapter.expanduser().resolve()
    digest = hashlib.sha256(os.path.normcase(str(resolved)).encode("utf-8")).hexdigest()[:8]
    return f"{safe_path_component(resolved.name)[:80]}-{digest}"


def default_backup_dir(input_dir: Path) -> Path:
    """根据章节原路径生成稳定且不易冲突的系统下载目录备份路径。"""
    chapter_dir = input_dir.expanduser().resolve()
    collection_dir = chapter_dir.parent
    collection_hash = hashlib.sha256(
        os.path.normcase(str(collection_dir)).encode("utf-8")
    ).hexdigest()[:12]
    chapter_hash = hashlib.sha256(
        os.path.normcase(str(chapter_dir)).encode("utf-8")
    ).hexdigest()[:8]
    collection_name = safe_path_component(collection_dir.name)
    chapter_name = safe_path_component(chapter_dir.name)
    return (
        get_downloads_directory()
        / "PicaComic Image Splitter Backups"
        / f"{collection_name}-{collection_hash}"
        / f"{chapter_name}-{chapter_hash}"
        / "back"
    )


def sha256_file(path: Path) -> str:
    """流式计算文件 SHA-256。"""
    digest = hashlib.sha256()
    with path.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def visible_on_white(image: Image.Image) -> Image.Image:
    """将包括调色板透明信息在内的图片合成到白色背景。"""
    if "A" in image.getbands() or "transparency" in image.info:
        rgba = image.convert("RGBA")
        white = Image.new("RGBA", rgba.size, (255, 255, 255, 255))
        return Image.alpha_composite(white, rgba).convert("RGB")
    return image.convert("RGB")


def is_blank_page(image: Image.Image) -> bool:
    """判断图片显示到白色画布后是否每个像素都为白色或近白色。"""
    visible = visible_on_white(image)
    pixels = np.asarray(visible, dtype=np.uint8)
    return bool(np.all(pixels >= BLANK_PAGE_MIN_CHANNEL_VALUE))


def is_pure_white_page(image: Image.Image) -> bool:
    """兼容旧函数名；实际判断纯白及近白空白页。"""
    return is_blank_page(image)


def discover_sources(
    input_dir: Path,
    max_width: int | None = None,
    exclude_webp: bool = False,
    skipped: list[tuple[str, str]] | None = None,
    source_paths: list[Path] | None = None,
) -> tuple[list[SourceImage], int]:
    """读取数字原页并筛选；不修改被排除的图片。"""
    input_dir = input_dir.expanduser().resolve()
    if not input_dir.is_dir():
        raise ValueError(f"输入目录不存在或不是目录：{input_dir}")

    if source_paths is not None:
        paths = source_paths
    else:
        paths = [path for path in input_dir.iterdir()
                 if path.is_file() and path.suffix.lower() in SUPPORTED_FORMATS]
    if not paths:
        raise ValueError("目录顶层没有 JPG/JPEG/PNG/WebP 图片。")

    invalid_names = [path.name for path in paths if not path.stem.isdecimal()]
    if invalid_names:
        raise ValueError(
            "发现非数字文件名，无法安全建立页序：" + ", ".join(invalid_names[:10])
        )

    numbers = [int(path.stem) for path in paths]
    duplicates = sorted(
        number for number, count in Counter(numbers).items() if count > 1
    )
    if duplicates:
        raise ValueError(f"发现重复数字编号，无法确定页序：{duplicates[:10]}")

    paths.sort(key=lambda path: int(path.stem))
    sources: list[SourceImage] = []
    for path in paths:
        if path.is_symlink() or not path.is_file():
            raise ValueError(f"原图必须是普通文件，不能是链接：{path}")
        if exclude_webp and path.suffix.lower() == ".webp":
            if skipped is not None:
                skipped.append((path.name, "排除 WebP"))
            continue
        expected_format = SUPPORTED_FORMATS[path.suffix.lower()]
        try:
            with Image.open(path) as image:
                if image.format != expected_format:
                    raise ValueError(
                        f"格式与扩展名不符：{path.name} 是 {image.format}"
                    )
                if max_width is not None and image.width > max_width:
                    if skipped is not None:
                        skipped.append((path.name, f"宽度 {image.width}px 超过 {max_width}px"))
                    continue
                if getattr(image, "n_frames", 1) != 1:
                    raise ValueError(f"不支持动画图片：{path.name}")
                orientation = image.getexif().get(274, 1)
                if orientation not in (None, 1):
                    raise ValueError(
                        f"图片包含非默认 EXIF 方向，停止以避免切错方向：{path.name}"
                    )
                quantization = getattr(image, "quantization", None)
                jpeg_subsampling = (
                    JpegImagePlugin.get_sampling(image)
                    if image.format == "JPEG"
                    else None
                )
                sources.append(
                    SourceImage(
                        path=path,
                        width=image.width,
                        height=image.height,
                        image_format=image.format,
                        mode=image.mode,
                        quantization=quantization,
                        jpeg_subsampling=jpeg_subsampling,
                        info=dict(image.info),
                    )
                )
        except (OSError, ValueError) as error:
            raise ValueError(f"无法读取 {path.name}：{error}") from error

    ignored_count = sum(
        1
        for path in input_dir.iterdir()
        if path.is_file() and path.suffix.lower() not in SUPPORTED_FORMATS
    )
    return sources, ignored_count


def detect_solid_gutters(image: Image.Image) -> list[tuple[int, int]]:
    """逐像素确认横跨全宽的近纯色间隔，排除文字、线条和明显渐变。"""
    pixels = np.asarray(visible_on_white(image), dtype=np.uint8)
    row_min = np.empty((image.height, 3), dtype=np.int16)
    row_max = np.empty_like(row_min)
    edge_valid = np.ones(image.height, dtype=bool)
    edge_width = min(2, image.width // 1000)
    # 分批统计原始宽度，避免缩略图漏掉细小文字和线条。
    for top in range(0, image.height, 128):
        batch = pixels[top:top + 128]
        interior = batch[:, edge_width:image.width - edge_width] if edge_width else batch
        row_min[top:top + len(batch)] = interior.min(axis=1)
        row_max[top:top + len(batch)] = interior.max(axis=1)
        if edge_width:
            # 最外侧至多两像素可有轻微编码杂色，明显画线仍使整行不合格。
            edges = np.concatenate((batch[:, :edge_width], batch[:, -edge_width:]), axis=1)
            midpoint = (row_min[top:top + len(batch)] + row_max[top:top + len(batch)]) / 2
            edge_valid[top:top + len(batch)] = np.all(
                np.abs(edges.astype(np.int16) - midpoint[:, None, :])
                <= GUTTER_EDGE_COLOR_TOLERANCE, axis=(1, 2)
            )
    uniform = np.all(row_max - row_min <= GUTTER_COLOR_TOLERANCE, axis=1) & edge_valid
    centers = (row_min + row_max) / 2
    color_changes = np.any(
        np.abs(np.diff(centers, axis=0)) > GUTTER_COLOR_TOLERANCE, axis=1
    )
    breaks = np.flatnonzero(~uniform[:-1] | ~uniform[1:] | color_changes) + 1
    boundaries = np.concatenate(([0], breaks, [image.height]))
    minimum_run = max(8, math.ceil(image.width * GUTTER_MIN_RUN_WIDTH_RATIO))
    gutters: list[tuple[int, int]] = []
    for start, end in zip(boundaries, boundaries[1:]):
        # 只缩短内容之间的间隔；整张纯色页及非白边缘保持原样。
        if start == 0 or end == image.height or end - start < minimum_run:
            continue
        if not np.all(uniform[start:end]):
            continue
        # 按区域累计色差分组，避免边界抗锯齿使中间的大块纯色整体失效。
        band_start = int(start)
        minimum = row_min[start].copy()
        maximum = row_max[start].copy()
        for row in range(int(start) + 1, int(end)):
            next_minimum = np.minimum(minimum, row_min[row])
            next_maximum = np.maximum(maximum, row_max[row])
            if np.any(next_maximum - next_minimum > GUTTER_COLOR_TOLERANCE):
                if row - band_start >= minimum_run:
                    gutters.append((band_start, row))
                band_start = row
                minimum, maximum = row_min[row].copy(), row_max[row].copy()
            else:
                minimum, maximum = next_minimum, next_maximum
        if end - band_start >= minimum_run:
            gutters.append((band_start, int(end)))
    return gutters


def analyze_horizontal_space(
    image: Image.Image,
) -> tuple[list[tuple[int, int]], np.ndarray]:
    """返回全宽纯色间隔与逐行墨量，缩略图只用于切口墨量评分。"""
    gray = visible_on_white(image).convert("L")
    sample_width = min(GUTTER_SAMPLE_WIDTH, image.width)
    if sample_width != image.width:
        gray = gray.resize(
            (sample_width, image.height),
            resample=Image.Resampling.BILINEAR,
        )

    pixels = np.asarray(gray, dtype=np.uint8)
    gutters = detect_solid_gutters(image)
    ink_ratio = np.mean(pixels < GUTTER_WHITE_THRESHOLD, axis=1)
    smoothing = np.ones(LOW_INK_ROW_SMOOTHING, dtype=np.float32)
    smoothing /= smoothing.size
    ink_scores = np.convolve(ink_ratio, smoothing, mode="same")
    return gutters, ink_scores


def detect_vertical_edge_trim(image: Image.Image) -> tuple[int, int]:
    """只检测并缩短上下边缘的大块近白空白，始终保留完整原始宽度。"""
    sample_width = min(EDGE_TRIM_SAMPLE_WIDTH, image.width)
    grayscale = visible_on_white(image).convert("L")
    if sample_width != image.width:
        grayscale = grayscale.resize(
            (sample_width, image.height),
            resample=Image.Resampling.BILINEAR,
        )

    pixels = np.asarray(grayscale, dtype=np.uint8)
    nonwhite_limit = max(2, math.ceil(sample_width * EDGE_TRIM_MAX_NONWHITE_RATIO))
    content_rows = np.count_nonzero(pixels < EDGE_TRIM_WHITE_THRESHOLD, axis=1) > nonwhite_limit
    content_positions = np.flatnonzero(content_rows)
    if content_positions.size == 0:
        return 0, image.height

    first_content = int(content_positions[0])
    last_content = int(content_positions[-1]) + 1
    minimum_margin = max(32, math.ceil(image.height * EDGE_TRIM_MIN_MARGIN_RATIO))
    safety_padding = max(16, math.ceil(image.height * EDGE_TRIM_SAFETY_PADDING_RATIO))

    crop_top = 0
    if first_content >= minimum_margin:
        crop_top = max(0, first_content - safety_padding)

    crop_bottom = image.height
    bottom_margin = image.height - last_content
    if bottom_margin >= minimum_margin:
        crop_bottom = min(image.height, last_content + safety_padding)

    if crop_bottom <= crop_top:
        return 0, image.height
    return crop_top, crop_bottom


def make_vertical_source_spans(
    image: Image.Image,
    crop_top: int,
    crop_bottom: int,
) -> tuple[tuple[int, int], ...]:
    """缩短上下近白边缘与过宽纯色间隔，只保留原图中连续的行区间。"""
    content = image.crop((0, crop_top, image.width, crop_bottom))
    gutters = detect_solid_gutters(content)
    retained_height = min(
        GUTTER_RETAINED_HEIGHT_MAX,
        max(
            GUTTER_RETAINED_HEIGHT_MIN,
            round(image.width * GUTTER_RETAINED_HEIGHT_RATIO),
        ),
    )
    compress_threshold = retained_height + max(16, math.ceil(image.width * 0.04))
    spans: list[tuple[int, int]] = []
    source_cursor = crop_top

    for gutter_start, gutter_end in gutters:
        gutter_height = gutter_end - gutter_start
        if gutter_height <= compress_threshold:
            continue

        removed_height = gutter_height - retained_height
        removed_start = gutter_start + (gutter_height - removed_height) // 2
        removed_end = removed_start + removed_height
        absolute_start = crop_top + removed_start
        absolute_end = crop_top + removed_end
        if source_cursor < absolute_start:
            spans.append((source_cursor, absolute_start))
        source_cursor = absolute_end

    if source_cursor < crop_bottom:
        spans.append((source_cursor, crop_bottom))
    if not spans:
        return ((crop_top, crop_bottom),)
    return tuple(spans)


def build_vertical_compacted_image(
    image: Image.Image,
    source_spans: tuple[tuple[int, int], ...],
) -> Image.Image:
    """按保留行区间拼接图片，保持原宽度和像素，不缩放图像。"""
    height = sum(bottom - top for top, bottom in source_spans)
    compacted = Image.new(image.mode, (image.width, height))
    compacted.info.update(image.info)
    if image.mode == "P":
        palette = image.getpalette()
        if palette is not None:
            compacted.putpalette(palette)

    output_top = 0
    for source_top, source_bottom in source_spans:
        strip = image.crop((0, source_top, image.width, source_bottom))
        compacted.paste(strip, (0, output_top))
        output_top += source_bottom - source_top
    return compacted


def source_y_for_compacted_y(plan: ImagePlan, compacted_y: int) -> int:
    """将压缩图中的纵坐标映射回原图，便于说明预览切口位置。"""
    remaining = max(0, compacted_y)
    for source_top, source_bottom in plan.source_spans:
        span_height = source_bottom - source_top
        if remaining <= span_height:
            return source_top + remaining
        remaining -= span_height
    return plan.effective_bottom


def detect_text_protected_intervals(image: Image.Image) -> list[tuple[int, int]]:
    """用小字形连通区域估计文字块范围，供切口避让使用。"""
    grayscale = visible_on_white(image).convert("L")
    if grayscale.width > EDGE_TRIM_SAMPLE_WIDTH:
        sampled_height = round(
            grayscale.height * EDGE_TRIM_SAMPLE_WIDTH / grayscale.width
        )
        grayscale = grayscale.resize(
            (EDGE_TRIM_SAMPLE_WIDTH, sampled_height),
            resample=Image.Resampling.BILINEAR,
        )

    gray_pixels = np.asarray(grayscale, dtype=np.uint8)
    binary = (gray_pixels < TEXT_COMPONENT_THRESHOLD).astype(np.uint8)
    component_count, _, stats, _ = cv2.connectedComponentsWithStats(binary, 8)
    y_scale = image.height / grayscale.height
    padding = max(24, round(image.width * TEXT_COMPONENT_PADDING_RATIO))
    component_stats = stats[1:component_count]
    valid_components = component_stats[
        (component_stats[:, 2] >= 3)
        & (component_stats[:, 3] >= 5)
        & (component_stats[:, 2] <= TEXT_COMPONENT_MAX_WIDTH)
        & (component_stats[:, 3] <= TEXT_COMPONENT_MAX_HEIGHT)
        & (component_stats[:, 4] >= 8)
        & (component_stats[:, 4] <= TEXT_COMPONENT_MAX_AREA)
    ]
    components = sorted(
        (
            int(y),
            int(y + height),
            int(x),
            int(x + width),
        )
        for x, y, width, height, _ in valid_components
    )
    line_groups: list[list[int]] = []
    horizontal_tolerance = max(40, round(grayscale.width * 0.2))
    for top, bottom, left, right in components:
        if (
            line_groups
            and top <= line_groups[-1][1] + 12
            and left <= line_groups[-1][3] + horizontal_tolerance
            and right >= line_groups[-1][2] - horizontal_tolerance
        ):
            group = line_groups[-1]
            group[1] = max(group[1], bottom)
            group[2] = min(group[2], left)
            group[3] = max(group[3], right)
            group[4] += 1
        else:
            line_groups.append([top, bottom, left, right, 1])

    margin = max(16, round(grayscale.width * 0.03))
    intervals: list[tuple[int, int]] = []
    for top, bottom, left, right, component_total in line_groups:
        line_width = right - left
        if (
            component_total < 3
            or line_width < max(20, round(grayscale.width * 0.03))
            or line_width > grayscale.width * 0.75
            or bottom - top > max(120, round(grayscale.width * 0.12))
        ):
            continue
        sample_left = max(0, left - margin)
        sample_right = min(grayscale.width, right + margin)
        sample_top = max(0, top - margin)
        sample_bottom = min(grayscale.height, bottom + margin)
        background = gray_pixels[
            sample_top:sample_bottom, sample_left:sample_right
        ]
        if np.mean(background >= 230) < TEXT_COMPONENT_MIN_BACKGROUND_RATIO:
            continue
        scaled_top = math.floor(top * y_scale)
        scaled_bottom = math.ceil(bottom * y_scale)
        intervals.append(
            (
                max(0, scaled_top - padding),
                min(image.height, scaled_bottom + padding),
            )
        )

    intervals.sort()
    merged: list[tuple[int, int]] = []
    for top, bottom in intervals:
        if merged and top <= merged[-1][1]:
            merged[-1] = (merged[-1][0], max(merged[-1][1], bottom))
        else:
            merged.append((top, bottom))
    return merged


def find_low_ink_rows(
    ink_scores: np.ndarray,
    ideal: int,
    tolerance: int,
    minimum_spacing: int,
    blocked_intervals: tuple[tuple[int, int], ...] = (),
) -> tuple[list[tuple[int, float]], float]:
    """在均分点附近选出墨量较低、彼此分散的候选切口。"""
    start = max(1, ideal - tolerance)
    end = min(len(ink_scores) - 1, ideal + tolerance)
    if start > end:
        return [], 1.0

    window = ink_scores[start : end + 1]
    minimum = float(np.min(window))
    maximum = float(np.max(window))
    score_range = maximum - minimum

    def ink_cost(position: int) -> float:
        score = float(ink_scores[position])
        relative_cost = (
            0.0 if score_range < 1e-9 else (score - minimum) / score_range
        )
        absolute_cost = min(score / 0.02, 1.0)
        return 0.7 * absolute_cost + 0.3 * relative_cost

    ideal_is_blocked = any(top <= ideal < bottom for top, bottom in blocked_intervals)
    normalized_ideal_score = 1.0 if ideal_is_blocked else ink_cost(ideal)
    bin_count = min(
        LOW_INK_CANDIDATE_COUNT,
        max(1, len(window) // max(1, minimum_spacing)),
    )
    edges = np.linspace(0, len(window), bin_count + 1, dtype=int)
    selected_by_position: dict[int, float] = {}
    for bin_start, bin_end in zip(edges, edges[1:]):
        if bin_start >= bin_end:
            continue
        bin_scores = window[bin_start:bin_end]
        positions = np.arange(start + bin_start, start + bin_end)
        available = np.ones(positions.size, dtype=bool)
        for blocked_start, blocked_end in blocked_intervals:
            available &= ~(
                (positions >= blocked_start) & (positions < blocked_end)
            )
        if not np.any(available):
            continue
        available_scores = bin_scores[available]
        bin_minimum = float(np.min(available_scores))
        available_offsets = np.flatnonzero(available)
        minimum_offsets = available_offsets[available_scores == bin_minimum]
        bin_center = (bin_start + bin_end - 1) / 2
        offset = min(minimum_offsets, key=lambda candidate: abs(candidate - bin_center))
        position = start + int(bin_start + offset)
        normalized_score = ink_cost(position)
        selected_by_position[position] = normalized_score
    return sorted(selected_by_position.items()), normalized_ideal_score


def choose_balanced_boundaries(
    height: int,
    width: int,
    gutter_ranges: list[tuple[int, int]],
    ink_scores: np.ndarray,
    reference_width: int,
    min_equivalent_height: int,
    max_equivalent_height: int,
    protected_intervals: tuple[tuple[int, int], ...] = (),
) -> tuple[tuple[int, ...], tuple[int, ...], tuple[int, ...]]:
    """优先选横向留白，其次避开墨量较大的行，并控制每段等效高度。"""
    equivalent_height = height * reference_width / width
    if equivalent_height <= max_equivalent_height:
        return (), (), ()

    minimum_piece_count = math.ceil(equivalent_height / max_equivalent_height)
    maximum_piece_count = math.floor(equivalent_height / min_equivalent_height)
    target_equivalent_height = (min_equivalent_height + max_equivalent_height) / 2
    target_piece_count = math.floor(
        equivalent_height / target_equivalent_height + 0.5
    )
    if maximum_piece_count >= minimum_piece_count:
        piece_count = min(
            maximum_piece_count,
            max(minimum_piece_count, target_piece_count),
        )
    else:
        # 高度不足以同时满足上下限时，优先使用最少段数保证不超过上限。
        piece_count = minimum_piece_count
    average_height = height / piece_count
    min_segment = min_equivalent_height * width / reference_width
    if min_segment * piece_count > height:
        # 5,000–6,000 等效像素的图片无法切成两段且同时满足 3,000 的下限。
        min_segment = average_height * MIN_SEGMENT_RATIO
    max_segment = max_equivalent_height * width / reference_width
    tolerance = average_height * GUTTER_SEARCH_RATIO
    minimum_spacing = max(4, round(width * 0.01))
    ideal_points = [
        round(height * part / piece_count)
        for part in range(1, piece_count)
    ]

    candidates: list[list[tuple[int, str, float]]] = []
    for boundary_index, ideal in enumerate(ideal_points, start=1):
        tolerance_pixels = math.ceil(tolerance)
        low_ink_rows, normalized_ideal_score = find_low_ink_rows(
            ink_scores,
            ideal,
            tolerance_pixels,
            minimum_spacing,
            protected_intervals,
        )
        feasible_start = max(
            1,
            math.ceil(boundary_index * min_segment),
            math.ceil(height - (piece_count - boundary_index) * max_segment),
        )
        feasible_end = min(
            height - 1,
            math.floor(boundary_index * max_segment),
            math.floor(height - (piece_count - boundary_index) * min_segment),
        )
        extended_tolerance = max(ideal - feasible_start, feasible_end - ideal)
        extended_rows, _ = find_low_ink_rows(
            ink_scores,
            ideal,
            max(0, extended_tolerance),
            minimum_spacing,
            protected_intervals,
        )
        choices: dict[int, tuple[str, float]] = {}
        ideal_is_protected = any(
            top <= ideal < bottom for top, bottom in protected_intervals
        )
        if normalized_ideal_score <= 0.05 and not ideal_is_protected:
            choices[ideal] = ("低墨量", normalized_ideal_score)
        for position, normalized_score in [*low_ink_rows, *extended_rows]:
            if feasible_start <= position <= feasible_end:
                choices[position] = ("低墨量", normalized_score)
        for protected_start, protected_end in protected_intervals:
            if protected_end < feasible_start or protected_start > feasible_end:
                continue
            edge_positions = {
                protected_start - 1,
                protected_start - 4,
                protected_end,
                protected_end + 4,
            }
            for position in edge_positions:
                if not feasible_start <= position <= feasible_end:
                    continue
                edge_rows, edge_score = find_low_ink_rows(
                    ink_scores,
                    position,
                    0,
                    minimum_spacing,
                    protected_intervals,
                )
                if edge_rows:
                    choices[position] = ("低墨量", edge_score)
        for gutter_start, gutter_end in gutter_ranges:
            overlap_start = max(feasible_start, gutter_start)
            overlap_end = min(feasible_end, gutter_end - 1)
            if overlap_start > overlap_end:
                continue
            interval_width = overlap_end - overlap_start + 1
            step = max(1, math.ceil(interval_width / 600))
            positions = set(range(overlap_start, overlap_end + 1, step))
            positions.update((overlap_start, overlap_end))
            center = (gutter_start + gutter_end - 1) // 2
            positions.add(min(overlap_end, max(overlap_start, center)))
            for position in positions:
                choices[position] = ("留白", 0.0)
        candidates.append(
            [
                (position, kind, score)
                for position, (kind, score) in sorted(choices.items())
            ]
        )

    # 状态为“上一个切点 -> 累计代价、切点和切口来源”。
    states: dict[int, tuple[float, tuple[int, ...], tuple[str, ...]]] = {
        0: (0.0, (), ())
    }
    for boundary_options in candidates:
        next_states: dict[int, tuple[float, tuple[int, ...], tuple[str, ...]]] = {}
        for previous, (previous_cost, previous_cuts, previous_kinds) in states.items():
            for position, kind, ink_cost in boundary_options:
                segment_height = position - previous
                if segment_height < min_segment or segment_height > max_segment:
                    continue
                balance_cost = (segment_height / average_height - 1) ** 2
                gutter_bonus = 0.1 if kind == "留白" else 0.0
                quiet_cost = ink_cost * 2 if kind != "留白" else 0.0
                distance_cost = (
                    abs(position - ideal_points[len(previous_cuts)])
                    / max(average_height, 1)
                    * 0.05
                )
                cost = (
                    previous_cost
                    + balance_cost
                    + quiet_cost
                    + distance_cost
                    - gutter_bonus
                )
                current = next_states.get(position)
                if current is None or cost < current[0]:
                    next_states[position] = (
                        cost,
                        (*previous_cuts, position),
                        (*previous_kinds, kind),
                    )
        states = next_states
        if not states:
            break

    best: tuple[float, tuple[int, ...], tuple[str, ...]] | None = None
    for previous, (cost, cuts, kinds) in states.items():
        final_height = height - previous
        if final_height < min_segment or final_height > max_segment:
            continue
        final_cost = cost + (final_height / average_height - 1) ** 2
        if best is None or final_cost < best[0]:
            best = (final_cost, cuts, kinds)

    if best is not None:
        boundaries, kinds = best[1], best[2]
        gutter_boundaries = tuple(
            position for position, kind in zip(boundaries, kinds) if kind == "留白"
        )
        low_ink_boundaries = tuple(
            position for position, kind in zip(boundaries, kinds) if kind == "低墨量"
        )
        return boundaries, gutter_boundaries, low_ink_boundaries

    # 均分边界是无法在候选切口中找到可行组合时的最后回退方案。
    return tuple(ideal_points), (), ()


def make_plans(
    sources: list[SourceImage],
    reference_width: int,
    min_equivalent_height: int,
    max_equivalent_height: int,
    keep_blank_pages: bool = False,
) -> list[ImagePlan]:
    plans: list[ImagePlan] = []
    for source in sources:
        with Image.open(source.path) as image:
            if not keep_blank_pages and is_blank_page(image):
                plans.append(ImagePlan(source, (), is_blank_white=True))
                continue
            crop_top, crop_bottom = detect_vertical_edge_trim(image)
            def make_plan(
                content_top: int,
                content_bottom: int,
                compact_whitespace: bool,
            ) -> ImagePlan:
                source_spans = (
                    make_vertical_source_spans(image, content_top, content_bottom)
                    if compact_whitespace
                    else ((content_top, content_bottom),)
                )
                compacted = build_vertical_compacted_image(image, source_spans)
                content_height = compacted.height
                if content_height * reference_width / source.width <= max_equivalent_height:
                    return ImagePlan(
                        source,
                        (),
                        crop_top=content_top,
                        crop_bottom=content_bottom,
                        source_spans=source_spans,
                    )

                gutter_ranges, ink_scores = analyze_horizontal_space(compacted)
                text_intervals = tuple(
                    detect_text_protected_intervals(compacted)
                )
                boundaries, gutter_boundaries, low_ink_boundaries = (
                    choose_balanced_boundaries(
                        content_height,
                        source.width,
                        gutter_ranges,
                        ink_scores,
                        reference_width,
                        min_equivalent_height,
                        max_equivalent_height,
                        text_intervals,
                    )
                )
                return ImagePlan(
                    source,
                    boundaries,
                    gutter_boundaries,
                    low_ink_boundaries,
                    content_top,
                    content_bottom,
                    text_intervals,
                    source_spans,
                )

            def has_safe_cuts(plan: ImagePlan) -> bool:
                if plan.piece_count <= 1:
                    return True
                if any(
                    position not in plan.gutter_boundaries
                    and any(
                        start <= position < end
                        for start, end in plan.text_protected_intervals
                    )
                    for position in plan.boundaries
                ):
                    return False
                can_meet_minimum = (
                    plan.effective_height * reference_width
                    >= min_equivalent_height
                    * plan.piece_count
                    * source.width
                )
                for top, bottom in zip(plan.cuts, plan.cuts[1:]):
                    height = (bottom - top) * reference_width / source.width
                    if height > max_equivalent_height + 1e-6:
                        return False
                    if can_meet_minimum and height < min_equivalent_height - 1e-6:
                        return False
                return True

            plan = make_plan(crop_top, crop_bottom, compact_whitespace=True)
            if not has_safe_cuts(plan):
                if crop_top > 0 or crop_bottom < source.height:
                    untrimmed_plan = make_plan(
                        0,
                        source.height,
                        compact_whitespace=True,
                    )
                    if has_safe_cuts(untrimmed_plan):
                        plan = untrimmed_plan
                    else:
                        plan = make_plan(
                            crop_top,
                            crop_bottom,
                            compact_whitespace=False,
                        )
                else:
                    plan = make_plan(
                        crop_top,
                        crop_bottom,
                        compact_whitespace=False,
                    )
                if not has_safe_cuts(plan):
                    plan = make_plan(
                        0,
                        source.height,
                        compact_whitespace=False,
                    )
                if not has_safe_cuts(plan):
                    raise ValueError(
                        f"无法同时找到避开文字且满足长度范围的切口：{source.path}"
                    )
        plans.append(plan)
    return plans


def make_output_parts(
    plans: list[ImagePlan], start_index: int, preserve_page_numbers: bool = False
) -> list[OutputPart]:
    """建立输出页序；筛选时保留原始页号，不挤占未处理图片的位置。"""
    parts: list[OutputPart] = []
    page_index = start_index
    for plan in plans:
        if plan.is_blank_white:
            continue
        if preserve_page_numbers:
            page_index = int(plan.source.path.stem)
        for segment_index, (top, bottom) in enumerate(zip(plan.cuts, plan.cuts[1:])):
            suffix = ""
            if plan.piece_count > 1 or plan.trimmed:
                suffix = f"-{segment_index}"
            parts.append(
                OutputPart(
                    plan=plan,
                    page_index=page_index,
                    segment_index=segment_index,
                    top=top,
                    bottom=bottom,
                    filename=(
                        f"{page_index}{suffix}{plan.source.path.suffix}"
                    ),
                )
            )
        page_index += 1
    return parts


def equivalent_height(part: OutputPart, reference_width: int) -> float:
    return part.expected_size[1] * reference_width / part.expected_size[0]


def minimum_height_is_feasible(
    plan: ImagePlan,
    reference_width: int,
    min_equivalent_height: int,
) -> bool:
    """判断处理后的总等效高度能否满足所有分段的最小高度。"""
    return (
        plan.effective_height * reference_width
        >= min_equivalent_height * plan.piece_count * plan.source.width
    )


def print_preview(
    input_dir: Path,
    sources: list[SourceImage],
    plans: list[ImagePlan],
    parts: list[OutputPart],
    ignored_count: int,
    reference_width: int,
    min_equivalent_height: int,
    max_equivalent_height: int,
    start_index: int,
    preview_limit: int,
) -> None:
    blank_plans = [plan for plan in plans if plan.is_blank_white]
    split_plans = [plan for plan in plans if plan.piece_count > 1]
    trimmed_plans = [plan for plan in plans if plan.trimmed]
    ext_counts = Counter(source.path.suffix.lower() for source in sources)
    output_ext_counts = Counter(part.plan.source.path.suffix.lower() for part in parts)
    output_formats = ", ".join(
        f"{ext} {count} 张" for ext, count in sorted(output_ext_counts.items())
    ) or "无"
    page_range = (
        f"{parts[0].filename} 至 {parts[-1].filename}"
        if parts
        else "无（没有保留页面）"
    )
    split_output_heights = [
        equivalent_height(part, reference_width)
        for part in parts
        if part.plan.piece_count > 1
    ]

    print(f"输入目录：{input_dir}")
    print(
        f"输入图片：{len(sources)} 张 "
        f"({', '.join(f'{ext} {count} 张' for ext, count in sorted(ext_counts.items()))})"
    )
    if ignored_count:
        print(f"忽略其他扩展名文件：{ignored_count} 个（不会修改）")
    print(
        f"切割规则：分段等效高度目标 {min_equivalent_height}–"
        f"{max_equivalent_height} px (@ {reference_width} px 宽)，"
        "缩短上下近白边缘与过宽横向纯色间隔并保留间距；左右边缘完整保留；"
        "切口优先完整横向留白，其次选择墨量较低的行；默认跳过白/近白空白页"
    )
    print(
        f"纵向留白有缩短：{len(trimmed_plans)} 张（左右边缘不裁）；"
        f"需切割：{len(split_plans)} 张；空白页跳过：{len(blank_plans)} 张；"
        f"预计输出：{len(parts)} 张"
    )
    for plan in blank_plans:
        print(f"  空白页跳过：{plan.source.path.name}（执行时仍保留原图备份）")
    print(
        f"输出格式：{output_formats}；页序格式：{page_range}"
    )
    if split_output_heights:
        print(
            f"切割段等效高度：{min(split_output_heights):.0f}–"
            f"{max(split_output_heights):.0f} px；"
            f"目标范围 {min_equivalent_height}–{max_equivalent_height} px"
        )
    print(
        f"未切割原图：{len(sources) - len(split_plans) - len(blank_plans)} 张，"
        f"均不超过 {max_equivalent_height} px"
    )
    infeasible_minimum = sum(
        1
        for plan in split_plans
        if not minimum_height_is_feasible(
            plan, reference_width, min_equivalent_height
        )
    )
    if infeasible_minimum:
        print(
            f"有 {infeasible_minimum} 张原图高度不足以同时满足上下限；"
            "这些图片会优先保证不超过上限，单段可能低于最小目标。"
        )

    preview_plans = [
        plan
        for plan in plans
        if plan.piece_count > 1 or plan.trimmed
    ]
    if preview_limit == 0:
        return
    print("切割与纵向留白压缩预览：")
    for plan in preview_plans[:preview_limit]:
        heights = [
            round(equivalent_height(part, reference_width))
            for part in parts
            if part.plan is plan
        ]
        cut_details = []
        for boundary in plan.boundaries:
            if boundary in plan.gutter_boundaries:
                source = "留白"
            elif boundary in plan.low_ink_boundaries:
                source = "低墨量"
            else:
                source = "均分"
            cut_details.append(
                f"y={source_y_for_compacted_y(plan, boundary)}（{source}）"
            )
        cuts = "、".join(cut_details) if cut_details else "无切口"
        action = f"{plan.piece_count} 段" if plan.piece_count > 1 else "保留 1 页"
        removed_whitespace = plan.source.height - plan.effective_height
        interior_removed = max(
            0,
            removed_whitespace
            - plan.crop_top
            - (plan.source.height - plan.effective_bottom),
        )
        print(
            f"  {plan.source.path.name}: {action}，"
            f"上下边缘留白 {plan.crop_top}px/"
            f"{plan.source.height - plan.effective_bottom}px，"
            f"大横向纯色间隔缩短 {interior_removed}px，"
            f"切口 {cuts}；等效高度 {' / '.join(map(str, heights))} px"
        )
    remaining = len(preview_plans) - min(preview_limit, len(preview_plans))
    if remaining:
        print(f"  ……其余 {remaining} 张符合相同的均分规则")


def save_piece(image: Image.Image, source: SourceImage, destination: Path) -> None:
    crop = image
    if source.image_format == "JPEG":
        if crop.mode not in ("RGB", "L", "CMYK"):
            if "A" in crop.getbands():
                rgba = crop.convert("RGBA")
                background = Image.new("RGB", crop.size, "white")
                background.paste(rgba, mask=rgba.getchannel("A"))
                crop = background
            else:
                crop = crop.convert("RGB")
        options: dict[str, object] = {"optimize": True}
        if source.quantization:
            options["qtables"] = source.quantization
            options["subsampling"] = source.jpeg_subsampling
        else:
            options.update({"quality": 95, "subsampling": 0})
        for key in ("icc_profile", "exif", "dpi", "comment"):
            value = source.info.get(key)
            if value is not None:
                options[key] = value
    elif source.image_format == "PNG":
        # PNG 是无损格式。保留裁切图的原始色彩模式，避免调色板或透明通道被转换。
        options = {"optimize": False, "compress_level": 6}
        for key in ("icc_profile", "exif", "dpi", "transparency"):
            value = source.info.get(key)
            if value is not None:
                options[key] = value
    else:
        if crop.mode not in ("RGB", "RGBA", "L"):
            crop = crop.convert("RGBA" if "A" in crop.getbands() else "RGB")
        quality = WEBP_QUALITY if crop.width > WEBP_QUALITY_MIN_WIDTH else 100
        options = {"quality": quality, "method": 0, "exact": True}
        for key in ("icc_profile", "exif", "xmp"):
            value = source.info.get(key)
            if value is not None:
                options[key] = value

    crop.save(destination, format=source.image_format, **options)


def verify_staged_parts(
    stage_dir: Path,
    parts: list[OutputPart],
    reference_width: int,
    min_equivalent_height: int,
    max_equivalent_height: int,
) -> None:
    expected_names = [part.filename for part in parts]
    actual_names = sorted(
        (path.name for path in stage_dir.iterdir() if path.is_file()),
        key=lambda name: tuple(int(part) for part in Path(name).stem.split("-")),
    )
    if actual_names != expected_names:
        raise RuntimeError("暂存结果的文件数或页序编号与预览不一致。")

    for part_number, part in enumerate(parts, start=1):
        path = stage_dir / part.filename
        try:
            with Image.open(path) as output:
                if output.format != part.plan.source.image_format:
                    raise RuntimeError(f"输出格式不符：{part.filename}")
                if output.size != part.expected_size:
                    raise RuntimeError(f"输出尺寸不符：{part.filename}")
                output.load()
        except OSError as error:
            raise RuntimeError(f"切片无法读取：{part.filename}：{error}") from error

        if equivalent_height(part, reference_width) > max_equivalent_height + 1e-6:
            raise RuntimeError(f"切片超过等效高度上限：{part.filename}")
        can_meet_minimum = minimum_height_is_feasible(
            part.plan, reference_width, min_equivalent_height
        )
        one_pixel_tolerance = reference_width / part.plan.source.width
        if (
            part.plan.piece_count > 1
            and can_meet_minimum
            and equivalent_height(part, reference_width)
            < min_equivalent_height - one_pixel_tolerance
        ):
            raise RuntimeError(f"切片低于等效高度下限：{part.filename}")
        if part_number % 100 == 0 or part_number == len(parts):
            print(f"核验切片：{part_number}/{len(parts)}", flush=True)


def move_to_recycle_bin(path: Path) -> None:
    """将文件或目录移入回收站；失败时保留原路径并抛出异常。"""
    if not path.exists():
        return

    resolved_path = path.expanduser().resolve()
    if os.name == "nt":
        from ctypes import wintypes

        class ShellFileOperation(ctypes.Structure):
            """Windows Shell 文件操作参数。"""

            _fields_ = [
                ("hwnd", wintypes.HWND),
                ("wFunc", ctypes.c_uint),
                ("pFrom", wintypes.LPCWSTR),
                ("pTo", wintypes.LPCWSTR),
                ("fFlags", ctypes.c_ushort),
                ("fAnyOperationsAborted", wintypes.BOOL),
                ("hNameMappings", ctypes.c_void_p),
                ("lpszProgressTitle", wintypes.LPCWSTR),
            ]

        source_buffer = ctypes.create_unicode_buffer(f"{resolved_path}\0\0")
        operation = ShellFileOperation()
        operation.wFunc = 3  # FO_DELETE
        operation.pFrom = ctypes.cast(source_buffer, wintypes.LPCWSTR)
        operation.fFlags = 0x0004 | 0x0010 | 0x0040 | 0x0400
        shell32 = ctypes.WinDLL("shell32", use_last_error=True)
        shell32.SHFileOperationW.argtypes = [ctypes.POINTER(ShellFileOperation)]
        shell32.SHFileOperationW.restype = ctypes.c_int
        result = shell32.SHFileOperationW(ctypes.byref(operation))
        if result != 0 or operation.fAnyOperationsAborted:
            raise OSError(result, f"无法移入回收站，文件已保留：{resolved_path}")
        if resolved_path.exists():
            raise OSError(f"移入回收站后路径仍存在，已保留：{resolved_path}")
        return

    try:
        from send2trash import send2trash
    except ImportError as error:
        raise RuntimeError(
            f"当前平台没有可用的回收站接口，已保留路径：{resolved_path}"
        ) from error
    send2trash(str(resolved_path))


def is_directory_link(path: Path) -> bool:
    """识别符号链接和 Windows 目录联接，避免递归越过输入边界。"""
    return path.is_symlink() or getattr(path, "is_junction", lambda: False)()


def skip_directory(path: Path) -> bool:
    """排除备份、临时、隐藏目录及目录链接。"""
    if is_directory_link(path):
        return True
    name = path.name.lower()
    hidden = bool(getattr(path.stat(), "st_file_attributes", 0) & 2)
    return (
        hidden
        or name.startswith(".")
        or name in {"back", "tmp", "temp", "__pycache__", "picacomic image splitter backups"}
        or "_split_stage_" in name
        or "_backup_stage_" in name
        or "_resplit_input_" in name
    )


def discover_chapters(root: Path, recursive: bool) -> tuple[list[Path], list[Path]]:
    """发现含图片的目录；根目录有图片时也作为独立章节。"""
    if not root.is_dir():
        raise ValueError(f"输入目录不存在或不是目录：{root}")
    if not recursive:
        return [root], []
    chapters: list[Path] = []
    excluded: list[Path] = []

    def report_walk_error(error: OSError) -> None:
        """目录不可读时中止，避免批处理漏章。"""
        raise error

    for current, directories, files in os.walk(root, followlinks=False, onerror=report_walk_error):
        directory = Path(current)
        allowed = []
        for name in sorted(directories):
            child = directory / name
            if skip_directory(child):
                excluded.append(child)
            else:
                allowed.append(name)
        directories[:] = allowed
        if MANIFEST_NAME in files or any(Path(name).suffix.lower() in SUPPORTED_FORMATS for name in files):
            chapters.append(directory)
    if not chapters:
        raise ValueError("输入目录及可遍历的子目录中没有漫画图片。")
    return chapters, excluded


def chapter_backup_dir(root: Path, chapter: Path, args: argparse.Namespace) -> Path:
    """自动按原章节路径生成备份；递归覆盖路径保留相对层级。"""
    if args.backup_dir is None:
        return default_backup_dir(chapter)
    base = args.backup_dir.expanduser().resolve()
    if not args.recursive:
        return base
    root_hash = hashlib.sha256(os.path.normcase(str(root)).encode("utf-8")).hexdigest()[:12]
    return base / f"{safe_path_component(root.name)}-{root_hash}" / chapter.relative_to(root) / "back"


def shared_blank_backup_dir(root: Path, chapter: Path, args: argparse.Namespace) -> Path:
    """为一次输入范围内的章节返回共同空白页归档目录。"""
    if args.backup_dir is not None:
        base = args.backup_dir.expanduser().resolve()
        if args.recursive:
            root_hash = hashlib.sha256(os.path.normcase(str(root.resolve())).encode("utf-8")).hexdigest()[:12]
            scope = base / f"{safe_path_component(root.name)}-{root_hash}"
        else:
            scope = base
        return scope / BLANK_BACKUP_SUBDIR

    scope = root.resolve() if args.recursive else chapter.resolve().parent
    scope_hash = hashlib.sha256(os.path.normcase(str(scope)).encode("utf-8")).hexdigest()[:12]
    scope_name = safe_path_component(scope.name)
    return (
        get_downloads_directory()
        / "PicaComic Image Splitter Backups"
        / f"{scope_name}-{scope_hash}"
        / BLANK_BACKUP_SUBDIR
    )


def validate_backup_location(chapter: Path, backup: Path, root: Path | None = None) -> None:
    """禁止在输入树内建立备份，也禁止把输入树置于备份内。"""
    for directory in (chapter, root or chapter):
        if backup == directory or backup in directory.parents or directory in backup.parents:
            raise ValueError(f"备份必须位于输入目录树之外：{backup}")
    if backup.exists() and (not backup.is_dir() or is_directory_link(backup)):
        raise ValueError(f"备份路径不是普通目录：{backup}")


def validate_blank_archive_chapter(blank_backup: Path, chapter: Path) -> Path:
    """验证共享归档目录中的章节子目录边界。"""
    directory = blank_backup / blank_archive_chapter_name(chapter)
    if directory.exists() or directory.is_symlink():
        if directory.is_symlink() or not directory.is_dir() or is_directory_link(directory):
            raise ValueError(f"空白页章节归档路径不是普通目录：{directory}")
        if directory.resolve().parent != blank_backup.resolve():
            raise ValueError(f"空白页章节归档路径越界：{directory}")
    return directory


def original_backup_path(
    backup: Path,
    name: str,
    subdir: str = "",
    blank_backup_dir: Path | None = None,
    backup_chapter: str = "",
) -> Path:
    """按记录中的安全子目录定位原图备份，兼容旧版布局。"""
    if subdir not in ("", BLANK_BACKUP_SUBDIR):
        raise ValueError(f"原图备份子目录无效：{subdir}")
    if not subdir:
        return backup / name
    if not backup_chapter:
        # 兼容旧版及过渡版清单：空白页仍在章节 back/blank_pages 下。
        return backup / subdir / name
    if blank_backup_dir is None:
        raise ValueError("清单指定了共享空白页归档，但缺少 blank_backup_dir。")
    if Path(backup_chapter).name != backup_chapter or backup_chapter in (".", ".."):
        raise ValueError(f"空白页章节归档名无效：{backup_chapter}")
    return blank_backup_dir / backup_chapter / name


def planned_backup_paths(job: ChapterJob) -> dict[str, Path]:
    """按本次计划将空白页集中到共享目录、普通原图留在章节备份中。"""
    return {
        plan.source.path.name: (
            job.blank_backup_dir / blank_archive_chapter_name(job.directory) / plan.source.path.name
            if plan.is_blank_white else job.backup_dir / plan.source.path.name
        )
        for plan in job.plans
    }


def check_hashes(expected: dict[Path, str]) -> None:
    """核对来源或备份快照，内容变化时停止，不继续替换或清理。"""
    for path, digest in expected.items():
        if path.is_symlink() or not path.is_file() or sha256_file(path) != digest:
            raise ValueError(f"文件缺失或 SHA-256 已变化：{path}")


def read_manifest(
    chapter: Path,
) -> tuple[dict[str, dict], bytes | None, Path | None, Path | None]:
    """读取原图到切片的对应关系，拒绝越界文件名及歧义页序。"""
    path = chapter / MANIFEST_NAME
    if not path.exists():
        return {}, None, None, None
    if path.is_symlink() or not path.is_file():
        raise ValueError(f"处理记录不是普通文件：{path}")
    data = path.read_bytes()
    try:
        manifest = json.loads(data)
        if manifest["version"] != 1 or not isinstance(manifest["sources"], dict):
            raise ValueError("记录版本或 sources 字段无效")
        records = manifest["sources"]
        blank_backup_value = manifest.get("blank_backup_dir")
        if (blank_backup_value is not None
                and (not isinstance(blank_backup_value, str) or not blank_backup_value.strip())):
            raise ValueError("blank_backup_dir 字段无效")
        recorded_blank_backup = (
            Path(blank_backup_value).expanduser().resolve()
            if blank_backup_value else None
        )
        pages: set[int] = set()
        outputs: set[str] = set()
        for name, record in records.items():
            original = Path(name)
            if original.name != name or original.suffix.lower() not in SUPPORTED_FORMATS or not original.stem.isdecimal():
                raise ValueError(f"原图文件名无效：{name}")
            page = int(original.stem)
            if page in pages:
                raise ValueError(f"重复原始页号：{page}")
            pages.add(page)
            if not re.fullmatch(r"[0-9a-f]{64}", record["sha256"]) or not isinstance(record["size"], int):
                raise ValueError(f"原图校验信息无效：{name}")
            if not isinstance(record["outputs"], list):
                raise ValueError(f"切片列表无效：{name}")
            if record.get("backup_subdir", "") not in ("", BLANK_BACKUP_SUBDIR):
                raise ValueError(f"原图备份子目录无效：{name}")
            backup_chapter = record.get("backup_chapter", "")
            if (not isinstance(backup_chapter, str)
                    or (backup_chapter and (Path(backup_chapter).name != backup_chapter
                                            or backup_chapter in (".", "..")))):
                raise ValueError(f"空白页章节归档名无效：{name}")
            if backup_chapter and record.get("backup_subdir", "") != BLANK_BACKUP_SUBDIR:
                raise ValueError(f"普通原图不能指定空白页章节归档名：{name}")
            if backup_chapter and recorded_blank_backup is None:
                raise ValueError(f"清单缺少共享空白页归档路径：{name}")
            for output in record["outputs"]:
                output_path = Path(output)
                if (output_path.name != output
                        or not (GROUPED_NAME.fullmatch(output_path.stem) or output_path.stem.isdecimal())
                        or output_path.suffix.lower() != original.suffix.lower() or output in outputs):
                    raise ValueError(f"切片文件名无效或重复：{output}")
                outputs.add(output)
        recorded_backup_value = manifest["backup_dir"]
        if not isinstance(recorded_backup_value, str):
            raise ValueError("backup_dir 字段无效")
        return (
            records,
            data,
            Path(recorded_backup_value).expanduser().resolve(),
            recorded_blank_backup,
        )
    except (KeyError, TypeError, AttributeError, UnicodeError, ValueError) as error:
        raise ValueError(f"章节处理记录无效：{path}：{error}") from error


def resplit_candidates(
    chapter: Path,
    backup: Path,
    blank_backup_dir: Path,
    records: dict[str, dict],
    image_paths: list[Path],
) -> tuple[list[Path], bool]:
    """只从可确认的原图备份重新切割，兼容旧版的整章重切。"""
    grouped = [path for path in image_paths if GROUPED_NAME.fullmatch(path.stem)]
    live = [path for path in image_paths if not GROUPED_NAME.fullmatch(path.stem)]
    if not backup.is_dir():
        raise ValueError(f"原图备份目录缺失：{backup}")
    if records:
        known_outputs = {name for record in records.values() for name in record["outputs"]}
        live = [path for path in live if path.name not in known_outputs]
        if any(path.name not in known_outputs for path in grouped):
            raise ValueError("发现处理记录以外的切片，无法确认来源；停止该章。")
        if any(path.name in records for path in live):
            raise ValueError("目录同时存在已处理页的原图与切片；请先核对来源。")
        paths = [
            original_backup_path(
                backup,
                name,
                record.get("backup_subdir", ""),
                blank_backup_dir,
                record.get("backup_chapter", ""),
            )
            for name, record in records.items()
        ]
        check_hashes({
            original_backup_path(
                backup,
                name,
                record.get("backup_subdir", ""),
                blank_backup_dir,
                record.get("backup_chapter", ""),
            ): record["sha256"]
            for name, record in records.items()
        })
        for name, record in records.items():
            source_backup = original_backup_path(
                backup,
                name,
                record.get("backup_subdir", ""),
                blank_backup_dir,
                record.get("backup_chapter", ""),
            )
            if source_backup.stat().st_size != record["size"]:
                raise ValueError(f"原图备份字节数已变化：{name}")
        return paths + live, False
    if not grouped or live:
        raise ValueError("旧版重切需要纯切片章节和唯一原图备份；混合目录缺少对应记录，停止该章。")
    originals = [path for path in backup.iterdir()
                 if path.suffix.lower() in SUPPORTED_FORMATS and path.stem.isdecimal()]
    if not originals:
        raise ValueError("原图备份为空；不能用旧切片或 *_before_resplit 文件猜测原图。")
    return originals, True


def validate_legacy_outputs(image_paths: list[Path], sources: list[SourceImage]) -> None:
    """旧版整章重切前核对原页数量、扩展名和切片序号，拒绝缺页备份。"""
    groups: dict[int, list[Path]] = {}
    for path in image_paths:
        if GROUPED_NAME.fullmatch(path.stem):
            page = int(path.stem.split("-")[0])
            groups.setdefault(page, []).append(path)
    for files in groups.values():
        segments = sorted(int(path.stem.split("-")[1]) for path in files)
        if segments != list(range(len(files))):
            raise ValueError("旧版切片缺段或序号重复，不能确认整章来源。")
    pages = sorted(groups)
    nonblank = []
    for source in sources:
        with Image.open(source.path) as image:
            if not is_blank_page(image):
                nonblank.append(source)
    # 兼容旧版保留纯白页和跳过纯白页的整章结果。
    for candidates in (sources, nonblank):
        if not candidates or len(candidates) != len(pages):
            continue
        original_pages = [int(source.path.stem) for source in candidates]
        sequential_pages = list(range(pages[0], pages[0] + len(pages)))
        if pages != original_pages and pages != sequential_pages:
            continue
        if all(all(path.suffix.lower() == source.path.suffix.lower() for path in groups[page])
               for page, source in zip(pages, candidates)):
            return
    raise ValueError("旧版原图备份数量或格式与旧结果不对应，可能缺少原页；停止该章。")


def prepare_chapter(root: Path, chapter: Path, args: argparse.Namespace) -> ChapterJob:
    """建立只读预览；在任何章节写入前确认整批来源和替换范围。"""
    records, manifest_bytes, recorded_backup, recorded_blank_backup = read_manifest(chapter)
    backup = chapter_backup_dir(root, chapter, args)
    if args.backup_dir is None and recorded_backup is not None:
        backup = recorded_backup
    if recorded_backup is not None and recorded_backup != backup:
        raise ValueError(f"备份路径与处理记录不一致：{chapter}")
    validate_backup_location(chapter, backup, root)
    blank_backup = shared_blank_backup_dir(root, chapter, args)
    if args.backup_dir is None and recorded_blank_backup is not None:
        blank_backup = recorded_blank_backup
    if recorded_blank_backup is not None and recorded_blank_backup != blank_backup:
        raise ValueError(f"空白页汇总目录与处理记录不一致：{chapter}")
    validate_backup_location(chapter, blank_backup, root)
    validate_blank_archive_chapter(blank_backup, chapter)
    image_paths = [path for path in chapter.iterdir()
                   if path.is_file() and path.suffix.lower() in SUPPORTED_FORMATS]
    has_results = bool(records) or any(GROUPED_NAME.fullmatch(path.stem) for path in image_paths)
    if has_results and not args.resplit:
        raise ValueError(f"章节已处理；请使用 --resplit 从原图备份重切：{chapter}")
    legacy = False
    candidates = None
    if args.resplit and has_results:
        candidates, legacy = resplit_candidates(
            chapter, backup, blank_backup, records, image_paths
        )
    skipped: list[tuple[str, str]] = []
    sources, ignored = discover_sources(chapter, args.max_width, args.exclude_webp, skipped, candidates)
    if legacy and skipped and sources:
        raise ValueError("旧版章节没有原图到切片的对应记录，不能安全局部重切；请整章重切。")
    if legacy and sources:
        validate_legacy_outputs(image_paths, sources)
    selected_names = {source.path.name for source in sources}
    source_hashes = {source.path.name: sha256_file(source.path) for source in sources}
    if legacy and sources:
        previous_outputs = [path for path in image_paths if GROUPED_NAME.fullmatch(path.stem)]
    else:
        previous_outputs = [chapter / output for name, record in records.items()
                            if name in selected_names for output in record["outputs"]]
    for path in previous_outputs:
        if path.is_symlink() or not path.is_file():
            raise ValueError(f"旧结果缺失或不是普通文件，停止该章：{path}")
    plans = make_plans(sources, args.reference_width, args.min_equivalent_height,
                       args.max_equivalent_height, keep_blank_pages=args.keep_blank_pages)
    check_hashes({source.path: source_hashes[source.path.name] for source in sources})
    preserve = args.max_width is not None or args.exclude_webp
    if records:
        untouched = any(name not in selected_names for name in records)
        preserve = preserve or untouched
    if preserve and args.start_index != 1:
        raise ValueError("局部重切保留原始页号，不能指定其他 --start-index。")
    parts = make_output_parts(plans, args.start_index, preserve)
    for source in sources:
        candidate_paths = (
            backup / source.path.name,
            backup / BLANK_BACKUP_SUBDIR / source.path.name,
            blank_backup / blank_archive_chapter_name(chapter) / source.path.name,
        )
        for path in candidate_paths:
            if path.exists():
                check_hashes({path: source_hashes[source.path.name]})
    previous_hashes = {path.name: sha256_file(path) for path in previous_outputs}
    replaceable = set(previous_outputs) | {
        source.path for source in sources if source.path.parent == chapter
    }
    planned_names = {part.filename for part in parts}
    if len(planned_names) != len(parts):
        raise ValueError("新结果存在重复文件名。")
    if any((chapter / name).exists() and chapter / name not in replaceable for name in planned_names):
        raise ValueError(f"新结果会覆盖不在替换范围内的文件：{chapter}")
    # 同页不同扩展名同样会破坏阅读顺序，不能只检查完整文件名。
    new_pages = {part.page_index for part in parts}
    for path in image_paths:
        if path in replaceable or path.name in selected_names:
            continue
        prefix = path.stem.split("-")[0]
        if prefix.isdecimal() and int(prefix) in new_pages:
            raise ValueError(f"新页号与未处理图片冲突：{path.name}")
    print(f"筛选条件：宽度 ≤ {args.max_width}px" if args.max_width is not None else "筛选条件：不限制宽度")
    print(f"WebP：{'排除' if args.exclude_webp else '包含'}；编号：{'保留原始页号' if preserve else '连续编号'}")
    print_preview(chapter, sources, plans, parts, ignored, args.reference_width,
                  args.min_equivalent_height, args.max_equivalent_height, args.start_index, args.preview_limit)
    for name, reason in skipped:
        print(f"  跳过并保持原样：{name}（{reason}）")
    if args.resplit:
        print(f"重切来源：{backup}；待替换旧切片：{len(previous_outputs)} 张")
    print(f"原图备份目录：{backup}")
    return ChapterJob(chapter, backup, blank_backup, sources, plans, parts, skipped,
                      previous_outputs, records, source_hashes, previous_hashes,
                      manifest_bytes)


def stage_output_parts(stage_dir: Path, parts: list[OutputPart]) -> None:
    """每张原图解码一次，按预览计划生成暂存结果。"""
    offset = 0
    while offset < len(parts):
        plan = parts[offset].plan
        source_parts = parts[offset:offset + plan.piece_count]
        if len(source_parts) != plan.piece_count:
            raise RuntimeError(f"输出计划不完整：{plan.source.path.name}")
        offset += plan.piece_count
        if plan.piece_count == 1 and not plan.trimmed:
            shutil.copy2(plan.source.path, stage_dir / source_parts[0].filename)
            continue
        with Image.open(plan.source.path) as image:
            image.load()
            compacted = build_vertical_compacted_image(
                image, plan.source_spans or ((plan.crop_top, plan.effective_bottom),))
            for part in source_parts:
                crop = compacted.crop((0, part.top, plan.source.width, part.bottom))
                save_piece(crop, plan.source, stage_dir / part.filename)


def copy_verified(
    source: Path, destination: Path, digest: str, created: list[Path] | None = None
) -> None:
    """复制且核对字节数和哈希，禁止覆盖已有文件。"""
    if destination.exists():
        raise FileExistsError(f"拒绝覆盖已有文件：{destination}")
    # 排他创建防止并发任务在检查之后创建同名备份。
    with source.open("rb") as reader, destination.open("xb") as writer:
        if created is not None:
            created.append(destination)
        shutil.copyfileobj(reader, writer)
    check_hashes({source: digest, destination: digest})
    if source.stat().st_size != destination.stat().st_size:
        raise OSError(f"复制后的字节数不符：{destination}")


def backup_sources(job: ChapterJob, sources: list[SourceImage]) -> dict[Path, str]:
    """保留原图备份；空白页集中归档并按章节分目录。"""
    validate_backup_location(job.directory, job.backup_dir)
    job.backup_dir.mkdir(parents=True, exist_ok=True)
    validate_backup_location(job.directory, job.backup_dir)
    validate_backup_location(job.directory, job.blank_backup_dir)
    job.blank_backup_dir.mkdir(parents=True, exist_ok=True)
    validate_backup_location(job.directory, job.blank_backup_dir)
    destinations = planned_backup_paths(job)
    blank_chapter_dir = validate_blank_archive_chapter(job.blank_backup_dir, job.directory)
    protected: dict[Path, str] = {}
    for source in sources:
        destination = destinations[source.path.name]
        destination.parent.mkdir(parents=True, exist_ok=True)
        expected_parent = blank_chapter_dir if destination.parent == blank_chapter_dir else job.backup_dir
        if (destination.parent.is_symlink() or not destination.parent.is_dir()
                or is_directory_link(destination.parent)
                or destination.parent.resolve() != expected_parent.resolve()):
            raise ValueError(f"原图备份子目录越界或不是普通目录：{destination.parent}")
        digest = job.source_hashes[source.path.name]
        if destination.exists():
            check_hashes({destination: digest})
        else:
            # 先放在独立暂存文件，校验通过后才成为可识别的原图备份。
            temporary = destination.parent / f".{source.path.name}.{uuid.uuid4().hex}.tmp"
            try:
                copy_verified(source.path, temporary, digest)
                # 使用排他目标写入，避免 rename 在不同平台覆盖已有备份。
                copy_verified(temporary, destination, digest)
            except Exception:
                print(f"原图备份失败；临时副本保留供核对：{temporary}", file=sys.stderr)
                raise
            recycle_temporary(temporary, destination.parent, {destination: digest})
        protected[destination] = digest
    return protected


def cleanup_duplicate_blank_backups(
    chapter: Path,
    backup: Path,
    blank_backup_dir: Path,
    records: dict[str, dict],
) -> int:
    """共享副本校验成功后，将旧章节备份中的重复空白原图移入回收站。"""
    moved = 0
    chapter_key = blank_archive_chapter_name(chapter)
    validate_backup_location(chapter, backup)
    validate_backup_location(chapter, blank_backup_dir)
    for name, record in records.items():
        if record.get("backup_subdir", "") != BLANK_BACKUP_SUBDIR:
            continue
        try:
            shared_copy = original_backup_path(
                backup,
                name,
                BLANK_BACKUP_SUBDIR,
                blank_backup_dir,
                record.get("backup_chapter", ""),
            )
            if not shared_copy.is_file() or shared_copy.is_symlink():
                raise ValueError(f"共享空白页副本缺失或不是普通文件：{shared_copy}")
            digest = record["sha256"]
            check_hashes({shared_copy: digest})
            if shared_copy.stat().st_size != record["size"]:
                raise ValueError(f"共享空白页副本字节数不符：{shared_copy}")
            # 旧清单可能仍指向章节内 blank_pages；只清理共享副本之外的已校验重复件。
            duplicates = (backup / name, backup / BLANK_BACKUP_SUBDIR / name)
            for duplicate in duplicates:
                if not duplicate.exists():
                    continue
                if duplicate.resolve() == shared_copy.resolve():
                    continue
                if duplicate.parent not in (backup, backup / BLANK_BACKUP_SUBDIR):
                    raise ValueError(f"旧空白页副本路径越界：{duplicate}")
                if duplicate.parent != backup and (
                    duplicate.parent.is_symlink()
                    or not duplicate.parent.is_dir()
                    or is_directory_link(duplicate.parent)
                    or duplicate.parent.resolve().parent != backup.resolve()
                ):
                    raise ValueError(f"旧空白页副本目录不是普通目录：{duplicate.parent}")
                check_hashes({duplicate: digest})
                if duplicate.stat().st_size != record["size"]:
                    raise ValueError(f"旧空白页副本字节数不符：{duplicate}")
                move_to_recycle_bin(duplicate)
                moved += 1
        except (OSError, RuntimeError, ValueError, KeyError) as error:
            print(
                f"旧章节空白页副本保留，未能安全集中：{chapter_key}/{name}；原因：{error}",
                file=sys.stderr,
            )
    return moved


def recycle_temporary(path: Path, parent: Path, protected: dict[Path, str]) -> None:
    """仅清理本次创建且边界明确的暂存路径；备份异常时保留现场。"""
    if not path.exists():
        return
    try:
        if path.is_symlink() or is_directory_link(path) or path.resolve().parent != parent.resolve():
            raise ValueError(f"暂存路径超出清理边界：{path}")
        check_hashes(protected)
        move_to_recycle_bin(path)
    except (OSError, RuntimeError, ValueError) as error:
        print(f"暂存路径未清理，已保留：{path}；原因：{error}", file=sys.stderr)


def archive_previous_outputs(job: ChapterJob) -> dict[Path, Path]:
    """在删除旧切片前保存校验副本，使用序号避免覆盖历史记录。"""
    archives: dict[Path, Path] = {}
    check_hashes({path: job.previous_hashes[path.name] for path in job.previous_outputs})
    for path in job.previous_outputs:
        index = 0
        while True:
            suffix = "" if index == 0 else f"_{index}"
            archive = job.backup_dir / f"{path.stem}_before_resplit{suffix}{path.suffix}"
            if not archive.exists():
                break
            index += 1
        copy_verified(path, archive, job.previous_hashes[path.name])
        archives[path] = archive
    return archives


def manifest_for_job(job: ChapterJob) -> bytes:
    """记录原图哈希、实际输出和归档位置，空白页也可重新处理。"""
    records = dict(job.records)
    plans_by_name = {plan.source.path.name: plan for plan in job.plans}
    for source in job.sources:
        plan = plans_by_name[source.path.name]
        records[source.path.name] = {
            "sha256": job.source_hashes[source.path.name],
            "size": source.path.stat().st_size,
            "outputs": [part.filename for part in job.parts if part.plan.source.path == source.path],
            "backup_subdir": BLANK_BACKUP_SUBDIR if plan.is_blank_white else "",
            "backup_chapter": blank_archive_chapter_name(job.directory) if plan.is_blank_white else "",
        }
    return json.dumps({"version": 1, "backup_dir": str(job.backup_dir),
                       "blank_backup_dir": str(job.blank_backup_dir), "sources": records},
                      ensure_ascii=False, indent=2).encode("utf-8")


def check_manifest_snapshot(job: ChapterJob) -> None:
    """执行前确认处理记录仍与预览时一致。"""
    path = job.directory / MANIFEST_NAME
    current = path.read_bytes() if path.exists() else None
    if current != job.manifest_bytes:
        raise ValueError(f"处理记录在预览后发生变化：{path}")


def rollback_commit(job: ChapterJob, placed: list[Path], archives: dict[Path, Path]) -> None:
    """提交失败时恢复旧切片和已移走的原图，保留全部外部备份。"""
    errors: list[str] = []
    for path in reversed(placed):
        try:
            move_to_recycle_bin(path)
        except (OSError, RuntimeError) as error:
            errors.append(str(error))
    backup_paths = planned_backup_paths(job)
    restore = [(source.path, backup_paths[source.path.name], job.source_hashes[source.path.name])
               for source in job.sources if source.path.parent == job.directory]
    restore += [(path, archive, job.previous_hashes[path.name]) for path, archive in archives.items()]
    for path, backup, digest in restore:
        try:
            if not path.exists():
                copy_verified(backup, path, digest)
            else:
                check_hashes({path: digest})
        except (OSError, RuntimeError, ValueError) as error:
            errors.append(str(error))
    if errors:
        raise RuntimeError("回滚未完成；原图和旧结果备份保留于外部目录：" + "；".join(errors))


def commit_outputs(job: ChapterJob, stage_dir: Path, protected: dict[Path, str]) -> None:
    """先归档旧结果，再替换新结果；任何中途失败均尝试回滚。"""
    check_manifest_snapshot(job)
    check_hashes(protected)
    archives = archive_previous_outputs(job)
    manifest_path = stage_dir / MANIFEST_NAME
    manifest_path.write_bytes(manifest_for_job(job))
    placed: list[Path] = []
    kept_originals = {
        part.plan.source.path for part in job.parts
        if part.plan.piece_count == 1 and not part.plan.trimmed
        and part.plan.source.path == job.directory / part.filename
        and part.plan.source.path not in job.previous_outputs
    }
    destinations = {job.directory / part.filename for part in job.parts}
    moved_originals: set[Path] = set()
    try:
        for path in job.previous_outputs:
            check_hashes({path: job.previous_hashes[path.name]})
            move_to_recycle_bin(path)
        # 连续编号可能复用其他原图的文件名，先确认备份再腾出这些路径。
        for source in job.sources:
            if source.path in destinations and source.path not in kept_originals:
                check_hashes({source.path: job.source_hashes[source.path.name]})
                move_to_recycle_bin(source.path)
                moved_originals.add(source.path)
        for part in job.parts:
            destination = job.directory / part.filename
            if destination in kept_originals:
                check_hashes({destination: sha256_file(stage_dir / part.filename)})
                continue
            copy_verified(stage_dir / part.filename, destination, sha256_file(stage_dir / part.filename), placed)
        check_hashes(protected)
        for source in job.sources:
            if (source.path.parent == job.directory
                    and source.path not in kept_originals | moved_originals):
                check_hashes({source.path: job.source_hashes[source.path.name]})
                move_to_recycle_bin(source.path)
        check_manifest_snapshot(job)
        # 处理记录是事务最后一步；失败时旧记录尚未更改。
        os.replace(manifest_path, job.directory / MANIFEST_NAME)
    except Exception:
        rollback_commit(job, placed, archives)
        raise


def apply_plans(
    input_dir: Path,
    sources: list[SourceImage],
    parts: list[OutputPart],
    reference_width: int,
    min_equivalent_height: int,
    max_equivalent_height: int,
    backup_dir: Path,
    job: ChapterJob,
) -> tuple[Path, list[OutputPart]]:
    """按同一预览计划暂存并验证结果，再备份及提交章节。"""
    input_dir = input_dir.expanduser().resolve()
    if any(source.path.resolve().parent != input_dir for source in sources):
        raise ValueError("原图必须全部是输入目录的直接子文件；重切时先复制到独立临时目录。")
    if backup_dir.resolve() != job.backup_dir:
        raise ValueError("备份目录与预览计划不一致。")
    validate_backup_location(job.directory, job.backup_dir)
    validate_backup_location(job.directory, job.blank_backup_dir)
    source_snapshot = {source.path: job.source_hashes[source.path.name] for source in sources}
    check_hashes(source_snapshot)
    stage_dir = Path(tempfile.mkdtemp(prefix=f".{job.directory.name}_split_stage_", dir=job.directory.parent))
    backup_paths = planned_backup_paths(job)
    protected = {backup_paths[source.path.name]: job.source_hashes[source.path.name]
                 for source in sources if backup_paths[source.path.name].exists()}
    try:
        stage_output_parts(stage_dir, parts)
        verify_staged_parts(stage_dir, parts, reference_width, min_equivalent_height, max_equivalent_height)
        check_hashes(source_snapshot)
        protected = backup_sources(job, sources)
        commit_outputs(job, stage_dir, protected)
        return job.backup_dir, parts
    finally:
        recycle_temporary(stage_dir, job.directory.parent, protected)


def execute_chapter(job: ChapterJob, args: argparse.Namespace) -> None:
    """执行单章；重切只复制已核验的原图，不把外部原图直接传给写入函数。"""
    if not job.sources:
        print(f"无符合条件的图片，保持章节原样：{job.directory}")
        return
    check_hashes({source.path: job.source_hashes[source.path.name] for source in job.sources})
    check_hashes({path: job.previous_hashes[path.name] for path in job.previous_outputs})
    temporary: Path | None = None
    sources = job.sources
    parts = job.parts
    input_dir = job.directory
    try:
        if any(source.path.parent != job.directory for source in sources):
            temporary = Path(tempfile.mkdtemp(prefix=f".{job.directory.name}_resplit_input_", dir=job.directory.parent))
            copies = []
            for source in sources:
                destination = temporary / source.path.name
                copy_verified(source.path, destination, job.source_hashes[source.path.name])
                copies.append(replace(source, path=destination))
            sources = copies
            by_name = {source.path.name: source for source in copies}
            plans = {id(plan): replace(plan, source=by_name[plan.source.path.name]) for plan in job.plans}
            parts = [replace(part, plan=plans[id(part.plan)]) for part in job.parts]
            input_dir = temporary
        blank_records = json.loads(manifest_for_job(job).decode("utf-8"))["sources"]
        backup, actual = apply_plans(input_dir, sources, parts, args.reference_width,
                                     args.min_equivalent_height, args.max_equivalent_height, job.backup_dir, job)
        moved_blank_copies = cleanup_duplicate_blank_backups(
            job.directory, job.backup_dir, job.blank_backup_dir, blank_records
        )
        print(f"章节完成：{job.directory}；原图 {len(sources)} 张 → 结果 {len(actual)} 张；筛选跳过 {len(job.skipped)} 张")
        print(f"原始图片保存在：{backup}")
        if moved_blank_copies:
            print(f"已将旧章节备份中的空白页重复副本移入回收站：{moved_blank_copies} 张")
    finally:
        if temporary is not None:
            # 唯一原图始终在原路径；每个临时副本必须有可验证的外部原图才清理。
            originals = {}
            backup_paths = planned_backup_paths(job)
            for source in job.sources:
                original = backup_paths[source.path.name]
                if not original.exists():
                    original = source.path
                originals[original] = job.source_hashes[source.path.name]
            recycle_temporary(temporary, job.directory.parent, originals)


def main() -> int:
    """先预览整批章节，全部通过后才按章执行；失败时停止后续章节。"""
    args = parse_args()
    requested = args.input_dir.expanduser().absolute()
    try:
        if is_directory_link(requested):
            raise ValueError("输入目录不能是符号链接或目录联接。")
        root = requested.resolve()
        chapters, excluded = discover_chapters(root, args.recursive)
        for path in excluded:
            print(f"跳过目录：{path}（备份、隐藏、临时或链接目录）")
        jobs = [prepare_chapter(root, chapter, args) for chapter in chapters]
        eligible = [job for job in jobs if job.sources]
        print(f"批次汇总：发现章节 {len(jobs)} 个；符合条件 {len(eligible)} 个；"
              f"原图 {sum(len(job.sources) for job in jobs)} 张；筛选跳过 {sum(len(job.skipped) for job in jobs)} 张；"
              f"空白页跳过 {sum(plan.is_blank_white for job in jobs for plan in job.plans)} 张；"
              f"预计输出 {sum(len(job.parts) for job in jobs)} 张")
        blank_jobs = [job for job in jobs if any(plan.is_blank_white for plan in job.plans)]
        if blank_jobs:
            blank_dirs = {job.blank_backup_dir for job in blank_jobs}
            if len(blank_dirs) != 1:
                raise ValueError("本批次章节计算出多个空白页汇总目录，停止以避免分散归档。")
            blank_count = sum(
                plan.is_blank_white for job in jobs for plan in job.plans
            )
            print(f"空白页汇总目录：{blank_jobs[0].blank_backup_dir}（{blank_count} 张，按章节分目录）")
        if not args.apply:
            print("当前为只读预览；添加 --apply 后才会写入结果和备份原图。")
            return 0
        for job in eligible:
            execute_chapter(job, args)
        print(f"处理完成：{len(eligible)} 个章节。各章独立提交，原图备份始终保留。")
        return 0
    except (OSError, RuntimeError, ValueError) as error:
        print(f"处理失败，后续章节未执行：{error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
