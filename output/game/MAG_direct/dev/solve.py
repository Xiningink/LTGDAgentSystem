"""Reference solver for Puzzle Magnet Lab.

Mirrors the GDScript simulation rules exactly and BFS-searches the shortest
solution for every level so the shipped level data can be trusted (and so we
can bake accurate par values).

Usage:
    python solve.py path/to/levels.json [--verbose]
"""

from __future__ import annotations

import json
import sys
from collections import deque
from itertools import product

DIRS = {
    "U": (0, -1),
    "D": (0, 1),
    "L": (-1, 0),
    "R": (1, 0),
}
DIR_ORDER = ["U", "D", "L", "R"]

WALL = "#"
VOID = "~"
HAZARD = "x"
EXIT = "E"
SWITCH = "*"


def parse_level(level):
    rows = level["map"]
    height = len(rows)
    width = max(len(r) for r in rows)
    tiles = {}
    items = {}  # (x, y) -> (kind, pol)
    player = None
    polarity = level.get("player_polarity", "N")
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            tiles[(x, y)] = ch
            if ch == "@":
                player = (x, y)
                tiles[(x, y)] = "."
            elif ch == "C":
                items[(x, y)] = ("metal", "")
                tiles[(x, y)] = "."
            elif ch == "R":
                items[(x, y)] = ("magnet", "N")
                tiles[(x, y)] = "."
            elif ch == "B":
                items[(x, y)] = ("magnet", "S")
                tiles[(x, y)] = "."
    return {
        "width": width,
        "height": height,
        "tiles": tiles,
        "items": items,
        "player": player,
        "polarity": polarity,
    }


def gate_letters(tiles):
    return {ch for ch in tiles.values() if ch.isupper() and ch in "ABCD"}


def plate_letters(tiles):
    return {ch for ch in tiles.values() if ch.islower() and ch in "abcd"}


def compute_gates(tiles, items, player, inert):
    opened = {}
    for gate in gate_letters(tiles):
        plate = gate.lower()
        plates = [p for p, ch in tiles.items() if ch == plate]
        opened[gate] = bool(plates) and all(
            (p == player or p in items) for p in plates
        )
    return opened


def in_bounds(tiles, pos):
    return pos in tiles


def player_can_enter(tiles, gates, inert, pos):
    if pos not in tiles:
        return False
    ch = tiles[pos]
    if ch in (WALL, VOID):
        return False
    if ch in "ABCD" and not gates.get(ch, False):
        return False
    if ch == HAZARD and pos not in inert:
        return False
    return True


def object_can_enter(tiles, gates, inert, pos):
    """Returns 'move', 'destroy' or None for an object entering pos."""
    if pos not in tiles:
        return None
    ch = tiles[pos]
    if ch in (WALL, VOID):
        return None
    if ch in "ABCD" and not gates.get(ch, False):
        return None
    if ch == EXIT:
        return None
    if ch == HAZARD and pos not in inert:
        return "destroy"
    return "move"


def chain_continue(cur_kind, other):
    if other is None:
        return "free"
    if cur_kind[0] == "metal":
        return "continue" if other[0] == "metal" else "block"
    # cur is a magnet being repelled by the field
    if other[0] == "metal":
        return "continue"
    return "continue" if other[1] == cur_kind[1] else "block"


def resolve_push(tiles, gates, inert, Items, start, direction):
    """Push the object at `start` one tile along direction.

    Returns (moves, destroys) where moves is a list of (src, dst) pairs for the
    objects that shift, and destroys is a list of (pos, kind) for objects that
    fall into an active hazard. Returns None when the push is impossible.
    """
    dx, dy = direction
    moves = []
    destroys = []
    pos = start
    kind = Items[pos]
    while True:
        nxt = (pos[0] + dx, pos[1] + dy)
        other = Items.get(nxt)
        entry = object_can_enter(tiles, gates, inert, nxt)
        if entry is None:
            return None
        if entry == "destroy":
            destroys.append((pos, nxt, kind))
            break
        if other is None:
            moves.append((pos, nxt))
            break
        verdict = chain_continue(kind, other)
        if verdict == "block":
            return None
        moves.append((pos, nxt))
        pos = nxt
        kind = other
    return moves, destroys


def step(state, direction):
    tiles = state["tiles"]
    dx, dy = direction
    player = state["player"]
    polarity = state["polarity"]
    items = dict(state["items"])
    inert = set(state["inert"])

    gates = compute_gates(tiles, items, player, inert)
    target = (player[0] + dx, player[1] + dy)
    if not player_can_enter(tiles, gates, inert, target):
        return None

    occupant = items.get(target)
    if occupant is not None:
        if occupant[0] == "magnet" and occupant[1] != polarity:
            # Opposite polarity: player and magnet exchange places.
            del items[target]
            items[player] = occupant
        else:
            # Same polarity magnet or metal crate: shove the object ahead.
            result = resolve_push(tiles, gates, inert, items, target, direction)
            if result is None:
                return None
            moves, destroys = result
            moving = [(dst, items[src]) for src, dst in moves]
            for src, _dst in moves:
                items.pop(src, None)
            for dst, item in moving:
                items[dst] = item
            for pos, dest, kind in destroys:
                if pos in items and items[pos] == kind:
                    del items[pos]
                if kind[0] == "metal":
                    inert.add(dest)

    new_state = {
        "tiles": tiles,
        "player": target,
        "polarity": "S" if tiles.get(target) == SWITCH and polarity == "N" else (
            "N" if tiles.get(target) == SWITCH and polarity == "S" else polarity
        ),
        "items": items,
        "inert": inert,
    }
    return new_state


def key(state):
    items = tuple(sorted((x, y, k, p) for (x, y), (k, p) in state["items"].items()))
    return (state["player"], state["polarity"], items, tuple(sorted(state["inert"])))


def solve(level, max_states=400000):
    parsed = parse_level(level)
    state = {
        "tiles": parsed["tiles"],
        "player": parsed["player"],
        "polarity": parsed["polarity"],
        "items": parsed["items"],
        "inert": set(),
    }
    if state["player"] is None:
        return None, 0

    start_key = key(state)
    seen = {start_key}
    queue = deque([(state, "")])
    explored = 0
    while queue:
        cur, path = queue.popleft()
        explored += 1
        if explored > max_states:
            return None, explored
        if cur["tiles"].get(cur["player"]) == EXIT:
            return path, explored
        for name in DIR_ORDER:
            nxt = step(cur, DIRS[name])
            if nxt is None:
                continue
            k = key(nxt)
            if k in seen:
                continue
            seen.add(k)
            queue.append((nxt, path + name))

    return None, explored


def render(state):
    lines = []
    for y in range(state.get("height", 0)):
        pass
    return lines


def main():
    if len(sys.argv) < 2:
        print("usage: solve.py <levels.json>")
        return 1
    with open(sys.argv[1], "r", encoding="utf-8") as fh:
        data = json.load(fh)

    failures = []
    for level in data["levels"]:
        solution, explored = solve(level)
        name = level.get("name", level.get("id", "?"))
        if solution is None:
            failures.append(level.get("id", name))
            print(f"[FAIL] {level['id']:>4} {name:<22} unsolvable (explored {explored})")
        else:
            print(
                f"[ ok ] {level['id']:>4} {name:<22} par {len(solution):>3}  "
                f"(states {explored:>6})  {solution}"
            )
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
