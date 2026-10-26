extends RefCounted

# Pure campaign rules. The controller owns wallet, purchase transactions,
# persistent ranks and claimed delivery/stage receipts. No I/O or real payments.
const L = preload("res://layout.gd")
const FLEET_KEYS := ["fleet_kyl","fleet_frys","fleet_schakt","fleet_timmer","fleet_adr","fleet_bransle"]
const GENERAL_KEYS := ["loader","belt","warehouse","parking"]
const KEYS := FLEET_KEYS + GENERAL_KEYS
const BASE_VALUES := {"schakt":1,"timmer":2,"kyl":3,"frys":4,"adr":6,"bransle":8}
const COSTS := {
    "fleet_kyl":[200,450,900],"fleet_frys":[200,450,900],
    "fleet_schakt":[200,450,900],"fleet_timmer":[200,450,900],
    "fleet_adr":[230,500,1000],"fleet_bransle":[230,500,1000],
    "loader":[180,360,700,1100,1600,2200],
    "belt":[220,440,800,1250,1800,2500],
    "warehouse":[260,520,900,1500,2300],
    "parking":[650,1400]
}

static func defaults() -> Dictionary:
    var ranks := {}
    for key in KEYS: ranks[key] = 0
    return ranks

static func sanitize(levels: Variant) -> Dictionary:
    var clean: Dictionary = defaults()
    if not levels is Dictionary:
        return clean
    for key in KEYS:
        var migrated := 0
        var old: Variant = levels.get("fleet",0)
        if key in FLEET_KEYS and (old is int or old is float) and is_finite(float(old)):
            migrated = clampi(ceili(clampf(float(old),0.0,10.0)/3.0),0,3)
        var value: Variant = levels.get(key,migrated)
        if value is int or value is float:
            if is_finite(float(value)):
                clean[key] = int(clampf(float(value),0.0,float(max_rank(key))))
    return clean

static func max_rank(key: String) -> int:
    return COSTS[key].size() if COSTS.has(key) else 0

static func cost(key: String, rank: int) -> int:
    if not COSTS.has(key) or rank >= max_rank(key):
        return 0
    return int(COSTS[key][maxi(0,rank)])

static func _rank(key: String, rank: int) -> int:
    return clampi(rank,0,max_rank(key))

static func capacity(kind: String, rank: int) -> int:
    return 3+_rank("fleet_"+kind,rank)

static func loading_multiplier(rank: int) -> float:
    return 1.0+.12*float(_rank("loader",rank))

static func belt_multiplier(rank: int) -> float:
    return 1.0+.08*float(_rank("belt",rank))

static func value_multiplier(rank: int) -> float:
    return 1.0+.25*float(_rank("warehouse",rank))

static func bay_count(rank: int) -> int:
    return 3+_rank("parking",rank)

static func effect_text(key: String, rank: int) -> String:
    if key in FLEET_KEYS:
        return "%d varor / lastbil" % capacity(key.trim_prefix("fleet_"),rank)
    match key:
        "loader": return "Normal lastfart" if rank == 0 else "+%d %% lastfart" % roundi((loading_multiplier(rank)-1.0)*100.0)
        "belt": return "Normal bandfart" if rank == 0 else "+%d %% bandfart" % roundi((belt_multiplier(rank)-1.0)*100.0)
        "warehouse": return "Basvaror" if rank == 0 else "+%d %% varuvärde" % roundi((value_multiplier(rank)-1.0)*100.0)
        "parking": return "%d öppna kajer" % bay_count(rank)
    return ""

static func next_effect_text(key: String, rank: int) -> String:
    if not COSTS.has(key):
        return ""
    if rank >= max_rank(key):
        return "Maxnivå"
    return effect_text(key,_rank(key,rank)+1)

