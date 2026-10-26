extends SceneTree

const P = preload("res://progression.gd")
const R = preload("res://puzzle.gd")
const PATH := "res://qa/_ci/v7-rewards.cfg"
var failures: Array[String] = []
var checks := 0

func check(value: bool, message: String) -> void:
    checks += 1
    if not value:
        failures.append(message)
        push_error(message)

func _initialize() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PATH.get_base_dir()))
    _waterline()
    _types_and_rounding()
    _actual_replay()
    _remaining_and_storage()
    if FileAccess.file_exists(PATH): DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
    print("V7_REWARDS_TESTS_OK: %d checks; truck-independent permanent waterlines, cumulative rounding, six resources, actual stage replay, remaining income and ConfigFile" % checks if failures.is_empty() else "V7_REWARDS_TESTS_FAILED: %d" % failures.size())
    quit(0 if failures.is_empty() else 1)

func _waterline() -> void:
    var original := {"campaign:v1:1:7":true,"campaign:v1:win:2":true,"nested":{"keep":[1,2]}}
    var before: Dictionary = original.duplicate(true)
    var first: Dictionary = P.cargo_reward(1,"kyl",3,3.0,original)
    check(first.ok and first.reward == 9 and first.credited == 9 and first.total == 9,"First real three-unit shipment pays nine coins")
    check(first.key == "campaign:v7:cargo:1:kyl","Receipt is keyed by stage/resource, never truck ID")
    check(original == before,"Successful quote never mutates input ledger")
    var ledger: Dictionary = first.ledger
    var again: Dictionary = P.cargo_reward(1,"kyl",3,3.0,ledger)
    check(again.reward == 0 and again.ledger == ledger,"Different truck replaying same cumulative shipment pays nothing")
    check(P.cargo_reward(1,"kyl",0,3.0,ledger).reward == 0,"Restart with zero delivered cannot lower permanent receipt")
    var undone: Dictionary = P.cargo_reward(1,"kyl",1,3.0,ledger)
    check(undone.reward == 0 and undone.credited == 9,"Undo to one unit retains the higher permanent waterline")
    var next: Dictionary = P.cargo_reward(1,"kyl",4,3.0,undone.ledger)
    check(next.reward == 3 and next.credited == 12,"Only the extra fourth unit pays its delta")
    check(P.cargo_reward(2,"kyl",3,3.0,ledger).reward == 9,"Next stage has independent goods")
    next.ledger.nested.keep.append(3)
    check(original == before and ledger.nested.keep == [1,2],"Returned ledger is a deep independent copy")
    for args in [["unknown",1,1.0],["kyl",-1,3.0],["kyl",1,-3.0],["kyl",1,INF],["kyl",1,NAN]]:
        var invalid: Dictionary = P.cargo_reward(1,args[0],args[1],args[2],ledger)
        check(not invalid.ok and invalid.reward == 0 and invalid.ledger == ledger,"Invalid input cannot create or consume a receipt")
    check(P.claim_key(1,7) == "campaign:v1:1:7","Historical truck claim API remains unchanged")

func _types_and_rounding() -> void:
    var ledger: Dictionary = {}
    var sum := 0
    for units in range(1,5):
        var quote: Dictionary = P.cargo_reward(4,"schakt",units,1.25,ledger)
        check(quote.reward == [1,2,1,1][units-1],"Cumulative quarter-coin values preserve rounding carries")
        sum += int(quote.reward)
        ledger = quote.ledger
    check(sum == 5 and P.cargo_reward(4,"schakt",4,1.25,{}).reward == sum,"Four one-unit trucks earn exactly one four-unit truck")
    ledger = {}
    for kind in P.BASE_VALUES:
        var value: float = float(P.BASE_VALUES[kind])*1.25
        var quote: Dictionary = P.cargo_reward(8,kind,5,value,ledger)
        check(quote.reward == roundi(5.0*value),"Each of six resources uses its actual upgraded value")
        ledger = quote.ledger
        check(P.cargo_reward(8,kind,2,value,ledger).reward == 0,"All six resources retain receipts across partial replay")
    check(ledger.size() == 6,"Six separate waterlines coexist")

func _actual_replay() -> void:
    var ledger: Dictionary = {}
    var total_paid := 0
    for upgraded in [false,true,false]:
        var ranks: Dictionary = P.defaults()
        ranks.warehouse = 1
        if upgraded:
            for key in P.FLEET_KEYS: ranks[key] = 3
        var config: Dictionary = P.stage_config(1,ranks)
        var completed: Dictionary = R.simulate(R.create_level(0,config))
        check(completed.ok and R.is_won(completed.state),"Real stage certificate ships all fixed goods")
        var attempt_paid := 0
        for kind in config.manifest:
            var quote: Dictionary = P.cargo_reward(1,kind,int(completed.state.manifest_delivered[kind]),float(config.cargo_values[kind]),ledger)
            attempt_paid += int(quote.reward)
            ledger = quote.ledger
        check(attempt_paid == (20 if total_paid == 0 else 0),"Restart with different capacities/truck IDs cannot farm identical fixed goods")
        total_paid += attempt_paid
    check(total_paid == 20,"Three completed attempts pay exactly one fixed eight-unit manifest")

func _remaining_and_storage() -> void:
    var config: Dictionary = P.stage_config(1,{"warehouse":1})
    var ledger: Dictionary = {"campaign:v1:1:7":true}
    check(P.remaining_income(1,config.manifest,config.cargo_values,ledger) == 80,"Income ceiling uses actual manifest plus unclaimed sixty-coin bonus")
    ledger = P.cargo_reward(1,"schakt",3,1.25,ledger).ledger
    check(P.remaining_income(1,config.manifest,config.cargo_values,ledger,false) == 16,"Already credited cumulative cargo value reduces remaining income")
    ledger["campaign:v1:win:1"] = true
    check(P.remaining_income(1,config.manifest,config.cargo_values,ledger) == 16,"Already claimed stage bonus is excluded")
    var before: Dictionary = ledger.duplicate(true)
    var file := ConfigFile.new()
    file.set_value("progress","rewards",ledger)
    check(file.save(PATH) == OK,"Isolated ConfigFile writes mixed historic/new ledger")
    var loaded := ConfigFile.new()
    check(loaded.load(PATH) == OK,"ConfigFile reloads reward ledger")
    var restored: Dictionary = loaded.get_value("progress","rewards")
    check(restored == before,"Integer waterlines and legacy bool claims survive disk roundtrip")
    check(P.cargo_reward(1,"schakt",3,1.25,restored).reward == 0,"Reload cannot replay previously shipped goods")
    check(P.cargo_reward(1,"schakt",4,1.25,restored).reward == 1,"Post-reload extra goods pay the fractional carry delta")
    check(P.remaining_income(1,config.manifest,config.cargo_values,restored) == 16 and ledger == before,"Income projection is pure")
    var bad := {"campaign:v7:cargo:1:kyl":true}
    check(P.cargo_reward(1,"kyl",1,3.0,bad).reward == 3,"Malformed bool waterline is not treated as one credited coin")
