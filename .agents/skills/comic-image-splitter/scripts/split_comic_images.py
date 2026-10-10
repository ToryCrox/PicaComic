#!/usr/bin/env python3
"""均衡切割超长漫画页，保持原格式并连续重新编号。"""

from __future__ import annotations

import argparse
import math
import shutil
import sys
import tempfile
from collections import Counter
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

try:
    import numpy as np
    from PIL import Image, ImageOps, JpegImagePlugin
except ImportError as error:  # pragma: no cover - dependency guard
    raise SystemExit(
        "需要安装 Pillow 和 NumPy：python -m pip install pillow numpy"
    ) from error


SUPPORTED_FORMATS = {
    ".jpg": "JPEG",
    ".jpeg": "JPEG",
    ".png": "PNG",
    ".webp": "WEBP",
}
GUTTER_SAMPLE_WIDTH = 320
GUTTER_WHITE_THRESHOLD = 245
GUTTER_ROW_WHITE_RATIO = 0.98
GUTTER_MIN_RUN_RATIO = 0.0015
GUTTER_SEARCH_RATIO = 0.18
MIN_SEGMENT_RATIO = 0.75


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

    @property
    def piece_count(self) -> int:
        return len(self.boundaries) + 1

    @property
    def cuts(self) -> tuple[int, ...]:
        return (0, *self.boundaries, self.source.height)


@dataclass(frozen=True)
class OutputPart:
    """一张输出切片。"""

    plan: ImagePlan
    index: int
    top: int
    bottom: int
    filename: str

    @property
    def expected_size(self) -> tuple[int, int]:
        return self.plan.source.width, self.bottom - self.top


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="均衡切割超长 JPG/PNG/WebP 漫画图片并连续重新编号。"
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
        "--max-equivalent-height",
        type=int,
        default=6000,
        help="每段在参考宽度下的最大等效高度，默认 6000。",
    )
    parser.add_argument(
        "--start-index",
        type=int,
        default=0,
        help="输出编号起点，默认 0。",
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="实际写入切片并将原图移入输入目录的 back 时间戳子目录；未指定时只预览。",
    )
    parser.add_argument(
        "--preview-limit",
        type=int,
        default=20,
        help="预览中最多列出多少张待切图片，默认 20。",
    )
    args = parser.parse_args()
    if args.reference_width <= 0 or args.max_equivalent_height <= 0:
        parser.error("参考宽度与等效高度上限必须大于 0。")
    if args.start_index < 0:
        parser.error("起始编号不能小于 0。")
    if args.preview_limit < 0:
        parser.error("预览条数不能小于 0。")
    return args


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


def find_horizontal_gutters(image: Image.Image) -> list[int]:
    """返回横向近白留白带中心，分析缩略图但不改变输出像素。"""
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
    minimum_run = max(4, math.ceil(image.height * GUTTER_MIN_RUN_RATIO))

    return [
        (int(start) + int(end)) // 2
        for start, end in zip(starts, ends)
        if end - start >= minimum_run and start > 0 and end < image.height
    ]


def choose_balanced_boundaries(
    height: int,
    width: int,
    gutter_centers: list[int],
    reference_width: int,
    max_equivalent_height: int,
) -> tuple[int, ...]:
    """在均分点附近择留白切口，并确保段长均衡且不超上限。"""
    equivalent_height = height * reference_width / width
    if equivalent_height <= max_equivalent_height:
        return ()

    piece_count = math.ceil(equivalent_height / max_equivalent_height)
    average_height = height / piece_count
    min_segment = average_height * MIN_SEGMENT_RATIO
    max_segment = max_equivalent_height * width / reference_width
    tolerance = average_height * GUTTER_SEARCH_RATIO
    ideal_points = [
        round(height * part / piece_count)
        for part in range(1, piece_count)
    ]

    candidates: list[list[tuple[int, bool]]] = []
    for ideal in ideal_points:
        choices: dict[int, bool] = {ideal: False}
        for center in gutter_centers:
            if abs(center - ideal) <= tolerance:
                choices[center] = True
        candidates.append(sorted((position, is_gutter) for position, is_gutter in choices.items()))

    # 状态为“上一个切点 -> 累计均分代价与边界列表”。
    states: dict[int, tuple[float, tuple[int, ...]]] = {0: (0.0, ())}
    for boundary_options in candidates:
        next_states: dict[int, tuple[float, tuple[int, ...]]] = {}
        for previous, (previous_cost, previous_cuts) in states.items():
            for position, is_gutter in boundary_options:
                segment_height = position - previous
                if segment_height < min_segment or segment_height > max_segment:
                    continue
                balance_cost = (segment_height / average_height - 1) ** 2
                gutter_bonus = 0.08 if is_gutter else 0.0
                cost = previous_cost + balance_cost - gutter_bonus
                current = next_states.get(position)
                if current is None or cost < current[0]:
                    next_states[position] = (cost, (*previous_cuts, position))
        states = next_states
        if not states:
            break

    best: tuple[float, tuple[int, ...]] | None = None
    for previous, (cost, cuts) in states.items():
        final_height = height - previous
        if final_height < min_segment or final_height > max_segment:
            continue
        final_cost = cost + (final_height / average_height - 1) ** 2
        if best is None or final_cost < best[0]:
            best = (final_cost, cuts)

    if best is not None:
        return best[1]

    # 均分边界总是可行的；切点不会产生狭长尾段。
    return tuple(ideal_points)


