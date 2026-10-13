"""用临时合成图片验证切割 skill，不操作用户图片或系统回收站。"""

from __future__ import annotations

import argparse
import contextlib
import importlib.util
import io
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
import uuid
from pathlib import Path
from unittest.mock import patch

from PIL import Image

PROJECT = Path(__file__).resolve().parents[2]
SCRIPT = PROJECT / ".agents/skills/comic-image-splitter/scripts/split_comic_images.py"
spec = importlib.util.spec_from_file_location("comic_splitter_under_test", SCRIPT)
splitter = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = splitter
spec.loader.exec_module(splitter)


class ComicImageSplitterTest(unittest.TestCase):
    """验证筛选不改原页、递归隔离、重切来源与失败回滚。"""

    def setUp(self) -> None:
        """为每例建立独立临时输入、备份和回收站替身。"""
        self.temporary = tempfile.TemporaryDirectory(prefix="pica_splitter_test_")
        self.root = Path(self.temporary.name).resolve()
        self.assertEqual(self.root.parent, Path(tempfile.gettempdir()).resolve())
        self.chapter = self.root / "comic" / "chapter"
        self.chapter.mkdir(parents=True)
        self.backup = self.root / "backups" / "back"
        self.trash = self.root / "trash"
        self.trash.mkdir()
        self.addCleanup(self.clean_fixture)
        recycler = patch.object(splitter, "move_to_recycle_bin", side_effect=self.recycle)
        recycler.start()
        self.addCleanup(recycler.stop)
        output = contextlib.redirect_stdout(io.StringIO())
        output.__enter__()
        self.addCleanup(output.__exit__, None, None, None)

    def clean_fixture(self) -> None:
        """仅清理由本测试创建且仍位于系统临时目录的目录。"""
        self.assertEqual(self.root.parent, Path(tempfile.gettempdir()).resolve())
        self.assertTrue(self.root.name.startswith("pica_splitter_test_"))
        self.temporary.cleanup()

    def recycle(self, path: Path) -> None:
        """模拟回收站移动，保留所有被移走文件以便核验。"""
        path = path.resolve()
        self.assertTrue(path.is_relative_to(self.root))
        if path.exists():
            shutil.move(str(path), str(self.trash / f"{uuid.uuid4().hex}_{path.name}"))

    def args(self, **changes) -> argparse.Namespace:
        """提供小尺寸图片适用的切割参数。"""
        defaults = dict(input_dir=self.chapter, backup_dir=self.backup,
                        max_width=None, exclude_webp=False, recursive=False,
                        resplit=False, reference_width=30,
                        min_equivalent_height=30, max_equivalent_height=50,
                        start_index=1, keep_blank_pages=False, preview_limit=20, apply=False)
        defaults.update(changes)
        return argparse.Namespace(**defaults)

    def image(self, name: str, size=(30, 100), color=(60, 60, 60), directory=None) -> Path:
        """保存一张合成的静态原图。"""
        directory = directory or self.chapter
        directory.mkdir(parents=True, exist_ok=True)
        path = directory / name
        Image.new("RGB", size, color).save(path)
        return path

    def prepare(self, args=None):
        """准备单章预览。"""
        return splitter.prepare_chapter(self.chapter, self.chapter, args or self.args())

    def snapshot(self, directory: Path) -> dict[str, bytes]:
        """读取目录文件快照，便于核对无写入与回滚。"""
        return {str(path.relative_to(directory)): path.read_bytes()
                for path in directory.rglob("*") if path.is_file()}

    def test_width_boundary_and_webp_exclusion_keep_skipped_bytes(self) -> None:
        """2160 包含在范围内，2161 与 WebP 不改名、不备份。"""
        self.image("1.jpg", (2160, 10))
        large = self.image("2.png", (2161, 10))
        webp = self.image("3.WEBP", (30, 10))
        later = self.image("7.png", (30, 10))
        skipped_bytes = {large: large.read_bytes(), webp: webp.read_bytes()}
        args = self.args(max_width=2160, exclude_webp=True)
        job = self.prepare(args)
        self.assertEqual([source.path.name for source in job.sources], ["1.jpg", "7.png"])
        self.assertEqual([part.filename for part in job.parts], ["1.jpg", "7.png"])
        self.assertEqual(len(job.skipped), 2)
        splitter.execute_chapter(job, args)
        for path, content in skipped_bytes.items():
            self.assertEqual(path.read_bytes(), content)
            self.assertFalse((self.backup / path.name).exists())
        self.assertEqual((self.chapter / "7.png").read_bytes(), (self.backup / later.name).read_bytes())

    def test_filtered_split_preserves_original_page_number(self) -> None:
        """切割后仍属于第 3 原页，而不是重排成第 1 页。"""
        self.image("3.png")
        job = self.prepare(self.args(max_width=2160))
        self.assertGreater(len(job.parts), 1)
        self.assertEqual([part.filename for part in job.parts],
                         [f"3-{index}.png" for index in range(len(job.parts))])
        self.assertTrue(all(part.expected_size[0] == 30 for part in job.parts))

    def test_palette_transparency_and_visible_pixel(self) -> None:
        """透明调色板页显示为纯白，有可见像素时保留。"""
        image = Image.new("P", (30, 100), 0)
        image.putpalette([0, 0, 0, 0, 0, 0] + [255] * 762)
        image.info["transparency"] = 0
        self.assertTrue(splitter.is_pure_white_page(image))
        image.save(self.chapter / "1.png")
        job = self.prepare()
        self.assertTrue(job.plans[0].is_blank_white)
        splitter.execute_chapter(job, self.args())
        self.assertEqual(json.loads((self.chapter / splitter.MANIFEST_NAME).read_bytes())["sources"]["1.png"]["outputs"], [])
        image.putpixel((15, 50), 1)
        self.assertFalse(splitter.is_pure_white_page(image))
        self.assertEqual(splitter.visible_on_white(image).getpixel((0, 0)), (255, 255, 255))

    def test_recursive_discovery_isolates_chapters_and_excluded_directories(self) -> None:
        """包含根目录与深层章节，但不遍历隐藏、备份和临时目录。"""
        root = self.root / "recursive"
        self.image("1.png", directory=root)
        self.image("1.jpg", directory=root / "book" / "a")
        self.image("1.png", directory=root / "book" / "b")
        for name in ("back", ".hidden", "tmp", "temp", ".a_split_stage_test"):
            self.image("1.png", directory=root / name)
        chapters, excluded = splitter.discover_chapters(root, True)
        self.assertEqual(set(chapters), {root, root / "book" / "a", root / "book" / "b"})
        self.assertEqual(len(excluded), 5)
        self.assertEqual(splitter.discover_chapters(root, False)[0], [root])
        args = self.args(recursive=True, backup_dir=self.root / "recursive_backups")
        jobs = [splitter.prepare_chapter(root, chapter, args) for chapter in chapters]
        for job in jobs:
            splitter.execute_chapter(job, args)
            self.assertTrue((job.directory / splitter.MANIFEST_NAME).exists())
        self.assertEqual(len({job.backup_dir for job in jobs}), 3)
        self.assertTrue((root / "back" / "1.png").exists())

    def test_directory_links_are_excluded(self) -> None:
        """目录链接不能把外部目录纳入批处理。"""
        link = self.chapter / "outside_link"
        outside = self.root / "outside"
        outside.mkdir()
        try:
            link.symlink_to(outside, target_is_directory=True)
        except OSError:
            self.skipTest("当前 Windows 未授权创建符号链接")
        self.assertTrue(splitter.skip_directory(link))

    def test_resplit_replaces_old_segments_from_backups(self) -> None:
        """重切使用原图，旧切片归档，所有原图备份字节保持不变。"""
        self.image("3.png")
        args = self.args(max_width=2160)
        splitter.execute_chapter(self.prepare(args), args)
        originals = self.snapshot(self.backup)
        before = self.snapshot(self.chapter)
        args = self.args(max_width=2160, resplit=True, min_equivalent_height=50, max_equivalent_height=80)
        job = self.prepare(args)
        self.assertTrue(all(source.path.parent == self.backup for source in job.sources))
        self.assertEqual(self.snapshot(self.chapter), before)
        splitter.execute_chapter(job, args)
        names = {path.name for path in self.chapter.glob("*.png")}
        self.assertEqual(names, {"3-0.png", "3-1.png"})
        self.assertEqual((self.backup / "3.png").read_bytes(), originals["3.png"])
        archives = list(self.backup.glob("*_before_resplit.png"))
        self.assertEqual(len(archives), 3)
        for archive in archives:
            old_name = archive.name.replace("_before_resplit", "")
            self.assertEqual(archive.read_bytes(), before[old_name])
        # 再次重切归档不能覆盖前一次归档。
        splitter.execute_chapter(self.prepare(args), args)
        self.assertTrue(list(self.backup.glob("*_before_resplit_1.png")))

    def test_partial_resplit_keeps_excluded_outputs_and_handles_new_originals(self) -> None:
        """已处理与未处理原页混合时，未选中的切片保持原样。"""
        self.image("1.png", (30, 10))
        self.image("2.webp", (30, 10))
        args = self.args()
        splitter.execute_chapter(self.prepare(args), args)
        webp_bytes = (self.chapter / "2.webp").read_bytes()
        self.image("4.jpg", (30, 10))
        args = self.args(resplit=True, exclude_webp=True)
        job = self.prepare(args)
        self.assertEqual([path.name for path in job.previous_outputs], ["1.png"])
        splitter.execute_chapter(job, args)
        self.assertEqual((self.chapter / "2.webp").read_bytes(), webp_bytes)
        self.assertTrue((self.chapter / "4.jpg").exists())
        self.assertFalse(list(self.chapter.parent.glob(".*_resplit_input_*")))

    def test_resplit_failure_restores_old_results_and_manifest(self) -> None:
        """新结果写入失败时恢复旧切片，处理记录保持原值。"""
        self.image("3.png")
        args = self.args(max_width=2160)
        splitter.execute_chapter(self.prepare(args), args)
        before = self.snapshot(self.chapter)
        args = self.args(resplit=True, max_width=2160)
        job = self.prepare(args)
        original_copy = splitter.copy_verified

        def fail_first_output(source, destination, digest, created=None):
            """模拟新结果写了一部分后发生磁盘错误。"""
            if created is not None:
                destination.write_bytes(b"partial")
                created.append(destination)
                raise OSError("模拟写入失败")
            return original_copy(source, destination, digest, created)

        with patch.object(splitter, "copy_verified", side_effect=fail_first_output):
            with self.assertRaisesRegex(OSError, "模拟写入失败"):
                splitter.execute_chapter(job, args)
        self.assertEqual(self.snapshot(self.chapter), before)
        self.assertTrue((self.backup / "3.png").exists())

    def test_tampered_backup_stops_before_modifying_chapter(self) -> None:
        """原图备份变化时停止，不能从旧切片猜测继续。"""
        self.image("1.png")
        splitter.execute_chapter(self.prepare(), self.args())
        before = self.snapshot(self.chapter)
        (self.backup / "1.png").write_bytes(b"tampered")
        with self.assertRaisesRegex(ValueError, "SHA-256"):
            self.prepare(self.args(resplit=True))
        self.assertEqual(self.snapshot(self.chapter), before)

    def test_original_recycle_failure_rolls_back_entire_chapter(self) -> None:
        """第二张原图回收失败时恢复第一张原图，并回滚全部新结果。"""
        self.image("1.png")
        self.image("2.png")
        before = self.snapshot(self.chapter)
        job = self.prepare()

        def reject_second_original(path):
            """模拟原图无法移入回收站，其他本次暂存仍可清理。"""
            if path == self.chapter / "2.png":
                raise OSError("模拟回收站失败")
            self.recycle(path)

        with patch.object(splitter, "move_to_recycle_bin", side_effect=reject_second_original):
            with self.assertRaisesRegex(OSError, "模拟回收站失败"):
                splitter.execute_chapter(job, self.args())
        self.assertEqual(self.snapshot(self.chapter), before)
        self.assertEqual((self.backup / "1.png").read_bytes(), before["1.png"])
        self.assertEqual((self.backup / "2.png").read_bytes(), before["2.png"])

    def test_source_change_after_preview_stops_before_writing(self) -> None:
        """预览后来源变化时不能使用旧计划继续处理。"""
        path = self.image("1.png", (30, 10))
        job = self.prepare()
        path.write_bytes(b"changed after preview")
        before = self.snapshot(self.chapter)
        with self.assertRaisesRegex(ValueError, "SHA-256"):
            splitter.execute_chapter(job, self.args())
        self.assertEqual(self.snapshot(self.chapter), before)
        self.assertFalse(self.backup.exists())

    def test_legacy_resplit_rejects_ambiguous_partial_selection(self) -> None:
        """旧版缺少对应记录时只允许整章重切，忽略旧归档副本。"""
        self.image("1-0.png", (30, 10))
        self.image("2-0.webp", (30, 10))
        self.image("1.png", (30, 10), directory=self.backup)
        self.image("2.webp", (30, 10), directory=self.backup)
        self.image("9-0_before_resplit.png", directory=self.backup)
        before = self.snapshot(self.chapter)
        with self.assertRaisesRegex(ValueError, "不能安全局部重切"):
            self.prepare(self.args(resplit=True, exclude_webp=True))
        self.assertEqual(self.snapshot(self.chapter), before)
        args = self.args(resplit=True)
        splitter.execute_chapter(self.prepare(args), args)
        records = json.loads((self.chapter / splitter.MANIFEST_NAME).read_bytes())["sources"]
        self.assertEqual(set(records), {"1.png", "2.webp"})

    def test_legacy_missing_original_is_rejected(self) -> None:
        """旧版备份缺少一个非空白原页时不能用部分原图替换整章。"""
        self.image("1-0.png", (30, 10))
        self.image("2-0.png", (30, 10))
        self.image("1.png", (30, 10), directory=self.backup)
        before = self.snapshot(self.chapter)
        with self.assertRaisesRegex(ValueError, "可能缺少原页"):
            self.prepare(self.args(resplit=True))
        self.assertEqual(self.snapshot(self.chapter), before)

    def test_resplit_can_restore_previously_skipped_blank_page(self) -> None:
        """纯白页没有切片也能通过记录找到原图并按新要求保留。"""
        self.image("3.png", (30, 10), color=(255, 255, 255))
        args = self.args(max_width=2160)
        splitter.execute_chapter(self.prepare(args), args)
        self.assertFalse(list(self.chapter.glob("*.png")))
        args = self.args(resplit=True, max_width=2160, keep_blank_pages=True)
        splitter.execute_chapter(self.prepare(args), args)
        self.assertEqual((self.chapter / "3.png").read_bytes(), (self.backup / "3.png").read_bytes())

    def test_all_excluded_is_successful_and_does_not_write(self) -> None:
        """全部被筛掉时成功报告零处理，不创建记录或备份。"""
        self.image("1.webp", (30, 10))
        before = self.snapshot(self.chapter)
        args = self.args(exclude_webp=True)
        job = self.prepare(args)
        self.assertEqual(job.sources, [])
        splitter.execute_chapter(job, args)
        self.assertEqual(self.snapshot(self.chapter), before)
        self.assertFalse(self.backup.exists())

    def test_recursive_validation_failure_writes_no_chapter(self) -> None:
        """后一章节来源错误时，预览阶段中止，前一章也不写入。"""
        root = self.root / "batch"
        self.image("1.png", directory=root / "a")
        self.image("bad.png", directory=root / "b")
        before = self.snapshot(root)
        argv = [str(SCRIPT), "--input-dir", str(root), "--recursive", "--apply", "--backup-dir", str(self.backup)]
        with patch.object(sys, "argv", argv), contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(splitter.main(), 1)
        self.assertEqual(self.snapshot(root), before)
        self.assertFalse(self.backup.exists())

    def test_cli_preview_has_no_filesystem_changes(self) -> None:
        """真实命令行预览显示筛选条件和原因，整个测试目录不变。"""
        self.image("3.png", (30, 10))
        self.image("4.webp", (30, 10))
        before = self.snapshot(self.root)
        result = subprocess.run([sys.executable, "-X", "utf8", str(SCRIPT), "--input-dir", str(self.chapter),
                                 "--backup-dir", str(self.backup), "--max-width", "2160", "--exclude-webp"],
                                capture_output=True, text=True, encoding="utf-8", check=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("排除 WebP", result.stdout)
        self.assertIn("只读预览", result.stdout)
        self.assertIn("3.png", result.stdout)
        self.assertEqual(self.snapshot(self.root), before)

    def test_input_and_backup_boundaries(self) -> None:
        """不能在输入树内备份，不能清理输入目录以外的原图。"""
        self.image("1.png")
        with self.assertRaisesRegex(ValueError, "输入目录树之外"):
            self.prepare(self.args(backup_dir=self.chapter / "back"))
        job = self.prepare()
        with self.assertRaisesRegex(ValueError, "直接子文件"):
            splitter.apply_plans(self.root, job.sources, job.parts, 30, 30, 50, self.backup, job)

    def gutter_image(self, color) -> Image.Image:
        """生成两块非纯色内容之间有全宽间隔的图片。"""
        image = Image.new("RGB", (120, 600), color)
        image.paste((20, 60, 120), (0, 0, 60, 100))
        image.paste((120, 60, 20), (60, 0, 120, 100))
        image.paste((20, 60, 120), (0, 500, 60, 600))
        image.paste((120, 60, 20), (60, 500, 120, 600))
        return image

    def test_colored_gutters_compact_without_changing_content(self) -> None:
        """黑、灰、粉、白间隔缩短后保留间距及两侧内容像素。"""
        for color in ((0, 0, 0), (60, 60, 75), (253, 237, 246), (255, 255, 255)):
            with self.subTest(color=color):
                image = self.gutter_image(color)
                spans = splitter.make_vertical_source_spans(image, 0, image.height)
                result = splitter.build_vertical_compacted_image(image, spans)
                self.assertEqual(result.size, (120, 248))
                self.assertEqual(result.crop((0, 0, 120, 100)).tobytes(),
                                 image.crop((0, 0, 120, 100)).tobytes())
                self.assertEqual(result.crop((0, 148, 120, 248)).tobytes(),
                                 image.crop((0, 500, 120, 600)).tobytes())
                self.assertEqual(result.getpixel((60, 124)), color)

    def test_minor_color_noise_is_accepted(self) -> None:
        """小幅压缩色差可以识别，区域色差按整体而非逐行累计。"""
        image = self.gutter_image((50, 60, 70))
        for row in range(100, 500):
            image.putpixel((row % image.width, row), (54, 64, 74))
        self.assertEqual(splitter.detect_solid_gutters(image), [(100, 500)])

    def test_gradients_and_thin_marks_are_preserved(self) -> None:
        """明显渐变及仅一像素宽的线条不会被缩略采样吞掉。"""
        gradient = self.gutter_image((50, 60, 70))
        for row in range(100, 500):
            value = 50 + (row - 100) // 5
            gradient.paste((value, value, value), (0, row, 120, row + 1))
        marked = self.gutter_image((253, 237, 246))
        marked.paste((0, 0, 0), (61, 100, 62, 500))
        self.assertEqual(splitter.detect_solid_gutters(marked), [])
        for image in (gradient, marked):
            self.assertEqual(splitter.make_vertical_source_spans(image, 0, 600), ((0, 600),))

    def test_edge_encoding_noise_does_not_hide_black_gutter(self) -> None:
        """全宽黑沟允许最外侧两像素轻微杂色，但明显边线仍受保护。"""
        image = self.gutter_image((0, 0, 0)).resize((2160, 600), Image.Resampling.NEAREST)
        image.paste((26, 26, 26), (0, 100, 2, 500))
        self.assertEqual(splitter.detect_solid_gutters(image), [(100, 500)])
        image.paste((255, 255, 255), (0, 100, 2, 500))
        self.assertEqual(splitter.detect_solid_gutters(image), [])

    def test_short_gutters_and_colored_pages_are_not_removed(self) -> None:
        """普通短间隔和整张非白纯色页保持原样。"""
        image = self.gutter_image((0, 0, 0))
        short = Image.new("RGB", (120, 240))
        short.paste(image.crop((0, 0, 120, 120)), (0, 0))
        short.paste(image.crop((0, 480, 120, 600)), (0, 120))
        self.assertEqual(splitter.make_vertical_source_spans(short, 0, 240), ((0, 240),))
        for color in ((0, 0, 0), (253, 237, 246)):
            solid = Image.new("RGB", (120, 600), color)
            self.assertFalse(splitter.is_blank_page(solid))
            self.assertEqual(splitter.detect_solid_gutters(solid), [])

    def test_unchanged_page_keeps_bytes_and_filename_without_encoding(self) -> None:
        """未处理页无后缀且不重编码、不回收同名原图，仍支持重切。"""
        original = self.image("7.webp", (30, 10))
        content = original.read_bytes()
        args = self.args(max_width=2160)
        with patch.object(splitter, "save_piece", side_effect=AssertionError("不应重编码")):
            job = self.prepare(args)
            self.assertEqual([part.filename for part in job.parts], ["7.webp"])
            splitter.execute_chapter(job, args)
        self.assertEqual(original.read_bytes(), content)
        self.assertFalse(list(self.trash.glob("*_7.webp")))
        resplit_args = self.args(max_width=2160, resplit=True)
        splitter.execute_chapter(self.prepare(resplit_args), resplit_args)
        self.assertEqual(original.read_bytes(), content)

    def test_compacted_single_page_still_has_segment_suffix(self) -> None:
        """实际缩短的单页仍按处理结果命名，并重新编码生成。"""
        self.gutter_image((0, 0, 0)).save(self.chapter / "7.png")
        args = self.args(max_width=2160, reference_width=120,
                         min_equivalent_height=300, max_equivalent_height=500)
        job = self.prepare(args)
        self.assertEqual([part.filename for part in job.parts], ["7-0.png"])
        splitter.execute_chapter(job, args)
        with Image.open(self.chapter / "7-0.png") as result:
            self.assertEqual(result.size, (120, 248))

    def test_resplit_can_replace_suffixed_results_with_unchanged_page(self) -> None:
        """旧分段结果重切后无需处理时，输出无后缀且原图字节保持一致。"""
        original = self.image("3.png").read_bytes()
        args = self.args(max_width=2160)
        splitter.execute_chapter(self.prepare(args), args)
        self.assertTrue((self.chapter / "3-0.png").exists())
        args = self.args(max_width=2160, resplit=True,
                         min_equivalent_height=80, max_equivalent_height=150)
        splitter.execute_chapter(self.prepare(args), args)
        self.assertEqual((self.chapter / "3.png").read_bytes(), original)
        self.assertFalse(list(self.chapter.glob("3-*.png")))

    def test_continuous_numbering_can_reuse_source_names(self) -> None:
        """白页移除后连续编号可复用原页名，内容不覆盖且可再次重切。"""
        self.image("1.png", (30, 10), color=(255, 255, 255))
        second = self.image("2.png", (30, 10), color=(80, 60, 40)).read_bytes()
        third = self.image("3.png", (30, 10), color=(40, 60, 80)).read_bytes()
        splitter.execute_chapter(self.prepare(), self.args())
        self.assertEqual((self.chapter / "1.png").read_bytes(), second)
        self.assertEqual((self.chapter / "2.png").read_bytes(), third)
        self.assertFalse((self.chapter / "3.png").exists())
        args = self.args(resplit=True)
        splitter.execute_chapter(self.prepare(args), args)
        self.assertEqual((self.chapter / "1.png").read_bytes(), second)
        self.assertEqual((self.chapter / "2.png").read_bytes(), third)

    def test_reused_source_name_failure_restores_originals(self) -> None:
        """腾出同名原图后写入失败，原图及旧目录状态均可恢复。"""
        self.image("1.png", (30, 10), color=(255, 255, 255))
        self.image("2.png", (30, 10), color=(40, 60, 80))
        before = self.snapshot(self.chapter)
        job = self.prepare()
        original_copy = splitter.copy_verified

        def fail_output(source, destination, digest, created=None):
            """只在提交新输出时模拟写入失败。"""
            if created is not None:
                raise OSError("模拟同名输出失败")
            return original_copy(source, destination, digest, created)

        with patch.object(splitter, "copy_verified", side_effect=fail_output):
            with self.assertRaisesRegex(OSError, "模拟同名输出失败"):
                splitter.execute_chapter(job, self.args())
        self.assertEqual(self.snapshot(self.chapter), before)


if __name__ == "__main__":
    unittest.main()
