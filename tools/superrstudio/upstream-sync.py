"""Assess an official RStudio release for SuperR, or prepare its integration.

assess   (default) Fetch only the selected release tag from the 'upstream'
         remote, check it against upstream's server and write a review
         report: upstream commits and files, files changed on both sides,
         toolchain and generated-file changes. Nothing else changes.
prepare  Also create branch upstream-sync/rstudio-<version> from --base (in a
         new worktree, or with --in-place in this clean checkout), merge the
         tag there without committing, move the upstream pin, run the source
         checks and write the review record next to the merge.

It never commits, pushes, or changes main or develop. Process, conflict
resolution and acceptance: docs/superrstudio/upstream/sync-process.md.
SPDX-License-Identifier: AGPL-3.0-only
"""

import argparse
import datetime
import json
import os
from pathlib import Path
import re
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[2]
UPSTREAM_URL = re.compile(r'https://github\.com/rstudio/rstudio(\.git)?/?')
TAG = re.compile(r'v(\d{4})\.(\d{2})\.(\d+)\+(\d+)')
# Upstream paths whose changes can require a build-dependency or toolchain
# update (docs/superrstudio/upstream/toolchain.md).
TOOLCHAIN = re.compile(
    r'^(dependencies/|cmake/|CMakeLists\.txt$|CMakePresets\.json$|src/cpp/CMakeLists\.txt$'
    r'|src/node/desktop/package(-lock)?\.json$|src/node/desktop/\.nvmrc$|src/gwt/build\.xml$'
    r'|src/gwt/lib/|package/win32/|version/(?!news/)|\.github/workflows/)')
VERSION_LINE = re.compile(r'(?i)(_VERSION\b|"electron"\s*:|"node"\s*:|cmake_minimum_required|^.version\s*[=:])')
GENERATED = {
    'src/cpp/session/resources/schema/user-prefs-schema.json': 'Rscript scripts/generate-prefs.R',
    'src/cpp/session/resources/schema/user-state-schema.json': 'Rscript scripts/generate-prefs.R',
    'src/cpp/session/session-options.json': 'Rscript scripts/generate-options.R',
    'src/cpp/server/server-options.json': 'Rscript scripts/generate-options.R',
    'src/gwt/src/org/rstudio/studio/client/workbench/commands/Commands.cmd.xml':
        'rebuild GWT (dev-build.ps1 -Component gwt) to regenerate Commands.cmd.xml.MD5',
}
PIN = 'superrstudio/upstream.json'
PRODUCT = 'package/superr/product.json'
HISTORY = 'superrstudio/upstream-history.json'


class SyncError(Exception):
    pass


def run(args, cwd=ROOT, check=True):
    result = subprocess.run(args, cwd=cwd, capture_output=True, text=True,
                            encoding='utf-8', errors='replace')
    if check and result.returncode != 0:
        raise SyncError(f"{' '.join(args)} failed ({result.returncode}): {result.stderr.strip()}")
    return result


def git(*args, cwd=ROOT, check=True):
    return run(['git', '-c', 'core.quotepath=false', *args], cwd=cwd, check=check).stdout.strip()


def lines(*args, cwd=ROOT):
    return [line for line in git(*args, cwd=cwd).splitlines() if line]


def is_ancestor(commit, ref, cwd=ROOT):
    code = run(['git', 'merge-base', '--is-ancestor', commit, ref], cwd=cwd, check=False).returncode
    if code not in (0, 1):
        raise SyncError(f'git merge-base --is-ancestor {commit} {ref} failed ({code})')
    return code == 0


def exists(ref, cwd=ROOT):
    return run(['git', 'rev-parse', '--verify', '--quiet', ref], cwd=cwd, check=False).returncode == 0


def show_json(rev, path, default=None):
    result = run(['git', 'show', f'{rev}:{path}'], check=False)
    if result.returncode != 0:
        if default is not None:
            return default
        raise SyncError(f'{path} not found in {rev}')
    return json.loads(result.stdout.lstrip('﻿'))


