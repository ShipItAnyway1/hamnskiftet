extends RefCounted
## V7 sound rack. Original local WAVs, independent music/SFX settings, pooled
## one-shot voices and a separate low driving loop. No downloads or services.

static func build(parent: Node) -> SoundRack:
    var rack := SoundRack.new()
    rack.name = "HamnskiftetAudio"
    parent.add_child(rack)
    rack.setup()
    return rack

class SoundRack:
    extends Node

    const DIRECTORY := "res://assets/audio/v7/"
    const CARGO_TYPES := ["kyl","frys","schakt","adr","timmer","bransle"]
    const EFFECTS := ["engine_start","air_brake","dock","gate","click","blocked","purchase","win","rescue","boom_barrier","lose","feed"]
    const MAX_VOICES := 20
    const SFX_BUS := "HamnskiftetSFX"
    static var _bus_users: int = 0
    static var _created_sfx_bus: bool = false
    var music_volume_db: float = -19.0
    var sfx_volume_db: float = -12.0
    var _sfx_enabled: bool = true
    var _music_enabled: bool = true
    var _activity: int = 0
    var _duck_time: float = 0.0
    var _streams: Dictionary = {}
    var _voices: Array[AudioStreamPlayer] = []
    var _cooldowns: Dictionary = {}
    var _music: AudioStreamPlayer
    var _engine: AudioStreamPlayer
    var _boss_layer: AudioStreamPlayer
    var _rescue_loop: AudioStreamPlayer
    var _boss_enabled: bool = false
    var _rescue_active: bool = false
    var _bus_registered: bool = false
    var _shutting_down: bool = false

    func setup() -> void:
        _ensure_sfx_bus()
        for kind in EFFECTS:
            _load_stream(str(kind))
        for kind in CARGO_TYPES:
            _load_stream("load_"+str(kind))
        _load_stream("harbor_groove",true)
        _load_stream("drive_loop",true)
        _load_stream("boss_layer",true)
        _load_stream("rescue_loop",true)
        _music = AudioStreamPlayer.new()
        _music.name = "OriginalHarborGroove"
        _music.volume_db = -60
        _music.stream = _streams.get("harbor_groove")
        add_child(_music)
        _engine = AudioStreamPlayer.new()
        _engine.name = "DrivingEngineBed"
        _engine.bus = SFX_BUS
        _engine.volume_db = -60
        _engine.stream = _streams.get("drive_loop")
        add_child(_engine)
        _boss_layer = AudioStreamPlayer.new()
        _boss_layer.name = "SynchronizedBossRhythm"
        _boss_layer.volume_db = -60
        _boss_layer.stream = _streams.get("boss_layer")
        add_child(_boss_layer)
        _rescue_loop = AudioStreamPlayer.new()
        _rescue_loop.name = "QuietHelicopterRotor"
        _rescue_loop.bus = SFX_BUS
        _rescue_loop.volume_db = -60
        _rescue_loop.stream = _streams.get("rescue_loop")
        add_child(_rescue_loop)
        for _index in range(10):
            _new_voice()
        set_meta("asset_count",_streams.size())
        set_meta("composition_seconds",_music.stream.get_length() if _music.stream != null else 0)
        set_meta("original_audio",true)
        set_process(true)

    func _load_stream(kind: String, loop: bool = false) -> void:
        var path: String = DIRECTORY+kind+".wav"
        var stream: AudioStreamWAV
        # Source checkouts retain the original WAV. Exported builds contain its
        # imported .sample remap, which must be loaded through ResourceLoader.
        if FileAccess.file_exists(path):
            stream = AudioStreamWAV.load_from_file(path)
        elif ResourceLoader.exists(path):
            var imported: Resource = load(path)
            if imported is AudioStreamWAV:
                stream = imported.duplicate()
        else:
            push_warning("Missing local audio: "+path)
            return
        if stream == null:
            return
        if loop:
            stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
            stream.loop_begin = 0
            stream.loop_end = roundi(stream.get_length()*float(stream.mix_rate))
        _streams[kind] = stream

    func _ensure_sfx_bus() -> void:
        if _bus_registered:
            return
        if AudioServer.get_bus_index(SFX_BUS) < 0:
            AudioServer.add_bus()
            var index: int = AudioServer.bus_count-1
            AudioServer.set_bus_name(index,SFX_BUS)
            var limiter := AudioEffectHardLimiter.new()
            limiter.ceiling_db = -3.0
            limiter.pre_gain_db = 0.0
            limiter.release = .10
            AudioServer.add_bus_effect(index,limiter)
            _created_sfx_bus = true
        _bus_users += 1
        _bus_registered = true

    func shutdown() -> void:
        if _shutting_down:
            return
        _shutting_down = true
        _sfx_enabled = false
        _music_enabled = false
        _activity = 0
        _boss_enabled = false
        _rescue_active = false
        _duck_time = 0
        set_process(false)
        # Stop before dropping streams. AudioServer releases a stopped playback
        # at its next mix quantum; rapid headless idle frames need not include one.
        for child in get_children():
            if child is AudioStreamPlayer:
                var player: AudioStreamPlayer = child
                player.stop()
                player.stream = null
                player.bus = "Master"
        _streams.clear()
        _cooldowns.clear()
        if _bus_registered:
            _bus_registered = false
            _bus_users = maxi(0,_bus_users-1)
            if _bus_users == 0 and _created_sfx_bus:
                var index: int = AudioServer.get_bus_index(SFX_BUS)
                if index > 0:
                    AudioServer.remove_bus(index)
                _created_sfx_bus = false

    func _exit_tree() -> void:
        shutdown()

    func _new_voice() -> AudioStreamPlayer:
        var voice := AudioStreamPlayer.new()
        voice.name = "EffectVoice_%02d" % _voices.size()
        voice.bus = SFX_BUS
        add_child(voice)
        _voices.append(voice)
        return voice

    func play_event(kind: String, cargo_type: String = "") -> bool:
        if _shutting_down or not _sfx_enabled:
            return false
        var event: String = kind
        match kind:
            "engine", "start", "drive_start":
                event = "engine_start"
            "depart", "brake":
                event = "air_brake"
            "buy", "upgrade":
                event = "purchase"
            "gate_move":
                event = "gate"
            "heli", "helicopter":
                event = "rescue"
            "barrier", "boom", "barrier_move":
                event = "boom_barrier"
            "loss", "fail":
                event = "lose"
            "load", "resource":
                event = "load_"+(cargo_type if cargo_type in CARGO_TYPES else "kyl")
        if not _streams.has(event):
            return false
        var now: int = Time.get_ticks_msec()
        var cooldown: int = 55 if event.begins_with("load_") else (400 if event == "win" else 35)
        if now-int(_cooldowns.get(event,-100000)) < cooldown:
            return false
        _cooldowns[event] = now
        var selected: AudioStreamPlayer
        var active: int = 0
        for voice in _voices:
            if voice.playing:
                active += 1
            elif selected == null:
                selected = voice
        if selected == null and _voices.size() < MAX_VOICES:
            selected = _new_voice()
        if selected == null:
            # Never cut off a loading sound to make room for another. Only a
            # pathological >20-overlap burst drops its additional one-shot.
            return false
        selected.stream = _streams[event]
        var offset: float = -3.0 if event in ["engine_start","air_brake","gate"] else 0.0
        if event == "win":
            offset = 1.0
        selected.volume_db = sfx_volume_db+offset-minf(3.0,float(active)*.30)
        selected.pitch_scale = 1.0
        selected.play()
        _duck_time = maxf(_duck_time,1.25 if event == "win" else .25)
        return true

    func set_sfx_enabled(enabled: bool) -> void:
        if _shutting_down:
            return
        _sfx_enabled = enabled
        if not enabled:
            for voice in _voices:
                voice.stop()
            if is_instance_valid(_engine):
                _engine.stop()
            if is_instance_valid(_rescue_loop):
                _rescue_loop.stop()
        _cooldowns.clear()

    func set_music_enabled(enabled: bool) -> void:
        if _shutting_down:
            return
        _music_enabled = enabled
        if not enabled and is_instance_valid(_music):
            _music.stop()
            _music.volume_db = -60
            _boss_layer.stop()
            _boss_layer.volume_db = -60

    func set_activity(count: int) -> void:
        if _shutting_down:
            return
        _activity = clampi(count,0,6)

    func set_rescue_active(active: bool) -> void:
        if not _shutting_down:
            _rescue_active = active

    func set_boss(enabled: bool) -> void:
        if not _shutting_down:
            _boss_enabled = enabled

    func _process(delta: float) -> void:
        _duck_time = maxf(0.0,_duck_time-delta)
        if _music_enabled and _music.stream != null:
            if not _music.playing:
                _music.play()
            var target: float = music_volume_db-(3.5 if _duck_time > 0 else 0.0)
            _music.volume_db = move_toward(_music.volume_db,target,delta*45.0)
            if _boss_enabled and _boss_layer.stream != null:
                if not _boss_layer.playing:
                    _boss_layer.volume_db = -60
                    _boss_layer.play(_music.get_playback_position())
                _boss_layer.volume_db = move_toward(_boss_layer.volume_db,-15.0-(3.5 if _duck_time > 0 else 0.0),delta*55.0)
            elif _boss_layer.playing:
                _boss_layer.volume_db = move_toward(_boss_layer.volume_db,-60.0,delta*75.0)
                if _boss_layer.volume_db < -56:
                    _boss_layer.stop()
        if _sfx_enabled and _activity > 0 and _engine.stream != null:
            if not _engine.playing:
                _engine.volume_db = -60
                _engine.play()
            var target: float = -30.0+minf(5.0,float(_activity-1)*1.5)
            _engine.volume_db = move_toward(_engine.volume_db,target,delta*65.0)
        elif _engine.playing:
            _engine.volume_db = move_toward(_engine.volume_db,-60.0,delta*70.0)
            if _engine.volume_db < -56:
                _engine.stop()
        if _sfx_enabled and _rescue_active and _rescue_loop.stream != null:
            if not _rescue_loop.playing:
                _rescue_loop.volume_db = -60
                _rescue_loop.play()
            _rescue_loop.volume_db = move_toward(_rescue_loop.volume_db,-27.0,delta*80.0)
        elif _rescue_loop.playing:
            _rescue_loop.volume_db = move_toward(_rescue_loop.volume_db,-60.0,delta*95.0)
            if _rescue_loop.volume_db < -56:
                _rescue_loop.stop()

    func get_mix_state() -> Dictionary:
        var playing: int = 0
        for voice in _voices:
            if voice.playing:
                playing += 1
        return {"sfx_enabled":_sfx_enabled,"music_enabled":_music_enabled,
            "active_voices":playing,"voice_pool_size":_voices.size(),
            "music_playing":_music.playing,"engine_playing":_engine.playing,
            "boss_enabled":_boss_enabled,"boss_playing":_boss_layer.playing,
            "rescue_active":_rescue_active,"rescue_playing":_rescue_loop.playing,
            "activity":_activity,"assets":_streams.size()}
