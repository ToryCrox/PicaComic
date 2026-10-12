#!/usr/bin/env python3
"""缩短漫画上下与横向白色留白并均衡切割长图，保持原格式与页序。"""

from __future__ import annotations

import argparse
import ctypes
import hashlib
import math
import os
import re
import shutil
import sys
import tempfile
import uuid
from collections import Counter
from dataclasses import dataclass
from pathlib import Path

try:
    import cv2
    import numpy as np
    from PIL import Image, ImageOps, JpegImagePlugin
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
GUTTER_SAMPLE_WIDTH = 320
GUTTER_WHITE_THRESHOLD = 250
GUTTER_ROW_WHITE_RATIO = 0.995
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
PURE_WHITE_PAGE_VALUE = 255
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


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="缩短纵向近白留白并均衡切割 JPG/PNG/WebP 漫画图片。"
    )
    parser.add_argument(
        "--input-dir",
        required=True,
        type=Path,
        help="必须显式指定图片目录；只处理该目录顶层的数字文件名图片。",
    )
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
        help="覆盖默认备份目录；递归处理或从临时目录处理时应传入原章节对应的外部备份目录。",
    )
    parser.add_argument(
        "--keep-blank-pages",
        action="store_true",
        help="保留纯白页；默认跳过纯白页并在执行时备份原图。",
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


def is_pure_white_page(image: Image.Image) -> bool:
    """判断图片显示到白色画布后是否每个像素都为纯白。"""
    if "A" in image.getbands():
        rgba = image.convert("RGBA")
        white = Image.new("RGBA", rgba.size, (255, 255, 255, 255))
        visible = Image.alpha_composite(white, rgba).convert("RGB")
    else:
        visible = image.convert("RGB")
    pixels = np.asarray(visible, dtype=np.uint8)
    return bool(np.all(pixels == PURE_WHITE_PAGE_VALUE))


def discover_sources(input_dir: Path) -> tuple[list[SourceImage], int]:
    input_dir = input_dir.expanduser().resolve()
    if not input_dir.is_dir():
        raise ValueError(f"输入目录不存在或不是目录：{input_dir}")

    paths = [
        path
        for path in input_dir.iterdir()
        if path.is_file() and path.suffix.lower() in SUPPORTED_FORMATS
    ]
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
        expected_format = SUPPORTED_FORMATS[path.suffix.lower()]
        try:
            with Image.open(path) as image:
                if image.format != expected_format:
                    raise ValueError(
                        f"格式与扩展名不符：{path.name} 是 {image.format}"
                    )
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


def analyze_horizontal_space(
    image: Image.Image,
) -> tuple[list[tuple[int, int]], np.ndarray]:
    """返回可靠的横向留白范围和逐行墨量，分析缩略图但不改变输出像素。"""
    gray = ImageOps.grayscale(image)
    sample_width = min(GUTTER_SAMPLE_WIDTH, image.width)
    if sample_width != image.width:
        gray = gray.resize(
            (sample_width, image.height),
            resample=Image.Resampling.BILINEAR,
        )

    pixels = np.asarray(gray, dtype=np.uint8)
    white_ratio = np.mean(pixels >= GUTTER_WHITE_THRESHOLD, axis=1)
    blank_rows = white_ratio >= GUTTER_ROW_WHITE_RATIO
    padded = np.concatenate(([False], blank_rows, [False])).astype(np.int8)
    changes = np.diff(padded)
    starts = np.flatnonzero(changes == 1)
    ends = np.flatnonzero(changes == -1)
    minimum_run = max(8, math.ceil(image.width * GUTTER_MIN_RUN_WIDTH_RATIO))
    gutters = [
        (int(start), int(end))
        for start, end in zip(starts, ends)
        if end - start >= minimum_run and start > 0 and end < image.height
    ]
    ink_ratio = np.mean(pixels < GUTTER_WHITE_THRESHOLD, axis=1)
    smoothing = np.ones(LOW_INK_ROW_SMOOTHING, dtype=np.float32)
    smoothing /= smoothing.size
    ink_scores = np.convolve(ink_ratio, smoothing, mode="same")
    return gutters, ink_scores


def detect_vertical_edge_trim(image: Image.Image) -> tuple[int, int]:
    """只检测并缩短上下边缘的大块近白空白，始终保留完整原始宽度。"""
    sample_width = min(EDGE_TRIM_SAMPLE_WIDTH, image.width)
    if "A" in image.getbands():
        rgba = image.convert("RGBA")
        white = Image.new("RGBA", rgba.size, (255, 255, 255, 255))
        grayscale = Image.alpha_composite(white, rgba).convert("L")
    else:
        grayscale = ImageOps.grayscale(image)
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
    """缩短上下边缘与过宽横向白沟，只保留原图中连续的行区间。"""
    content = image.crop((0, crop_top, image.width, crop_bottom))
    gutters, _ = analyze_horizontal_space(content)
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
    if "A" in image.getbands():
        rgba = image.convert("RGBA")
        white = Image.new("RGBA", rgba.size, (255, 255, 255, 255))
        grayscale = Image.alpha_composite(white, rgba).convert("L")
    else:
        grayscale = ImageOps.grayscale(image)
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
            if not keep_blank_pages and is_pure_white_page(image):
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


def make_output_parts(plans: list[ImagePlan], start_index: int) -> list[OutputPart]:
    parts: list[OutputPart] = []
    page_index = start_index
    for plan in plans:
        if plan.is_blank_white:
            continue
        for segment_index, (top, bottom) in enumerate(zip(plan.cuts, plan.cuts[1:])):
            parts.append(
                OutputPart(
                    plan=plan,
                    page_index=page_index,
                    segment_index=segment_index,
                    top=top,
                    bottom=bottom,
                    filename=(
                        f"{page_index}-{segment_index}{plan.source.path.suffix}"
                    ),
                )
            )
        page_index += 1
    return parts


def equivalent_height(part: OutputPart, reference_width: int) -> float:
    return part.expected_size[1] * reference_width / part.expected_size[0]


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
        f"{parts[0].page_index}-0 至 {parts[-1].filename}"
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
        "缩短上下边缘与过宽横向白沟并保留间距；左右边缘完整保留；"
        "切口优先完整横向留白，其次选择墨量较低的行；默认跳过纯白页"
    )
    print(
        f"纵向留白有缩短：{len(trimmed_plans)} 张（左右边缘不裁）；"
        f"需切割：{len(split_plans)} 张；纯白页跳过：{len(blank_plans)} 张；"
        f"预计输出：{len(parts)} 张"
    )
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
        if plan.effective_height * reference_width
        < min_equivalent_height * plan.piece_count * plan.source.width
    )
    if infeasible_minimum:
        print(
            f"有 {infeasible_minimum} 张原图高度不足以同时满足上下限；"
            "这些图片会优先保证不超过上限，单段可能低于最小目标。"
        )

    preview_plans = [
        plan
        for plan in plans
        if plan.is_blank_white or plan.piece_count > 1 or plan.trimmed
    ]
    if preview_limit == 0:
        return
    print("切割与纵向留白压缩预览：")
    for plan in preview_plans[:preview_limit]:
        if plan.is_blank_white:
            print(f"  {plan.source.path.name}: 纯白页，默认跳过并备份原图")
            continue
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
            f"大横向白沟缩短 {interior_removed}px，"
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
        source_equivalent_height = (
            part.plan.effective_height * reference_width / part.plan.source.width
        )
        one_pixel_tolerance = reference_width / part.plan.source.width
        can_meet_minimum = (
            source_equivalent_height
            + one_pixel_tolerance
            >= min_equivalent_height * part.plan.piece_count
        )
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