def write_json(path, data):
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + '\n', encoding='utf-8', newline='\n')


def version_key(version):
    match = TAG.fullmatch('v' + version)
    if not match:
        raise SyncError(f'Unexpected RStudio version {version}')
    return tuple(int(part) for part in match.groups())


def name_status(old, new):
    changes = {}
    for line in lines('diff', '--name-status', '--no-renames', old, new):
        status, path = line.split('\t', 1)
        changes[path] = status[0]
    return changes


def fetch_tag(tag):
    """Fetch one upstream tag (never others) after checking it on upstream's server."""
    url = git('remote', 'get-url', 'upstream')
    if not UPSTREAM_URL.fullmatch(url):
        raise SyncError(f"Remote 'upstream' is {url}, expected https://github.com/rstudio/rstudio")
    refs = {}
    for line in lines('ls-remote', 'upstream', f'refs/tags/{tag}', f'refs/tags/{tag}^{{}}'):
        sha, ref = line.split('\t')
        refs[ref] = sha
    if not refs:
        raise SyncError(f'{tag} is not a tag of {url}')
    annotated = f'refs/tags/{tag}^{{}}' in refs
    remote = refs[f'refs/tags/{tag}^{{}}'] if annotated else refs[f'refs/tags/{tag}']
    if exists(f'refs/tags/{tag}'):
        local = git('rev-parse', f'refs/tags/{tag}^{{commit}}')
        if local != remote:
            raise SyncError(f'Local tag {tag} is {local} but upstream has {remote}; investigate, never overwrite it')
    else:
        git('fetch', '--no-tags', 'upstream', f'refs/tags/{tag}:refs/tags/{tag}')
    commit = git('rev-parse', f'refs/tags/{tag}^{{commit}}')
    if commit != remote:
        raise SyncError(f'Fetched {tag} is {commit}, upstream reports {remote}')
    return commit, annotated, url


def assess(tag, base):
    if not TAG.fullmatch(tag):
        raise SyncError(f'{tag} is not an RStudio release tag (vYYYY.MM.PATCH+BUILD)')
    version = tag[1:]
    base_commit = git('rev-parse', '--verify', f'{base}^{{commit}}')
    pin = show_json(base_commit, PIN)
    old = pin['commit']
    new, annotated, url = fetch_tag(tag)
    if version_key(version) <= version_key(pin['version']):
        raise SyncError(f'{tag} is not newer than the SuperR baseline {pin["version"]} on {base}')
    if is_ancestor(new, base_commit):
        raise SyncError(f'{tag} is already in {base}')

    upstream = name_status(old, new)
    superr = name_status(old, base_commit)
    superr_modified = {path for path, status in superr.items() if status != 'A'}
    superr_added = {path for path, status in superr.items() if status == 'A'}
    toolchain = sorted(path for path in upstream if TOOLCHAIN.search(path))
    version_lines = []
    for start in range(0, len(toolchain), 100):
        for line in lines('diff', '-U0', old, new, '--', *toolchain[start:start + 100]):
            if line.startswith('diff --git'):
                current = line.split(' b/', 1)[-1]
            elif line[:1] in '+-' and not line.startswith(('+++', '---')) and VERSION_LINE.search(line[1:]):
                version_lines.append(f'{current}: {line}')
    return {
        'tag': tag,
        'version': version,
        'short': version.split('+')[0],
        'commit': new,
        'annotated': annotated,
        'url': url,
        'date': git('log', '-1', '--format=%cs', new),
        'base': base,
        'base_commit': base_commit,
        'pin': pin,
        'pin_in_new': is_ancestor(old, new),
        'count': int(git('rev-list', '--count', f'{old}..{new}')),
        'commits': lines('log', '--no-merges', '--format=%h %cs %s', f'{old}..{new}'),
        'upstream': upstream,
        'both': sorted(superr_modified & set(upstream)),
        'collisions': sorted(path for path in superr_added if upstream.get(path) == 'A'),
        'toolchain': toolchain,
        'version_lines': version_lines,
        'generated': sorted(path for path in upstream if path in GENERATED),
        'news': {path: git('show', f'{new}:{path}') for path, status in sorted(upstream.items())
                 if path.startswith('version/news/') and status != 'D'},
        'manifest': show_json(base_commit, 'superrstudio/integration-points.json', {'files': {}})['files'],
    }


