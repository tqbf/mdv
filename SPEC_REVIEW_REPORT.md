# Specification Review Report

> - **Subject:** `SPEC.md` v0.7 — mdv (Markdown viewer, native macOS GUI + CLI launcher)
> - **Method:** four-pass review under the `spec-review` rubric: comprehension, local precision, cross-consistency, and implementation simulation.
> - **Review boundary:** `SPEC.md` is treated as the source of truth. This review assesses the specification, not whether the current Swift implementation conforms to it.
> - **Finding lineage:** F-001 through F-075 are recorded by the specification as applied. New findings continue at F-076.

## 1. Executive Summary

`SPEC.md` is **Level 2 — Implementable**, but **not ready for an implementation or conformance claim without material clarification**. It has unusually strong breadth: explicit actors and scope, detailed renderer contracts, a normative lifecycle table, measurable formulas, extensive edge cases, acceptance scenarios, and a dense implementation/test traceability matrix.

This review found **18 new findings: 0 CRITICAL, 7 HIGH, 9 MEDIUM, and 2 LOW**. The main weaknesses are concentrated rather than systemic:

- launch and navigation rules conflict at three state boundaries;
- the remote-image exception contradicts a security invariant;
- the absolute no-crash promise lacks resource-exhaustion semantics;
- the release tag gate has a documented bypass;
- the required render harness is named but not specified as a reproducible CLI;
- several otherwise strong algorithms and acceptance checks omit one decisive boundary or tie rule.

The specification remains substantially stronger than a typical design document. Resolving the seven HIGH findings and aligning the affected tests would move it close to Level 3.

## 2. Overall Maturity

**Level 2 — Implementable.** A competent engineer can build most of mdv directly from the contracts. However, two competent implementations can still diverge materially on startup, back-stack contents, remote network behavior, release eligibility, resource exhaustion, and render-harness behavior. Those differences are user-visible or determine whether conformance can be tested.

The document does not meet Level 3 while T-28 explicitly records an observation instead of an expected result, R-40 conflicts with the lifecycle failure path, and R-39 lacks enough CLI semantics to reproduce its own cited acceptance checks.

## 3. Findings Summary

| ID | Severity | Location | Title |
| -- | -------- | -------- | ----- |
| F-076 | HIGH | R-40, §3.1, E-03, Figure 3.1, T-28 | Launch with an unreadable history head has contradictory terminal state |
| F-077 | HIGH | R-40, R-18, T-28, §11 | Cold-start file arguments leave back-stack behavior unresolved |
| F-078 | HIGH | R-18, R-27, R-28, T-22, T-27 | Cross-file bookmark and placeholder jumps conflict with the general push rule |
| F-079 | HIGH | §0 trust boundary, R-16, I-001, I-003 | Remote-image fetching contradicts the no-network-content invariant |
| F-080 | HIGH | §0 trust boundary, R-16, R-36, I-002, E-11 | The no-crash guarantee has no resource-exhaustion contract |
| F-081 | HIGH | §1 release actor, R-34, §5.3, K-11, T-02 | The release tag gate can be bypassed by `VERSION` |
| F-082 | HIGH | R-39, §9.0, T-13, T-17, T-19 | The required render harness is not specified as an executable contract |
| F-083 | MEDIUM | R-01, R-20, I-013, T-25 | History recency invariant contradicts selecting-route behavior |
| F-084 | MEDIUM | R-11, K-07, §7.2, T-18 | Mermaid width formulas disagree at narrow widths |
| F-085 | MEDIUM | R-24, E-24, T-23 | Empty in-document find queries have no semantics |
| F-086 | MEDIUM | R-19, C-11, E-06, T-22 | Cross-file fragment links have no destination-position rule |
| F-087 | MEDIUM | C-08, K-09, T-26 | Anchor fingerprint normalization is underdefined |
| F-088 | MEDIUM | R-25, C-03, T-24 | Equal-rank global search results have no tie-breaker |
| F-089 | MEDIUM | R-32, C-04, §11, §9 | Preference persistence is not fully verified |
| F-090 | MEDIUM | R-30, C-04, T-11 | The zoom acceptance case gives incompatible HUD results |
| F-091 | MEDIUM | I-008, T-32 | The idle-CPU acceptance threshold is not reproducible |
| F-092 | LOW | §3.1, Figure 3.1, E-21 | The lifecycle diagram omits the deletion self-transition |
| F-093 | LOW | R-24, R-27, C-10, K-10, E-17, T-19, T-23, T-39 | Normative variables and related numeric expressions use inconsistent notation |

