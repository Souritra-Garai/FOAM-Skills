# fvModels: source terms and cellZone selection

Covers `fv::semiImplicitSource` and the v14 `cellZone`/zoneGenerator
mechanism used to target it. See `source_index.md` for where fvModels live
in the source tree generally.

## `semiImplicitSource`

`src/fvModels/general/semiImplicitSource`. Implements, per field:

```
S(x) = Su + Sp*x
```

added to the equation as `eqn += Su - fvm::SuSp(-Sp, psi)` (confirmed in
`semiImplicitSource.C`).

**Dimensions** (volumeMode `specific`):
- `Su` = `eqn.dimensions() / dimVolume` — e.g. m/s² for a U/momentum source.
- `Sp` = `Su.dimensions() / psi.dimensions()` — e.g. 1/s for U.
- `Sp` is always scalar, even for vector fields.

## Su-only vs. Sp-relaxation forcing

For a small/point-like oscillating source embedded in a background flow,
`Su` and `Sp` give qualitatively different behavior — which matters a lot
for picking the amplitude:

- **`implicit 0` + oscillating `explicit`** (pure `Su`, a body-force
  acceleration): the achieved velocity amplitude is **not** the number you
  type — it depends on how long fluid resides in the source cell relative
  to the forcing period. For a small cellZone (e.g. one cell, ~1 mm) in a
  fast crossflow (~10 m/s), residence time ~1e-4 s vs. a 0.02 s (50 Hz)
  period means the acceleration gets swept away almost instantly:
  quasi-steady estimate `ΔU ≈ amplitude * (cellLength / U)`. An amplitude
  of 150 m/s² in this regime gave only ~0.02 m/s — invisible against a
  10 m/s flow. (A naive "inertial oscillator" estimate `ΔU ≈ amplitude/omega`
  overshoots vs. reality here because it ignores convective sweep-out; for
  a localized source in fast crossflow, residence-time scaling is the right
  one to reach for first.)

- **Nonzero negative `implicit` (`Sp = -lambda`) + `explicit = lambda*target(t)`**
  (a relaxation/penalty source, `S(x) = lambda*(target(t) - x)`): relaxes
  the field toward an explicit time-varying *target* value, essentially
  independent of local convection, once `lambda` is chosen well above both
  `1/(residence time)` and `1/deltaT`. This gives direct, predictable
  control of the achieved oscillation amplitude — set `explicit` amplitude
  = `lambda * desired amplitude`, `implicit = -lambda`. Because `Sp` is
  negative, `fvm::SuSp` treats it implicitly (added to the matrix diagonal),
  so it stays unconditionally stable no matter how large `lambda` is
  (verified: `lambda=1e5` with target 10 m/s gave an actual ±8.5 m/s swing
  at the source cell, vs. ~0.02 m/s from the pure-`Su` version at a 20x
  smaller nominal amplitude).

**Takeaway**: for any small/point-like oscillating fvModel source embedded
in a background flow, use the relaxation form (both `Su` and `Sp`) rather
than `Su`-only if you need the resulting amplitude to be
predictable/comparable to a known velocity scale — `Su`-only forcing
requires guessing through the residence-time scaling and re-testing,
whereas `Sp`-relaxation lets you specify the target directly.

## cellZone selection (v14 zoneGenerator)

v14 fvModels select their `cellZone` via the `zoneGenerator` mechanism,
inline in the dict — this **replaces** `topoSet`. No separate
`topoSetDict` utility/file is needed or used in v14 for this.

Example, a point source:

```
cellZone { type containsPoints; points ((0.1 0 0)); }
```

(`src/meshTools/zoneGenerators/cell/containsPoints`). Other generators:
`box`, `sphere`, named lookup (`cellZone myZone;`), `all`, and boolean
combinators (`union`/`intersection`/`difference`).
