"""Check that SuperR's changes to upstream files are documented and intact.

Compares the working tree with the pinned upstream commit
(superrstudio/upstream.json) using superrstudio/integration-points.json:
every modified upstream file must be listed, every listed file must still
differ from upstream and contain its markers, and the upstream version must
agree across the pin, package/superr/product.json and version/. Run it after
every upstream merge, before committing it.
"""

import hashlib
import json
from pathlib import Path
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[2]


def git(*args):
    return subprocess.check_output(
        ['git', '-C', str(ROOT), *args], text=True, encoding='utf-8'
    ).splitlines()


def read_json(path):
    return json.loads((ROOT / path).read_text(encoding='utf-8-sig'))


def check():
    pin = read_json('superrstudio/upstream.json')
    manifest = read_json('superrstudio/integration-points.json')
    listed = manifest['files']
    errors = []

    # Working tree against the pin, so an uncommitted merge is checked too.
    modified = set(git('diff', '--name-only', '--no-renames', '--diff-filter=MDT', pin['commit']))
    for path in sorted(modified - set(listed)):
        errors.append(f'{path}: modifies an upstream file but is not in integration-points.json')

    for path, entry in sorted(listed.items()):
        file = ROOT / path
        if not file.is_file():
            errors.append(f'{path}: missing')
            continue
        if path not in modified:
            errors.append(f'{path}: identical to upstream {pin["version"]}; the SuperR change was lost')
        text = file.read_text(encoding='utf-8', errors='replace')
        for marker in entry.get('markers', []):
            if marker not in text:
                errors.append(f'{path}: marker not found: {marker}')
        if 'md5_of' in entry:
            digest = hashlib.md5((ROOT / entry['md5_of']).read_bytes()).hexdigest()
            if text.strip() != digest:
                errors.append(f'{path}: does not match the MD5 of {entry["md5_of"]}; rebuild GWT to regenerate it')

    for path in manifest['superr_files']:
        if not (ROOT / path).is_file():
            errors.append(f'{path}: SuperR file missing')

    # One upstream version everywhere: the pin, the product (reported to R
    # packages and the installer) and upstream's own version files.
    product = read_json('package/superr/product.json')['upstream']
    if (product['version'], product['commit']) != (pin['version'], pin['commit']):
        errors.append('package/superr/product.json upstream version/commit differ from superrstudio/upstream.json')
    calendar = (ROOT / 'version/CALENDAR_VERSION').read_text(encoding='utf-8').strip()
    patch = (ROOT / 'version/PATCH').read_text(encoding='utf-8').strip()
    if pin['version'].split('+')[0] != f'{calendar}.{patch}':
        errors.append(f'version/CALENDAR_VERSION and version/PATCH ({calendar}.{patch}) differ from the pin {pin["version"]}')

    if errors:
        raise ValueError('\n'.join(errors))
    print(f'PASS: {len(listed)} upstream files carry SuperR changes, all documented and intact '
          f'against {pin["version"]}; {len(manifest["superr_files"])} SuperR files present')


if __name__ == '__main__':
    try:
        check()
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        print(f'FAIL: {error}', file=sys.stderr)
        sys.exit(1)
