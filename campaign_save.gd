extends RefCounted

const P = preload("res://progression.gd")
const R = preload("res://puzzle.gd")

# Permanent wallet/ranks/receipts live outside this snapshot. Incompatible V5
# active boards return {}, allowing main to keep purchases and start safe V7.
# Animation positions are not serialized: main resumes transit at reserved docks.
static func validate(value: Variant, levels: Dictionary, highest: int) -> Dictionary:
    if not value is Dictionary or value.is_empty(): return {}
    var s: Dictionary = value
    if not s.get("stage") is int or not bool(s.get("campaign",false)): return {}
    var stage: int = int(s.stage)
    if stage < 1 or stage > highest+1: return {}
    var config: Dictionary = P.stage_config(stage,levels)
    if not s.get("config") is Dictionary or not _same_config(s.config,config): return {}
    var initial: Dictionary = R.create_level(stage-1,config)
    for field in ["total","width","height","cargo_total","cargo_value_total","manifest","belt_limit","solution","solution_steps","required_route","certificate_version","certificate_valid"]:
        if s.get(field) != initial[field]: return {}
    for field in ["trucks","belt","bays","feed_left","feed_right","obstacles"]:
        if not s.get(field) is Array: return {}
    for field in ["manifest_delivered","departures_by_type"]:
        if not s.get(field) is Dictionary: return {}
    for field in ["delivered","cargo_delivered","moves","ticks","rescue_used"]:
        if not s.get(field) is int or int(s[field]) < 0: return {}
    if s.trucks.size() != initial.trucks.size() or s.bays.size() != 5 or s.belt.size() != R.BELT_SIZE: return {}
    if s.obstacles.size() != initial.obstacles.size() or R.belt_count(s) > int(config.belt_limit): return {}
    var occupied: Dictionary = {}
    for index in range(s.obstacles.size()):
        if not s.obstacles[index] is Dictionary: return {}
        var obstacle: Dictionary = s.obstacles[index]
        var original: Dictionary = initial.obstacles[index]
        if obstacle.size() != original.size(): return {}
        for field in original:
            if field != "opened" and obstacle.get(field) != original[field]: return {}
        if not obstacle.get("opened") is bool: return {}
        var needed: String = str(obstacle.required_type)
        var opened: bool = int(s.delivered) >= int(obstacle.opens_after) and (needed == "" or int(s.departures_by_type.get(needed,0)) > 0)
        if bool(obstacle.opened) != opened: return {}
        if not opened:
            for cell in R.obstacle_cells(obstacle): occupied[cell] = true
    var inventory: Dictionary = {}
    for cargo in initial.feed_left+initial.feed_right: inventory[int(cargo.id)] = cargo
    var remaining: Dictionary = initial.manifest.duplicate(true)
    var done := 0
    var cargo_done := 0
    var done_types: Dictionary = {}
    var done_counts: Dictionary = {}
    var reserved: Dictionary = {}
    var occupants: Array[int] = []
    for id in range(s.trucks.size()):
        if not s.trucks[id] is Dictionary: return {}
        var truck: Dictionary = s.trucks[id]
        var canonical: Dictionary = initial.trucks[id]
        for field in ["id","x","y","len","type","capacity","quality"]:
            if truck.get(field) != canonical[field]: return {}
        if not truck.get("dir") is int or int(truck.dir) not in [int(canonical.dir),(int(canonical.dir)+2)%4]: return {}
        if not truck.get("loaded") is int or not truck.get("target_load") is int or not truck.get("status") is String: return {}
        var amount: Variant = truck.get("delivery_value")
        var expected: Variant = truck.get("expected_value")
        if not _finite_number(amount) or not _finite_number(expected): return {}
        var status: String = str(truck.status)
        var loaded: int = int(truck.loaded)
        var target: int = int(truck.target_load)
        if status not in ["yard","driving","loading","departing","done"] or loaded < 0 or loaded > int(truck.capacity): return {}
        if status == "yard":
            if loaded != 0 or target != -1: return {}
            for cell in R._cells(truck):
                if occupied.has(cell): return {}
                occupied[cell] = true
        else:
            if target < 0 or target > int(truck.capacity) or loaded > target: return {}
            if status == "driving" and loaded != 0: return {}
            if status in ["departing","done"] and (target <= 0 or loaded != target): return {}
            if status != "done":
                occupants.append(id)
                reserved[truck.type] = int(reserved.get(truck.type,0))+target-loaded
        var unit_value: float = float(config.cargo_values[truck.type])
        var forecast: int = mini(int(truck.capacity),int(config.manifest[truck.type])) if status == "yard" else target
        if not is_equal_approx(float(amount),float(loaded)*unit_value) or not is_equal_approx(float(expected),float(forecast)*unit_value): return {}
        remaining[truck.type] = int(remaining[truck.type])-loaded
        if status == "done":
            done += 1
            cargo_done += loaded
            done_types[truck.type] = int(done_types.get(truck.type,0))+loaded
            done_counts[truck.type] = int(done_counts.get(truck.type,0))+1
    if int(s.delivered) != done or int(s.cargo_delivered) != cargo_done or int(s.moves) < done+occupants.size(): return {}
    if s.manifest_delivered != done_types or s.departures_by_type != done_counts: return {}
    var seen_bays: Array[int] = []
    for bay in range(s.bays.size()):
        if not s.bays[bay] is int: return {}
        var id: int = int(s.bays[bay])
        if id >= 0:
            if id not in occupants or id in seen_bays or bay >= int(config.bay_count): return {}
            seen_bays.append(id)
        elif id != (-1 if bay < int(config.bay_count) else -2): return {}
    if seen_bays.size() != occupants.size(): return {}
    if null in s.feed_left or null in s.feed_right: return {}
    var seen: Dictionary = {}
    var unconsumed: Dictionary = {}
    for cargo in s.feed_left+s.feed_right+s.belt:
        if cargo == null: continue
        if not cargo is Dictionary or not cargo.get("id") is int: return {}
        var id: int = int(cargo.id)
        if not inventory.has(id) or seen.has(id) or cargo != inventory[id]: return {}
        seen[id] = true
        remaining[cargo.type] = int(remaining[cargo.type])-1
        unconsumed[cargo.type] = int(unconsumed.get(cargo.type,0))+1
    for kind in remaining:
        if int(remaining[kind]) != 0 or int(reserved.get(kind,0)) > int(unconsumed.get(kind,0)): return {}
    if R.is_won(s): return {}
    var restored: Dictionary = s.duplicate(true)
    restored.config = config
    return restored

static func _finite_number(value: Variant) -> bool:
    return (value is int or value is float) and is_finite(float(value))

static func _same_config(actual: Dictionary, expected: Dictionary) -> bool:
    if actual.size() != expected.size(): return false
    for key in expected:
        if expected[key] is float:
            if not _finite_number(actual.get(key)) or not is_equal_approx(float(actual[key]),float(expected[key])): return false
        elif actual.get(key) != expected[key]: return false
    return true
