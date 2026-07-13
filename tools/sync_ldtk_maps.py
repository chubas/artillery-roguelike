#!/usr/bin/env python3
"""Convert LDtk simplified CSV exports to Artillery Space ASCII maps."""

from __future__ import annotations

import argparse
import csv
import json
import os
import re
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


SOURCE_ENV = "LDTK_SIMPLIFIED_DIR"
REQUIRED_FILES = ("data.json", "Terrain.csv", "SpawnZones.csv")
VALID_MAP_CHARS = frozenset(".M0123456789")
VALID_SPAWN_VALUES = frozenset(range(5))
PLAYER_VALUES = (1, 2)
ENEMY_VALUES = (3, 4)
ID_PATTERN = re.compile(r"^[A-Za-z0-9_-]+$")


class MapSyncError(ValueError):
    """An input or configuration error that should be shown to the user."""


@dataclass(frozen=True)
class ConvertedMap:
    map_id: str
    text: str
    width: int
    height: int


def load_terrain_mapping(path: Path) -> dict[int, str]:
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except OSError as error:
        raise MapSyncError(f"cannot read config {path}: {error}") from error
    except json.JSONDecodeError as error:
        raise MapSyncError(f"invalid JSON in config {path}: {error}") from error

    raw_mapping = document.get("terrain_values")
    if not isinstance(raw_mapping, dict) or not raw_mapping:
        raise MapSyncError("config must contain a non-empty 'terrain_values' object")

    mapping: dict[int, str] = {}
    for raw_value, character in raw_mapping.items():
        try:
            value = int(raw_value)
        except (TypeError, ValueError) as error:
            raise MapSyncError(
                f"terrain mapping key {raw_value!r} is not an integer"
            ) from error
        if value < 0:
            raise MapSyncError(f"terrain mapping key {value} cannot be negative")
        if not isinstance(character, str) or character not in VALID_MAP_CHARS:
            raise MapSyncError(
                f"terrain value {value} must map to one of "
                f"{''.join(sorted(VALID_MAP_CHARS))!r}"
            )
        mapping[value] = character

    if mapping.get(0) != ".":
        raise MapSyncError("terrain value 0 must map to '.' because LDtk uses it as empty")
    return mapping


def read_csv_grid(path: Path) -> list[list[int]]:
    try:
        with path.open(newline="", encoding="utf-8-sig") as csv_file:
            raw_rows = list(csv.reader(csv_file))
    except OSError as error:
        raise MapSyncError(f"cannot read {path.name}: {error}") from error

    if not raw_rows:
        raise MapSyncError(f"{path.name} is empty")

    grid: list[list[int]] = []
    expected_width: int | None = None
    for row_number, raw_row in enumerate(raw_rows, start=1):
        while raw_row and raw_row[-1].strip() == "":
            raw_row.pop()
        if not raw_row:
            raise MapSyncError(f"{path.name} row {row_number} is empty")

        row: list[int] = []
        for column_number, raw_cell in enumerate(raw_row, start=1):
            cell = raw_cell.strip()
            if cell == "":
                raise MapSyncError(
                    f"{path.name} row {row_number}, column {column_number} is empty"
                )
            try:
                row.append(int(cell))
            except ValueError as error:
                raise MapSyncError(
                    f"{path.name} row {row_number}, column {column_number} "
                    f"is not an integer: {cell!r}"
                ) from error

        if expected_width is None:
            expected_width = len(row)
        elif len(row) != expected_width:
            raise MapSyncError(
                f"{path.name} row {row_number} has {len(row)} cells; "
                f"expected {expected_width}"
            )
        grid.append(row)

    return grid


def _horizontal_runs(row: list[int], value: int) -> list[tuple[int, int]]:
    runs: list[tuple[int, int]] = []
    start: int | None = None
    for x, cell in enumerate(row):
        if cell == value and start is None:
            start = x
        elif cell != value and start is not None:
            runs.append((start, x - 1))
            start = None
    if start is not None:
        runs.append((start, len(row) - 1))
    return runs