def apply_plans(
    input_dir: Path,
    sources: list[SourceImage],
    parts: list[OutputPart],
    reference_width: int,
    min_equivalent_height: int,
    max_equivalent_height: int,
    backup_dir: Path,
) -> tuple[Path, list[OutputPart]]:
    input_dir = input_dir.expanduser().resolve()
    external_sources = [
        source.path
        for source in sources
        if source.path.expanduser().resolve().parent != input_dir
    ]
    if external_sources:
        examples = ", ".join(str(path) for path in external_sources[:3])
        raise ValueError(
            "拒绝处理来源于输入目录之外的原图；请先将原图复制到独立输入目录，"
            f"避免备份或清理暂存目录时误移动/删除来源文件：{examples}"
        )

    backup_dir = backup_dir.expanduser().resolve()
    if (
        backup_dir == input_dir
        or backup_dir in input_dir.parents
        or input_dir in backup_dir.parents
    ):
        raise ValueError(f"备份目录必须位于输入目录之外：{backup_dir}")
    if backup_dir.exists() and not backup_dir.is_dir():
        raise ValueError(f"备份路径已存在但不是目录：{backup_dir}")
    backup_conflicts = []
    for source in sources:
        backup_path = backup_dir / source.path.name
        if backup_path.is_file() and (
            backup_path.stat().st_size != source.path.stat().st_size
            or sha256_file(backup_path) != sha256_file(source.path)
        ):
            backup_conflicts.append(backup_path)
        elif backup_path.exists() and not backup_path.is_file():
            backup_conflicts.append(backup_path)
    if backup_conflicts:
        examples = ", ".join(str(path) for path in backup_conflicts[:5])
        raise ValueError(
            "外部备份目录中存在与当前原图不同的同名文件，拒绝覆盖："
            f"{examples}"
        )
    output_conflicts = [
        input_dir / part.filename
        for part in parts
        if (input_dir / part.filename).exists()
    ]
    if output_conflicts:
        examples = ", ".join(str(path) for path in output_conflicts[:5])
        raise ValueError(f"拒绝覆盖输入目录中已有结果：{examples}")

    parent = input_dir.parent
    stage_dir = Path(
        tempfile.mkdtemp(prefix=f".{input_dir.name}_split_stage_", dir=parent)
    )
    backup_stage_dir: Path | None = None

    try:
        actual_parts: list[OutputPart] = []
        part_offset = 0
        processed_sources = 0
        total_output_sources = len({part.plan.source.path for part in parts})
        while part_offset < len(parts):
            plan = parts[part_offset].plan
            # 每张源图只读一次；同一张图的所有裁切共享这次解码结果。
            source_parts = parts[part_offset : part_offset + plan.piece_count]
            if len(source_parts) != plan.piece_count:
                raise RuntimeError(f"输出计划不完整：{plan.source.path.name}")
            part_offset += plan.piece_count
            if plan.piece_count == 1 and not plan.trimmed:
                part = source_parts[0]
                shutil.copy2(plan.source.path, stage_dir / part.filename)
                actual_parts.append(part)
                processed_sources += 1
                if (
                    processed_sources % 25 == 0
                    or processed_sources == total_output_sources
                ):
                    print(
                        f"生成切片暂存：{processed_sources}/{len(sources)} 张原图",
                        flush=True,
                    )
                continue

            with Image.open(plan.source.path) as image:
                image.load()
                compacted = build_vertical_compacted_image(
                    image,
                    plan.source_spans
                    or ((plan.crop_top, plan.effective_bottom),),
                )
                for source_part in source_parts:
                    crop = compacted.crop(
                        (0, source_part.top, plan.source.width, source_part.bottom)
                    )
                    save_piece(crop, plan.source, stage_dir / source_part.filename)
                    actual_parts.append(source_part)
            processed_sources += 1
            if (
                processed_sources % 25 == 0
                or processed_sources == total_output_sources
            ):
                print(
                    f"生成切片暂存：{processed_sources}/{len(sources)} 张原图",
                    flush=True,
                )

        verify_staged_parts(
            stage_dir,
            actual_parts,
            reference_width,
            min_equivalent_height,
            max_equivalent_height,
        )

        backup_dir.parent.mkdir(parents=True, exist_ok=True)
        backup_stage_dir = Path(
            tempfile.mkdtemp(
                prefix=f".{backup_dir.name}_backup_stage_", dir=backup_dir.parent
            )
        )
        for source in sources:
            backup_path = backup_dir / source.path.name
            if backup_path.exists():
                continue
            staged_backup_path = backup_stage_dir / source.path.name
            shutil.copy2(source.path, staged_backup_path)
            if (
                staged_backup_path.stat().st_size != source.path.stat().st_size
                or sha256_file(staged_backup_path) != sha256_file(source.path)
            ):
                raise OSError(
                    f"原图备份校验失败，原图仍保留在输入目录：{source.path}"
                )

        backup_dir.mkdir(parents=True, exist_ok=True)
        for staged_backup_path in backup_stage_dir.iterdir():
            backup_path = backup_dir / staged_backup_path.name
            if backup_path.exists():
                if (
                    not backup_path.is_file()
                    or backup_path.stat().st_size != staged_backup_path.stat().st_size
                    or sha256_file(backup_path) != sha256_file(staged_backup_path)
                ):
                    raise FileExistsError(f"拒绝覆盖不同内容的原图备份：{backup_path}")
                move_to_recycle_bin(staged_backup_path)
            else:
                staged_backup_path.rename(backup_path)

        placed_outputs: list[Path] = []
        try:
            for part in actual_parts:
                staged_path = stage_dir / part.filename
                output_path = input_dir / part.filename
                staged_path.rename(output_path)
                placed_outputs.append(output_path)
            for source in sources:
                move_to_recycle_bin(source.path)
        except Exception:
            rollback_errors: list[str] = []
            for source in sources:
                if source.path.exists():
                    continue
                backup_path = backup_dir / source.path.name
                try:
                    shutil.copy2(backup_path, source.path)
                    if sha256_file(backup_path) != sha256_file(source.path):
                        raise OSError(f"恢复原图后校验失败：{source.path}")
                except (OSError, RuntimeError) as error:
                    rollback_errors.append(str(error))
            for output_path in reversed(placed_outputs):
                try:
                    move_to_recycle_bin(output_path)
                except (OSError, RuntimeError) as error:
                    rollback_errors.append(str(error))
            if rollback_errors:
                raise RuntimeError(
                    "回滚未完成；原始备份仍保存在下载目录。以下操作未能完成："
                    + "；".join(rollback_errors)
                )
            raise

        print(f"原图备份目录：{backup_dir}")
        return backup_dir, actual_parts
    finally:
        if backup_stage_dir is not None and backup_stage_dir.exists():
            try:
                move_to_recycle_bin(backup_stage_dir)
            except (OSError, RuntimeError) as error:
                print(
                    "备份暂存目录无法移入回收站，已保留在原处："
                    f"{backup_stage_dir}；原因：{error}",
                    file=sys.stderr,
                )
        if stage_dir.exists():
            if stage_dir.parent.resolve() != parent.resolve():
                raise RuntimeError(f"拒绝清理输入目录以外的暂存路径：{stage_dir}")
            try:
                move_to_recycle_bin(stage_dir)
            except (OSError, RuntimeError) as error:
                print(
                    f"暂存目录无法移入回收站，已保留在原处：{stage_dir}；原因：{error}",
                    file=sys.stderr,
                )


