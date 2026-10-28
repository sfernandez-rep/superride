# Preliminary scientific package assessment

Observed 2026-10-27. **None of these packages was installed locally.**
The [official CRAN source index](https://cran.r-project.org/src/contrib/PACKAGES.gz)
contained all 14 candidates below. Its downloaded compressed file had SHA-256
`331c860513bafcc06de2b3ab9f2fa1072779907d7ed3a511cf3893b50fe9f8c0`.
The extracted metadata is preserved in
[the dated snapshot](baseline/cran-packages-2026-10-27.json).
Package MD5 fields are provenance from CRAN, not a security verification.

| Package | Version in index | Declared license | Native compilation | Intended assessment |
| --- | --- | --- | --- | --- |
| ggplot2 | 4.0.3 | MIT + file LICENSE | No | Plot model, code generation and final rendering |
| dplyr | 1.2.1 | MIT + file LICENSE | Yes | Explicit reproducible transformations |
| tidyr | 1.3.2 | MIT + file LICENSE | Yes | Reshaping operations |
| readr | 2.2.0 | MIT + file LICENSE | Yes | Delimited-data import |
| readxl | 1.6.0 | MIT + file LICENSE | Yes | Excel import |
| vegan | 2.7-6 | GPL-2 | Yes | Ecology and ordination |
| BiodiversityR | 2.18-1 | GPL-3 | No | Biodiversity; evaluate Rcmdr/tcltk dependency cost |
| FSA | 0.10.1 | GPL (>= 2) | No | Fisheries methods, one validated method at a time |
| TropFishR | 1.6.6 | GPL-3 | No | Length-frequency and growth models; optimization dependencies |
| sf | 1.1-3 | GPL-2 or MIT + file LICENSE | Yes | Spatial methods; separate native-library assessment |
| renv | 1.3.1 | MIT + file LICENSE | No | Existing project environment isolation |
| svglite | 2.2.2 | GPL (>= 2) | Yes | SVG preview/export and font behavior |
| plotly | 4.12.1 | MIT + file LICENSE | No | Optional interaction adapter, fidelity comparison |
| esquisse | 2.1.0 | GPL-3 or file LICENSE | No | Existing visual ggplot authoring and add-in reuse |

Compilation refers to the package itself; its dependencies can also need native
tooling. No `OS_type` restriction appeared in these index entries, which is not
proof of Windows or Ubuntu compatibility. Full license files and dependency
licenses still require review before bundling or adapting code.

Current ggplot2 requires R >= 4.1 and readxl >= 4.2, while upstream's Windows
bootstrap installs R 3.6.3. The old build runtime cannot certify the modern
scientific workflow. Separate build requirements, the supported user R matrix,
and per-project package constraints. Preserve the selected R version and renv
lockfile; offer explicit installation choices only when a workflow needs them.

The [CRAN ggplot2 check results](https://cran.r-project.org/web/checks/check_results_ggplot2.html)
observed during initialization show 4.0.3 OK on release Windows x64 and release
Linux, with development-R notes. Those are CRAN results, not SuperRStudio tests
and not validation of exact target environments.

Remaining per-package work: inspect maintainer/release activity and open issues,
CRAN check details for target R versions, Windows binary availability, Ubuntu
system requirements and transitive licenses. Then test installation in a
disposable library or renv project, numerical behavior and failure messages.
Availability in the index does not establish maintenance quality, scientific
validity or suitability for automatic installation.
