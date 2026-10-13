"""验证一次性迁移的备份、Windows 文件释放及失败恢复。"""

from contextlib import contextmanager
import importlib.util
import json
import os
from pathlib import Path
import sqlite3
import tempfile
import unittest
from unittest.mock import patch

from PIL import Image

project = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('migration', project / 'tool/migrate_image_favorites.py')
migration = importlib.util.module_from_spec(spec)
spec.loader.exec_module(migration)


@contextmanager
def database(file):
    """事务结束后显式释放数据库文件句柄。"""
    connection = sqlite3.connect(file)
    try:
        with connection:
            yield connection
    finally:
        connection.close()


@unittest.skipUnless(os.name == 'nt', '编码工具按 Windows 本机用途提供')
class MigrationTests(unittest.TestCase):
    """所有测试只访问各自的临时目录。"""

    def setUp(self):
        self.workspace = tempfile.TemporaryDirectory(prefix='pica_migration_test_')
        self.old = Path(self.workspace.name) / '旧数据'
        self.root = Path(self.workspace.name) / '下载目录'
        (self.old / 'images').mkdir(parents=True)
        self.root.mkdir()
        with database(self.old / 'history.db') as connection:
            connection.execute('CREATE TABLE history(target TEXT)')
            connection.execute("INSERT INTO history VALUES('保留历史')")
            connection.execute('CREATE TABLE image_favorites(id TEXT,title TEXT,cover TEXT,ep INTEGER,page INTEGER,other TEXT)')
            for comic in ('a', 'b'):
                connection.execute('INSERT INTO image_favorites VALUES(?,?,?,?,?,?)',
                    (f'picacg-{comic}', comic, '33.webp', 1, 34,
                     json.dumps({'url': f'file://C:/old/{comic}/1/33.webp', 'eps': ['chapter']})))
        with database(self.root / 'download.db') as connection:
            connection.execute('CREATE TABLE download(id TEXT,directory TEXT,json TEXT)')
            for comic, color in [('a', 'red'), ('b', 'blue')]:
                directory = self.root / 'comics' / comic / '1'
                directory.mkdir(parents=True)
                Image.new('RGB', (90, 160), color).save(directory / '33.webp', 'WEBP')
                connection.execute('INSERT INTO download VALUES(?,?,?)', (comic, comic, '{}'))
        Image.new('RGB', (90, 160), 'red').save(self.old / 'images/33.webp', 'WEBP')
        self.executable = project / 'assets/executables/cwebp.exe'

    def tearDown(self):
        self.workspace.cleanup()

    def verify(self):
        """检查记录完整、旧历史保留、备份可读取及缩略图比例。"""
        with database(self.root / 'image_favorites.db') as connection:
            self.assertEqual(connection.execute('SELECT count(*) FROM image_favorites').fetchone()[0], 2)
            self.assertEqual(connection.execute('PRAGMA integrity_check').fetchone()[0], 'ok')
        with database(self.old / 'history.db') as connection:
            self.assertEqual(connection.execute('SELECT target FROM history').fetchone()[0], '保留历史')
            self.assertEqual(connection.execute("SELECT count(*) FROM sqlite_master WHERE name='image_favorites'").fetchone()[0], 0)
        self.assertFalse((self.old / 'images').exists())
        backup = next((self.root / 'image_favorites/migration_backup').iterdir())
        with database(backup / 'history.db') as connection:
            self.assertEqual(connection.execute('SELECT count(*) FROM image_favorites').fetchone()[0], 2)
        self.assertTrue((backup / 'images/33.webp').exists())
        thumbnails = list((self.root / 'image_favorites/thumbnails').glob('*.webp'))
        self.assertEqual(len(thumbnails), 2)
        for file in thumbnails:
            with Image.open(file) as image:
                self.assertEqual(image.format, 'WEBP')
                self.assertEqual(image.width * 16, image.height * 9)

    def test_complete_migration_closes_database_before_install(self):
        """完整迁移后可以重命名新库，确认文件句柄已关闭。"""
        records = migration.plan_records(self.old, self.root)
        self.assertEqual(sum(row['_old_differs'] for row in records), 1)
        migration.apply_migration(self.old, self.root, records, self.executable)
        self.verify()
        target = self.root / 'image_favorites.db'
        moved = self.root / 'verify.db'
        target.rename(moved)
        moved.rename(target)

    def test_install_failure_keeps_old_data_and_can_resume(self):
        """模拟安装阶段文件占用，旧数据保留且可以接续安装。"""
        records = migration.plan_records(self.old, self.root)
        original_rename = Path.rename

        def blocked_rename(file, target):
            if file.name == 'image_favorites.db':
                raise PermissionError('模拟 Windows 文件占用')
            return original_rename(file, target)

        with patch.object(Path, 'rename', blocked_rename):
            with self.assertRaises(PermissionError):
                migration.apply_migration(self.old, self.root, records, self.executable)
        self.assertTrue((self.old / 'images/33.webp').exists())
        with database(self.old / 'history.db') as connection:
            self.assertEqual(connection.execute('SELECT count(*) FROM image_favorites').fetchone()[0], 2)
        stage = next((self.root / 'image_favorites').glob('.migration-*'))
        migration.resume_migration(self.old, self.root, stage, records)
        self.verify()


if __name__ == '__main__':
    unittest.main()
