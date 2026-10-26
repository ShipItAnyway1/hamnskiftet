extends SceneTree
# Read-only handoff check. Backup is local and excluded from version control.
const P = preload("res://progression.gd")
const Save = preload("res://campaign_save.gd")
func _initialize() -> void:
    var before := ConfigFile.new()
    var current := ConfigFile.new()
    assert(before.load("res://qa/v7/profile-backup/before-v7.cfg") == OK)
    assert(current.load("user://hamnskiftet.cfg") == OK)
    var previous_ranks: Dictionary = P.sanitize(before.get_value("campaign","upgrades",{}))
    previous_ranks.parking = maxi(int(previous_ranks.parking),int(before.get_value("progress","bays",3))-3)
    var ranks: Dictionary = P.sanitize(current.get_value("campaign","upgrades",{}))
    var highest: int = int(current.get_value("campaign","highest_stage",0))
    assert(current.get_value("progress","coins") == before.get_value("progress","coins"),"Existing wallet must survive migration")
    assert(highest == int(before.get_value("campaign","highest_stage",0)),"Completed stages must survive migration")
    assert(ranks == previous_ranks,"Purchased ranks and docks must survive migration")
    for setting in ["sound","music"]:
        assert(current.get_value("settings",setting,true) == before.get_value("settings",setting,true),"Audio preferences must survive migration")
    var previous_claims: Dictionary = before.get_value("progress","rewards",{})
    var claims: Dictionary = current.get_value("progress","rewards",{})
    for key in previous_claims:
        assert(claims.has(key) and claims[key] == previous_claims[key],"Historical receipts must survive migration")
    var state: Dictionary = current.get_value("campaign","state",{})
    var active_ranks: Dictionary = P.sanitize(current.get_value("campaign","active_upgrades",ranks))
    assert(not Save.validate(state,active_ranks,highest).is_empty(),"New active order must validate under V7")
    assert(int(state.config.version) == 7 and int(state.total) > int(state.cargo_total),"Handoff must use new fixed-order rules")
    print("V7_PLAYER_HANDOFF_OK coins=",current.get_value("progress","coins")," highest=",highest," active_stage=",state.stage," trucks=",state.total," goods=",state.cargo_total," ranks_preserved=true historical_claims_preserved=",previous_claims.size()," audio_preferences_preserved=true")
    quit()
