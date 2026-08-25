> **Note**: this file is a verbatim copy of `~/codeVault/notes/openfoam-amr.md`
> (an explicit exception to this skill's usual "pointer index, not a copy"
> convention — the source notes live outside this repo, so the content is
> duplicated here rather than referenced, to keep the skill self-contained).
> If the two ever diverge, treat `~/codeVault/notes/openfoam-amr.md` as
> authoritative and re-sync this copy.

# OpenFOAM 14 adaptive mesh refinement — working notes

Generic notes from wiring up `fvMeshTopoChangers::refiner` AMR on a real
solver case. Not tied to any one case — read this before adding AMR to
any OpenFOAM 14 case.

## Dictionary shape (`constant/dynamicMeshDict`)

```
topoChanger
{
    type            refiner;
    libs            ("libfvMeshTopoChangers.so");
    mover           none;           // required sibling key, even with no motion

    refineInterval  5;              // check every N timesteps
    nBufferLayers   2;               // grading between refinement levels
    maxCells        200000;          // hard cap
    dumpLevel       true;            // writes a `cellLevel` volScalarField

    // Single-field mode:
    field  T;  lowerRefineLevel 1000;  upperRefineLevel 5000;  maxRefinement 2;

    // OR multi-criterion mode (any number of named regions, OR-combined
    // into one refine set unless each gets its own `cellZone`):
    refinementRegions
    {
        flame  { field Qdot;     lowerRefineLevel 1e7; upperRefineLevel 1e15; maxRefinement 2; }
        strain { field magGradU; lowerRefineLevel 1e4; upperRefineLevel 1e15; maxRefinement 2; }
    }

    // Only needed for surfaceScalarFields (fluxes); silences a warning
    // and tells it how to fill values on new faces (`none` or `NaN`).
    correctFluxes ( (phi none) );
}
```

- `unrefineLevel`, mentioned in the class's own header doc-comment, is
  **dead** — not read anywhere in the source. Don't rely on it;
  unrefinement is purely topological (2:1 consistency + no surrounding
  cell still in the refine set).
- Region fields must already exist as registered fields when the
  topoChanger runs its check — i.e. computed by a function object, not
  something derived only at write time.

## The one that will actually bite you: 2D (`empty`-patch) meshes