## 4. Detailed Findings

### F-076 — Launch with an unreadable history head has contradictory terminal state

**Severity:** HIGH

**Location:** R-40; §3.1 `EMPTY` and `LOADING`; E-03; Figure 3.1; T-28

**Observation**

R-40 says the application shows `EMPTY` **only** when history is empty. The `LOADING` row and Figure 3.1 instead send an unreadable initial file with no previous document to `EMPTY`. A persisted history may legally contain a path that was deleted, became unreadable, or ceased to be valid UTF-8. The specification does not say whether launch then keeps the non-empty history and shows `EMPTY`, removes the failed row, or tries later rows until one loads.

**Why it matters**

This is the initial-state rule. Each interpretation produces a different selected row, watcher, search population, and visible first screen.

**Potential consequence**

A conforming implementation can violate either R-40 or E-03 for a common stale-history case. The current acceptance set does not distinguish the alternatives.

**Recommended resolution**

Choose one launch policy and state it in R-40 and §3.1. The smallest change is: attempt the head once; if it is unreadable, enter `EMPTY` while retaining history, explicitly making this a second allowed `EMPTY` entry. If the intended behavior is to find the first readable row instead, define ordering, whether failed rows remain, and the all-unreadable outcome. Add the stale-head case to T-28.

### F-077 — Cold-start file arguments leave back-stack behavior unresolved

**Severity:** HIGH

**Location:** R-40; R-18; T-28; §11 row R-40

**Observation**

R-40 says whether a cold-start file argument pushes the automatically restored history head onto the back stack is “to be verified.” T-28 tells the tester to record the result and file an open defect for one outcome instead of stating the required outcome. Section 11 nevertheless treats the plain R-40 row as realised and verified.

**Why it matters**

Back navigation after `mdv B.md` is observable behavior. An implementer cannot infer whether history head A was a real navigation origin or merely an initialization artifact.

**Potential consequence**

Two implementations can both claim conformance while ⌘← either opens A or does nothing. T-28 cannot return pass/fail for this branch.

**Recommended resolution**

Make the decision normative. Recommended: when a cold-start argument is already available, initialize directly with that file and do not create a snapshot for a document the reader never saw. Replace the observational clause in T-28 with the selected expected result and mark R-40 verified only after that assertion exists.

### F-078 — Cross-file bookmark and placeholder jumps conflict with the general push rule

**Severity:** HIGH

**Location:** R-18; R-27; R-28; T-22; T-27

**Observation**

R-18 first says loading a different file pushes the outgoing document and clears the forward stack. The same row later says bookmark and placeholder jumps do not push. R-27 permits a bookmark to load another file, and R-28 explicitly permits the placeholder to load another file. T-27 expects a cross-file placeholder jump not to create a back destination, but no equivalent cross-file bookmark assertion exists.

**Why it matters**

The general rule and its apparent exceptions overlap. The resulting stack contents differ after ordinary navigation.

**Potential consequence**

After jumping from A to a bookmark or placeholder in B, ⌘← can return to A in one implementation and not another.

**Recommended resolution**

Rewrite R-18 as an ordered rule: different-file loads push **except** bookmark and placeholder jumps, if that is intended. State whether the exception applies regardless of whether the target is the current file. Add one cross-file bookmark case to T-22 or T-26.

### F-079 — Remote-image fetching contradicts the no-network-content invariant