static func stage_config(stage: int, levels: Variant = {}) -> Dictionary:
    var number: int = maxi(1,stage)
    var ranks: Dictionary = sanitize(levels)
    var counts := [10,12,14,16,18,22,26,30]
    var footprints := [Vector2i(8,10),Vector2i(8,10),Vector2i(10,12),Vector2i(10,12),Vector2i(12,12),Vector2i(12,14),Vector2i(14,14),Vector2i(14,16)]
    var step: int = mini(number-1,counts.size()-1)
    var dimensions: Vector2i = footprints[step]
    var origin := Vector2i(floori(float(L.WIDTH-dimensions.x)*.5),floori(float(L.HEIGHT-dimensions.y)*.5))
    var types: Array = ["schakt","kyl"] if number == 1 else ["schakt","timmer","kyl","frys"]
    if number >= 3:
        types.append("adr")
    if number >= 5:
        types.append("bransle")
    var amounts := [[4,4],[3,3,2,2],[4,3,2,2,1],[5,3,3,2,1],[4,3,2,2,1,4],[5,4,3,3,1,2],[5,4,4,3,2,2],[6,5,4,3,3,3]]
    var manifest: Dictionary = {}
    for index in range(types.size()):
        var amount_index: int = ((index-(number-8))%6+6)%6 if number >= 8 else index
        manifest[types[index]] = int(amounts[step][amount_index])
    var capacities: Dictionary = {}
    for kind in BASE_VALUES: capacities[kind] = capacity(kind,int(ranks["fleet_"+kind]))
    var cargo_values: Dictionary = {}
    for kind in types:
        cargo_values[kind] = float(BASE_VALUES[kind])*value_multiplier(int(ranks.warehouse))
    return {"version":7,"stage":number,"seed":218003+number*104729,"count":int(counts[step]),
        "spawn_bounds":Rect2i(origin,dimensions),"types":types,
        "capacities":capacities,"obstacles_enabled":number >= 3,"manifest":manifest,
        "goods_total":[8,10,12,14,16,18,20,24][step],"boss":number%5 == 0,"belt_limit":6 if number%5 == 0 else 8,
        "gate_type":"bransle" if number >= 5 else ("adr" if number >= 3 else ""),
        "opens_after":3 if number >= 8 else 2,
        "cargo_values":cargo_values,"quality":int(ranks.warehouse),"bay_count":bay_count(int(ranks.parking)),
        "loading_multiplier":loading_multiplier(int(ranks.loader)),"belt_multiplier":belt_multiplier(int(ranks.belt))}

static func stage_bonus(stage: int) -> int:
    return 50+maxi(1,stage)*10

static func delivery_reward(truck: Dictionary) -> int:
    return roundi(maxf(0.0,float(truck.get("delivery_value",0.0))))

static func claim_key(stage: int, id: int) -> String:
    return "campaign:v1:%d:%d" % [maxi(1,stage),id]

static func _cargo_key(stage: int, kind: String) -> String:
    return "campaign:v7:cargo:%d:%s" % [maxi(1,stage),kind]

static func _credited(ledger: Dictionary, key: String) -> int:
    var value: Variant = ledger.get(key,0)
    if (value is int or value is float) and is_finite(float(value)):
        return maxi(0,int(value))
    return 0

static func cargo_reward(stage: int, kind: String, shipped_units: int, unit_value: float, ledger: Dictionary) -> Dictionary:
    # Permanent high-water mark: restarting, undoing or choosing another truck
    # cannot pay for the same shipped cargo twice. Round the cumulative value,
    # so splitting decimal-valued goods between trucks never changes earnings.
    var result := {"ok":false,"ledger":ledger.duplicate(true),"reward":0,"key":"","credited":0,"total":0}
    if not BASE_VALUES.has(kind) or shipped_units < 0 or unit_value < 0.0 or not is_finite(unit_value):
        return result
    var amount: float = float(shipped_units)*unit_value
    if not is_finite(amount) or amount >= float(9223372036854775807):
        return result
    var key: String = _cargo_key(stage,kind)
    var before: int = _credited(ledger,key)
    var total: int = roundi(amount)
    var after: int = maxi(before,total)
    result.ok = true
    result.key = key
    result.total = total
    result.credited = after
    result.reward = after-before
    result.ledger[key] = after
    return result

static func remaining_income(stage: int, manifest: Dictionary, cargo_values: Dictionary, ledger: Dictionary, include_bonus: bool = true) -> int:
    # The fixed order is the income ceiling; surplus parked trucks add no value.
    var remaining: int = 0
    for kind in BASE_VALUES:
        var units: Variant = manifest.get(kind,0)
        var value: Variant = cargo_values.get(kind,0.0)
        if not (units is int or units is float) or not (value is int or value is float):
            continue
        if not is_finite(float(units)) or not is_finite(float(value)):
            continue
        var quote: Dictionary = cargo_reward(stage,kind,maxi(0,int(units)),float(value),ledger)
        if quote.ok:
            remaining += int(quote.reward)
    var bonus_claim: Variant = ledger.get("campaign:v1:win:%d" % maxi(1,stage),false)
    if include_bonus and not (bonus_claim is bool and bonus_claim):
        remaining += stage_bonus(stage)
    return remaining

static func purchase(levels: Variant, balance: int, key: String) -> Dictionary:
    # Pure atomic proposal: caller commits ranks/wallet and saves on ok=true.
    # Input dictionaries are never mutated, including on rejected purchases.
    var ranks: Dictionary = sanitize(levels)
    var wallet: int = maxi(0,balance)
    var result := {"ok":false,"levels":ranks,"balance":wallet,"cost":0,"reason":""}
    if not COSTS.has(key):
        result.reason = "invalid"
        return result
    var price: int = cost(key,int(ranks[key]))
    result.cost = price
    if price == 0:
        result.reason = "max"
    elif wallet < price:
        result.reason = "funds"
    else:
        ranks[key] = int(ranks[key])+1
        result.balance = wallet-price
        result.ok = true
    return result
