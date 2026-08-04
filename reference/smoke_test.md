# Smoke-testing OpenFOAM options

Goal: confirm a solver, scheme, boundary condition, or fvModel entry actually
works — without running the full case. Two variants below; pick based on
context.

## A. Full-pipeline smoke test (patch controlDict, run, restore)

Use when the thing to check only shows up once the solver actually executes
(e.g. a new fvModel, a boundary condition, a solver setting).

1. **Back up the case's `system/controlDict`** before touching it:
   ```bash
   cp system/controlDict system/controlDict.bak
   ```
2. **Patch for a short run.** Minimal edits needed:
   - `stopAt endTime;` with `endTime` set to `startTime + 2*deltaT` (2 steps),
     or `stopAt writeNow;` combined with a short `endTime` if adaptive
     timestep is in play.
   - `writeInterval 1;` (or equivalent) so output is written every step —
     otherwise a 2-step run may write nothing to inspect.
   - Leave `writeControl`, `deltaT`, and physics settings untouched — the
     point is to test the real settings, not a scaled-down version of them.
3. **Run the actual solver** (don't use a different/lighter solver than the
   real case uses):
   ```bash
   <solverName> -case <caseDir> > log.smoketest 2>&1
   ```
4. **Check the log**, not just the exit code:
   ```bash
   grep -Ei 'FOAM FATAL|error|nan|inf|diverg' log.smoketest
   tail -n 40 log.smoketest
   ```
   A clean exit with no FATAL/NaN and a written timestep directory is a pass.
5. **Restore the original controlDict** and remove smoke-test artifacts:
   ```bash
   mv system/controlDict.bak system/controlDict
   rm -rf <writtenTimeDirs> log.smoketest
   ```
   Never leave the case directory in the patched state — always restore
   before reporting results.

## B. Single dictionary entry check (no full run)

Use when only a specific entry needs validating — syntax, whether it parses,
whether a referenced model/BC name is recognized — and a full solve is
overkill.

- **Dictionary syntax/parse check** — most solvers and utilities parse and
  validate all case dictionaries on startup before the first iteration; a run
  that fails immediately with a clear `FOAM FATAL ERROR` pointing at the
  dictionary is enough signal — no need to let it iterate.
- **`foamDictionary` for targeted inspection/edits**:
  ```bash
  foamDictionary -entry <path.to.entry> -value system/fvSchemes
  ```
  Confirms the entry exists and shows its resolved value without running
  anything.
- **List available runtime-selectable options** (e.g. confirm a boundary
  condition or fvModel type name is registered) by searching the source
  rather than guessing:
  ```bash
  grep -rl "addToRunTimeSelectionTable" /opt/openfoam14/src | xargs grep -l "<typeName>"
  ```
  See `source_index.md` for where these tables typically live per module.
- If the entry can only be validated in context (e.g. a boundary condition
  needs a real field to attach to), fall back to variant A but scope the run
  to just enough steps for that entry's code path to execute.
