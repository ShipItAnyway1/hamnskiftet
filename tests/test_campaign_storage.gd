extends SceneTree

# Uses real ConfigFile load/store and transaction rollback. The virtual method
# keeps every read/write on this disposable project-local profile.
class StoredGame:
    extends "res://main.gd"
    var fail_store := false
    func _progress_path() -> String:
        return "res://qa/v5/_campaign-test.cfg"
    func _sound(_kind: String, _cargo_type: String = "") -> void:
        pass
    func _refresh_audio_settings() -> void:
        super._refresh_audio_settings()
        if soundscape != null:
            soundscape.set_sfx_enabled(false)
            soundscape.set_music_enabled(false)
    func _store_progress() -> Error:
        if fail_store:
            return ERR_FILE_CANT_WRITE
        return super._store_progress()

const P = preload("res://progression.gd")
const Rules = preload("res://puzzle.gd")
const PROFILE := "res://qa/v5/_campaign-test.cfg"
var failures: Array[String] = []

func check(value: bool, message: String) -> void:
    if not value:
        failures.append(message)
        push_error(message)

func _initialize() -> void:
    _run.call_deferred()

func _dispose(game) -> void:
    game.set_process(false)
    game.generation += 1
    for tween in game.active_tweens:
        if tween.is_valid(): tween.kill()
    await process_frame
    await process_frame
    game.queue_free()
    await process_frame
    await process_frame

func _run() -> void:
    var directory: String = ProjectSettings.globalize_path("res://qa/v5")
    DirAccess.make_dir_recursive_absolute(directory)
    if FileAccess.file_exists(PROFILE):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE))
    var first = StoredGame.new()
    root.add_child(first)
    await process_frame
    check(FileAccess.file_exists(PROFILE),"Real initial profile is written only to isolated test path")
    first.balance = 1000
    for key in ["fleet_kyl","loader","belt","warehouse","parking","parking"]:
        check(first._buy_upgrade(key),"Real stored purchase succeeds")
    var ranks: Dictionary = first.upgrades.duplicate(true)
    first.balance = 777
    first.highest_stage = 3
    first.sound_enabled = false
    first.reward_claims[P.claim_key(1,3)] = true
    first.reward_claims["campaign:v1:win:1"] = true
    first._save_progress()
    var ledger: Dictionary = first.reward_claims.duplicate(true)
    var cfg := ConfigFile.new()
    check(cfg.load(PROFILE) == OK,"Actual ConfigFile is readable")
    check(cfg.get_value("progress","coins") == 777 and cfg.get_value("progress","bays") == 5,"Wallet and purchased docks are persisted")
    check(cfg.get_value("campaign","upgrades") == ranks and cfg.get_value("campaign","highest_stage") == 3,"Ranks and campaign completion are persisted")
    check(cfg.get_value("progress","rewards") == ledger,"Permanent claim ledger is persisted")
    var file_before: String = FileAccess.get_file_as_string(PROFILE)
    var wallet_before: int = int(first.balance)
    first.fail_store = true
    check(not first._buy_upgrade("belt"),"A failed real store rejects the purchase")
    check(first.balance == wallet_before and first.upgrades == ranks and first.unlocked_bays == 5,"Failed persistence rolls back ranks, debit and entitlement")
    check(FileAccess.get_file_as_string(PROFILE) == file_before,"Failed transaction leaves prior saved profile intact")
    first.fail_store = false
    await _dispose(first)

    var second = StoredGame.new()
    root.add_child(second)
    await process_frame
    check(second.balance == 777 and second.upgrades == ranks and second.unlocked_bays == 5,"Fresh scene reloads the real saved wallet/ranks/docks")
    check(second.highest_stage == 3 and second.reward_claims == ledger and not second.sound_enabled,"Fresh scene reloads progression, claim protection and settings")
    check(second.current_stage == 4 and second.state.total == 16 and second.harbor.visible,"Boot preview respects reloaded next campaign stage")
    check(second.state.config.quality == ranks.warehouse and second.state.bays == [-1,-1,-1,-1,-1],"Reloaded upgrades reach the next generated stage")
    await _resume_campaign(second)

    # V4 global fleet ranks migrate into every resource. An obsolete active
    # board is rejected independently from the permanent wallet and receipts.
    var v4 := ConfigFile.new()
    v4.set_value("progress","schema",4)
    v4.set_value("progress","coins",432)
    v4.set_value("progress","bays",4)
    v4.set_value("progress","rewards",{"campaign:v1:1:3":true})
    v4.set_value("campaign","upgrades",{"fleet":7,"loader":2,"belt":1,"warehouse":1,"parking":1})
    v4.set_value("campaign","highest_stage",2)
    v4.set_value("campaign","state",{"campaign":true,"stage":3,"config":{"version":4}})
    v4.set_value("campaign","active_upgrades",{"fleet":7,"loader":2,"belt":1,"warehouse":1,"parking":1})
    check(v4.save(PROFILE) == OK,"V4 migration fixture is isolated")
    var v5 = StoredGame.new()
    root.add_child(v5)
    await process_frame
    check(v5.balance == 432 and v5.highest_stage == 2 and not v5.stage_active and v5.state.total == 14,"V4 incompatible active board refresh keeps wallet and campaign progress")
    for key in P.FLEET_KEYS:
        check(v5.upgrades[key] == 3,"V4 fleet rank7 becomes rank3 for every resource")
    check(v5.upgrades.loader == 2 and v5.upgrades.parking == 1 and v5.reward_claims.has("campaign:v1:1:3"),"V4 general ranks, owned dock and prior receipts survive")
    await _dispose(v5)

    # A legacy owner of five docks must keep both purchases after migration.
    var legacy := ConfigFile.new()
    legacy.set_value("progress","schema",2)
    legacy.set_value("progress","coins",30)
    legacy.set_value("progress","bays",5)
    legacy.set_value("progress","rewards",{"v2:0:1":true})
    check(legacy.save(PROFILE) == OK,"Legacy test fixture is written to isolated profile")
    var migrated = StoredGame.new()
    root.add_child(migrated)
    await process_frame
    check(migrated.upgrades.parking == 2 and migrated.unlocked_bays == 5 and migrated.balance == 30,"Owned legacy docks migrate without repurchase or wallet reset")
    check(migrated.reward_claims.has("v2:0:1") and not migrated._buy_upgrade("parking"),"Legacy receipts survive and max parking cannot charge again")
    await _dispose(migrated)
    DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE))
    if failures.is_empty():
        print("CAMPAIGN_STORAGE_TESTS_OK: isolated real saves/reloads, purchases, failed-write rollback, active driving/loading/departing resume, cargo/value/claims, corrupt snapshot fallback and legacy migration")
        quit(0)
    else:
        print("CAMPAIGN_STORAGE_TESTS_FAILED: ",failures.size())
        quit(1)

