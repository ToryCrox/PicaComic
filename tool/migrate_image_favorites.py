"""一次性转换本机图片收藏；默认只检查，--apply 才迁移并清理旧数据。"""

import argparse
import concurrent.futures
from contextlib import closing
import datetime
import hashlib
import json
import ntpath
import os
from pathlib import Path
import re
import shutil
import sqlite3
import subprocess

from PIL import Image


def readonly(file):
    """以只读模式打开实际存在的数据库。"""
    connection = sqlite3.connect(file.resolve().as_uri() + '?mode=ro', uri=True)
    connection.row_factory = sqlite3.Row
    return connection


def portable(value):
    """移除旧元数据中的本机地址。"""
    if isinstance(value, str):
        return None if value.startswith('file://') or ntpath.isabs(value) else value
    if isinstance(value, dict):
        return {key: portable(item) for key, item in value.items()
                if portable(key) is not None and portable(item) is not None}
    if isinstance(value, list):
        return [portable(item) for item in value if portable(item) is not None]
    return value


def digest(file):
    """计算文件内容摘要，验证原图及迁移备份。"""
    with file.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def plan_records(old, root):
    """按漫画身份和旧地址文件名定位，保留旧章节、页码。"""
    with closing(readonly(old / 'history.db')) as history:
        rows = [dict(row) for row in history.execute('SELECT * FROM image_favorites ORDER BY rowid')]
    with closing(readonly(root / 'download.db')) as downloads:
        items = {row['id']: dict(row) for row in downloads.execute('SELECT id,directory,json FROM download')}
    records = []
    for row in rows:
        source, comic_id = row['id'].split('-', 1)
        source = 'htmanga' if source == 'htManga' else source
        if source == 'ehentai':
            match = re.search(r'/g/(\d+)/', comic_id)
            download_id = match.group(1) if match else comic_id
        else:
            prefix = {'jm': 'jm', 'hitomi': 'hitomi', 'htmanga': 'Ht', 'nhentai': 'nhentai'}
            download_id = prefix.get(source, '') + comic_id
        item = items.get(download_id)
        metadata = json.loads(row['other'])
        source_url = metadata.get('url', '')
        file = None
        relative = None
        if item:
            directory = (root / 'comics' / item['directory']).resolve()
            if not directory.is_relative_to((root / 'comics').resolve()):
                raise RuntimeError('下载记录目录越界')
            episode = directory / str(row['ep']) if source in ('jm', 'picacg') else directory
            filenames = [source_url.replace('\\', '/').rsplit('/', 1)[-1],
                         row['cover'].replace('\\', '/').rsplit('/', 1)[-1]]
            for filename in filenames:
                candidate = episode / filename
                if filename and candidate.is_file() and candidate.resolve().is_relative_to(directory):
                    file = candidate
                    relative = candidate.relative_to(directory).as_posix()
                    break
        identity = json.dumps([source, comic_id, row['ep'], row['page']],
                              ensure_ascii=False, separators=(',', ':'))
        record_id = hashlib.sha256(identity.encode()).hexdigest()
        clean = portable(metadata)
        clean.pop('url', None)
        if source == 'jm' and item:
            comic = json.loads(item['json'])['comic']
            clean['eps'] = [value for key, value in sorted(comic['series'].items(), key=lambda pair: int(pair[0]))]
        old_copy = old / 'images' / row['cover']
        storage = 'download'
        if file is None:
            if not old_copy.is_file():
                raise RuntimeError(f'原图无法定位：{row["id"]} 第 {row["page"]} 页')
            file = old_copy
            relative = f'originals/{record_id}{file.suffix.lower()}'
            storage = 'standalone'
            download_id = ''
        records.append({
            'record_id': record_id, 'source_key': source, 'comic_id': comic_id,
            'title': row['title'], 'ep': row['ep'], 'page': row['page'],
            'storage': storage, 'download_id': download_id, 'image_path': relative,
            'image_url': source_url if source_url.startswith(('https://', 'http://')) else '',
            'other': json.dumps(clean, ensure_ascii=False, separators=(',', ':')),
            '_file': file, '_hash': digest(file),
            '_old_differs': old_copy.is_file() and digest(old_copy) != digest(file),
        })
    if len({row['record_id'] for row in records}) != len(records):
        raise RuntimeError('迁移后的收藏身份出现重复，未修改数据')
    return records