def report(data, merge=None):
    pin = data['pin']
    out = [
        f"# Upstream review: RStudio {data['version']}",
        '',
        f"Generated {datetime.date.today().isoformat()} by `tools/superrstudio/upstream-sync.py "
        f"{data['tag']} --action {'prepare' if merge else 'assess'} --base {data['base']}`. "
        'Process: [sync-process.md](../sync-process.md); criteria: [acceptance.md](../acceptance.md).',
        '',
        '| Item | Value |',
        '| --- | --- |',
        f"| Upstream tag | `{data['tag']}` ({'annotated' if data['annotated'] else 'lightweight'}, verified with `git ls-remote` against {data['url']}) |",
        f"| Upstream commit | `{data['commit']}`, committed {data['date']} (check the release date in Posit's release notes) |",
        f"| Current SuperR baseline | `{pin['tag']}` (`{pin['commit']}`) |",
        f"| SuperR base | `{data['base']}` at `{data['base_commit']}` |",
        f"| Current baseline contained in the new tag | {'yes' if data['pin_in_new'] else '**no**: the new tag is not a descendant; review every both-sides file'} |",
        f"| Upstream commits | {data['count']} ({len(data['commits'])} non-merge) |",
        f"| Upstream files changed | {len(data['upstream'])} |",
        f"| Changed on both sides | {len(data['both'])} |",
        f"| Toolchain/dependency files changed | {len(data['toolchain'])} |",
        f"| Comparison | https://github.com/rstudio/rstudio/compare/{pin['tag'].replace('+', '%2B')}...{data['tag'].replace('+', '%2B')} |",
        '',
        '## Upstream release notes',
        '',
    ]
    if data['news']:
        for path, text in data['news'].items():
            out += [f'`{path}`:', '', *[f'> {line}' if line else '>' for line in text.splitlines()], '']
    else:
        out += ['No `version/news/` file changed; read the upstream release notes.', '']

    out += ['## Files changed on both sides (review first)', '']
    if data['both']:
        out += ['| File | Upstream change | SuperR area | Note |', '| --- | --- | --- | --- |']
        for path in data['both']:
            entry = data['manifest'].get(path, {})
            out.append(f"| `{path}` | {data['upstream'][path]} | {entry.get('area', '')} | {entry.get('note', '')} |")
    else:
        out.append('None: upstream did not change any file that SuperR modifies.')
    out += ['', '## SuperR files that upstream now also adds', '']
    out += [f'- `{path}`' for path in data['collisions']] or ['None.']

    out += ['', '## Toolchain and dependency changes', '',
            'Apply them as described in [toolchain.md](../toolchain.md) before building.', '']
    out += [f'- `{path}` ({data["upstream"][path]})' for path in data['toolchain']] or ['None.']
    if data['version_lines']:
        out += ['', 'Version-related lines:', '', '```diff', *data['version_lines'], '```']
    out += ['', '## Generated files changed upstream', '']
    out += [f'- `{path}`: {GENERATED[path]}' for path in data['generated']] or ['None.']

    if merge:
        out += ['', '## Merge', '',
                f"Branch `{merge['branch']}` in `{merge['where']}`; merge not committed.", '']
        if merge['conflicts']:
            out += ['Conflicts to resolve (keep upstream\'s change and re-apply the SuperR change; see sync-process.md):', '']
            for path in merge['conflicts']:
                entry = data['manifest'].get(path)
                note = f" (SuperR: {entry['area']}) {entry.get('note', '')}".rstrip() if entry else ''
                out.append(f'- `{path}`{note}')
        else:
            out.append('No conflicts.')
        out += ['', 'Source checks at preparation:', '']
        for name, (code, text) in merge['checks'].items():
            out.append(f"- `{name}`: {'PASS' if code == 0 else 'FAIL' if code > 0 else 'not run'}")
            out += [f'  > {line}' for line in text.splitlines()[-12:] if line.strip()]

    out += ['', '## Upstream commits (non-merge)', '', '<details>', '', '```',
            *data['commits'], '```', '', '</details>', '',
            '## All upstream file changes', '', '<details>', '', '```',
            *[f'{status}\t{path}' for path, status in sorted(data['upstream'].items())],
            '```', '', '</details>', '',
            '## Acceptance', '',
            'Complete every gate before the pull request is approved; record the result and the evidence.', '',
            '| Gate | Result | Evidence |', '| --- | --- | --- |']
    for gate in ('A1 Source review (both-sides files, release notes, security fixes)',
                 'A2 Conflicts resolved; check-baseline, check-integration, check-identity',
                 'A3 Toolchain and dependency changes applied',
                 'A4 Native, GWT and Electron build',
                 'A5 SuperR R contract tests (visual-scatter, lfq-tropfishr, deps)',
                 'A6 Upstream test suites (rsession, core) against the previous baseline',
                 'A7 Live desktop GUI scenarios',
                 'A8 Installer build and packaged-application tests',
                 'A9 Benchmarks against the previous baseline',
                 'A10 Project compatibility (fixture and copied projects)',
                 'A11 Licences, NOTICE, attribution, MODIFIED-FILES',
                 'A12 History status accepted; CI green; owner approval'):
        out.append(f'| {gate} | | |')
    return '\n'.join(out) + '\n'