func _resume_campaign(game) -> void:
    check(game._start_stage(4),"Loaded profile starts its allowed fourth stage")
    game.set_process(false)
    check(Rules.move_obstacle(game.state,2).ok,"Active saved stage includes a genuinely moved gate")
    game._save_progress()
    var first_id: int = int(game.state.solution[0])
    var second_id: int = int(game.state.solution[1])
    game._dispatch(first_id)
    check(str(game.state.trucks[first_id].status) == "driving","Real dispatch supplies a persisted in-transit state")
    game._save_progress()
    var driving_snapshot: Dictionary = game.state.duplicate(true)
    var proof: Dictionary = load("res://campaign_save.gd").validate(driving_snapshot,game.active_upgrades,game.highest_stage)
    check(not proof.is_empty(),"Actual in-transit campaign state validates before serialization")
    var saved_probe := ConfigFile.new()
    saved_probe.load(PROFILE)
    var stored_proof: Dictionary = load("res://campaign_save.gd").validate(saved_probe.get_value("campaign","state",{}),saved_probe.get_value("campaign","active_upgrades",{}),int(saved_probe.get_value("campaign","highest_stage",0)))
    check(not stored_proof.is_empty(),"ConfigFile rounding cannot invalidate a valid active snapshot")
    var wallet: int = int(game.balance)
    var previous_claims: Dictionary = game.reward_claims.duplicate(true)
    await _dispose(game)
    var driving = StoredGame.new()
    root.add_child(driving)
    await process_frame
    check(driving.stage_active and driving.current_stage == 4 and driving.harbor.visible and driving.paused,"Fresh boot resumes active stage in locked harbor continue mode")
    if not driving.stage_active:
        await _dispose(driving)
        return
    check(str(driving.state.trucks[first_id].status) == "loading" and first_id in driving.state.bays,"In-transit truck safely resumes at its reserved dock")
    check(driving.state.obstacles == driving_snapshot.obstacles,"Gate position survives real active-state reload")
    check(_cargo(driving.state) == _cargo(driving_snapshot) and driving.balance == wallet and driving.reward_claims == previous_claims,"Transit normalization preserves goods, money and receipts")
    check(not driving._buy_upgrade("belt"),"Resume harbor cannot buy upgrades during the saved stage")
    driving._close_harbor()
    var frames := 0
    while int(driving.state.trucks[first_id].loaded) == 0 and frames < 1800:
        await process_frame
        frames += 1
    driving._open_harbor()
    check(int(driving.state.trucks[first_id].loaded) > 0 and str(driving.state.trucks[first_id].status) == "loading","Real belt supplies a partial load to persist")
    driving._save_progress()
    var partial_snapshot: Dictionary = driving.state.duplicate(true)
    var partial_elapsed: float = float(driving.elapsed)
    await _dispose(driving)
    var partial = StoredGame.new()
    root.add_child(partial)
    await process_frame
    check(partial.stage_active and str(partial.state.trucks[first_id].status) == "loading","Loading state survives restart")
    check(partial.state.trucks[first_id].loaded == partial_snapshot.trucks[first_id].loaded and partial.state.trucks[first_id].delivery_value == partial_snapshot.trucks[first_id].delivery_value,"Actual loaded count and accumulated cargo value survive restart")
    check(_cargo(partial.state) == _cargo(partial_snapshot) and is_equal_approx(partial.elapsed,partial_elapsed),"All unconsumed goods and stage time survive restart")
    partial.qa_multiplier = 60
    partial._close_harbor()
    await _wait_done(partial,first_id)
    var first_reward: int = P.delivery_reward(partial.state.trucks[first_id])
    check(partial.balance == wallet+first_reward and partial.reward_claims.has(P.claim_key(4,first_id)),"Resumed real delivery earns its one actual receipt")
    partial._open_harbor()
    partial._save_progress()
    var credited: Dictionary = partial.reward_claims.duplicate(true)
    var earned_wallet: int = int(partial.balance)
    await _dispose(partial)
    var delivered = StoredGame.new()
    root.add_child(delivered)
    await process_frame
    check(delivered.state.delivered == 1 and str(delivered.state.trucks[first_id].status) == "done","Completed truck remains delivered after real reload")
    check(delivered.balance == earned_wallet and delivered.reward_claims == credited,"Newly earned money and claim remain durable")
    # Construct the normal rules state immediately before a departure animation.
    # The loader/controller route itself was exercised above and in the full
    # campaign test; this fixture isolates the resume phase boundary.
    delivered.set_process(false)
    check(Rules.dispatch(delivered.state,second_id).ok,"Next proven route truck reserves a dock")
    Rules.arrive(delivered.state,second_id)
    var ticks := 0
    while str(delivered.state.trucks[second_id].status) == "loading" and ticks < 1200:
        Rules.tick(delivered.state)
        ticks += 1
    check(str(delivered.state.trucks[second_id].status) == "departing","Fixture reaches a valid fully loaded pending departure")
    delivered._save_progress()
    var departing_snapshot: Dictionary = delivered.state.duplicate(true)
    await _dispose(delivered)
    var departing = StoredGame.new()
    root.add_child(departing)
    await process_frame
    check(departing.stage_active and str(departing.state.trucks[second_id].status) == "departing" and second_id in departing.state.bays,"Pending departure resumes with its bay still reserved")
    check(_cargo(departing.state) == _cargo(departing_snapshot) and departing.balance == earned_wallet,"Pending departure has neither lost goods nor an early payment")
    departing.qa_multiplier = 60
    departing._close_harbor()
    await _wait_done(departing,second_id)
    var final_wallet: int = earned_wallet+P.delivery_reward(departing.state.trucks[second_id])
    check(departing.balance == final_wallet and departing.reward_claims.has(P.claim_key(4,second_id)),"Resumed pending departure earns exactly one reward")
    departing._open_harbor()
    departing._save_progress()
    await _dispose(departing)
    var corrupt := ConfigFile.new()
    check(corrupt.load(PROFILE) == OK,"Active saved fixture exists for corruption test")
    var broken: Dictionary = corrupt.get_value("campaign","state")
    broken.trucks[0].loaded = 999
    corrupt.set_value("campaign","state",broken)
    check(corrupt.save(PROFILE) == OK,"Corruption is confined to disposable profile")
    var fallback = StoredGame.new()
    root.add_child(fallback)
    await process_frame
    check(not fallback.stage_active and fallback.current_stage == 4 and fallback.state.delivered == 0,"Invalid snapshot safely returns to a fresh allowed stage")
    check(fallback.balance == final_wallet and fallback.highest_stage == 3 and fallback.reward_claims.has(P.claim_key(4,second_id)),"Snapshot rejection preserves permanent wallet, progression and receipts")
    await _dispose(fallback)

func _cargo(state: Dictionary) -> Dictionary:
    var items: Dictionary = {}
    for cargo in state.feed_left+state.feed_right+state.belt:
        if cargo != null:
            items[int(cargo.id)] = cargo.duplicate(true)
    return items

func _wait_done(game, id: int) -> void:
    var frames := 0
    while str(game.state.trucks[id].status) != "done" and frames < 10000:
        await process_frame
        frames += 1
    check(str(game.state.trucks[id].status) == "done","Resumed animation eventually completes its delivery")