def encode_thumbnail(record, folder, executable):
    """生成与应用相同参数的竖向中心裁切 WebP。"""
    file = record['_file']
    with Image.open(file) as image:
        width, height = image.size
    units = min(width // 9, height // 16)
    crop_width, crop_height = (9 * units, 16 * units) if units else (width, height)
    target = max(1, min(units, 48))
    output = folder / f'{record["record_id"]}.webp'
    result = subprocess.run([
        str(executable), '-q', '80', '-m', '4', '-mt', '-metadata', 'none',
        '-crop', str((width - crop_width) // 2), str((height - crop_height) // 2),
        str(crop_width), str(crop_height), '-resize', str(target * 9), str(target * 16),
        '-o', str(output), '--', str(file),
    ], capture_output=True, timeout=30,
       creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
    if result.returncode:
        raise RuntimeError(result.stderr.decode(errors='replace'))
    with Image.open(output) as image:
        if image.format != 'WEBP' or image.size != (target * 9, target * 16):
            raise RuntimeError('缩略图格式或尺寸不正确')
        image.load()
    if digest(file) != record['_hash']:
        raise RuntimeError('迁移期间原图发生变化')


def ensure_app_closed():
    """Windows 迁移前拒绝与运行中的应用同时写入。"""
    if os.name == 'nt':
        result = subprocess.run(['tasklist', '/FI', 'IMAGENAME eq pica_comic.exe', '/FO', 'CSV', '/NH'],
                                capture_output=True, creationflags=subprocess.CREATE_NO_WINDOW)
        if b'pica_comic.exe' in result.stdout.lower():
            raise RuntimeError('请先退出 PicaComic，再执行迁移')


def apply_migration(old, root, records, executable):
    """备份、验证并安装新库，最后清理已经完成转换的旧数据。"""
    ensure_app_closed()
    target_db = root / 'image_favorites.db'
    if target_db.exists():
        raise RuntimeError('新收藏数据库已存在，不覆盖已有收藏')
    stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
    folder = root / 'image_favorites'
    backup = folder / 'migration_backup' / stamp
    stage = folder / f'.migration-{stamp}'
    backup.mkdir(parents=True)
    stage.mkdir()
    with closing(readonly(old / 'history.db')) as history, closing(sqlite3.connect(backup / 'history.db')) as snapshot:
        history.backup(snapshot)
    shutil.copytree(old / 'images', backup / 'images')
    for file in (old / 'images').iterdir():
        if file.is_file() and digest(file) != digest(backup / 'images' / file.name):
            raise RuntimeError('旧图片备份校验失败，未清理旧数据')
    thumbnails = stage / 'thumbnails'
    originals = stage / 'originals'
    thumbnails.mkdir()
    originals.mkdir()
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        list(pool.map(lambda row: encode_thumbnail(row, thumbnails, executable), records))
    source = (Path(__file__).resolve().parents[1] / 'lib/foundation/image_favorites_repository.dart').read_text(encoding='utf-8')
    schema = re.search(r"createTableSql = '''(.*?)'''", source, re.S).group(1)
    with closing(sqlite3.connect(stage / 'image_favorites.db')) as database:
        database.execute(schema)
        database.execute('CREATE INDEX image_favorites_title ON image_favorites(title)')
        database.execute('CREATE INDEX image_favorites_download ON image_favorites(download_id)')
        database.execute('PRAGMA user_version=1')
        for record in records:
            values = {key: value for key, value in record.items() if not key.startswith('_')}
            database.execute(f'INSERT INTO image_favorites ({",".join(values)}) VALUES ({",".join("?" for _ in values)})', list(values.values()))
            if record['storage'] == 'standalone':
                output = stage / record['image_path']
                shutil.copyfile(record['_file'], output)
                if digest(output) != record['_hash']:
                    raise RuntimeError('独立原图校验失败')
        if database.execute('PRAGMA integrity_check').fetchone()[0] != 'ok':
            raise RuntimeError('新收藏数据库完整性检查失败')
        if database.execute('SELECT count(*) FROM image_favorites').fetchone()[0] != len(records):
            raise RuntimeError('新收藏数量不正确')
        database.commit()
    report = {
        'count': len(records), 'download_references': sum(row['storage'] == 'download' for row in records),
        'old_copies_differ': sum(row['_old_differs'] for row in records),
        'backup': str(backup), 'database': str(target_db),
        'records': [{key: value for key, value in row.items() if not key.startswith('_')}
                    for row in records],
    }
    (backup / 'report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    for name in ('originals', 'thumbnails'):
        destination = folder / name
        if destination.exists():
            if any(destination.iterdir()):
                raise RuntimeError(f'目标 {name} 目录非空，不覆盖已有文件')
            destination.rmdir()
        (stage / name).rename(destination)
    (stage / 'image_favorites.db').rename(target_db)
    stage.rmdir()
    # 新库安装并验证后才删除旧表；history 中其他数据完全保留。
    ensure_app_closed()
    with closing(sqlite3.connect(old / 'history.db')) as history:
        history.execute('DROP TABLE image_favorites')
        history.commit()
    images = (old / 'images').resolve()
    if images.parent != old.resolve() or images.name != 'images':
        raise RuntimeError('旧图片清理目录检查失败')
    shutil.rmtree(images)
    print(json.dumps({key: value for key, value in report.items() if key != 'records'}, ensure_ascii=True))


def resume_migration(old, root, stage, records):
    """继续已经备份并验证的迁移，处理 Windows 安装阶段的文件占用。"""
    ensure_app_closed()
    folder = (root / 'image_favorites').resolve()
    stage = stage.resolve()
    if stage.parent != folder or not stage.name.startswith('.migration-'):
        raise RuntimeError('恢复目录不属于本次下载目录')
    backup = folder / 'migration_backup' / stage.name.removeprefix('.migration-')
    report = json.loads((backup / 'report.json').read_text(encoding='utf-8'))
    expected = {row['record_id'] for row in records}
    if expected != {row['record_id'] for row in report['records']}:
        raise RuntimeError('旧收藏在迁移期间发生变化，不继续安装')
    pending_db = stage / 'image_favorites.db'
    target_db = root / 'image_favorites.db'
    database = pending_db if pending_db.exists() else target_db
    with closing(readonly(database)) as connection:
        actual = {row['record_id'] for row in connection.execute('SELECT record_id FROM image_favorites')}
        if actual != expected or connection.execute('PRAGMA integrity_check').fetchone()[0] != 'ok':
            raise RuntimeError('恢复数据库校验失败')
    for row in records:
        thumbnail = (stage / 'thumbnails' if (stage / 'thumbnails').exists() else folder / 'thumbnails') / f'{row["record_id"]}.webp'
        with Image.open(thumbnail) as image:
            if image.format != 'WEBP' or image.width * 16 != image.height * 9 or image.width > 432 or image.height > 768:
                raise RuntimeError('恢复缩略图校验失败')
            image.load()
        if digest(row['_file']) != row['_hash']:
            raise RuntimeError('恢复原图校验失败')
    for file in (old / 'images').iterdir():
        if file.is_file() and digest(file) != digest(backup / 'images' / file.name):
            raise RuntimeError('恢复旧图片备份校验失败')
    for name in ('originals', 'thumbnails'):
        source = stage / name
        destination = folder / name
        if not source.exists():
            continue
        if destination.exists():
            if any(destination.iterdir()):
                raise RuntimeError('恢复目标目录非空，不覆盖已有文件')
            destination.rmdir()
        source.rename(destination)
    if pending_db.exists():
        if target_db.exists():
            raise RuntimeError('新库已存在，不覆盖')
        pending_db.rename(target_db)
    ensure_app_closed()
    with closing(sqlite3.connect(old / 'history.db')) as history:
        history.execute('DROP TABLE image_favorites')
        history.commit()
    images = (old / 'images').resolve()
    if images.parent != old.resolve() or images.name != 'images':
        raise RuntimeError('旧图片清理位置无效')
    shutil.rmtree(images)
    stage.rmdir()
    print(json.dumps({key: value for key, value in report.items() if key != 'records'}, ensure_ascii=True))


def main():
    """命令行入口，输入目录必须显式提供。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--old', type=Path, required=True)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--resume', type=Path)
    args = parser.parse_args()
    records = plan_records(args.old, args.root)
    if args.resume:
        if not args.apply:
            raise RuntimeError('恢复迁移也必须显式指定 --apply')
        resume_migration(args.old, args.root, args.resume, records)
        return
    if not args.apply:
        print(json.dumps({'count': len(records), 'download_references': sum(row['storage'] == 'download' for row in records),
                          'old_copies_differ': sum(row['_old_differs'] for row in records)}))
        return
    executable = Path(__file__).resolve().parents[1] / 'assets/executables/cwebp.exe'
    apply_migration(args.old, args.root, records, executable)


if __name__ == '__main__':
    main()