**Severity:** HIGH

**Location:** §0 trust boundary; R-16; I-001; I-003

**Observation**

The trust boundary explicitly classifies image URLs as untrusted document content. R-16 and I-001 allow an enabled remote-image path to issue a network request for such a URL. I-003 says document content never reaches an external URL or network request and lists no remote-image exception.

**Why it matters**

I-003 is a security invariant. It is false whenever remote images are enabled because the document-provided URL necessarily determines the network destination and request target.

**Potential consequence**

A verifier cannot determine whether remote fetching is a permitted disclosure or an invariant violation. Security documentation can overstate privacy guarantees.

**Recommended resolution**

Add an explicit R-16 exception to I-003: only the user-enabled remote-image URL may leave the process, and no other document bytes may be attached. Define whether redirects, cookies, referrers, authentication state, and URL query strings are permitted; trace those rules to a network-level acceptance check.

### F-080 — The no-crash guarantee has no resource-exhaustion contract

**Severity:** HIGH

**Location:** §0 trust boundary; R-16; R-36; I-002; E-11

**Observation**

R-36 and I-002 promise that no document content terminates the application. The specification accepts arbitrary files, data URIs, remote images, Mermaid source, and LaTeX source but defines no maximum input size, decoded image dimensions, download size, network timeout, layout budget, recursion/depth limit, or cancellation deadline. Parser errors have fallbacks; memory and time exhaustion do not.

**Why it matters**

An absolute robustness guarantee is not implementable or verifiable without bounded inputs or defined exhaustion behavior.

**Potential consequence**

Implementations can hang, allocate without bound, or be terminated by the OS on the same hostile document while each claims that ordinary parse failures are covered.

**Recommended resolution**

Define measurable limits for file bytes, decoded/raster image dimensions or bytes, remote download bytes and duration, and renderer work where practical. Specify the visible fallback and cancellation behavior when a limit is exceeded. Add adversarial boundary checks; narrow R-36 to the bounded domain if an absolute guarantee is not intended.

### F-081 — The release tag gate can be bypassed by `VERSION`

**Severity:** HIGH

**Location:** §1 release actor; R-34; §5.3 `dist`; K-11; T-02

**Observation**

R-34 requires `make dist` to refuse unless `HEAD` carries an exact `vX.Y.Z` tag. Section 5.3 says `VERSION=x.y.z` overrides tag lookup for `dist`, while calling that invocation “not a release path.” It still invokes the named `dist` chain and produces release-shaped artifacts. K-11 requires the artifact version to equal the tag. T-02 checks only the untagged invocation without an override and is cited as proving K-11, though it never verifies a successful tagged artifact.

**Why it matters**

Release eligibility and artifact provenance are supply-chain behavior, not an internal implementation choice.

**Potential consequence**

An untagged commit can produce an artifact indistinguishable by name and signing pipeline from a tagged release, contrary to R-34 and K-11.

**Recommended resolution**

Remove the override from `dist`, or move it to a separately named non-publishable target whose outputs cannot satisfy K-11. Add a positive tagged-release acceptance check covering filename, embedded provenance, signature, notarization, staple, and checksum; keep T-02 as the negative gate check.

### F-082 — The required render harness is not specified as an executable contract

**Severity:** HIGH

**Location:** R-39; §9.0; T-13; T-17; T-19

**Observation**

R-39 names `--scan` and `--check` but does not define command syntax, accepted inputs, output location, stdout/stderr, exit codes, fallback handling, golden lookup, or comparison tolerance. It requires raw `test-docs/mermaid/*.mmd` files, while T-13 describes scanning every fenced Mermaid block under that directory. T-17 and T-19 do not provide complete harness invocations.

**Why it matters**

The harness is the specified evidence mechanism for renderer conformance. Different harnesses can accept different corpora and return different pass/fail results.

**Potential consequence**

R-39 can be implemented without making T-13, T-17, or T-19 reproducible from a clean checkout, defeating the requirement's purpose.

