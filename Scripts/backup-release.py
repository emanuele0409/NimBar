#!/usr/bin/env python3
"""Keep immutable, verified local packages and matching source snapshots."""
import argparse
import hashlib
import json
import plistlib
import re
import shutil
import subprocess
import tarfile
import tempfile
import zipfile
from pathlib import Path


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def verify(folder, files):
    for name, expected in files.items():
        if Path(name).name != name or digest(folder / name) != expected:
            raise ValueError(f'Backup verification failed: {name}')


def backup(packages, backups, source_root=None):
    names = ['NimBar.dmg', 'NimBar.zip', 'SHA256SUMS.txt']
    present = [(packages / name).is_file() for name in names]
    if not any(present):
        return None
    if not all(present):
        raise ValueError('Previous packages are incomplete; refusing to replace them.')
    expected = {}
    for line in (packages / 'SHA256SUMS.txt').read_text().splitlines():
        value, name = line.split()
        if name not in names[:2] or not re.fullmatch(r'[0-9a-f]{64}', value):
            raise ValueError('Unexpected package checksum entry.')
        expected[name] = value
    if set(expected) != set(names[:2]):
        raise ValueError('Missing package checksums.')
    verify(packages, expected)
    with zipfile.ZipFile(packages / 'NimBar.zip') as archive:
        info = plistlib.loads(archive.read('NimBar.app/Contents/Info.plist'))
    version = info['CFBundleShortVersionString']
    build = info['CFBundleVersion']
    channel = info.get('NIMBARReleaseChannel', 'unknown')
    for value in [version, build, channel]:
        if not isinstance(value, str) or not re.fullmatch(r'[A-Za-z0-9.-]+', value):
            raise ValueError('Invalid version metadata.')
    target = backups / f'{version}-{channel}-build-{build}-{expected["NimBar.zip"][:12]}'
    if target.exists():
        recorded = json.loads((target / 'backup.json').read_text())
        verify(target, recorded['files'])
        if any(recorded['files'].get(name) != value for name, value in expected.items()):
            raise ValueError('Existing backup does not match these packages.')
        return target
    backups.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix='.backup-', dir=backups))
    try:
        for name in names:
            shutil.copy2(packages / name, temporary / name)
        files = {name: digest(temporary / name) for name in names}
        if source_root is not None:
            paths = subprocess.check_output(
                ['git', 'ls-files', '-z', '--cached', '--others', '--exclude-standard'], cwd=source_root
            ).decode().split('\0')
            with tarfile.open(temporary / 'Source.tar.gz', 'w:gz') as archive:
                for name in sorted(set(filter(None, paths))):
                    path = source_root / name
                    if name.startswith(('.scratch/', 'build/')) or path.suffix.lower() in {'.p12', '.pfx', '.key', '.pem'}:
                        continue
                    if path.is_file():
                        archive.add(path, arcname=name, recursive=False)
            files['Source.tar.gz'] = digest(temporary / 'Source.tar.gz')
        verify(temporary, files)
        (temporary / 'backup.json').write_text(json.dumps({
            'version': version, 'channel': channel, 'build': build, 'files': files
        }, indent=2) + '\n')
        temporary.rename(target)
    finally:
        if temporary.exists():
            shutil.rmtree(temporary)
    return target


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('packages', type=Path)
    parser.add_argument('backups', type=Path)
    parser.add_argument('--source-root', type=Path)
    args = parser.parse_args()
    result = backup(args.packages, args.backups, args.source_root)
    print(f'Backup verified: {result}' if result else 'No previous packages to back up.')
