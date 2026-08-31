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

## 2026-08-26 — heat flux through a non-`wall` patch, via a `coded` functionObject

- **`wallHeatFlux` (builtin functionObject) only works on `wall`-type
  patches** — its `read()` explicitly filters `patchSet_` down to
  `isA<wallPolyPatch>` and warns/skips anything else
  (`src/functionObjects/field/wallHeatFlux/wallHeatFlux.C`). No dict option
  to disable this. If the boundary you want conductive heat flux through is
  a plain `patch` (e.g. an inlet/outlet with real mass throughflow, so
  relabeling it `wall` would be physically misleading), `wallHeatFlux` is a
  dead end regardless of dict settings.
- **Fix: `thermophysicalTransportModel::q(patchi)`** (the exact field
  `wallHeatFlux` itself uses internally) works on *any* patch index — the
  wall restriction is purely `wallHeatFlux`'s own application-level filter,
  not a property of the underlying field. Returns `[W/m^2]`, **positive =
  flux out of the domain** along the outward face normal (confirmed from
  `unityLewisFourier::q() = -alphaEff*snGrad(he)`: a colder boundary than
  the interior gives positive/outward q). Sum `q(patchi) * mesh.boundary()
  [patchi].magSf()` over the patch for total heat flow in Watts. Object is
  registered under the plain name `"thermophysicalTransport"`
  (`thermophysicalTransportModel::typeName`, looked up via
  `mesh.lookupObject<thermophysicalTransportModel>("thermophysicalTransport")`
  for a single-phase/no-group case).
- **Wrote this as a `type coded;` functionObject** (`libs
  ("libutilityFunctionObjects.so");`, `codeInclude`/`codeOptions`/`codeLibs`/
  `codeExecute` blocks — same dynamicCode compile pipeline as the `#calc`
  expressions already used elsewhere in dictionaries) rather than a real
  compiled functionObject class, since it only needed ~20 lines. Full
  working example: `JiCF-BC/counterFlowFlame2D/system/functions`
  (`heatFluxPorts`).
- **Three API mismatches hit while smoke-testing it** (this install's
  `fvMesh`/`polyBoundaryMesh`/`Time` API differs from what `wallHeatFlux.C`'s
  own source patterns would suggest — each caused a real compile error,
  caught via the smoke-test protocol, not guessed):
  - `mesh.poly().boundary()`, **not** `mesh.boundaryMesh()` (`fvMesh` has no
    `boundaryMesh()` member in this version — `wallHeatFlux.C` itself uses
    `mesh_.poly().boundary()`, worth pattern-matching from source instead of
    assuming the more commonly-documented older API).
  - `polyBoundaryMesh::findIndex(name)`, **not** `.findPatchID(name)` (the
    latter doesn't exist on this class here).
  - `Time::timeName()` takes a **required** `scalar` argument in this
    version (`static word timeName(const scalar, int precision = ...)`) —
    there is no bare no-arg instance overload; call it as
    `mesh.time().timeName(mesh.time().value())`.
  - Link step separately needs `-lthermophysicalTransportModel` (**singular**
    — the abstract interface library) in `codeLibs`, not a model-specific
    plural one (`-lthermophysicalTransportModels` doesn't exist as a real
    `.so`; the concrete per-formulation libraries are named things like
    `libfluidMulticomponentThermophysicalTransportModels.so`, none of which
    are needed just to call virtual interface methods on an already-
    constructed model instance).
- Related, not yet used: OpenFOAM ships a standalone adiabatic-flame-
  temperature utility (`applications/utilities/thermophysical/
  adiabaticFlameT/`, see the 2026-08-18 entry above) — worth trying instead
  of a from-scratch Python JANAF calculation next time that specific number
  is needed, though the Python route (independent of the OpenFOAM build/
  install, easy to adapt for a non-standard preheat/composition) worked fine
  here too.

## 2026-08-26 — "finished" vs "converged": `residualControl` on a refined flame mesh

From tuning `JiCF-BC/counterFlowFlame2D` (infinitely-fast-chemistry opposed-jet
flame). All three points generalise to any PIMPLE run whose steady state is a
sharp, mesh-resolved feature.

- **Refining the mesh can break `residualControl`'s auto-stop, not just slow
  it.** A reaction sheet resolved onto ~1 cell "flickers" between cells each
  timestep, so `U`/`T` residuals settle into a bounded noise floor (~0.05–0.4
  here) and never decay to a tight tolerance. The run is physically converged
  (position/temperature stationary) but the residual criterion never fires.
- **Loosening the residual tolerance to compensate is the wrong fix** — the
  same loosened threshold is also satisfied trivially by an early,
  still-undeveloped timestep (PIMPLE's outer-corrector residual collapses
  several orders of magnitude by iteration ~3 in *every* timestep, including
  the initial-condition ones). Observed a "converged" false-positive after 9
  timesteps at `t=2.5e-5 s`. No single scalar threshold separates "really
  done" from "hasn't started" once the genuine noise floor overlaps what the
  pre-ignition transient hits.
- **Working pattern:** keep the tight `residualControl` (it never
  false-positives — it just may never fire), and add a fixed `endTime`
  backstop sized from where a *physical* observable actually stops moving
  (flame position from a sampled centreline, `Qdot` peak location), not from a
  residual. Then check which criterion actually stopped the run — grep the log
  for the solver's own `"PIMPLE solution converged"` banner; absent ⇒ it hit
  `endTime`, which is a valid stop but a different claim. A finished run and a
  converged run are not the same thing on a refined mesh.
- Aside (case-setup, less general): on a graded blockMesh the Courant-limiting
  cells for a counterflow flame sit **at the flame**, not the ports —
  thermal-expansion-accelerated gas there can exceed both cold inlet speeds —
  so grade the fine band onto the (measured) stagnation-plane/flame region,
  not the ports.
