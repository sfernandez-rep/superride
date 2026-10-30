# Benchmarks (phase 4, Milestone F)

Run with `tools\superrstudio\bench.ps1 -Runs 3 -Repetitions 5`. The raw JSON goes to `.cache\superrstudio\bench`.

## Test system

| | |
| --- | --- |
| Date | 2026-10-29 |
| CPU | AMD Ryzen 7 5700X3D, 8 cores / 16 threads |
| Memory | 32 GB |
| OS | Windows 11 Pro for Workstations 10.0.26300 |
| Software | R 4.6.1, ggplot2 4.0.3, data.table 1.18.6.1, TropFishR 1.6.6 (isolated library) |

**Inputs.** Generated with a fixed seed: numeric, categorical and date columns with 1,000, 10,000 and 100,000 rows. TropFishR's synLFQ7 expanded to 27,871 individual lengths.

## R level (`tools/superrstudio/bench/bench-r.R`)

Each figure is the median elapsed time of one call, timed with `Sys.time()`. On Windows `proc.time()` only resolves about 10 ms.

| Operation | 1,000 rows | 10,000 rows | 100,000 rows |
| --- | --- | --- | --- |
| Inspect a data.frame (staleness snapshot is a reference) | 0.3 ms | 0.6 ms | 1.1 ms |
| Inspect a data.table (snapshot is serialized) | 0.7 ms | 1.6 ms | 7.6 ms |
| Generate code, scatter + lm (statistics included) | 3.7 ms | 8.2 ms | 54 ms |
| Preview map, scatter + lm | 0.30 s | 0.35 s | 2.07 s |
| Preview map, histogram | 0.11 s | 0.11 s | 0.13 s |
| Preview map, date X lines, **before** | 0.13 s | 0.69 s | 5.75 s |
| Preview map, date X lines, **after** | 0.11 s | 0.13 s | 0.36 s |

**Other R-level measurements**

| Measurement | Result |
| --- | --- |
| Listing datasets among 10 / 200 data frames | 0.3 ms / 3.5 ms |
| Switching from a 10,000-row to a 100,000-row dataset, then rendering a scatter | 1.9 s |
| Snapshot memory for 100,000 rows | data.frame: none extra (a reference); data.table: 3.5 MB serialized copy |
| TropFishR data check (27,871 rows) | 0.19 s |
| LFQ creation with two plots | 0.75 s |
| Catch curve with M | 37 ms |
| ELEFAN_GA (population 30, 20 generations), in process | 4.57 s |
| The same ELEFAN_GA call through the background runner, start to recorded run | 5.78 s |

The background runner adds about 1.2 s: Rscript start-up, loading TropFishR, and transferring the job and result. In exchange the session stays responsive and the run can be cancelled. The desktop test checks that the console answers during a run.

## Optimisation made (justified by the measurements)

**Profile of the 100,000-row line preview**

| Step | Time |
| --- | --- |
| `ggplot_build` | 0.08 s |
| `ggplot_gtable` | 0.15 s |
| Rasterising one 100,000-vertex polyline with antialiased Cairo PNG at double resolution | 4.3 s |

**Device comparison for 100,000 rows**

| Plot | Cairo PNG | Cairo PNG without antialiasing | Windows GDI PNG | SVG |
| --- | --- | --- | --- | --- |
| Line | 4.3 s | 0.30 s | 0.92 s | 0.14 s (1.5 MB) |
| Points | 1.6 s | 0.9 s | 3.6 s | 1.8 s (35 MB) |

**The change**

- The preview counted every layer row towards its 5,000-row SVG limit.
- SVG stores one element per point but a single element per path. So paths (lines, smooths, densities) are now counted separately, by vertices, up to 100,000.
- Line previews of up to 100,000 rows stay vector and keep their quality. They became 16× faster.
- Point previews are unchanged: SVG would be large and no faster.
- The element map and hit testing are identical.
- Covered by `visual-scatter.R`: a 20,000-row line is SVG; 20,000 points, and points with a line, are PNG.

## Desktop (`tests/superrstudio/bench-desktop.cjs`)

Each configuration runs one discarded warm-up launch, then three measured launches; the figures are medians. Each launch uses an isolated profile and the same R 4.6.1 and library.
- **ready**: from starting the desktop process to `window.rstudio.ready`.
- **console**: the round-trip time of `invisible(1)` from the console, 20 times.
- **memory**: working sets after the measurements.

| Configuration | Ready | Console round trip | R session | Electron (all processes) |
| --- | --- | --- | --- | --- |
| Upstream baseline build (`v2026.10.0+233`, unmodified) | 3.32 s | 29 ms | 128.1 MB | 562 MB |
| This fork, SuperRStudio features **off** | 3.34 s | 30 ms | 128.4 MB | 629 MB |
| This fork, features **on**, idle | 3.41 s | 29 ms | 132.1 MB | 634 MB |
| Features on, after the plot editor previewed 100,000 rows | 3.40 s | 29 ms | 266 MB | 693 MB |