def make_plans(
    sources: list[SourceImage],
    reference_width: int,
    max_equivalent_height: int,
) -> list[ImagePlan]:
    plans: list[ImagePlan] = []
    for source in sources:
        equivalent_height = source.height * reference_width / source.width
        if equivalent_height <= max_equivalent_height:
            plans.append(ImagePlan(source, ()))
            continue
        piece_count = math.ceil(equivalent_height / max_equivalent_height)
        ideal_boundaries = tuple(
            round(source.height * part / piece_count)
            for part in range(1, piece_count)
        )
        plans.append(ImagePlan(source, ideal_boundaries))
    return plans


def make_output_parts(plans: list[ImagePlan], start_index: int) -> list[OutputPart]:
    parts: list[OutputPart] = []
    next_index = start_index
    for plan in plans:
        for top, bottom in zip(plan.cuts, plan.cuts[1:]):
            parts.append(
                OutputPart(
                    plan=plan,
                    index=next_index,
                    top=top,
                    bottom=bottom,
                    filename=f"{next_index}{plan.source.path.suffix}",
                )
            )
            next_index += 1
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
    max_equivalent_height: int,
    start_index: int,
    preview_limit: int,
) -> None:
    split_plans = [plan for plan in plans if plan.piece_count > 1]
    ext_counts = Counter(source.path.suffix.lower() for source in sources)
    output_ext_counts = Counter(part.plan.source.path.suffix.lower() for part in parts)
    output_heights = [equivalent_height(part, reference_width) for part in parts]

    print(f"输入目录：{input_dir}")
    print(
        f"输入图片：{len(sources)} 张 "
        f"({', '.join(f'{ext} {count} 张' for ext, count in sorted(ext_counts.items()))})"
    )
    if ignored_count:
        print(f"忽略其他扩展名文件：{ignored_count} 个（不会修改）")
    print(
        f"切割规则：等效高度 > {max_equivalent_height} px "
        f"(@ {reference_width} px 宽) 时均衡分段，留白优先"
    )
    print(f"需切割：{len(split_plans)} 张；预计输出：{len(parts)} 张")
    print(
        f"输出格式：{', '.join(f'{ext} {count} 张' for ext, count in sorted(output_ext_counts.items()))}；"
        f"编号：{start_index}–{start_index + len(parts) - 1}"
    )
    print(
        f"输出段等效高度：{min(output_heights):.0f}–{max(output_heights):.0f} px；"
        f"上限 {max_equivalent_height} px"
    )

    if preview_limit == 0:
        return
    print("切割预览：")
    for plan in split_plans[:preview_limit]:
        heights = [
            round((bottom - top) * reference_width / plan.source.width)
            for top, bottom in zip(plan.cuts, plan.cuts[1:])
        ]
        print(
            f"  {plan.source.path.name}: {plan.piece_count} 段，"
            f"等效高度 {' / '.join(map(str, heights))} px"
        )
    remaining = len(split_plans) - min(preview_limit, len(split_plans))
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
        options = {"quality": 100, "method": 0, "exact": True}
        for key in ("icc_profile", "exif", "xmp"):
            value = source.info.get(key)
            if value is not None:
                options[key] = value

    crop.save(destination, format=source.image_format, **options)


def verify_staged_parts(
    stage_dir: Path,
    parts: list[OutputPart],
    reference_width: int,
    max_equivalent_height: int,
) -> None:
    expected_names = [part.filename for part in parts]
    actual_names = sorted(
        (path.name for path in stage_dir.iterdir() if path.is_file()),
        key=lambda name: int(Path(name).stem),
    )
    if actual_names != expected_names:
        raise RuntimeError("暂存结果的文件数或连续编号与预览不一致。")

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
        if part_number % 100 == 0 or part_number == len(parts):
            print(f"核验切片：{part_number}/{len(parts)}", flush=True)


def unique_sibling_dir(parent: Path, base_name: str) -> Path:
    candidate = parent / base_name
    suffix = 1
    while candidate.exists():
        candidate = parent / f"{base_name}_{suffix}"
        suffix += 1
    return candidate