**Recommended resolution**

Specify the harness as a CLI table: each invocation, positional arguments, options, file discovery rules, output naming, deterministic environment, exit statuses, and `--check` comparison metric/tolerance. Resolve whether `--scan` consumes raw `.mmd`, Markdown fences, or both. Provide exact commands in T-13, T-17, and T-19.

### F-083 — History recency invariant contradicts selecting-route behavior

**Severity:** MEDIUM

**Location:** R-01; R-20; I-013; T-25

**Observation**

R-01 and R-20 say selecting a sidebar row, existing search hit, or navigation snapshot does not reorder history. I-013 says the most recently **opened** path is first. T-25 explicitly opens the third row while requiring the order to remain unchanged and cites I-013.

**Why it matters**

“Opened” includes both adding and selecting routes in R-01, so the invariant cannot hold with the test.

**Potential consequence**

An implementation that moves a selected row to the top satisfies I-013 but fails R-20 and T-25; one that does not has the opposite inconsistency.

**Recommended resolution**

Change I-013 to “the most recently **added** path is first,” using R-01's defined route term. Retain T-25 as the conformance example.

### F-084 — Mermaid width formulas disagree at narrow widths

**Severity:** MEDIUM

**Location:** R-11; K-07; §7.2; T-18

**Observation**

R-11 and K-07 use the floored minimum of natural width and column width minus 36 pt. Section 7.2 inserts a lower bound of 1 pt with $\max(w_{\mathrm{col}} - 36, 1)$. The formulas differ whenever $w_{\mathrm{col}} < 37$ pt. T-18 covers wide and ordinary resize cases but not the lower boundary.

**Why it matters**

Without the lower bound, the normative formula can produce zero or negative raster widths.

**Potential consequence**

Narrow windows can trigger different sizes, fallback behavior, or renderer errors across implementations.

**Recommended resolution**

Make §7.2 the single normative formula and have R-11 and K-07 reference it verbatim. Add a T-18 case below 37 pt of available column width and assert the 1 pt result or the chosen minimum viable width.

### F-085 — Empty in-document find queries have no semantics

**Severity:** MEDIUM

**Location:** R-24; E-24; T-23

**Observation**

R-24 defines case-insensitive substring matching with the query taken verbatim but does not special-case an empty string. E-24 defines empty and whitespace-only behavior only for global search. Empty-string substring matching can mean no matches, one match per boundary, or an unavailable next/previous action.

**Why it matters**

The find bar starts empty, so this is an ordinary state rather than a pathological input.

**Potential consequence**

The match count, button enabled state, and ⌘G behavior can diverge immediately after opening the find bar.

**Recommended resolution**

State that an empty in-document query produces no matches and disables stepping, or define the intended alternative. Preserve R-24's “verbatim” rule for non-empty whitespace queries. Add both cases to T-23.

### F-086 — Cross-file fragment links have no destination-position rule

**Severity:** MEDIUM

**Location:** R-19; C-11; E-06; T-22

**Observation**

R-19 defines local-file navigation and separately defines scrolling for a link that is exactly `#fragment`. It does not say what happens for `other.md#fragment`: open at the matching heading, restore the file's stored scroll position, or open at the top. It also does not state when percent-decoding occurs before C-11 comparison.

**Why it matters**

Cross-file anchors are a common Markdown link form and affect both file loading and position restoration.

**Potential consequence**

Two conforming implementations can display different sections after the same link click.

**Recommended resolution**

Define the processing order for path plus fragment: resolve path, load under the adding-route rules, normalize or decode the fragment, then either scroll to the first matching slug or apply an explicitly chosen top/restore rule. Add a cross-file fragment and a percent-encoded fragment to T-22.

### F-087 — Anchor fingerprint normalization is underdefined

**Severity:** MEDIUM

**Location:** C-08; K-09; T-26

**Observation**

