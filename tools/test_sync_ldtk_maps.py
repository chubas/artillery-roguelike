#!/usr/bin/env python3

import json
import tempfile
import unittest
from pathlib import Path

from sync_ldtk_maps import (
    MapSyncError,
    convert_level,
    load_terrain_mapping,
    read_csv_grid,
    rectangles_for_value,
)


class LdtkMapSyncTests(unittest.TestCase):
    def setUp(self) -> None:
        self.terrain_mapping = {
            0: ".",
            1: "1",
            2: "2",
            3: "3",
            4: "4",
            5: "5",
            6: "6",
            7: "7",
            8: "8",
            9: "9",
            10: "0",
            11: "M",
        }

    def _write_level(
        self,
        directory: Path,
        terrain: str = "0,10,11,\n1,2,3,\n",
        spawn_zones: str = "1,1,3,\n2,2,4,\n",
    ) -> None:
        metadata = {
            "width": 48,
            "height": 32,
            "customFields": {
                "rl_id": "test_map",
                "rl_name": "Test Map",
                "rl_description": "A test",
                "rl_notes": "First line\nSecond line",
            },
            "entities": {},
        }
        (directory / "data.json").write_text(
            json.dumps(metadata), encoding="utf-8"
        )
        (directory / "Terrain.csv").write_text(terrain, encoding="utf-8")
        (directory / "SpawnZones.csv").write_text(
            spawn_zones, encoding="utf-8"
        )

    def test_loads_extensible_terrain_mapping(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            config_path = Path(temporary) / "mapping.json"
            config_path.write_text(
                json.dumps(
                    {
                        "terrain_values": {
                            "0": ".",
                            "1": "1",
                            "10": "0",
                            "11": "M",
                        }
                    }
                ),
                encoding="utf-8",
            )
            self.assertEqual(
                load_terrain_mapping(config_path),
                {0: ".", 1: "1", 10: "0", 11: "M"},
            )

    def test_csv_parser_ignores_trailing_empty_columns(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            csv_path = Path(temporary) / "Terrain.csv"
            csv_path.write_text("0,1,10,\n11,2,3,\n", encoding="utf-8")
            self.assertEqual(
                read_csv_grid(csv_path),
                [[0, 1, 10], [11, 2, 3]],
            )

    def test_rectangle_cover_merges_only_identical_row_runs(self) -> None:
        grid = [
            [1, 1, 0, 1],
            [1, 1, 0, 1],
            [1, 0, 0, 1],
        ]
        self.assertEqual(
            rectangles_for_value(grid, 1),
            [(0, 0, 1, 1), (3, 0, 3, 2), (0, 2, 0, 2)],
        )

    def test_conversion_maps_tiles_zones_and_flattens_metadata(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            level_dir = Path(temporary)
            self._write_level(level_dir)

            converted = convert_level(level_dir, self.terrain_mapping)

            self.assertEqual((converted.width, converted.height), (3, 2))
            self.assertIn("notes: First line Second line\n", converted.text)
            self.assertIn("spawn_zones: [[0, 0, 1, 0], [0, 1, 1, 1]]", converted.text)
            self.assertIn("enemy_zones: [[2, 0, 2, 0], [2, 1, 2, 1]]", converted.text)
            self.assertTrue(converted.text.endswith("data:\n.0M\n123\n"))

    def test_conversion_syncs_optional_auto_fill_fields(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            level_dir = Path(temporary)
            self._write_level(level_dir)
            metadata_path = level_dir / "data.json"
            metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
            metadata["customFields"]["autoFillTerrain"] = True
            metadata["customFields"]["autoFillTerrainValues"] = "[3, 6]"
            metadata_path.write_text(json.dumps(metadata), encoding="utf-8")

            converted = convert_level(level_dir, self.terrain_mapping)

            self.assertIn("autoFillTerrain: true\n", converted.text)
            self.assertIn("autoFillTerrainValues: [3, 6]\n", converted.text)

    def test_conversion_syncs_entities_as_grid_coordinates(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            level_dir = Path(temporary)
            self._write_level(level_dir)
            metadata_path = level_dir / "data.json"
            metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
            metadata["entities"] = {
                "Boss1": [
                    {
                        "id": "Boss1",
                        "x": 24,
                        "y": 8,
                        "width": 16,
                        "height": 16,
                    }
                ]
            }
            metadata_path.write_text(json.dumps(metadata), encoding="utf-8")

            converted = convert_level(level_dir, self.terrain_mapping)

            self.assertIn("Entity_Boss1: [1, 0]\n", converted.text)

    def test_conversion_rejects_enabled_auto_fill_without_values(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            level_dir = Path(temporary)
            self._write_level(level_dir)
            metadata_path = level_dir / "data.json"
            metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
            metadata["customFields"]["autoFillTerrain"] = True
            metadata["customFields"]["autoFillTerrainValues"] = ""
            metadata_path.write_text(json.dumps(metadata), encoding="utf-8")

            with self.assertRaisesRegex(
                MapSyncError, "autoFillTerrainValues is missing or empty"
            ):
                convert_level(level_dir, self.terrain_mapping)

    def test_conversion_rejects_mismatched_grid_dimensions(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            level_dir = Path(temporary)
            self._write_level(
                level_dir,
                terrain="0,1,\n0,1,\n",
                spawn_zones="1,3,\n",
            )
            with self.assertRaisesRegex(MapSyncError, "grid dimensions differ"):
                convert_level(level_dir, self.terrain_mapping)

    def test_conversion_rejects_unmapped_terrain_values(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            level_dir = Path(temporary)
            self._write_level(
                level_dir,
                terrain="0,99,\n",
                spawn_zones="1,3,\n",
            )
            with self.assertRaisesRegex(MapSyncError, "unmapped value"):
                convert_level(level_dir, self.terrain_mapping)


if __name__ == "__main__":
    unittest.main()