def apply_plans(
    input_dir: Path,
    sources: list[SourceImage],
    parts: list[OutputPart],
    reference_width: int,
    max_equivalent_height: int,
) -> tuple[Path, list[OutputPart]]:
    parent = input_dir.parent
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    stage_dir = Path(
        tempfile.mkdtemp(prefix=f".{input_dir.name}_split_stage_", dir=parent)
    )
    back_root = input_dir / "back"

    try:
        actual_parts: list[OutputPart] = []
        part_offset = 0
        processed_sources = 0
        while part_offset < len(parts):
            plan = parts[part_offset].plan
            # 每张源图只读一次；同一张图的所有裁切共享这次解码结果。
            source_parts = parts[part_offset : part_offset + plan.piece_count]
            if len(source_parts) != plan.piece_count:
                raise RuntimeError(f"输出计划不完整：{plan.source.path.name}")
            part_offset += plan.piece_count
            if plan.piece_count == 1:
                part = source_parts[0]
                shutil.copy2(plan.source.path, stage_dir / part.filename)
                actual_parts.append(part)
                processed_sources += 1
                if processed_sources % 25 == 0 or processed_sources == len(sources):
                    print(
                        f"生成切片暂存：{processed_sources}/{len(sources)} 张原图",
                        flush=True,
                    )
                continue

            with Image.open(plan.source.path) as image:
                image.load()
                gutters = find_horizontal_gutters(image)
                boundaries = choose_balanced_boundaries(
                    plan.source.height,
                    plan.source.width,
                    gutters,
                    reference_width,
                    max_equivalent_height,
                )
                actual_plan = ImagePlan(plan.source, boundaries)
                if actual_plan.piece_count != plan.piece_count:
                    raise RuntimeError(
                        f"留白对齐改变了段数，停止处理：{plan.source.path.name}"
                    )
                for source_part, top, bottom in zip(
                    source_parts, actual_plan.cuts, actual_plan.cuts[1:]
                ):
                    part = OutputPart(
                        plan=actual_plan,
                        index=source_part.index,
                        top=top,
                        bottom=bottom,
                        filename=source_part.filename,
                    )
                    crop = image.crop(
                        (0, part.top, plan.source.width, part.bottom)
                    )
                    save_piece(crop, plan.source, stage_dir / part.filename)
                    actual_parts.append(part)
            processed_sources += 1
            if processed_sources % 25 == 0 or processed_sources == len(sources):
                print(
                    f"生成切片暂存：{processed_sources}/{len(sources)} 张原图",
                    flush=True,
                )

        verify_staged_parts(
            stage_dir,
            actual_parts,
            reference_width,
            max_equivalent_height,
        )

        back_root.mkdir(exist_ok=True)
        backup_dir = unique_sibling_dir(back_root, timestamp)
        backup_dir.mkdir()
        moved_originals: list[Path] = []
        placed_outputs: list[Path] = []
        try:
            for source in sources:
                backup_path = backup_dir / source.path.name
                source.path.replace(backup_path)
                moved_originals.append(backup_path)
            for part in actual_parts:
                staged_path = stage_dir / part.filename
                output_path = input_dir / part.filename
                staged_path.replace(output_path)
                placed_outputs.append(output_path)
        except Exception:
            for output_path in reversed(placed_outputs):
                if output_path.exists():
                    output_path.unlink()
            for backup_path in reversed(moved_originals):
                original_path = input_dir / backup_path.name
                if backup_path.exists() and not original_path.exists():
                    backup_path.replace(original_path)
            if backup_dir.exists() and not any(backup_dir.iterdir()):
                backup_dir.rmdir()
            raise

        print(f"原图备份目录：{backup_dir}")
        return backup_dir, actual_parts
    finally:
        if stage_dir.exists():
            shutil.rmtree(stage_dir)


def main() -> int:
    args = parse_args()
    input_dir = args.input_dir.expanduser().resolve()

    try:
        sources, ignored_count = discover_sources(input_dir)
        plans = make_plans(
            sources,
            args.reference_width,
            args.max_equivalent_height,
        )
        parts = make_output_parts(plans, args.start_index)
        print_preview(
            input_dir,
            sources,
            plans,
            parts,
            ignored_count,
            args.reference_width,
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
            args.max_equivalent_height,
        )
        print(
            f"处理完成：{len(sources)} 张原图 → {len(parts)} 张结果；"
            f"编号 {args.start_index}–{args.start_index + len(parts) - 1}。"
        )
        output_heights = [
            equivalent_height(part, args.reference_width) for part in actual_parts
        ]
        split_ratios = [
            (part.bottom - part.top) / (part.plan.source.height / part.plan.piece_count)
            for part in actual_parts
            if part.plan.piece_count > 1
        ]
        print(
            f"切片核验：等效高度 {min(output_heights):.0f}–"
            f"{max(output_heights):.0f} px；切割段相对均分目标 "
            f"{min(split_ratios):.0%}–{max(split_ratios):.0%}。"
        )
        print(f"原始图片已保存在：{backup_dir}")
        return 0
    except (OSError, RuntimeError, ValueError) as error:
        print(f"处理失败：{error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
