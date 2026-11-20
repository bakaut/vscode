#!/usr/bin/env python3
"""Reproducibly vendor audited local VSIX files into a packaged Code Offline app.

No third-party binary is committed to the source repository. Download occurs
only on the CI build runner, before packaging. 'verify' is strictly offline.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import sys
import tempfile
import time
import urllib.error
import urllib.request
from urllib.parse import urlsplit
import zipfile

ROOT = Path(__file__).resolve().parent
LOCK = ROOT / 'bundled-extensions.lock.json'
PLATFORMS = {'linux-x64', 'darwin-x64', 'darwin-arm64'}
MAX_FILE = 200 * 1024 * 1024
MAX_TOTAL = 650 * 1024 * 1024
MAX_ENTRIES = 60000
SHA_RE = re.compile(r'^[0-9a-f]{64}$')
TOKEN_RE = re.compile(r'^[a-zA-Z0-9_.-]+$')


def required(cond, message):
    if not cond:
        raise RuntimeError(message)


def load_lock(platform):
    required(platform in PLATFORMS, 'Unsupported target platform: ' + platform)
    lock = json.loads(LOCK.read_text(encoding='utf-8'))
    required(lock['schema'] == 1 and lock['source'] == 'https://open-vsx.org/api', 'Invalid lock manifest')
    entries = lock['extensions']
    ids = [x['id'].lower() for x in entries]
    required(len(ids) == len(set(ids)) == 12, 'Duplicate or missing locked extensions')
    for entry in entries:
        ext_id, version = entry['id'], entry['version']
        required(re.fullmatch(r'[a-zA-Z0-9_.-]+\.[a-zA-Z0-9_.-]+', ext_id) is not None, 'Invalid extension id')
        required(TOKEN_RE.fullmatch(version) is not None, 'Invalid version')
        required(entry['license'] in ('MIT', 'EPL-2.0', 'MPL-2.0'), 'Unreviewed extension license')
        variant = platform if platform in entry['variants'] else 'universal'
        required(SHA_RE.fullmatch(entry['variants'].get(variant, '')) is not None, 'Missing pinned SHA256: ' + ext_id)
    return entries


def archive_url(entry, variant):
    publisher, name = entry['id'].split('.', 1)
    version = entry['version']
    segment = '' if variant == 'universal' else variant + '/'
    suffix = '' if variant == 'universal' else '@' + variant
    filename = entry['id'] + '-' + version + suffix + '.vsix'
    return f'https://open-vsx.org/api/{publisher}/{name}/{segment}{version}/file/{filename}'


def fetch_file(url, expected_hash, output):
    required(url.startswith('https://open-vsx.org/api/'), 'Download host is not allowlisted')
    for attempt in range(3):
        try:
            request = urllib.request.Request(url, headers={'User-Agent': 'CodeOffline-Build/1.0'})
            with urllib.request.urlopen(request, timeout=75) as response, output.open('wb') as target:
                destination = urlsplit(response.geturl())
                required(destination.scheme == 'https' and destination.hostname in ('open-vsx.org', 'openvsx.eclipsecontent.org'), 'Unsafe redirect during VSIX download')
                digest = hashlib.sha256()
                total = 0
                while True:
                    block = response.read(1024 * 1024)
                    if not block:
                        break
                    total += len(block)
                    required(total <= MAX_FILE, 'VSIX too large')
                    digest.update(block)
                    target.write(block)
            required(total > 0 and digest.hexdigest() == expected_hash, 'SHA256 mismatch: ' + url)
            return
        except (OSError, urllib.error.URLError) as exc:
            if attempt == 2:
                raise RuntimeError('VSIX download failed after 3 attempts: ' + url) from exc
            time.sleep(2 ** attempt)


def package_manifest(zf, entry):
    required('extension/package.json' in zf.namelist(), 'Missing extension/package.json')
    manifest = json.loads(zf.read('extension/package.json'))
    actual_id = str(manifest.get('publisher', '')) + '.' + str(manifest.get('name', ''))
    required(actual_id.lower() == entry['id'].lower(), 'Wrong publisher/name: ' + actual_id)
    required(manifest.get('version') == entry['version'], 'Wrong VSIX version')
    required('engines' in manifest and 'vscode' in manifest['engines'], 'VS Code engines missing')
    return manifest


def extract(zf, dest):
    archive_size = 0
    included = []
    for item in zf.infolist():
        posix = PurePosixPath(item.filename)
        required(not posix.is_absolute() and '..' not in posix.parts and '\\' not in item.filename, 'Unsafe VSIX ZIP path')
        if not posix.parts or posix.parts[0] != 'extension':
            continue
        if len(posix.parts) == 1:
            continue
        included.append((item, Path(*posix.parts[1:])))
        mode = (item.external_attr >> 16)
        required(stat.S_IFMT(mode) not in (stat.S_IFLNK, stat.S_IFCHR, stat.S_IFBLK), 'Symlink/device in VSIX')
        archive_size += item.file_size
        required(item.file_size <= MAX_FILE and archive_size <= MAX_TOTAL, 'Uncompressed VSIX too large')
    required(len(zf.infolist()) <= MAX_ENTRIES and included, 'Too many or no VSIX entries')
    for info, name in included:
        path = dest / name
        if info.is_dir():
            path.mkdir(parents=True, exist_ok=True)
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            required(not path.exists(), 'Duplicate VSIX file name: ' + str(name))
            with zf.open(info) as source, path.open('wb') as target:
                shutil.copyfileobj(source, target, length=1024 * 1024)
            mode = info.external_attr >> 16
            path.chmod(0o755 if mode & 0o111 else 0o644)


def check_installation(app, platform, entries):
    ext_dir = app / 'extensions'
    count = 0
    for entry in entries:
        path = ext_dir / entry['id'].lower() / 'package.json'
        required(path.is_file(), 'Bundled extension missing: ' + entry['id'])
        manifest = json.loads(path.read_text(encoding='utf-8'))
        actual = str(manifest.get('publisher', '')) + '.' + str(manifest.get('name', ''))
        required(actual.lower() == entry['id'].lower(), 'Unexpected bundled identity: ' + entry['id'])
        required(manifest.get('version') == entry['version'], 'Bundled version mismatch: ' + entry['id'])
        count += 1
    marker = ext_dir / 'code-offline-extensions.json'
    required(marker.is_file(), 'Missing bundled VSIX attestation')
    data = json.loads(marker.read_text(encoding='utf-8'))
    required(data['platform'] == platform and data['extensions'] == [
        {'id': e['id'], 'version': e['version'], 'sha256': e['variants'].get(platform, e['variants'].get('universal'))}
        for e in entries
    ], 'VSIX build attestation mismatch')
    print(f'Verified {count} bundled extensions for {platform} in {app}')


def install(app, platform, entries):
    ext_dir = app / 'extensions'
    required(ext_dir.is_dir(), 'No packaged built-in extensions directory: ' + str(ext_dir))
    with tempfile.TemporaryDirectory(prefix='code-offline-vsix-') as work:
        for entry in entries:
            variant = platform if platform in entry['variants'] else 'universal'
            sha = entry['variants'][variant]
            url = archive_url(entry, variant)
            archive = Path(work) / (entry['id'] + '.vsix')
            print(f'Downloading {entry["id"]} {entry["version"]} [{variant}]', flush=True)
            fetch_file(url, sha, archive)
            target = ext_dir / entry['id'].lower()
            required(not target.exists(), 'Duplicate bundled extension: ' + entry['id'])
            target.mkdir()
            with zipfile.ZipFile(archive) as zf:
                package_manifest(zf, entry)
                extract(zf, target)
            archive.unlink()
            print('Installed ' + entry['id'] + ', pinned SHA256 ' + sha, flush=True)
    marker = {'platform': platform, 'extensions': [
        {'id': e['id'], 'version': e['version'], 'sha256': e['variants'].get(platform, e['variants'].get('universal'))}
        for e in entries
    ]}
    (ext_dir / 'code-offline-extensions.json').write_text(json.dumps(marker, indent=2) + '\n', encoding='utf-8')
    check_installation(app, platform, entries)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['install', 'verify'])
    parser.add_argument('--app', required=True, type=Path)
    parser.add_argument('--platform', required=True)
    args = parser.parse_args()
    try:
        entries = load_lock(args.platform)
        if args.action == 'install':
            install(args.app.resolve(), args.platform, entries)
        else:
            check_installation(args.app.resolve(), args.platform, entries)
    except Exception as exc:
        print('Code Offline VSIX error: ' + str(exc), file=sys.stderr)
        sys.exit(1)
