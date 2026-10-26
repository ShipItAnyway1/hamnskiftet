extends SceneTree
## Headless: Godot --headless --path truck-depot --script res://tests/test_audio.gd
## Reproducible integration checks, not a perceptual music review.
const Audio = preload("res://audio_manager.gd")
var failures: Array[String] = []

func _initialize() -> void:
    call_deferred("run")

func check(condition: bool, message: String) -> void:
    if not condition:
        failures.append(message)
        push_error(message)

func run() -> void:
    var manager := Audio.build(root)
    manager.set_music_enabled(false)
    check(int(manager.get_mix_state().assets) == 22,"All V7 local audio streams load without editor imports")
    for kind in ["kyl","frys","schakt","adr","timmer","bransle"]:
        check(manager.play_event("load",kind),"Distinct loading sound starts for "+str(kind))
    check(int(manager.get_mix_state().active_voices) == 6,"Six simultaneous cargo sounds do not interrupt one another")
    check(not manager.play_event("load","kyl"),"Immediate repeated identical sound is debounced")
    check(not manager.play_event("not_an_event"),"Unknown events are ignored safely")
    for event in ["engine","brake","buy","gate_move","dock","click","blocked","win"]:
        check(manager.play_event(event),"Game event alias resolves: "+str(event))
    check(int(manager.get_mix_state().active_voices) == 14,"Pool grows for overlapping events instead of replacing existing voices")
    for event in ["rescue","boom_barrier","lose","feed"]:
        check(manager.play_event(event),"New V7 event starts: "+str(event))
    manager.set_sfx_enabled(false)
    check(int(manager.get_mix_state().active_voices) == 0,"SFX mute stops effect voices")
    check(not manager.play_event("click"),"Muted effects do not restart")
    manager.set_sfx_enabled(true)
    manager.set_music_enabled(true)
    manager.set_activity(2)
    manager.set_boss(true)
    manager.set_rescue_active(true)
    for _index in range(4):
        await process_frame
    check(bool(manager.get_mix_state().music_playing),"Original music loop starts independently")
    check(bool(manager.get_mix_state().engine_playing),"Driving activity starts the quiet engine loop")
    check(bool(manager.get_mix_state().boss_playing),"Boss layer runs alongside continuous music")
    check(bool(manager.get_mix_state().rescue_playing),"Helicopter has its own quiet rotor loop")
    manager.set_sfx_enabled(false)
    check(bool(manager.get_mix_state().music_playing),"Muting SFX leaves music playing")
    check(bool(manager.get_mix_state().boss_playing) and not bool(manager.get_mix_state().rescue_playing),"SFX mute stops rotor and preserves the boss music layer")
    manager.set_music_enabled(false)
    manager.set_sfx_enabled(true)
    for _index in range(3):
        await process_frame
    check(not bool(manager.get_mix_state().music_playing),"Music mute stops music")
    check(bool(manager.get_mix_state().engine_playing),"Music mute leaves enabled driving audio working")
    check(not bool(manager.get_mix_state().boss_playing) and bool(manager.get_mix_state().rescue_playing),"Music mute preserves enabled rotor while stopping boss music")
    manager.set_sfx_enabled(false)
    check(not bool(manager.get_mix_state().engine_playing),"SFX mute stops driving loop")
    var music: AudioStreamWAV = manager._streams.harbor_groove
    check(is_equal_approx(music.get_length(),76.8) and music.stereo,"Music is a 76.8-second original stereo composition")
    check(music.loop_mode == AudioStreamWAV.LOOP_FORWARD and music.loop_end == 2457600,"Music loop spans exact full-frame composition")
    check(is_equal_approx(manager._streams.boss_layer.get_length(),music.get_length()),"Boss layer has the exact same composition length")
    var engine: AudioStreamWAV = manager._streams.drive_loop
    check(engine.loop_mode == AudioStreamWAV.LOOP_FORWARD and is_equal_approx(engine.get_length(),2.0),"Driving texture loops over its exact two seconds")
    music = null
    engine = null
    manager.shutdown()
    manager.shutdown()
    check(not manager.play_event("click"),"Shutdown is idempotent and prevents new playback")
    check(AudioServer.get_bus_index("HamnskiftetSFX") < 0,"Final rack shutdown releases its owned audio bus")
    manager.free()
    # AudioServer's stopped playbacks are retired by the audio mix thread, not
    # by SceneTree idle frames. Allow several real 32kHz buffer quanta to drain.
    await create_timer(.10).timeout
    if failures.is_empty():
        print("TRUCK_AUDIO_V7_OK:22 local streams,18 overlapping events,76.8s score+boss,independent rotor/engine/SFX/music and clean shutdown")
    quit(0 if failures.is_empty() else 1)
