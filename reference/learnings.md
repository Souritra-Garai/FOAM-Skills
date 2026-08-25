# Learnings scratch pad

Low-friction dump for anything discovered mid-session that's worth keeping —
a gotcha, a working pattern, a class/file location, something that turned out
wrong in another reference file. Append here first; don't stop to figure out
which module doc it "really" belongs in.

Periodically (not every session) review this file and fold entries into the
right place in `smoke_test.md` / `source_index.md` / `case_setup.md`, then
delete them from here. An entry sitting here for a while isn't a problem.

Format: one entry per finding, dated, terse.

---

<!-- Example:
## 2026-08-04
Boundary condition `fixedFluxPressure` requires a companion velocity BC that
sets a flux-consistent value — using plain `zeroGradient` for U alongside it
silently gives wrong pressure at inflow/outflow patches in incompressible
solvers. Caught during pitzDaily smoke test.
-->

## 2026-08-06
User's (Souritra's) house dictionary formatting style, observed across
`JiCF-BC/counterFlowFlame2D`. Worth matching when hand-writing or
programmatically patching a case for them — they're precise about it:
- **Tabs, not spaces**, everywhere, including between a key and its value —
  not space-aligned columns. Standard OpenFOAM header banner
  (`/*---...---*\` + version comment block) kept verbatim on every file.
- One entry per line, **blank line between every top-level entry/sub-block**
  (`dim {...}` then blank then `num {...}` then blank then
  `factor_velocity ...;`, etc.) — dictionaries read as loosely spaced
  paragraphs, not packed.
- Inline comments are a tab after the `;`, used specifically to name a unit
  or explain a non-obvious derived value (`factor_nozzle 14.58; // Nozzle
  area ratio: inlet / outlet`), not for restating the obvious.
- File always ends with exactly **two blank lines then the closing banner**
  (`// ****...**** //`) — consistent even in short macro files with no
  content-relevant reason for the gap.
- `system/controlDict` additionally uses mid-file
  `// * * * ... * * * //` divider comments to group related entries
  (solver choice / time control / write control) — a heavier-weight
  separator reserved for logically distinct groups within one file, not used
  in every file.

## 2026-08-06
Macro modularization pattern (`JiCF-BC/counterFlowFlame2D/macros/`): exactly
three small dicts, split by *what kind of thing you're changing* rather than
by which OpenFOAM file consumes them — `inletConditions` (physics: nozzle +
crossflow streams, pressure), `box` (mesh geometry `dim`/`num` + velocity
scale factors), `tolerances` (`linear_solver`/`convergence`). Every other
file in `0/`/`system/`/`constant/` references these via
`${${FOAM_CASE}/macros/<file>!<key>}` (nested keys via `!parent/child`, e.g.
`!nozzle/V`) instead of being hand-edited, so one macro edit propagates
everywhere it's used. `#calc "..."` wraps any arithmetic combination of two
macro refs (negation, `0.5 * dim/y`, multiplying two factors together) since
`${...}` substitution alone is textual, not arithmetic. Good pattern to
reach for whenever a case needs the same handful of parameters exposed
cleanly to outside tooling (a notebook, a sweep driver) without the tooling
touching `0/`/`system/`/`constant/` directly — keeps the diff of a
parameter sweep to just the 3 macro files.

Companion Python-side technique making this durable under repeated
programmatic edits (`JiCF-BC/modules/FOAM_Dictionary.py`): a macro file is
only fully re-serialized (`formatDictionary`) the first time it's created;
every subsequent write locates just the changed value's byte span
(`tokenizeWithSpans`/`parseTokenSpans`) and patches that span in place
(`patchText`), leaving every comment/blank-line/alignment choice above
untouched. Worth reaching for this span-patch approach over
read-dict/mutate/re-serialize-whole-file whenever a user cares about hand
formatting surviving automated edits.

## 2026-08-18 — thermophysicalModels / JANAF / mixture rules

- **General JANAF database ships in `etc/`**, not just per-tutorial: raw
  Chemkin `THERMO ALL` format at `etc/thermoData/therm.dat` (Burcat/Goos/
  Ruscic database, ~2355 species), pre-converted to OpenFOAM dict syntax at
  `etc/thermoData/thermoData`. Thermo (Cp/h) only — **no transport data**;
  there is no general Sutherland `As`/`Ts` database anywhere in the install.

- **`chemkinToFoam`'s "transport file" arg is not a real Chemkin `trans.dat`**
  (Lennard-Jones σ/ε) — it's already an OpenFOAM-format dict of per-species
  `transport{As;Ts;}` (or a wildcard `".*"` fallback), consumed via
  `transportDict_.subDict(name)` in `chemkinReader/chemkinLexer.L`. It does
  not compute Sutherland coefficients from kinetic theory. Corollary: several
  shipped GRI-Mech-based tutorials (e.g. `counterFlowFlame2D_GRI`) end up with
  **identical `As`/`Ts` across all species** because they relied on the
  wildcard default rather than per-species values — don't assume a tutorial's
  transport numbers are physically distinct just because they're present.

- **Dict `mixture` keyword ≠ C++ class name, for one specific pair**: the dict
  keyword `multicomponentMixture` selects C++ class
  `coefficientMulticomponentMixture` — its `typeName()` deliberately returns
  `"multicomponentMixture<...>"` instead of its own class name
  (`coefficientMulticomponentMixture.H:92-95`). Grepping source for a dict
  keyword you saw in a case won't always find the implementing class by name;
  check `typeName()` overrides too. `coefficientWilkeMulticomponentMixture`
  does *not* have this quirk — its `typeName()` matches its class name.

- **Two multicomponent mixture classes give genuinely different numbers**,
  both under `src/thermophysicalModels/multicomponentThermo/mixtures/`:
  - `coefficientMulticomponentMixture` (dict: `multicomponentMixture`) mixes
    `As`/`Ts` by mass fraction first (`sutherlandTransportI.H` operator`+=`),
    then evaluates `mu(T)` once — *not* the same as mass-fraction-averaging
    each species' evaluated `mu_k(T)`, since `mu(T)` is nonlinear in `Ts`.
    Verified numerically (N2/H2O, Y=0.7/0.3): diverges from the naive
    per-species average by up to ~38% in mu, ~25% in kappa, at 300 K.
  - `coefficientWilkeMulticomponentMixture` (dict:
    `coefficientWilkeMulticomponentMixture`, the newer/default choice in
    current tutorials e.g. `counterFlowFlame2D`) does real mole-fraction
    Wilke's-rule (1950) weighting of each species' own evaluated `mu_k(T)`,
    then reuses the same Wilke weights (not a separate rule) to weight each
    species' own Eucken `kappa_k(T)` — O(N²) per state vs O(N) for the above.
  - Thermo (Cp/h) mixing is mass-fraction-additive in **both** classes; only
    the transport-property mixing differs.

- **Standalone mesh-free thermo utilities are a real, working pattern**:
  `applications/test/thermoMixture/` and
  `applications/utilities/thermophysical/adiabaticFlameT/` build with just
  `EXE_INC = -I$(LIB_SRC)/thermophysicalModels/specie/lnInclude` and
  `EXE_LIBS = -lspecie`, no `fvMesh`/`Time`/case — just `argList`+`IFstream`+
  `dictionary`. `janafThermo.C`/`sutherlandTransport.C` aren't in
  `specie/Make/files` — they're template-only (`NoRepository` pattern,
  compiled into the consumer's translation unit), so `-lspecie` alone
  suffices even when instantiating those templates yourself.

- **OF14 dict filename is `physicalProperties`**, not `thermophysicalProperties`
  (older-version convention) — confirmed in both a v14 tutorial and a v12-era
  case still running fine under v14, so the case-level format is stable
  across this rename.