C-08 defines a fingerprint as “the block's words joined by single spaces, lower-cased, truncated to 80 characters.” It does not define what counts as a word, which whitespace classes split words, the case-folding locale or Unicode operation, or whether 80 counts bytes, Unicode scalars, UTF-16 code units, or grapheme clusters.

**Why it matters**

Fingerprints are durable identifiers used after edits and across launches. Different normalization changes which block wins.

**Potential consequence**

Anchors containing non-ASCII case, combining marks, emoji, or unusual whitespace resolve differently across implementations.

**Recommended resolution**

Specify an exact normalization pipeline and truncation unit. For example: split on Unicode whitespace, join with U+0020, apply locale-independent Unicode lowercase without additional normalization, then take the first 80 extended grapheme clusters. Add Unicode and whitespace boundary cases to the future C-08 unit group.

### F-088 — Equal-rank global search results have no tie-breaker

**Severity:** MEDIUM

**Location:** R-25; C-03; T-24

**Observation**

C-03 specifies `ORDER BY rank LIMIT 80` but no secondary order for equal FTS5 ranks. R-25 exposes an ordered result list, and the limit makes tie ordering affect which rows are included.

**Why it matters**

Database row order without a complete ordering key is not a deterministic contract.

**Potential consequence**

The same index can return a different result sequence or a different subset at the 80-row boundary.

**Recommended resolution**

Define a stable secondary key, such as normalized absolute path and then article id, and include it in the normative query. Add an equal-rank case crossing the result limit.

### F-089 — Preference persistence is not fully verified

**Severity:** MEDIUM

**Location:** R-32; C-04; §9; §11 rows R-32 and C-04

**Observation**

R-32 requires every C-04 preference to survive relaunch. Section 11 cites T-11, T-21, T-25, and T-31, but those tests cover only some keys. The acceptance set does not verify relaunch persistence for smart typography, remote-image loading, sidebar collapse, inspector visibility, bookmark expansion/height, or editor selection. Invalid-type and invalid-enumeration fallback behavior in C-04 is also largely untested.

**Why it matters**

The traceability row overstates the evidence for a broad universal requirement.

**Potential consequence**

Several preference keys can be ignored, reset, or mishandled while all cited tests pass.

**Recommended resolution**

Add a compact table-driven persistence acceptance check covering every C-04 key, including wrong-type, out-of-range, and unknown-enumeration cases. Update §11 to cite the complete check rather than partial feature tests.

### F-090 — The zoom acceptance case gives incompatible HUD results

**Severity:** MEDIUM

**Location:** R-30; C-04; T-11

**Observation**

R-30 says the HUD appears after each change and displays the rounded current scale. T-11 writes `1.25`, invokes ⌘=, then says the HUD shows 125% while the scale lands on 140%. A post-change HUD cannot show both the pre-change and resulting value. The same case is intended to disambiguate snapping at a half-tenth but does not state the tie rule directly.

**Why it matters**

The test expected result conflicts with the formula it is meant to verify.

**Potential consequence**

A correct 140% HUD can fail T-11, while a stale 125% HUD can pass its wording.

**Recommended resolution**

Specify the step algorithm and tie rule explicitly. If `1.25` snaps to `1.3` and then increments to `1.4`, T-11 should require the post-change HUD to show 140%. If the HUD intentionally previews the stored value first, define the two display events and their timing.

### F-091 — The idle-CPU acceptance threshold is not reproducible

**Severity:** MEDIUM

**Location:** I-008; T-32

**Observation**

T-32 requires `top` samples over 30 seconds to show at most 1% CPU but does not define sampling interval, warm-up, aggregation, process selection, display scale, machine state, or whether every sample, mean, median, or percentile must meet the threshold. I-008's actual invariant is bitmap backing and static-page idle behavior; the numeric threshold appears only in the test.

**Why it matters**

A metric is reproducible only when its population, aggregation, and conditions are defined.

**Potential consequence**

The same build can pass or fail based on one transient sample or tester interpretation.

**Recommended resolution**