def rectangles_for_value(
    grid: list[list[int]], value: int
) -> list[tuple[int, int, int, int]]:
    """Return an exact deterministic rectangle cover using merged row runs."""
    completed: list[tuple[int, int, int, int]] = []
    active: dict[tuple[int, int], tuple[int, int, int, int]] = {}

    for y, row in enumerate(grid):
        row_runs = _horizontal_runs(row, value)
        row_run_set = set(row_runs)

        for run in sorted(active):
            if run not in row_run_set:
                completed.append(active[run])

        next_active: dict[tuple[int, int], tuple[int, int, int, int]] = {}
        for x0, x1 in row_runs:
            previous = active.get((x0, x1))
            if previous is None:
                next_active[(x0, x1)] = (x0, y, x1, y)
            else:
                next_active[(x0, x1)] = (x0, previous[1], x1, y)
        active = next_active

    completed.extend(active[run] for run in sorted(active))
    return sorted(completed, key=lambda rect: (rect[1], rect[0], rect[3], rect[2]))


def _flatten_metadata(value: object, field_name: str) -> str:
    if not isinstance(value, str):
        raise MapSyncError(f"custom field {field_name!r} must be a string")
    return " ".join(value.split())


def _load_metadata(path: Path) -> tuple[str, str, str, str]:
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except OSError as error:
        raise MapSyncError(f"cannot read {path.name}: {error}") from error
    except json.JSONDecodeError as error:
        raise MapSyncError(f"invalid JSON in {path.name}: {error}") from error

    custom_fields = document.get("customFields")
    if not isinstance(custom_fields, dict):
        raise MapSyncError("data.json is missing the customFields object")

    names = ("rl_id", "rl_name", "rl_description", "rl_notes")
    missing = [name for name in names if name not in custom_fields]
    if missing:
        raise MapSyncError(
            f"data.json is missing custom field(s): {', '.join(missing)}"
        )

    values = tuple(_flatten_metadata(custom_fields[name], name) for name in names)
    map_id = values[0]
    if not map_id or not ID_PATTERN.fullmatch(map_id):
        raise MapSyncError(
            "rl_id must contain only letters, numbers, underscores, and hyphens"
        )
    return values  # type: ignore[return-value]


def _format_rectangles(rectangles: Iterable[tuple[int, int, int, int]]) -> str:
    return json.dumps(list(rectangles), separators=(", ", ", "))


def convert_level(level_dir: Path, terrain_mapping: dict[int, str]) -> ConvertedMap:
    missing = [name for name in REQUIRED_FILES if not (level_dir / name).is_file()]
    if missing:
        raise MapSyncError(f"missing required file(s): {', '.join(missing)}")

    map_id, title, description, notes = _load_metadata(level_dir / "data.json")
    terrain = read_csv_grid(level_dir / "Terrain.csv")
    spawn_zones = read_csv_grid(level_dir / "SpawnZones.csv")

    terrain_size = (len(terrain[0]), len(terrain))
    spawn_size = (len(spawn_zones[0]), len(spawn_zones))
    if terrain_size != spawn_size:
        raise MapSyncError(
            f"grid dimensions differ: Terrain.csv is {terrain_size[0]}x"
            f"{terrain_size[1]}, SpawnZones.csv is {spawn_size[0]}x{spawn_size[1]}"
        )

    unknown_terrain = sorted(
        {cell for row in terrain for cell in row if cell not in terrain_mapping}
    )
    if unknown_terrain:
        raise MapSyncError(
            "Terrain.csv contains unmapped value(s): "
            + ", ".join(map(str, unknown_terrain))
        )

    unknown_spawn = sorted(
        {cell for row in spawn_zones for cell in row if cell not in VALID_SPAWN_VALUES}
    )
    if unknown_spawn:
        raise MapSyncError(
            "SpawnZones.csv contains unsupported value(s): "
            + ", ".join(map(str, unknown_spawn))
        )

    player_rectangles = [
        rectangle
        for value in PLAYER_VALUES
        for rectangle in rectangles_for_value(spawn_zones, value)
    ]
    enemy_rectangles = [
        rectangle
        for value in ENEMY_VALUES
        for rectangle in rectangles_for_value(spawn_zones, value)
    ]
    if not player_rectangles:
        raise MapSyncError("SpawnZones.csv contains no player zones (values 1 or 2)")
    if not enemy_rectangles:
        raise MapSyncError("SpawnZones.csv contains no enemy zones (values 3 or 4)")

    width, height = terrain_size
    terrain_rows = [
        "".join(terrain_mapping[cell] for cell in row) for row in terrain
    ]
    metadata_lines = [
        f"id: {map_id}",
        f"title: {title}",
        f"description: {description}",
        f"notes: {notes}",
        f"width: {width}",
        f"height: {height}",
        f"spawn_zones: {_format_rectangles(player_rectangles)}",
        f"enemy_zones: {_format_rectangles(enemy_rectangles)}",
        "data:",
    ]
    text = "\n".join(metadata_lines + terrain_rows) + "\n"
    return ConvertedMap(map_id=map_id, text=text, width=width, height=height)


