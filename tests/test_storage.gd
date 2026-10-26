extends SceneTree

# Real save/load methods with an isolated file, never the player's profile.
class StorageGame:
    extends "res://main.gd"
    func _ready() -> void:
        pass
    func _process(_delta: float) -> void:
        pass
    func _progress_path() -> String:
        return "res://qa/_storage-regression.cfg"

var failed := false

func check(value: bool, message: String) -> void:
    if not value:
        failed = true
        push_error(message)

func fixture():
    var game := StorageGame.new()
    root.add_child(game)
    game.sound_button = Button.new()
    game.add_child(game.sound_button)
    return game

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var game = fixture()
    var path: String = ProjectSettings.globalize_path(game._progress_path())
    DirAccess.make_dir_recursive_absolute(path.get_base_dir())
    if FileAccess.file_exists(path):
        DirAccess.remove_absolute(path)
    game.balance = 37
    game.unlocked_bays = 4
    game.sound_enabled = false
    game.reward_claims = {"v2:0:63":true,"v2:win:0":true}
    game._save_progress()
    game.free()
    var resumed = fixture()
    resumed._load_progress()
    check(resumed.balance == 37 and resumed.unlocked_bays == 4,"Cold start restores exact purchased state and remaining money")
    check(not resumed.sound_enabled and resumed.reward_claims == {"v2:0:63":true,"v2:win:0":true},"Cold start preserves claimed rewards and sound preference")
    resumed.balance = 0
    resumed.unlocked_bays = 5
    resumed._save_progress()
    resumed.free()
    var spent = fixture()
    spent._load_progress()
    check(spent.balance == 0 and spent.unlocked_bays == 5,"Spent balance stays zero on restart; starter money is never granted again")
    spent.free()
    var old := ConfigFile.new()
    old.set_value("progress","coins",11)
    old.save(path)
    var migrated = fixture()
    migrated._load_progress()
    check(migrated.balance == 120 and migrated.unlocked_bays == 3,"Existing small profile migrates to a usable one-time starter balance")
    migrated.free()
    old = ConfigFile.new()
    old.set_value("progress","coins",900)
    old.save(path)
    var established = fixture()
    established._load_progress()
    check(established.balance == 900,"Migration preserves a larger existing earned balance")
    established.free()
    DirAccess.remove_absolute(path)
    print("TRUCK_STORAGE_TESTS_OK: real file roundtrip, permanent docks, spent balance, reward claims and one-time migration" if not failed else "TRUCK_STORAGE_TESTS_FAILED")
    quit(1 if failed else 0)