Either test I-008 structurally and retain CPU as diagnostic evidence, or define a benchmark protocol: warm-up, sample cadence, aggregate, allowed transient percentile, test document, window state, and hardware/OS baseline. Place the threshold in a K-nn requirement if it is normative.

### F-092 — The lifecycle diagram omits the deletion self-transition

**Severity:** LOW

**Location:** §3.1 `VIEWING`; Figure 3.1; E-21

**Observation**

The normative table states that deleting the displayed file leaves the window in `VIEWING` with its existing content. Figure 3.1 cites E-21 but has no `VIEWING` self-transition for delete or an unreadable reload.

**Why it matters**

The diagram is illustrative, but its stated coverage is incomplete and can mislead a lifecycle reader.

**Potential consequence**

An implementer relying on the diagram may treat deletion as an unspecified exit or conflate it with history-row deletion.

**Recommended resolution**

Add a `VIEWING --> VIEWING` edge labeled with E-21, or narrow the figure caption so it does not claim that transition.

### F-093 — Normative variables and related numeric expressions use inconsistent notation

**Severity:** LOW

**Location:** R-24; R-27; C-10; K-10; E-17; T-19; T-23; T-39

**Observation**

Normative variables appear as Markdown italics (`*m*`, `*n*`) rather than math, and K-10 writes the three heading scales as `$1.75 / 1.4 / 1.15$` without naming each value in the expression. Related rows alternate between italic, code, and math forms.

**Why it matters**

The document otherwise uses LaTeX consistently. Mixed notation weakens symbol ownership and can render the heading-scale slash as division rather than a tuple.

**Potential consequence**

This is primarily editorial, but it makes formula and identifier tooling less reliable.

**Recommended resolution**

Use `$m$`, `$n$`, and `$i$` for mathematical variables. Replace the heading-scale shorthand with named assignments such as $h_1 = 1.75$, $h_2 = 1.40$, and $h_3 = 1.15$.

## 5. Requirements Review

Most R-nn rows are observable and name their triggering route, result, and cross-reference. Rendering, history, reload, and persistence requirements are particularly concrete. The material exceptions are R-40's unresolved branch, R-18's overlapping general rule and exceptions, R-34's conflict with §5.3, and R-36's unbounded universal guarantee. No major product capability is missing from the stated scope.

## 6. Interface and Data-Contract Review

The GUI, launcher, persistence schema, renderer entry points, and build targets are well enumerated. C-15 is a strong serialized-data contract. C-08 needs an exact Unicode normalization/truncation algorithm. C-03 needs a complete ordering key. R-39 is the largest interface gap: a named CLI with undefined invocation and exit semantics is not independently implementable.

Compatibility is generally explicit through platform and dependency pins. The required future Swift/SQL grammar additions name repositories only in D-15 and rely on later README pins; this is acceptable once the chosen commits and fixture outputs are checked in.

## 7. State and Failure Review

The lifecycle table is a strong foundation and correctly separates `EMPTY`, `LOADING`, `VIEWING`, `RELOADING`, and `CLOSED`. Failure fallback for unreadable files, transient saves, missing bookmarks, parser rejection, persistence faults, and remote-image failures is extensive.

The blocking state defects are the unreadable history head at launch and the cold-start/back-stack branch. Navigation snapshot policy also needs an explicit exception order. Retry semantics are defined for transient zero-byte reloads and migrations, but cancellation/resource behavior for oversized or long-running untrusted inputs is not.

## 8. Determinism and Algorithm Review

The column-width and ink-weight formulas are unusually precise, and the ink metric defines its empty-set case. Mermaid repair order, math rewrite order, slug behavior, section boundaries, and FTS token construction are mostly deterministic.

Remaining nondeterminism: the 1 pt raster lower bound is not repeated consistently, equal-rank search results lack a tie-breaker, anchor fingerprint normalization is not Unicode-complete, and the `1.25` zoom acceptance case conflicts with its resulting HUD value.

