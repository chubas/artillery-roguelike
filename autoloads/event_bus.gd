# Global signal hub (M3 spec §2.1). No gameplay system imports or calls another
# directly — all cross-system communication flows through these signals. This is the
# rule that makes the interaction layer emergent.
#
# Scope decision (M3 plan): GAMEPLAY events route through here. The high-frequency
# per-tile render signal (TerrainManager.tile_changed) stays a direct local connection
# to TerrainRenderer for clarity and to avoid thousands of global emits per collapse.
extends Node

# ── Turn signals ─────────────────────────────────────────────────────────────
signal turn_started(side: String)          # "player" or "enemy"
signal turn_ended(side: String)
signal round_started(round_index: int)

# ── Unit signals ─────────────────────────────────────────────────────────────
signal unit_moved(unit: Unit, from: Vector2i, to: Vector2i)
signal unit_fired(unit: Unit, shot: ShotDefinition)
signal unit_hit_dealt(unit: Unit, target: Unit, damage: int, element: String)
signal unit_hit_taken(unit: Unit, damage: int, element: String, source: Unit)
signal unit_killed(unit: Unit, killer: Unit)
signal unit_died(unit: Unit)
signal unit_tile_entered(unit: Unit, tile_pos: Vector2i)
signal unit_shield_changed(unit: Unit, shield: int)
signal unit_armor_changed(unit: Unit, armor: int)

# ── Status signals ───────────────────────────────────────────────────────────
signal status_applied(target: Unit, status_id: String, stacks: int)
signal status_removed(target: Unit, status_id: String)
signal status_ticked(target: Unit, status_id: String, stacks: int)

# ── Terrain signals (gameplay-facing; render path stays local) ───────────────
signal tile_damaged(col: int, row: int, dmg: int, remaining_hp: int)
signal tile_destroyed(col: int, row: int, tile_type: int)
signal tile_status_applied(col: int, row: int, status_id: String)
signal tile_status_removed(col: int, row: int, status_id: String)
signal tile_status_ticked(col: int, row: int, status_id: String)
signal terrain_crushed(col: int, row: int, damage: int, victims: Array)
# ── Mineral / Ore signals (M42) ───────────────────────────────────────────────
signal mineral_destroyed(col: int, row: int)   # a MINERAL vein broke → spawn an Ore here
signal ore_collected(value: int)               # a unit collected an Ore worth `value` source voxels

# ── Projectile signals ───────────────────────────────────────────────────────
signal projectile_impact(world_pos: Vector2, impact_voxel: Vector2i, element: String)
signal aoe_resolved(center: Vector2i, radius: int, affected_tiles: Array)

# ── Deployable signals (M6, M31) ──────────────────────────────────────────────
signal deployable_placed(deployable: Deployable)   # M31: for deploy_appear animation
signal deployable_died(deployable: Deployable)
signal mine_detonated(mine: Deployable)

# ── Environment signals (M8) ──────────────────────────────────────────────────
signal wind_changed(strength: float)   # -1.0..1.0; emitted each round; 0 = calm