def run_checks(where):
    checks = {}
    script = Path(where) / 'tools' / 'superrstudio'
    commands = {
        'check-baseline.py': [sys.executable, str(script / 'check-baseline.py')],
        'check-integration.py': [sys.executable, str(script / 'check-integration.py')],
    }
    if os.name == 'nt':
        commands['check-identity.ps1'] = ['powershell', '-NoProfile', '-File', str(script / 'check-identity.ps1')]
    for name, command in commands.items():
        result = run(command, cwd=where, check=False)
        checks[name] = (result.returncode, (result.stdout + result.stderr).strip())
    return checks


def prepare(data, worktree, in_place):
    branch = f"upstream-sync/rstudio-{data['short']}"
    if exists(f'refs/heads/{branch}') or lines('ls-remote', '--heads', 'origin', branch):
        raise SyncError(f'Branch {branch} already exists (locally or on origin); review or remove it first')
    if in_place:
        if lines('status', '--porcelain', '--untracked-files=no'):
            raise SyncError('--in-place needs a checkout without uncommitted changes')
        where = ROOT
        git('switch', '-c', branch, data['base_commit'])
    else:
        where = Path(worktree) if worktree else ROOT.parent / f"{ROOT.name}-sync-{data['short']}"
        if where.exists():
            raise SyncError(f'{where} already exists')
        git('worktree', 'add', '-b', branch, str(where), data['base_commit'])

    merged = run(['git', 'merge', '--no-ff', '--no-commit', data['commit']], cwd=where, check=False)
    if merged.returncode not in (0, 1) or not exists('MERGE_HEAD', cwd=where):
        raise SyncError(f'git merge failed ({merged.returncode}): {merged.stderr.strip()}')
    conflicts = lines('diff', '--name-only', '--diff-filter=U', cwd=where)

    # The pin moves with the merge: upstream.json, the product's upstream
    # version (reported to R packages, used by the installer) and the history.
    review = f"docs/superrstudio/upstream/reviews/rstudio-{data['short']}.md"
    pin = dict(data['pin'], version=data['version'], tag=data['tag'], commit=data['commit'],
               release_date=data['date'], verified_date=datetime.date.today().isoformat(),
               assessment='under-review')
    write_json(Path(where) / PIN, pin)
    product = json.loads((Path(where) / PRODUCT).read_text(encoding='utf-8-sig'))
    product['upstream'].update(version=data['version'], commit=data['commit'])
    write_json(Path(where) / PRODUCT, product)
    history = json.loads((Path(where) / HISTORY).read_text(encoding='utf-8-sig'))
    history['baselines'].append({
        'version': data['version'], 'tag': data['tag'], 'commit': data['commit'],
        'upstream_release_date': data['date'], 'method': 'merge', 'incorporated': None,
        'superr_commit': None, 'sync_branch': branch, 'review': review, 'acceptance': [],
        'status': 'under-review'})
    write_json(Path(where) / HISTORY, history)

    checks = run_checks(where) if not conflicts else {
        'check-baseline.py': (-1, 'after resolving the conflicts'),
        'check-integration.py': (-1, 'after resolving the conflicts')}
    path = Path(where) / review
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(report(data, {'branch': branch, 'where': where, 'conflicts': conflicts,
                                  'checks': checks}), encoding='utf-8', newline='\n')
    git('add', PIN, PRODUCT, HISTORY, review, cwd=where)

    message = Path(where) / git('rev-parse', '--git-path', 'MERGE_MSG', cwd=where)
    message.write_text(
        f"Merge upstream RStudio {data['version']} into SuperR\n\n"
        f"Prepared on {branch} by tools/superrstudio/upstream-sync.py. Not accepted\n"
        f"until the review record's acceptance gates are complete and the pull\n"
        f"request is approved.\n\n"
        f"Upstream-Tag: {data['tag']}\n"
        f"Upstream-Commit: {data['commit']}\n"
        f"Previous-Upstream: {data['pin']['tag']} {data['pin']['commit']}\n"
        f"Upstream-Commits: {data['count']}\n"
        f"Review: {review}\n", encoding='utf-8', newline='\n')
    return branch, where, conflicts, checks, review


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('tag', help='official RStudio release tag, e.g. v2026.10.1+239')
    parser.add_argument('--action', choices=('assess', 'prepare'), default='assess')
    parser.add_argument('--base', default='develop', help='SuperR branch to integrate into (default: develop)')
    parser.add_argument('--worktree', help='prepare: worktree path (default: ../<checkout>-sync-<version>)')
    parser.add_argument('--in-place', action='store_true', help='prepare: use this clean checkout instead of a worktree')
    parser.add_argument('--report', help='assess: report path (default: .cache/superrstudio/upstream-sync/)')
    args = parser.parse_args()
    try:
        data = assess(args.tag, args.base)
        if args.action == 'assess':
            path = Path(args.report) if args.report else (
                ROOT / '.cache' / 'superrstudio' / 'upstream-sync' / f"rstudio-{data['short']}-assessment.md")
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(report(data), encoding='utf-8', newline='\n')
            print(f"{data['tag']} ({data['commit']}): {data['count']} upstream commits, "
                  f"{len(data['upstream'])} files, {len(data['both'])} changed on both sides, "
                  f"{len(data['toolchain'])} toolchain files.\nReport: {path}")
            return
        branch, where, conflicts, checks, review = prepare(data, args.worktree, args.in_place)
        failed = [name for name, (code, _) in checks.items() if code > 0]
        print(f"Merged {data['tag']} into {branch} at {where} (not committed).")
        print(f"Conflicts: {len(conflicts)}" + ''.join(f'\n  {path}' for path in conflicts))
        print('Checks: ' + ', '.join(f"{name} {'PASS' if code == 0 else 'FAIL' if code > 0 else 'pending'}"
                                     for name, (code, _) in checks.items()))
        print(f'Review record: {Path(where) / review}')
        print('Next (docs/superrstudio/upstream/sync-process.md): review and resolve, rerun the checks, '
              f'commit (message prepared), build, run the acceptance gates, push {data["tag"]} and the branch, '
              'open a pull request into develop.')
        if conflicts or failed:
            sys.exit(2)
    except SyncError as error:
        print(f'FAIL: {error}', file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