`hexRef8` (what `refiner` is built on) has **zero awareness of
`empty`/2D geometry** — checked the source, no `geometricD` handling
anywhere. It always splits every hex 2×2×2, including through the
`empty` direction. A single-cell-thick `empty` layer becomes 2 cells
thick, which violates the fundamental invariant `empty` patches require
(exactly one layer, flat in that direction) → corrupted mesh → segfault
on the very first refinement, typically inside whatever face-field
mapping runs during the topology change (for a compressible solver:
`fvMeshTopoChangers::refiner::refineUfs`, dereferencing the face-momentum
field's boundary data on the now-broken patch).

**Fix**: replace the `empty` patch pair with a `cyclic` pair
(`type cyclic; neighbourPatch <other>;` on each side, same face lists).
This keeps the case physically 2D/periodic in the thin direction while
giving `hexRef8` a topology it knows how to refine. No BC file changes
needed if `#includeEtc "caseDicts/setConstraintTypes"` is used — it
resolves constraint types (`empty`/`cyclic`/`symmetry`/...) from the
actual patch type in `polyMesh/boundary`, not the patch name.

Cost tradeoff: refinement is isotropic, so any refined cell also gets
`2^maxRefinement` more cells through the thin direction, for no physical
benefit in a truly 2D problem. There's no dictionary knob to restrict
refinement to fewer directions.

Corroborating signal worth checking early: official OpenFOAM tutorials
for solvers that construct a face-momentum field (`rhoUf`, in the
`isothermalFluid`/`multicomponentFluid`/etc. module family) and that ship
a 2D case only ever enable `distributor` (parallel load balancing) in
their own `dynamicMeshDict`, never `topoChanger` — a hint the combination
wasn't validated for `empty`-patch meshes.

## Other config gaps that show up once refinement actually fires

- **`system/fvSolution` needs a `pcorr`/`pcorrFinal` solver entry.**
  Solvers with a `correctPhi`-style flux correction gate it on
  `mesh.topoChanging()`, not just `correctPhi`, so it silently activates
  the moment AMR is turned on and fails with `keyword pcorr is undefined`
  if missing. Copy the `p` solver settings, `relTol 0`.
- **Function objects feeding the refine criteria must run every
  timestep**, not just at write time (`executeControl timeStep
  executeInterval 1`) — the topoChanger reads the field before the next
  solve, not at end of run. Output write frequency (`writeControl`) can
  still stay sparse.

## How to validate before touching the real case

Don't trust source-reading alone for a mechanism this deep in the mesh
engine — reproduce empirically in a scratch copy first:

1. Force a **cheap, guaranteed** refinement trigger to isolate the
   topology-change mechanism from whether your physical thresholds are
   ever met: pick a field with a known uniform initial value and set
   `lowerRefineLevel`/`upperRefineLevel` to bracket it (e.g. `T`,
   bounds `-1`..`1e6`). This should mark ~every cell and refine the
   whole domain in one shot — the fastest way to hit the crash (or prove
   there isn't one) without waiting for real flow development.
2. Once that's crash-free, run a **short, partial-domain** case — pick
   thresholds that only capture *some* cells (e.g. near a boundary,
   where BC-driven gradients appear almost immediately). This exercises
   the harder code path (graded/partial refinement, buffering,
   unrefinement) that a full-domain test skips over.
3. `checkMesh -latestTime` after each: watch for `Mesh has 3 solution
   (non-empty) directions` truly meaning 3 (confirms cyclic conversion
   took), zero skewness/non-orthogonality growth, "Mesh OK."
4. `DebugSwitches { refiner 1; hexRef8 1; }` in `controlDict` turns on
   extra runtime consistency checks compiled into stock (non-Debug)
   builds — free extra validation, no rebuild needed.
5. Only port the config into the real case once steps 1–3 are clean.
   Real physical thresholds still need tuning against actual field
   statistics from a real run (`postProcess -dict <ad-hoc functions
   dict> -latestTime` with `volFieldValue`/`operation max|min`,
   `cellZone all;` — not `regionType all;`) — don't assume thresholds
   derived under one set of BCs/velocities transfer to a re-tuned case.

## `fvSchemes`/`fvSolution` need non-orthogonal-aware settings

`hexRef8` refinement interfaces (a coarse cell face bordering several finer
cell faces) are non-orthogonal even when the base mesh is a perfectly
regular hex block — cell centres either side of the interface don't line up
squarely. If `fvSchemes` was written assuming a clean structured mesh, it's
likely using the cheap orthogonal forms, and those silently drop the
non-orthogonal correction term everywhere AMR has actually refined:

```
laplacianSchemes { default  Gauss linear orthogonal; }   // wrong once AMR is on
snGradSchemes    { default  orthogonal; }                // wrong once AMR is on
```

**Fix**: switch both to `corrected` (confirmed against every stock
`refiner`-based AMR tutorial — `damBreak3D`, `floatingObject`,
`rotatingCube` — which all use `Gauss linear corrected` / `corrected`,
never `orthogonal`):

```
laplacianSchemes { default  Gauss linear corrected; }
snGradSchemes    { default  corrected; }
```

And in `fvSolution`, `nNonOrthogonalCorrectors` needs to be **≥1** once
AMR is on — the `corrected` scheme only *computes* a non-orthogonal
correction, the corrector loop is what actually converges it in per
timestep. (The stock tutorials above leave it at `0`, but they're gentle
VOF cases with `nBufferLayers 1`/`maxRefinement 1-2`; a case with sharper
gradients or `nBufferLayers 2`+ benefits from `1`.) `gradSchemes` and
`divSchemes` don't need changing — `Gauss linear` gradients and limited
div schemes (`limitedLinear`, `limitedLinearV`, etc.) are unaffected by
this and match what the tutorials use.

## Parallel AMR (`decomposePar` + `mpirun ... -parallel`) with cyclic patches

If the 2D `empty`-patch fix above (converting to a `cyclic` pair) was
applied, don't assume it also works decomposed. Tested on OpenFOAM 14: a
mesh with a `refiner` `topoChanger` **and** any `cyclic` patch pair fails
on the very first parallel timestep with

```
--> FOAM FATAL ERROR:
Problem. Cannot find (...) or ... in 4(...)
    From function Foam::label Foam::globalMeshData::findTransform(...)
    in file meshes/polyMesh/globalMeshData/globalMeshData.C
```

Confirmed independent of decomposition `method` (`scotch` and `simple`
both fail identically) and of `numberOfSubdomains` (fails at both 2 and
8) — this is `refiner`'s parallel `globalMeshData` transform-matching
failing to resolve the cyclic patch's translation once the mesh is split
across processors, not a decomposition config mistake. A **serial** run
(no `decomposePar`) with the exact same `cyclic`-patched, AMR-enabled
mesh runs fine; a **parallel** run with the same mesh but AMR
(`topoChanger`) removed also runs fine. It's specifically the
three-way combination (parallel + AMR + cyclic) that's broken. None of
the stock `refiner`-based tutorials (`damBreak3D`, `floatingObject`,
`rotatingCube`) use any `cyclic`/`empty` patch, which fits — this
combination looks untested upstream, not just unlucky.

**Practical takeaway**: if a 2D case needed the `empty`→`cyclic`
conversion to make AMR work at all, treat parallel AMR on that case as
broken until proven otherwise on the specific OpenFOAM version in use.
Options: run serial (fine for smaller meshes/`maxCells` caps), or drop
AMR when running in parallel, or wait for it to actually be needed and
re-test — don't assume `decomposePar` "just works" on top of an AMR case
that only became possible via a cyclic-patch workaround.

## Debugging tools that mattered

- No debug build / no `gdb` on this box → stack traces from OpenFOAM's
  own `sigSegv` handler only give function names, no line numbers.
  Source-reading + targeted empirical repro (above) substituted fine.
- `postProcess -dict <file> -latestTime` needs a real `FoamFile` header
  in the ad-hoc dict, and `volFieldValue` wants `cellZone all;` (not
  `regionType all;`) for a global extremum.
