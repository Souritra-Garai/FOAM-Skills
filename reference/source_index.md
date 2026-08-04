# OpenFOAM v14 source map

Install root: `/opt/openfoam14`. Confirm any path below still exists before
relying on it — the source tree changes between versions (v14 restructured
solvers significantly vs. older OpenFOAM releases: most physics now lives
under `applications/modules/`, run through the single `foamRun` binary,
rather than one binary per solver like `simpleFoam`/`interFoam` in older
versions).

## Top-level layout

| Path | Contents |
|---|---|
| `src/OpenFOAM` | Core library: fields, containers, meshes, primitives, dimensionedTypes, matrices, db (runtime selection, IOobject) |
| `src/finiteVolume` | FV discretization: `fvMesh`, `fvMatrices`, `fvPatchFields` (all boundary condition types live in `fields/fvPatchFields`), schemes |
| `src/meshTools` | Mesh manipulation utilities (searching, refinement helpers, mesh-to-mesh) |
| `src/fvModels` | Source terms / constraints applied within a region (`general`, `interRegion`, rotor/propeller disks) — this is v14's mechanism for things older versions called `fvOptions` |
| `src/fvConstraints` | Field constraints (bounding, limiting) applied during solve |
| `src/transportModels` — not present as a single dir in v14; see `physicalProperties`, `twoPhaseModels`, `multiphaseModels` | Transport/rheology properties |
| `src/MomentumTransportModels`, `ThermophysicalTransportModels` | Turbulence and thermal transport models (renamed from `turbulenceModels` in older versions) |
| `src/thermophysicalModels` | Equations of state, thermodynamics, transport properties for compressible/reacting flow |
| `src/lagrangian`, `Lagrangian` | Particle tracking / discrete-phase modeling |
| `src/sampling` | Sampling/probing utilities (function objects for post-processing) |
| `src/functionObjects` | Runtime function objects (field calculations, forces, monitoring) |
| `applications/solvers` | Legacy standalone solvers still shipped as separate binaries (`potentialFoam`, `chemFoam`, `boundaryFoam`) |
| `applications/modules` | Physics modules run via `foamRun -solver <module>`, e.g. `incompressibleFluid`, `compressibleVoF`, `multiphaseEuler`, `solid`, `fluid` |
| `applications/utilities` | Pre/post-processing utilities, organized into `mesh`, `preProcessing`, `postProcessing`, `surface`, `thermophysical`, `parallelProcessing` |
| `tutorials` | Example cases, organized to mirror `applications/modules` and `applications/solvers` names |

## Finding things in source

- **A boundary condition's implementation**: `find /opt/openfoam14/src/finiteVolume/fields/fvPatchFields -iname "*<name>*"`
- **A runtime-selectable type (fvModel, BC, turbulence model, etc.)**: search
  for its `addToRunTimeSelectionTable` registration —
  ```bash
  grep -rl "addToRunTimeSelectionTable.*<baseClass>.*<typeName>" /opt/openfoam14/src
  ```
- **Which module a solver keyword corresponds to**: `applications/modules/<name>`
  — check its `createFields.H`/`.C` for the physics it wires up, and match
  against `tutorials/<name>` for example case setups.
- **A class's header**: OpenFOAM classes are one class per file with a
  matching name — `find /opt/openfoam14/src -iname "<ClassName>.H"`.

## Notes / gotchas (add to as discovered)

- v14 merged most solver binaries into `foamRun`; don't assume a tutorial's
  historic solver name (e.g. `simpleFoam`) still exists as a binary — check
  `applications/modules` and the case's `controlDict` `application`/`solver` entry.
