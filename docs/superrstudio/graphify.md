# Local code navigation with Graphify

Reviewed 2026-10-28. Selected [Graphify Labs / graphify](https://github.com/Graphify-Labs/graphify),
branch `v8`, reviewed revision `0a8cd4e1e342235fe53e881fb5d591bf0460071f`.
The [official Python distribution](https://pypi.org/project/graphifyy/0.9.97/)
is **graphifyy 0.9.97**, Apache-2.0 (retain its bundled NOTICE and third-party
licenses when redistributing). Other repositories also named Graphify are
different projects; do not mix their installation instructions or licenses.

## Assessment and scope

The installed CLI parses code locally with tree-sitter and stores a JSON graph.
It supports C/C++, Java and JavaScript/TypeScript on Windows. The project ships
Codex and Claude integrations, but they are optional: both agents can call our
project-local wrapper without installing hooks or changing their global setup.
Symbols, imports, calls, inheritance, inferred cross-file links and graph queries
can help find integration points. This is syntactic analysis, not a C++ compiler,
GWT compiler, debugger, complete dependency model or proof of runtime behavior.

The upstream project was active on 2026-10-27. Its rapid release pace warrants
pinning and review before upgrades. Version 0.9.97's CLI also refreshes installed
assistant integrations automatically; our wrapper disables that behavior.
No global assistant skill, MCP server, Git hook or cloud account was installed.

The local CLI requires no subscription or model credits. Upstream separately
offers a commercial cloud service and optional LLM/document/media extraction.
Neither is enabled. `GRAPHIFY_BACKEND=none` and `--code-only` prevent semantic
model use; `GRAPHIFY_NO_AUTO_REFRESH=1` prevents integration rewrites. No API keys
are needed. Upstream declares no telemetry in its [README](https://github.com/Graphify-Labs/graphify/blob/0a8cd4e1e342235fe53e881fb5d591bf0460071f/README.md).
This is a scoped source review, not a complete security audit. Cloud upload,
remote models and external database connections require separate authorization.

## Installed state and reproduction

Native Python 3.13.15 virtual environment:
`.cache/superrstudio/graphify-venv`. Packages were installed as binary wheels;
no third-party installation script or source build was executed.

The downloaded `graphifyy-0.9.97-py3-none-any.whl` was checked against PyPI's
SHA-256: `eb24dd7f93293753c001ca36e7304e0b52e86fe4124c2f531dcdb3d64865e01a`.
The wheel's CLI, dependencies and backend controls were inspected before use.
The optional R parser was added as `tree-sitter-language-pack==0.11.0`.
The reviewed wheel/source and complete install logs remain under
`.cache/superrstudio/graphify-review/`; the resolved package list is
`installed.txt` there. These generated files are intentionally not versioned.

For a new machine, create the venv with native Python, download the exact wheel
from the linked release, verify the hash above, then install that wheel and the
pinned R parser using `pip install --only-binary=:all:`. Do not use an unpinned
`graphify install` command: it registers assistant integrations outside this repo.

```powershell
./tools/superrstudio/graphify-local.ps1 Version
./tools/superrstudio/graphify-local.ps1 Index
./tools/superrstudio/graphify-local.ps1 Explain -Terms 'sourceModuleRFile'
./tools/superrstudio/graphify-local.ps1 Path -Terms 'A','B'
```

The wrapper indexes only `src`, respects ignored build/dependency directories,
and writes to `.cache/superrstudio/graphify-source/graphify-out/`. It does not
merge into a global graph or change OS configuration. Re-index after source
changes; the tool uses an incremental cache. Verify query hits in actual files
and inspect parse warnings before relying on missing edges.

## Observed limitations

The first session-module scan processed 490 code files and produced 7,679 nodes
and 19,343 edges after adding the R grammar. Eighteen C++ files had partial parse
errors (including JSNI/preprocessor-like constructs); numerous R files still
yielded no symbols despite the parser being available. R support is therefore
incomplete for RStudio's `.rs.addFunction` style. This does not block development:
use `rg`, actual source and compiler/runtime tests for missing relationships.

The full `src` scan then processed 4,586 code files and produced 87,531 nodes,
241,592 edges and 1,753 communities. It reported 71 partially parsed files,
235 files without symbols and 28 nodes missing a `source_file` field. A local
`Explain sourceModuleRFile` query successfully located the real implementation
at `cpp/session/SessionModuleContext.cpp:2272`, but exposed few incoming links:
do not treat those sparse edges as a complete caller list.
