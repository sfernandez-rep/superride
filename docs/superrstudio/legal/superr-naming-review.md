# Preliminary naming and trademark review: "SuperR"

Date: 2026-10-29. **Status: preliminary, not a clearance.** This is a
technical record prepared by the development agent from public web searches.
It is not legal advice and does not replace a professional trademark search.

## Question

Can the fork be distributed publicly as **SuperR** (application SuperR,
executable `SuperR.exe`) without a material risk of infringing or appearing to
use someone else's mark, in particular Posit's "RStudio" mark and the R
project's name and logo?

## Method and limits

- Four public web searches (2026-10-29) for "SuperR" and "Super R" as software,
  as a trademark, and for the R Foundation's and Posit's trademark policies.
- **Not done:** no query of the official registers (USPTO, EUIPO, WIPO Global
  Brand Database, national offices of Spain or Latin American countries), no
  search of Nice classes 9 and 42 by a professional, and no common-law or
  domain-name survey beyond the search results. The search tool cannot query
  those databases directly.

## Findings

| Topic | Finding | Assessment |
| --- | --- | --- |
| Existing software named "SuperR" | None found. The only match was this project's own repository. The closest names are the CRAN package `super` (string interpolation, 2024) and unrelated "Super…" products such as SuperCROSS. | No conflict found, but this is **not proof** that no registration exists |
| "SuperR" as a registered mark | No record found in the search results; "Super"-prefixed software marks exist (e.g. SUPERNOVA, SUPERCRUISE) | Unverified; needs a register search |
| Posit's "RStudio" mark | Posit's guidelines require written permission for any use of its marks, including as part of a product or for software derived from Posit software | The product name no longer contains "RStudio". Factual statements ("an independent fork of RStudio") remain nominative use |
| Repository name | Renamed to `sfernandez-rep/superride` on 2026-10-29 (owner decision) | **Resolved:** the repository name no longer contains "rstudio". GitHub redirects the old URL, which still contains it; that redirect cannot be removed without breaking links |
| R language name and logo | No official R Foundation trademark policy was found. Informal R-help statements (not official positions) say "R" and its logo are not registered, and the logo is CC-BY-SA 4.0 | Low to moderate. The SuperR logo is a blue ribbon "R", not the R logo (no grey ellipse), but it is a letter R used in the R ecosystem |
| Endorsement | The About dialog, installer metadata and documentation state that SuperR is not developed, endorsed or supported by Posit | Addressed in the product |

Sources:
- [Posit trademark guidelines](https://posit.co/about/trademark-guidelines)
- [RStudio trademark FAQ](https://rstudio.com/about/trademark/faq)
- [Forking and trademarks (NLnet)](https://NLnet.nl/NGI0/bestpractices/Forking_and_Trademarks.pdf)
- [R-help, guidelines for the use of the R logo (2008)](https://stat.ethz.ch/pipermail/r-help/2008-January/150728.html)
- [R-help, "Good Will Legal Question" (2023)](https://stat.ethz.ch/pipermail/r-help/2023-March/477049.html)
- [CRAN package `super`](https://rpkg.net/package/super)

## Conclusion

**The name is not cleared.** Nothing found conflicts with "SuperR", but a web
search cannot establish that no conflict exists. One point stays open:

- there has been no register search in classes 9 and 42.

(The repository-name concern was resolved on 2026-10-29: the repository is
now `superride`.)

Following the release rules, the distributable is built and tested, but
**it is not published as a public GitHub release** until the owner:

1. has a register search done for "SuperR" (USPTO, EUIPO, WIPO; Spain and the
   target Latin American countries if relevant) or obtains legal advice; and
2. (done 2026-10-29) renamed the repository to `superride`.

Until then the installer is produced as a CI artifact or as a local build
only, with this record linked from the release notes draft.