## 9. Edge-Case Review

Coverage is strong: malformed files, empty files, atomic saves, missing files, duplicate slugs, unsupported diagrams, invalid math, corrupted storage, multi-window routing, and removed navigation targets all have rows or tests.

Material omissions are an unreadable persisted history head, empty in-document find, cross-file fragments, and resource exhaustion. Narrow-width raster behavior is specified inconsistently rather than omitted.

## 10. Non-Functional Requirement Review

Build platform, cache sizes, zoom bounds, UI dimensions, reload latency, release signing, and several timing constraints are measurable. The 30-second CPU check is not a reproducible metric, and the universal no-crash claim is not bounded by resource limits. No throughput or opening-latency target is specified; that is acceptable because the product intent's “fast” language is not framed as a normative requirement.

## 11. Security and Trust-Boundary Review

The document correctly marks all document content as untrusted, disables the App Sandbox explicitly, blocks remote images by default, prohibits document execution, and limits logging. The principal defect is that I-003 denies the network disclosure that R-16 necessarily permits. Remote fetch redirects, credentials, referrers, timeouts, and byte limits must be specified because the feature crosses the only runtime network trust boundary.

The release tag bypass is also a provenance risk: it allows release-shaped artifacts without the exact tag required by the release actor and R-34.

## 12. Observability and Provenance Review

Identifiers, persistence locations, schema version, migration behavior, diagnostic prefixes, dependency pins, artifact names, and traceability to source symbols are strong. The specification intentionally minimizes logs, so in-place fallbacks and deterministic persistence are the primary evidence surfaces.

Provenance is weakened by §5.3's `VERSION` override and by T-02's lack of a successful tagged-release verification. Renderer provenance is also incomplete until R-39 defines exact harness commands and corpus discovery.

## 13. Testing and Verification Review

The test catalog is broad and generally maps behavior to observable outcomes. It includes positive, negative, boundary, failure, integration, visual, persistence, and lifecycle checks. The §11 matrix provides unusually good navigation from requirements to evidence.

Verification is not yet objective for R-40, R-39, R-32, the resource guarantee, or T-32. T-28 is observational rather than asserting. T-02 cannot prove K-11's positive artifact contract. T-11 contains incompatible HUD expectations. T-13's fenced-block wording does not match R-39's required raw `.mmd` corpus.

## 14. Metrics and Evaluation Review

The §7.1 ink metric is the strongest evaluation contract in the document: population, luminance function, threshold set, aggregation, degenerate case, and comparison threshold are all defined, and T-17 cites it correctly. The §7.2 worked example also computes correctly for a wide default-theme window.

T-32 does not define an aggregation for CPU samples. Render snapshot “pixel tolerance” in §9.0 has no value or formula; that belongs in the R-39 harness contract. Search ranking is delegated to FTS5 but needs a deterministic tie rule at the output boundary.

## 15. Traceability Review

The intent → requirement → contract/invariant → test → implementation matrix is extensive. Most major behavior has at least one path through the chain. The primary broken links are:

- R-40 → T-28: no expected outcome for one branch;
- R-39 → T-13/T-17/T-19: no executable command contract;
- R-32/C-04 → cited tests: only a subset of keys is exercised;
- K-11 → T-02: only rejection is tested, not a conforming artifact;
- R-36/I-002 → evidence: parser failures are covered, resource exhaustion is not.

## 16. Internal-Consistency Review

The document is largely self-consistent after its prior review history, but the remaining conflicts are material. R-40 conflicts with E-03 and §3.1 for an unreadable history head; R-18's general push rule overlaps its no-push cases; I-003 conflicts with R-16; R-34 conflicts with the `VERSION` override; I-013 conflicts with selecting routes; and K-07 differs from §7.2 at the lower width boundary.

The two diagrams are captioned and correctly marked illustrative. Figure 3.1 needs the E-21 self-transition to match the normative table.

## 17. Architecture Review

