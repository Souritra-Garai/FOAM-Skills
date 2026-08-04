#!/usr/bin/env bash
# Grants Claude Code no-prompt permissions for OpenFOAM work, on any machine:
#   - read-only (Read/Grep/Glob + common read Bash) on the OpenFOAM install dir
#   - full read/write (Read/Grep/Glob/Edit/Write + Bash) on the skill dir and
#     the OpenFOAM user run directory
#
# Merges into ~/.claude/settings.json (user-level, cross-project) without
# touching any other keys already in that file. Safe to re-run — rules are
# de-duplicated.
#
# Also symlinks the skill dir into ~/.claude/skills/openfoam-v14 so Claude
# Code actually discovers and loads it — permissions alone don't do that.
#
# Usage:
#   setup-permissions.sh <openfoam_install_dir> <skill_dir> <run_dir>
#
# Example:
#   ./setup-permissions.sh /opt/openfoam14 \
#       "$HOME/Documents/CodeVault/openfoam-skill" \
#       "$HOME/OpenFOAM/$(whoami)-14"

set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "Usage: $0 <openfoam_install_dir> <skill_dir> <run_dir>" >&2
  exit 1
fi

OPENFOAM_DIR=$(realpath -m "$1")
SKILL_DIR=$(realpath -m "$2")
RUN_DIR=$(realpath -m "$3")

for d in "$OPENFOAM_DIR" "$SKILL_DIR" "$RUN_DIR"; do
  if [ ! -d "$d" ]; then
    echo "Warning: $d does not exist yet — adding rules anyway." >&2
  fi
done

if ! command -v python3 >/dev/null 2>&1; then
  echo "Error: python3 is required for safe JSON merging but was not found." >&2
  exit 1
fi

SKILLS_DIR="$HOME/.claude/skills"
SKILL_LINK="$SKILLS_DIR/openfoam-v14"
mkdir -p "$SKILLS_DIR"
if [ -L "$SKILL_LINK" ]; then
  # Already a symlink — repoint it if it's stale, otherwise leave it.
  if [ "$(readlink "$SKILL_LINK")" != "$SKILL_DIR" ]; then
    ln -sfn "$SKILL_DIR" "$SKILL_LINK"
    echo "Repointed existing symlink $SKILL_LINK -> $SKILL_DIR"
  fi
elif [ -e "$SKILL_LINK" ]; then
  echo "Warning: $SKILL_LINK already exists and is not a symlink — leaving it untouched." >&2
  echo "         Claude Code may not be loading the skill from $SKILL_DIR." >&2
else
  ln -s "$SKILL_DIR" "$SKILL_LINK"
  echo "Linked $SKILL_LINK -> $SKILL_DIR"
fi

SETTINGS_FILE="$HOME/.claude/settings.json"
mkdir -p "$(dirname "$SETTINGS_FILE")"

python3 - "$SETTINGS_FILE" "$OPENFOAM_DIR" "$SKILL_DIR" "$RUN_DIR" <<'PYEOF'
import json
import sys
import os

settings_file, openfoam_dir, skill_dir, run_dir = sys.argv[1:5]

if os.path.exists(settings_file):
    with open(settings_file) as f:
        content = f.read().strip()
        settings = json.loads(content) if content else {}
else:
    settings = {}

perms = settings.setdefault("permissions", {})
allow = perms.setdefault("allow", [])
add_dirs = perms.setdefault("additionalDirectories", [])

def add_unique(lst, items):
    for item in items:
        if item not in lst:
            lst.append(item)

# Read-only rules for the OpenFOAM install directory
readonly_rules = [
    f"Read(//{openfoam_dir.lstrip('/')}/**)",
    f"Grep(//{openfoam_dir.lstrip('/')}/**)",
    f"Glob(//{openfoam_dir.lstrip('/')}/**)",
    f"Bash(cat {openfoam_dir}/*)",
    f"Bash(ls {openfoam_dir}/*)",
    f"Bash(ls -la {openfoam_dir}/*)",
    f"Bash(find {openfoam_dir}*)",
    f"Bash(head {openfoam_dir}/*)",
    f"Bash(tail {openfoam_dir}/*)",
    f"Bash(wc {openfoam_dir}/*)",
    f"Bash(file {openfoam_dir}/*)",
    f"Bash(grep -r * {openfoam_dir}*)",
    f"Bash(grep -rl * {openfoam_dir}*)",
    f"Bash(grep -rn * {openfoam_dir}*)",
]

# Full read/write rules for a working directory (skill dir, run dir)
def readwrite_rules(path):
    p = path.lstrip('/')
    return [
        f"Read(//{p}/**)",
        f"Grep(//{p}/**)",
        f"Glob(//{p}/**)",
        f"Edit(//{p}/**)",
        f"Write(//{p}/**)",
        f"Bash(cd {path} && *)",
    ]

add_unique(allow, readonly_rules)
add_unique(allow, readwrite_rules(skill_dir))
add_unique(allow, readwrite_rules(run_dir))
add_unique(add_dirs, [openfoam_dir, skill_dir, run_dir])

with open(settings_file, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")

print(f"Updated {settings_file}")
print(f"  read-only:  {openfoam_dir}")
print(f"  read/write: {skill_dir}")
print(f"  read/write: {run_dir}")
PYEOF