def _atomic_write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            newline="\n",
            dir=path.parent,
            prefix=f".{path.name}.",
            suffix=".tmp",
            delete=False,
        ) as temporary:
            temporary.write(text)
            temporary_path = Path(temporary.name)
        os.replace(temporary_path, path)
    finally:
        if temporary_path is not None:
            temporary_path.unlink(missing_ok=True)


def sync_maps(
    source_dir: Path, output_dir: Path, terrain_mapping: dict[int, str]
) -> tuple[int, int]:
    if not source_dir.is_absolute():
        raise MapSyncError(f"{SOURCE_ENV} must be an absolute path")
    if not source_dir.is_dir():
        raise MapSyncError(f"source directory does not exist: {source_dir}")

    level_dirs = sorted(path for path in source_dir.iterdir() if path.is_dir())
    if not level_dirs:
        raise MapSyncError(f"source directory contains no level directories: {source_dir}")

    converted: list[tuple[Path, ConvertedMap]] = []
    errors: list[str] = []
    seen_ids: dict[str, Path] = {}
    for level_dir in level_dirs:
        try:
            result = convert_level(level_dir, terrain_mapping)
            if result.map_id in seen_ids:
                raise MapSyncError(
                    f"duplicate rl_id {result.map_id!r}; also used by "
                    f"{seen_ids[result.map_id].name}"
                )
            seen_ids[result.map_id] = level_dir
            converted.append((level_dir, result))
        except MapSyncError as error:
            errors.append(f"{level_dir.name}: {error}")

    if errors:
        for error in errors:
            print(f"error: {error}", file=sys.stderr)
        print(
            f"Sync failed: 0 converted, {len(errors)} error(s).",
            file=sys.stderr,
        )
        return 0, len(errors)

    for level_dir, result in converted:
        destination = output_dir / f"{result.map_id}.txt"
        _atomic_write(destination, result.text)
        print(
            f"Converted {level_dir.name} -> {destination} "
            f"({result.width}x{result.height})"
        )
    print(f"Sync complete: {len(converted)} converted, 0 errors.")
    return len(converted), 0


def _parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    script_dir = Path(__file__).resolve().parent
    project_dir = script_dir.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--source-dir",
        type=Path,
        help=f"LDtk simplified export root (default: ${SOURCE_ENV})",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=project_dir / "data" / "maps",
        help="destination directory (default: project data/maps)",
    )
    parser.add_argument(
        "--config",
        type=Path,
        default=script_dir / "ldtk_map_sync.json",
        help="terrain mapping JSON file",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(argv)
    source_dir = args.source_dir
    if source_dir is None:
        source_value = os.environ.get(SOURCE_ENV)
        if not source_value:
            print(
                f"error: set {SOURCE_ENV} to the absolute path of the LDtk "
                "simplified export directory",
                file=sys.stderr,
            )
            return 2
        source_dir = Path(source_value)

    try:
        terrain_mapping = load_terrain_mapping(args.config)
        _, error_count = sync_maps(
            source_dir.expanduser(),
            args.output_dir.expanduser(),
            terrain_mapping,
        )
    except MapSyncError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 1 if error_count else 0


if __name__ == "__main__":
    raise SystemExit(main())