The architecture supports the stated requirements: block parsing is cached, renderers have repair/fallback layers, window navigation state is per-window, durable data is divided between SQLite and `UserDefaults`, and an offscreen harness is the right verification boundary for native rendering.

The proposed `mdvCore` extraction is non-normative and reasonable. R-39 must prevent the harness from copying pipeline logic; otherwise the verifier could test behavior different from the application. Network loading needs an explicit policy boundary, not only a preference toggle.

## 18. Implementation-Agent Readiness

**NO — MATERIAL QUESTIONS REMAIN**

Minimum blocking questions:

1. What happens when the persisted history head is missing, unreadable, or invalid UTF-8 at launch?
2. Does a cold-start file argument create a back-stack snapshot for the automatically restored history head?
3. Do cross-file bookmark and placeholder jumps override the general different-file push rule?
4. What exact document-derived network data is permitted when remote images are enabled, including redirects and request metadata?
5. What bounded input/resource domain makes R-36 and I-002 implementable, and what fallback occurs on limit exhaustion?
6. Can `make dist VERSION=x.y.z` run on an untagged commit, or is exact-tag provenance mandatory for every `dist` artifact?
7. What are the exact `render-harness` commands, inputs, outputs, exit codes, comparison metric, and corpus discovery rules?

After those decisions, the MEDIUM findings can be resolved without architectural redesign.

## 19. Quality Scorecard

| Dimension | Score |
| --------- | ----: |
| Scope clarity | 5 |
| Terminology | 4 |
| Requirement precision | 3 |
| Interface completeness | 3 |
| Data-contract completeness | 3 |
| State/lifecycle definition | 2 |
| Algorithm precision | 3 |
| Failure semantics | 3 |
| Edge-case coverage | 4 |
| Non-functional requirements | 2 |
| Security specification | 2 |
| Observability/provenance | 4 |
| Testability | 3 |
| Evaluation/metrics | 3 |
| Traceability | 4 |
| Internal consistency | 2 |
| Architecture consistency | 4 |
| Implementation readiness | 2 |

Scale: 0 = absent; 1 = seriously deficient; 2 = weak; 3 = adequate; 4 = strong; 5 = implementation-grade.

## 20. Remediation Plan

### P0 — Blocking

1. **F-076:** define startup behavior for an unreadable persisted history head and align R-40, §3.1, E-03, Figure 3.1, and T-28.
2. **F-077:** decide the cold-start argument/back-stack outcome and turn T-28 into an assertion.
3. **F-078:** define bookmark/placeholder exceptions to R-18's general push rule.
4. **F-079:** reconcile I-003 with the remote-image network exception and state permitted request data.
5. **F-080:** bound untrusted resource consumption or narrow the universal no-crash guarantee.
6. **F-081:** make exact-tag release provenance unambiguous and add a positive artifact test.
7. **F-082:** specify the render harness and corpus as an executable verification contract.

### P1 — Important

1. **F-083:** align I-013 with “most recently added.”
2. **F-084:** use one raster-width formula, including the lower bound.
3. **F-085:** define empty in-document find behavior.
4. **F-086:** define path-plus-fragment navigation and percent-decoding.
5. **F-087:** define fingerprint Unicode normalization and truncation units.
6. **F-088:** add a stable FTS rank tie-breaker.
7. **F-089:** verify every C-04 preference and invalid stored value.
8. **F-090:** correct T-11 and state zoom tie rounding.
9. **F-091:** make the CPU criterion reproducible or non-normative.

### P2 — Improvement

1. **F-092:** synchronize Figure 3.1 with E-21.
2. **F-093:** normalize mathematical notation in normative rows and tests.

## 21. Final Verdict

Specification maturity:
Level 2

Implementation readiness:
NOT READY

Primary blocker:
Startup and navigation semantics still contain contradictory or deliberately unresolved state transitions.

Most important improvement:
Resolve the seven P0 decisions and convert their acceptance rows from observations into deterministic pass/fail assertions.