**Interpretation**
- **Start-up and console latency:** the three configurations are equal within run-to-run noise (about ±0.2 s and ±5 ms).
- **R session memory:** sourcing the SuperRStudio modules adds about 4 MB.
- **After the 100,000-row preview:** the session holds the generated 100,000-row data frame (about 2.4 MB) plus R's graphics and memory pools from rendering, which R keeps for reuse.
- **The Electron difference (+67 MB) is a build artefact, not a feature cost.**
  - This checkout's client is a GWT *draft* compilation (`dev-build.ps1`: unoptimised, 37 MB of JavaScript), while the baseline worktree's client is a regular compilation (13.9 MB).
  - With the features off, no SuperRStudio code runs beyond a status request.
  - A like-for-like memory comparison needs both clients compiled the same way. This is listed as a follow-up.

**Plot editor in the window** (features on, 100,000 rows; from the last change to the new preview, including the editor's 250 ms settle delay)

| Plot | Latency | Preview format |
| --- | --- | --- |
| Lines (date X) | 1.49 s | SVG |
| Points | 2.36 s | PNG |

Points spend about 2.0 s in R (Cairo rasterisation of 100,000 antialiased points). Lines spend 0.36 s in R; the rest is transfer and the browser decoding a 1.5 MB SVG. Both are follow-up candidates. They were not changed in this session, because the remaining costs are in rendering quality trade-offs (antialiasing) and browser decoding.

## Fourth session: Visual tab, theme switch, preview canvas (2026-10-29, afternoon)

The same commands were run after adding the Visual workbench tab, the light/dark switch and the resizable canvas. The machine was more loaded than in the morning run: the unmodified baseline itself went from 3.32 s to 3.94 s, and console round trips from 29 ms to 45 ms. **Only comparisons within the same run are meaningful.**

| Configuration (medians of 3 + warm-up) | Ready | Console | R session | Electron |
| --- | --- | --- | --- | --- |
| Upstream baseline build | 3.94 s | 45 ms | 128.3 MB | 567 MB |
| This fork, features off | 4.29 s | 45 ms | 128.4 MB | 643 MB |
| This fork, features on, idle (Visual tab, theme switch) | 4.27 s | 48 ms | 132.0 MB | 643 MB |
| Features on, after a 100,000-row preview | 4.30 s | 45 ms | 266 MB | 702 MB |

**Interpretation**
- **Start-up with the features off or on is equal** (4.29 s against 4.27 s). The Visual tab, the layout migration and the toolbar switch add no measurable start-up cost.
- **The gap to the baseline (0.35 s here, none in the morning run) is not from new code.** It appears with the features off too, the client size is unchanged (35.7 MB draft against 13.3 MB optimised), and it was absent on the less loaded machine. Parsing the unoptimised draft client is the likely cost under load. Confirming this needs an optimised client build of this fork; it remains the open follow-up.
- **In-window preview latency at 100,000 rows** was 1.83 s for lines and 2.90 s for points, against 1.49 s and 2.36 s in the morning. That is the same proportional slowdown as the R-level timings of this run (100,000-row lines 0.47 s against 0.36 s).

**Preview canvas (R level, 10,000 rows, scatter with lm)**

| Canvas | Preview |
| --- | --- |
| 5 × 3.75 in | 0.42 s |
| 10 × 7.5 in | 0.54 s |
| 16 × 9 in (bitmap capped at 2,400 px) | 0.54 s |

A large canvas costs about 0.1 s more per preview. The 2,400-pixel cap bounds the cost beyond about 12 in.

## Like-for-like: optimised clients on both sides (2026-10-29)

`dev-build.ps1 -Component gwt -Optimized` compiles this fork's client with upstream's normal `gwtc` target, the one release builds use, instead of draft mode. The result is 13.41 MB of JavaScript, against 13.26 MB in the baseline: the SuperRStudio features add about 0.15 MB to the client. With both clients optimised, the same benchmark gives:

| Configuration (medians of 3 + warm-up) | Ready | Console | R session | Electron |
| --- | --- | --- | --- | --- |
| Upstream baseline build | 3.70 s | 43 ms | 128.1 MB | 563 MB |
| This fork, features off | 3.50 s | 39 ms | 128.1 MB | 562 MB |
| This fork, features on, idle | 3.67 s | 44 ms | 132.0 MB | 567 MB |
| Features on, after a 100,000-row preview | 3.65 s | 42 ms | 268 MB | 620 MB |

**Conclusion**
- The fork starts as fast as unmodified RStudio and uses the same Electron memory.
- The earlier Electron difference (+67 MB) and the start-up gap under load (0.35 s) were caused entirely by the unoptimised draft client used for development.
- With the features on, the R session uses 4 MB more at idle (the sourced modules).
- The baseline's warm-up launch took 97.7 s (a first launch after the client changed on disk). It is excluded by design, like every warm-up.

The ggplot2, visual and theme desktop scenarios pass on the optimised client too.

## Not measured or not comparable yet

- **Unmodified installed RStudio.** It was not used, to keep the official installation untouched. The baseline is the pristine upstream build in the `SuperRStudio-baseline` worktree, run through the same development launcher.
- **GPU or frame-rate UI responsiveness.** UI responsiveness is measured as console round trips and window latencies.
- **Linux.**
