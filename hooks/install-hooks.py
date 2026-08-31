#!/usr/bin/env python3
"""Add or remove the Omarchy Pet hooks in Claude Code and Codex configs.

    install-hooks.py            add the hooks (idempotent)
    install-hooks.py --remove   remove exactly the hooks this script added

Both agents use the same hook schema (settings.json / hooks.json ->
{"hooks": {"<Event>": [{"matcher": ..., "hooks": [{"type": "command", ...}]}]}}).
Every entry this script writes carries "_omarchyPet": true so removal never
touches hooks that belong to other tools. A timestamped backup of each file is
written to ~/.local/state/config-backups/ before any change.
"""
import json, pathlib, shutil, sys, time

HOME = pathlib.Path.home()
STATE = HOME / ".local/bin/omarchy-pets-agent-state"   # absolute: hook shells may not have ~/.local/bin in PATH
TARGETS = {
    # file: (events -> (state argument, matcher or None))
    HOME / ".claude/settings.json": {
        "UserPromptSubmit": ("running", ""),
        "Stop": ("done", ""),
        "Notification": ("notify", ""),   # permission / idle prompts -> "waiting"
        "SessionEnd": ("idle", ""),
    },
    HOME / ".codex/hooks.json": {
        "UserPromptSubmit": ("running", None),
        "Stop": ("done", None),
    },
}
AGENT = {".claude": "claude", ".codex": "codex"}


def backup(path: pathlib.Path) -> None:
    dest = HOME / ".local/state/config-backups" / path.parent.name.lstrip(".")
    dest.mkdir(parents=True, exist_ok=True)
    shutil.copy2(path, dest / f"{path.name}.bak.{time.strftime('%Y%m%d-%H%M%S')}")


def load(path: pathlib.Path) -> dict:
    return json.loads(path.read_text()) if path.exists() else {}


def add(cfg: dict, event: str, cmd: str, matcher):
    groups = cfg.setdefault("hooks", {}).setdefault(event, [])
    for g in groups:
        for h in g.get("hooks", []):
            if h.get("_omarchyPet") and h.get("command") == cmd:
                return False
    group = {"hooks": [{"type": "command", "command": cmd, "timeout": 5, "_omarchyPet": True}]}
    if matcher is not None:
        group["matcher"] = matcher
    groups.append(group)
    return True


def remove(cfg: dict) -> int:
    """Drop every hook entry flagged _omarchyPet; prune empty groups and events."""
    n = 0
    for event in list(cfg.get("hooks", {}).keys()):
        kept = []
        for g in cfg["hooks"][event]:
            mine = [h for h in g.get("hooks", []) if h.get("_omarchyPet")]
            n += len(mine)
            g["hooks"] = [h for h in g.get("hooks", []) if not h.get("_omarchyPet")]
            if g["hooks"]:
                kept.append(g)
        if kept:
            cfg["hooks"][event] = kept
        else:
            del cfg["hooks"][event]
    return n


def main() -> None:
    removing = "--remove" in sys.argv
    for path, events in TARGETS.items():
        if not path.exists():
            print(f"skip {path} (not found)")
            continue
        cfg = load(path)
        agent = AGENT[path.parent.name]
        before = json.dumps(cfg, sort_keys=True)
        if removing:
            remove(cfg)
        else:
            for event, (state, matcher) in events.items():
                add(cfg, event, f"{STATE} {agent} {state}", matcher)
        if json.dumps(cfg, sort_keys=True) != before:
            backup(path)
            path.write_text(json.dumps(cfg, indent=2) + "\n")
            print(f"{'removed from' if removing else 'updated'} {path}")
        else:
            print(f"unchanged {path}")


if __name__ == "__main__":
    main()