def main() -> int:
    args = parse_args()
    input_dir = args.input_dir.expanduser().resolve()

    try:
        sources, ignored_count = discover_sources(input_dir)
        plans = make_plans(
            sources,
            args.reference_width,
            args.min_equivalent_height,
            args.max_equivalent_height,
            keep_blank_pages=args.keep_blank_pages,
        )
        parts = make_output_parts(plans, args.start_index)
        print_preview(
            input_dir,
            sources,
            plans,
            parts,
            ignored_count,
            args.reference_width,
            args.min_equivalent_height,
            args.max_equivalent_height,
            args.start_index,
            args.preview_limit,
        )
        if not args.apply:
            print("当前为只读预览；添加 --apply 后才会写入切片和备份原图。")
            return 0

        backup_dir, actual_parts = apply_plans(
            input_dir,
            sources,
            parts,
            args.reference_width,
            args.min_equivalent_height,
            args.max_equivalent_height,
            args.backup_dir or default_backup_dir(input_dir),
        )
        filename_range = (
            f"文件名范围 {parts[0].filename}–{parts[-1].filename}"
            if parts
            else "没有保留页面"
        )
        print(f"处理完成：{len(sources)} 张原图 → {len(parts)} 张结果；{filename_range}。")
        blank_page_count = sum(plan.is_blank_white for plan in plans)
        if blank_page_count:
            print(f"已跳过纯白页：{blank_page_count} 张；原图备份在下载目录。")
        split_heights = [
            equivalent_height(part, args.reference_width)
            for part in actual_parts
            if part.plan.piece_count > 1
        ]
        split_ratios = [
            (part.bottom - part.top)
            / (part.plan.effective_height / part.plan.piece_count)
            for part in actual_parts
            if part.plan.piece_count > 1
        ]
        if split_heights:
            print(
                f"切片核验：切割段等效高度 {min(split_heights):.0f}–"
                f"{max(split_heights):.0f} px；切割段相对均分目标 "
                f"{min(split_ratios):.0%}–{max(split_ratios):.0%}。"
            )
        print(f"原始图片已保存在：{backup_dir}")
        return 0
    except (OSError, RuntimeError, ValueError) as error:
        print(f"处理失败：{error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
