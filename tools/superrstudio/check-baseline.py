"""Check source provenance; --pristine also gates the unmodified baseline phase.

--accepted additionally requires every recorded upstream baseline to be
accepted (pull requests into main; see docs/superrstudio/upstream/).
"""

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


def is_ancestor(commit, ref):
    return subprocess.run(
        ['git', '-C', str(ROOT), 'merge-base', '--is-ancestor', commit, ref]
    ).returncode == 0


def check_history(pin, accepted):
    history = json.loads((ROOT / 'superrstudio/upstream-history.json').read_text(encoding='utf-8-sig'))
    for entry in history['baselines']:
        if entry['status'] not in ('accepted', 'under-review', 'reverted'):
            raise ValueError(f"Unknown status for {entry['version']}: {entry['status']}")
        if accepted and entry['status'] == 'under-review':
            raise ValueError(f"Upstream {entry['version']} is under review, not accepted")
    # Reverted updates stay recorded; the pin is the last one still in effect.
    current = [entry for entry in history['baselines'] if entry['status'] != 'reverted'][-1]
    if (current['version'], current['tag'], current['commit']) != (pin['version'], pin['tag'], pin['commit']):
        raise ValueError('The last baseline in superrstudio/upstream-history.json that is not reverted is not the upstream pin')
    return current['status']


def check(pristine, accepted):
    pin = json.loads((ROOT / 'superrstudio/upstream.json').read_text(encoding='utf-8-sig'))
    commit = pin['commit']
    if not re.fullmatch(r'[0-9a-f]{40}', commit):
        raise ValueError('Upstream commit must be a full SHA-1 revision')
    if pin['tag'] != 'v' + pin['version']:
        raise ValueError('Version and source tag disagree')
    if git('rev-parse', '--verify', f"refs/tags/{pin['tag']}^{{commit}}") != commit:
        raise ValueError('Local release tag does not match the upstream pin')
    # An upstream merge being prepared (tools/superrstudio/upstream-sync.py)
    # is checked before it is committed: the pin is then in MERGE_HEAD.
    merging = subprocess.run(
        ['git', '-C', str(ROOT), 'rev-parse', '--verify', '--quiet', 'MERGE_HEAD'],
        capture_output=True,
    ).returncode == 0
    if not (is_ancestor(commit, 'HEAD') or (merging and is_ancestor(commit, 'MERGE_HEAD'))):
        raise ValueError('The upstream pin is not in the history of HEAD')
    status = check_history(pin, accepted)

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
    print(f"PASS: {pin['version']} at {commit} ({status}); {mode}")
    print('This check does not compile or launch RStudio.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pristine', action='store_true')
    parser.add_argument('--accepted', action='store_true')
    args = parser.parse_args()
    try:
        check(args.pristine, args.accepted)
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        print(f'FAIL: {error}', file=sys.stderr)
        sys.exit(1)
