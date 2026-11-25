#!/usr/bin/env python3
"""Copy the portable Agent Display skill into a local agent's skill directory."""
import argparse
import filecmp
from pathlib import Path
import shutil
import sys
import tempfile

SOURCE = Path(__file__).resolve().parents[1] / "skills/agent-display"


def same_tree(a, b):
    if not b.is_dir() or b.is_symlink():
        return False
    comparison = filecmp.dircmp(a, b, ignore=["__pycache__", ".DS_Store"])
    if comparison.left_only or comparison.right_only or comparison.common_funny:
        return False
    for name in comparison.common_files:
        if not filecmp.cmp(a / name, b / name, shallow=False):
            return False
    return all(same_tree(a / name, b / name) for name in comparison.common_dirs)


def install(parent):
    target = parent / "agent-display"
    if target.exists() or target.is_symlink():
        if same_tree(SOURCE, target):
            return f"Already installed: {target}"
        raise FileExistsError(f"{target} already exists and differs. Back up or rename that skill before installing this version; nothing was overwritten.")
    parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".agent-display-install-", dir=parent) as temp:
        staged = Path(temp) / "agent-display"
        shutil.copytree(SOURCE, staged, ignore=shutil.ignore_patterns("__pycache__", "*.pyc", ".DS_Store"))
        # A concurrent installation must not be replaced, including an empty directory.
        target.mkdir()
        try:
            for entry in staged.iterdir():
                entry.rename(target / entry.name)
        except BaseException:
            shutil.rmtree(target)
            raise
    return f"Installed: {target}"


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--agent", choices=["codex", "claude", "both"], default="both")
    parser.add_argument("--scope", choices=["user", "project"], default="user")
    parser.add_argument("--project", type=Path, default=Path.cwd(), help="Project root for --scope project")
    parser.add_argument("--skills-dir", type=Path, help="Install to another agent's skill directory instead")
    args = parser.parse_args(argv)
    root = Path.home() if args.scope == "user" else args.project.expanduser().resolve()
    if args.skills_dir:
        parents = [args.skills_dir.expanduser().resolve()]
    else:
        parents = []
        if args.agent in ["codex", "both"]:
            parents.append(root / ".agents/skills")
        if args.agent in ["claude", "both"]:
            parents.append(root / ".claude/skills")
    try:
        for parent in parents:
            print(install(parent))
    except OSError as exc:
        print(f"Installation stopped: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
