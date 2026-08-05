# openfoam-v14 — a Claude Code skill

A [Claude Code Skill](https://docs.claude.com/en/docs/claude-code/skills) for
working with an OpenFOAM v14 installation: setting up cases, smoke-testing
options before a full run, navigating the source tree, and building up
fvModel/case-setup knowledge over time instead of losing it at the end of
each chat.

It's a **pointer index, not a copy** of OpenFOAM's docs or source — `SKILL.md`
stays small and loads first; the `reference/*.md` files load only when a task
actually needs them, and always point back at the real source under the
OpenFOAM install rather than re-explaining it.

## Contents

| Path | Purpose |
|---|---|
| `SKILL.md` | The skill itself — trigger description + index, read by Claude Code |
| `reference/smoke_test.md` | Run 1–2 timesteps to sanity-check settings before a full run |
| `reference/source_index.md` | Map of the OpenFOAM v14 source tree (`src/`, `applications/`) |
| `reference/case_setup.md` | Case directory structure (`0/`, `constant/`, `system/`) |
| `reference/fv_models.md` | fvModel source terms (`semiImplicitSource`), `cellZone`/zoneGenerator |
| `reference/learnings.md` | Scratch pad — mid-session findings not yet triaged into a proper doc |
| `scripts/setup-permissions.sh` | One-shot setup for a new machine (see below) |

## Setup on a machine

Requires an OpenFOAM v14 install and `python3`.

```bash
git clone https://github.com/Souritra-Garai/FOAM-Skills.git openfoam-skill
cd openfoam-skill
./scripts/setup-permissions.sh \
  /opt/openfoam14 \                        # OpenFOAM install dir
  "$(pwd)" \                                # this skill dir
  "$HOME/OpenFOAM/$(whoami)-14"             # OpenFOAM user run directory
```

This does two things, and is safe to re-run:

1. **Symlinks the skill into `~/.claude/skills/openfoam-v14`** so Claude Code
   actually discovers and loads it — cloning the repo alone doesn't do this.
2. **Merges no-prompt permissions into `~/.claude/settings.json`**: read-only
   `Read`/`Grep`/`Glob` + common read-only `Bash` on the OpenFOAM install dir,
   and full `Read`/`Grep`/`Glob`/`Edit`/`Write`/`Bash` on the skill dir and the
   run dir. It merges rather than overwrites — any other settings you already
   have are left untouched.

Works the same way whether you're driving Claude Code from a terminal or from
an editor that runs Claude Code as its agent backend (e.g. Zed's Agent Panel
via the ACP registry).

## Keeping it up to date

Mid-session, propose new findings into `reference/learnings.md` rather than
letting them evaporate at the end of the chat. Periodically triage that file:
fold small notes into the relevant existing reference doc, or — if an entry
is substantial and self-contained — give it its own reference file (see
`fv_models.md` for an example) and list it in `SKILL.md`.

Since this is a normal git repo, running `setup-permissions.sh` (or just a
plain `git pull`) on another machine picks up everything learned elsewhere.
