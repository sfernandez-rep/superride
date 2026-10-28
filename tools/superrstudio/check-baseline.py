"""Check source provenance; --pristine also gates the unmodified baseline phase."""

import argparse
import json
from pathlib import Path
import re
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[2]


def git(*args):
    return subprocess.check_output(
        ['git', '-C', str(ROOT), *args], text=True, encoding='utf-8'
    ).strip()


def check(pristine):
    pin = json.loads((ROOT / 'superrstudio/upstream.json').read_text(encoding='utf-8'))
    commit = pin['commit']
    if not re.fullmatch(r'[0-9a-f]{40}', commit):
        raise ValueError('Upstream commit must be a full SHA-1 revision')
    if pin['tag'] != 'v' + pin['version']:
        raise ValueError('Version and source tag disagree')
    if git('rev-parse', '--verify', f"refs/tags/{pin['tag']}^{{commit}}") != commit:
        raise ValueError('Local release tag does not match the upstream pin')
    subprocess.run(
        ['git', '-C', str(ROOT), 'merge-base', '--is-ancestor', commit, 'HEAD'],
        check=True,
    )

    # Compare the working tree as well as committed content; local edits must fail.
    protected = ['COPYING', 'NOTICE']
    if pristine:
        protected += [
            'CMakeLists.txt', 'CMakePresets.json', 'cmake', 'dependencies',
            'src', 'package', 'docker', 'jenkins', 'version', 'e2e',
        ]
    changes = git('diff', '--name-only', commit, '--', *protected)
    untracked = git('ls-files', '--others', '--exclude-standard', '--', *protected)
    if changes or untracked:
        raise ValueError('Protected upstream content changed:\n' + changes + '\n' + untracked)
    for path in (
        'src/cpp/session/modules/data/DataViewer.cpp',
        'src/cpp/session/include/session/SessionModuleContext.hpp',
        'src/gwt/src/org/rstudio/studio/client/dataviewer/DataTable.java',
        'src/node/desktop/src/main/session-launcher.ts',
    ):
        if not (ROOT / path).is_file():
            raise ValueError('Expected upstream source is missing: ' + path)
    mode = 'pristine application/build source' if pristine else 'provenance and licenses'
    print(f"PASS: {pin['version']} at {commit}; {mode}")
    print('This check does not compile or launch RStudio.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pristine', action='store_true')
    args = parser.parse_args()
    try:
        check(args.pristine)
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        print(f'FAIL: {error}', file=sys.stderr)
        sys.exit(1)
