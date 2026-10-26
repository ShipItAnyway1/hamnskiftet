extends RefCounted

const L = preload("res://layout.gd")
const Models = preload("res://models.gd")
const Art = preload("res://ui_assets.gd")
const INK := Color("f3f9ff")
const MUTED := Color("adc8e5")
const PAPER := Color("123b68")
const CREAM := Color("184e81")
const GOLD := Color("ffd34a")
const GOLD_INK := Color("ffe38a")

class ContextLabel:
    extends Label
    var competing_toast: Label
    func _process(_delta: float) -> void:
        visible = not text.strip_edges().is_empty() and (competing_toast == null or not competing_toast.visible)

static func _style(color: Color, radius: int = 20, shadow: int = 0, border: Color = Color.TRANSPARENT) -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = color
    style.set_corner_radius_all(radius)
    style.shadow_color = Color(.015,.045,.13,.68)
    style.shadow_size = shadow
    style.shadow_offset = Vector2(0,5)
    if border.a > 0:
        style.set_border_width_all(2)
        style.border_color = border
    return style

static func panel(_game, parent: Node, pos: Vector2, dimensions: Vector2, color: Color, radius: int = 24, shadow: int = 7) -> Panel:
    var node := Panel.new()
    node.position = pos
    node.size = dimensions
    node.add_theme_stylebox_override("panel",_style(color,radius,shadow,Color("3179ac")))
    parent.add_child(node)
    return node

static func _label(game, parent: Node, text: String, pos: Vector2, dimensions: Vector2, font_size: int = 24, color: Color = INK, bold: bool = false) -> Label:
    var label := Label.new()
    label.text = text
    label.position = pos
    label.size = dimensions
    label.add_theme_font_override("font",game.heading if bold else game.font)
    label.add_theme_font_size_override("font_size",font_size)
    label.add_theme_color_override("font_color",color)
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    parent.add_child(label)
    return label

static func _image(parent: Node, texture: Texture2D, pos: Vector2, dimensions: Vector2) -> TextureRect:
    var image := TextureRect.new()
    image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    image.texture = texture
    image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    image.position = pos
    image.mouse_filter = Control.MOUSE_FILTER_IGNORE
    image.size = dimensions
    parent.add_child(image)
    return image

static func icon(parent: Node, kind: String, pos: Vector2, size: float = 36) -> TextureRect:
    return _image(parent,Models.icon(kind),pos,Vector2.ONE*size)

static func _button(game, parent: Node, text: String, pos: Vector2, dimensions: Vector2, action: Callable, primary: bool = false, image: String = "", font_size: int = 25) -> Button:
    var button := Button.new()
    button.text = text
    button.position = pos
    button.add_theme_font_override("font",game.heading)
    button.add_theme_font_size_override("font_size",font_size)
    var text_color := Color("17335a") if primary else INK
    for property in ["font_color","font_hover_color","font_pressed_color"]:
        button.add_theme_color_override(property,text_color)
    button.add_theme_color_override("font_disabled_color",Color("8aa5bd"))
    var base: Color = GOLD if primary else Color("267bd5")
    for state_name in ["normal","hover","pressed","disabled"]:
        var fill: Color = base
        if state_name == "hover": fill = base.lightened(.09)
        elif state_name == "pressed": fill = base.darkened(.10)
        elif state_name == "disabled": fill = Color("244c70")
        var edge := Color("ffed9b") if primary else Color("66b8ff")
        if state_name == "disabled": edge = Color("396583")
        var box := _style(fill,16,0 if state_name == "pressed" else 5,edge)
        box.shadow_color = Color("091d3b")
        box.shadow_offset = Vector2(0,4)
        box.content_margin_left = 48 if image != "" and text != "" else 12
        box.content_margin_right = 12
        box.set_border_width_all(1)
        box.border_width_top = 3 if state_name != "pressed" else 1
        box.border_width_bottom = 4 if state_name != "pressed" else 1
        button.add_theme_stylebox_override(state_name,box)
    button.add_theme_stylebox_override("focus",_style(Color.TRANSPARENT,16,0,Color("a0efff")))
    button.pressed.connect(action)
    button.size = dimensions
    parent.add_child(button)
    if image != "":
        var icon_size: float = minf(34,dimensions.y-18)
        var x: float = 13 if text != "" else (dimensions.x-icon_size)*.5
        _image(button,Art.icon(image,"17335a" if primary else "f3f9ff"),Vector2(x,(dimensions.y-icon_size)*.5),Vector2.ONE*icon_size)
    return button

static func build(game) -> void:
    var layer := CanvasLayer.new()
    game.add_child(layer)
    game.ui = Control.new()
    game.ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    game.ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
    layer.add_child(game.ui)
    var top := panel(game,game.ui,Vector2(18,14),Vector2(864,96),Color("102f57"),24,8)
    _image(top,Art.icon("truck"),Vector2(15,15),Vector2(62,62))
    _label(game,top,"HAMNSKIFTET",Vector2(91,9),Vector2(235,40),30,INK,true)
    game.title_label = _label(game,top,"Morgonpasset · depå 01",Vector2(93,51),Vector2(235,29),21,MUTED)
    var rescue_button := _button(game,top,"Heli",Vector2(326,19),Vector2(100,56),func(): game.call("_toggle_rescue"),true,"",22)
    rescue_button.tooltip_text = "Rädda en vald lastbil · första gången gratis"
    game.ui.set_meta("rescue_button",rescue_button)
    var mission := _label(game,game.ui,"ORDER  0 / 0 varor",Vector2(23,111),Vector2(854,26),21,Color("b5eafa"),true)
    mission.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    game.ui.set_meta("mission_label",mission)
    var cargo_button := _button(game,top,"Gods",Vector2(437,19),Vector2(117,56),func(): game.call("_open_cargo_legend"),false,"cargo",20)
    cargo_button.tooltip_text = "Godstyper, myntvärde och nya leveranser"
    game.ui.set_meta("cargo_legend_button",cargo_button)
    var wallet := panel(game,top,Vector2(568,13),Vector2(197,67),Color("1c507e"),20,0)
    _image(wallet,Art.icon("coin"),Vector2(11,13),Vector2(43,43))
    game.money_label = _label(game,wallet,"120",Vector2(59,8),Vector2(122,49),31,GOLD_INK,true)
    game.money_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    game.pause_button = _button(game,top,"II",Vector2(783,13),Vector2(62,67),game._toggle_pause,false,"",31)
    game.pause_button.tooltip_text = "Paus och välj depå"

    var bottom := panel(game,game.ui,Vector2(18,1264),Vector2(864,160),Color("102f57"),24,8)
    bottom.name = "TestToolbar"
    bottom.visible = bool(game.get("test_mode"))
    game.ui.set_meta("test_toolbar",bottom)
    game.progress_label = _label(game,bottom,"0 / 64 avgångar",Vector2(22,9),Vector2(280,35),26,INK,true)
    game.cargo_label = _label(game,bottom,"0 / 198 lastade",Vector2(488,14),Vector2(353,29),23,MUTED)
    game.cargo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    var incoming := _label(game,bottom,"",Vector2(314,14),Vector2(158,29),22,Color("79e4ed"),true)
    incoming.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    incoming.visible = false
    game.ui.set_meta("incoming_count",incoming)
    game.progress_bar = ProgressBar.new()
    game.progress_bar.position = Vector2(22,49)
    game.progress_bar.show_percentage = false
    game.progress_bar.add_theme_font_size_override("font_size",1)
    game.progress_bar.add_theme_stylebox_override("background",_style(Color("244d73"),5))
    game.progress_bar.add_theme_stylebox_override("fill",_style(Color("2ed5df"),5))
    game.progress_bar.size = Vector2(820,9)
    bottom.add_child(game.progress_bar)
    # The initial theme notification can grow a ProgressBar to the old font
    # height. Apply the slim track after its theme/minimum size has settled.
    game.progress_bar.set_deferred("size",Vector2(820,9))
    game.undo_button = _button(game,bottom,"Ångra",Vector2(18,77),Vector2(136,64),game._undo,false,"undo",23)
    _button(game,bottom,"Hamn",Vector2(164,77),Vector2(158,64),func(): game.call("_open_harbor"),true,"harbor",24)
    game.dock_button = _button(game,bottom,"Kajer 3 / 5",Vector2(332,77),Vector2(172,64),game._open_shop,false,"dock",22)
    game.speed_button = _button(game,bottom,"1×",Vector2(514,77),Vector2(64,64),game._toggle_speed,false,"",25)
    _button(game,bottom,"",Vector2(588,77),Vector2(56,64),func(): game._change_zoom(-.15),false,"minus")
    _button(game,bottom,"",Vector2(652,77),Vector2(56,64),func(): game._change_zoom(.15),false,"plus")
    var fit := _button(game,bottom,"Hela",Vector2(718,77),Vector2(128,64),game._toggle_view,false,"fit",24)
    fit.tooltip_text = "Växla mellan närvy och hela hamnen"
    game.ui.set_meta("view_button",fit)
    game.status_label = ContextLabel.new()
    game.status_label.position = Vector2(42,1216)
    game.status_label.size = Vector2(816,33)
    game.status_label.add_theme_font_override("font",game.font)
    game.status_label.add_theme_font_size_override("font_size",23)
    game.status_label.add_theme_color_override("font_color",INK)
    game.status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    game.ui.add_child(game.status_label)
    game.status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    game.status_label.add_theme_stylebox_override("normal",_style(Color(.04,.15,.28,.95),16,3))
    game.toast_label = _label(game,game.ui,"",Vector2(73,1204),Vector2(754,50),22,Color("f3f9ff"),true)
    game.toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    game.toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    game.toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    var toast := _style(Color("0c3156"),18,5,Color("36cbe7"))
    toast.content_margin_left = 22
    toast.content_margin_right = 22
    game.toast_label.add_theme_stylebox_override("normal",toast)
    game.toast_label.visible = false
    game.status_label.competing_toast = game.toast_label
    _modal(game)
    _shop(game)
    _cargo_legend(game)

static func _backdrop(parent: Node) -> Control:
    var backdrop := Control.new()
    backdrop.size = Vector2(900,1440)
    parent.add_child(backdrop)
    var dim := ColorRect.new()
    dim.color = Color(.015,.045,.12,.83)
    dim.size = backdrop.size
    backdrop.add_child(dim)
    return backdrop

static func _modal(game) -> void:
    game.modal = _backdrop(game.ui)
    var card := panel(game,game.modal,Vector2(90,288),Vector2(720,846),PAPER,36,22)
    game.modal.set_meta("card",card)
    var artwork := _image(card,Art.harbor_card(),Vector2(204,20),Vector2(312,153))
    game.modal.set_meta("harbor_art",artwork)
    game.modal_title = _label(game,card,"En liten paus",Vector2(30,190),Vector2(660,66),42,INK,true)
    game.modal_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    game.modal_text = _label(game,card,"",Vector2(47,271),Vector2(626,90),26,MUTED)
    game.modal_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    game.modal_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    var library := Control.new()
    library.position = Vector2(48,375)
    library.size = Vector2(624,80)
    library.mouse_filter = Control.MOUSE_FILTER_IGNORE
    card.add_child(library)
    game.modal.set_meta("cargo_library",library)
    for i in range(L.COLORS.size()):
        var kind: String = str(L.COLORS.keys()[i])
        var x: float = float(i)*104
        icon(library,kind,Vector2(x+30,0),44)
        var caption: String = "ADR" if kind == "adr" else str(L.NAMES[kind])
        var name_label := _label(game,library,caption,Vector2(x,48),Vector2(104,30),22,INK,true)
        name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    var reward := _label(game,card,"",Vector2(48,375),Vector2(624,88),27,GOLD_INK,true)
    reward.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    reward.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    reward.add_theme_constant_override("line_spacing",0)
    reward.add_theme_stylebox_override("normal",_style(Color("1b547f"),23,3,Color("5c98bc")))
    reward.visible = false
    game.modal.set_meta("win_reward",reward)
    game.modal_action = _button(game,card,"Fortsätt spela",Vector2(34,475),Vector2(652,72),game._modal_continue,true,"play",29)
    var depot_heading := _label(game,card,"VÄLJ DEPÅ",Vector2(35,576),Vector2(650,30),22,MUTED,true)
    var depot_first := _button(game,card,"01 · 64 lastbilar",Vector2(34,620),Vector2(318,62),func(): game._new_level(0),false,"",25)
    var depot_second := _button(game,card,"02 · 88 lastbilar",Vector2(368,620),Vector2(318,62),func(): game._new_level(1),false,"",25)
    game.level_buttons.append(depot_first)
    game.level_buttons.append(depot_second)
    var restart := _button(game,card,"Börja om",Vector2(34,716),Vector2(206,62),func(): game.call("_restart_current"),false,"restart",25)
    game.sound_button = _button(game,card,"Ljudeffekter",Vector2(258,716),Vector2(206,62),game._toggle_sound,false,"sound",23)
    var music := _button(game,card,"Musik",Vector2(482,716),Vector2(204,62),func(): game.call("_toggle_music"),false,"music",23)
    game.ui.set_meta("music_toggle",music)
    var pause_only: Array[Control] = [depot_heading,depot_first,depot_second,restart,game.sound_button,music]
    game.modal.set_meta("pause_only",pause_only)
    game.modal.set_meta("pause_actions",[restart,game.sound_button,music])
    # This group is independent of the legacy test controls above.
    var help := Control.new()
    help.name = "PauseHelp"
    help.position = Vector2(34,450)
    help.size = Vector2(652,362)
    card.add_child(help)
    var undo := _button(game,help,"Ångra · 100 guld",Vector2.ZERO,Vector2(318,70),func(): game.call("_paid_undo"),false,"undo",24)
    var rescue := _button(game,help,"Heli · 1 gratis",Vector2(334,0),Vector2(318,70),func(): game.call("_toggle_rescue"),true,"",24)
    var help_balance := _label(game,help,"",Vector2(0,77),Vector2(652,50),21,GOLD_INK,true)
    help_balance.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    restart.reparent(help)
    restart.position = Vector2(0,134)
    restart.size = Vector2(652,64)
    restart.text = "Börja om · gratis"
    game.sound_button.reparent(help)
    game.sound_button.position = Vector2(0,214)
    game.sound_button.size = Vector2(318,62)
    music.reparent(help)
    music.position = Vector2(334,214)
    music.size = Vector2(318,62)
    var test_toggle := _button(game,help,"Testläge: av",Vector2(0,297),Vector2(318,56),func(): game.call("_toggle_test_mode"),false,"",22)
    var harbor_button := _button(game,help,"Till hamnen",Vector2(334,297),Vector2(318,56),func(): game.call("_open_harbor"),false,"harbor",22)
    game.modal.set_meta("pause_help",help)
    game.modal.set_meta("paid_undo",undo)
    game.modal.set_meta("rescue_button",rescue)
    game.modal.set_meta("help_balance",help_balance)
    game.modal.set_meta("test_toggle",test_toggle)
    game.modal.set_meta("pause_harbor",harbor_button)
    game.modal.set_meta("pause_only",[depot_heading,depot_first,depot_second,help])
    game.modal.set_meta("pause_actions",[])
    game.modal.visible = false

static func configure_modal(game, victory: bool) -> void:
    var card: Control = game.modal.get_meta("card")
    var help: Control = game.modal.get_meta("pause_help")
    var art: TextureRect = game.modal.get_meta("harbor_art")
    help.visible = not victory
    if not victory:
        card.position = Vector2(90,290)
        card.size = Vector2(720,860)
        art.position = Vector2(270,18)
        art.size = Vector2(180,96)
        game.modal_title.position = Vector2(30,130)
        game.modal_text.position = Vector2(47,208)
        game.modal_action.position = Vector2(34,340)
        game.modal.get_meta("cargo_library").visible = false
    else:
        game.modal_title.position = Vector2(30,190)
        game.modal_text.position = Vector2(47,271)
        game.modal_action.position = Vector2(34,475)
    # Legacy depot chooser belongs only to explicit test mode.
    var legacy: Array = game.modal.get_meta("pause_only",[])
    for index in range(mini(3,legacy.size())):
        legacy[index].visible = false
    refresh_support(game)

static func refresh_support(game) -> void:
    if not is_instance_valid(game.ui): return
    var testing := bool(game.get("test_mode"))
    game.ui.get_meta("test_toolbar").visible = testing
    var state: Dictionary = game.get("state") if game.get("state") is Dictionary else {}
    var used := bool(state.get("rescue_used",false))
    var busy := bool(game.get("rescue_busy"))
    var free_bay: bool = -1 in state.get("bays",[])
    var mode := bool(game.get("helicopter_mode"))
    var price := "50 guld" if used else "gratis"
    var top: Button = game.ui.get_meta("rescue_button")
    top.text = "Välj bil" if mode else ("Heli\n50 guld" if used else "Heli\nGratis")
    top.add_theme_font_size_override("font_size",18)
    top.tooltip_text = "Vänd en lastbil 180° · %s · 1 gratis per runda, sedan 50 guld" % price
    top.disabled = busy or not free_bay or bool(game.get("won")) or (used and int(game.get("balance")) < 50)
    if game.modal.has_meta("pause_help"):
        var button: Button = game.modal.get_meta("rescue_button")
        button.text = "Heli · "+price
        button.disabled = busy or not free_bay or (used and int(game.get("balance")) < 50)
        var undo: Button = game.modal.get_meta("paid_undo")
        var history: Array = game.get("history") if game.get("history") is Array else []
        undo.text = "Ångra · gratis" if testing else "Ångra · 100 guld"
        undo.tooltip_text = "Gratis återställning i testläge" if testing else "Återställ senaste draget · 100 guld"
        undo.disabled = history.is_empty() or (not testing and int(game.get("balance")) < 100) or busy
        game.modal.get_meta("help_balance").text = "Ditt saldo: %d guld\nHeli vänder bilen 180° · 1 gratis/runda, sedan 50 guld" % int(game.get("balance"))
        game.modal.get_meta("test_toggle").text = "Testläge: på" if testing else "Testläge: av"
        game.modal.get_meta("pause_harbor").disabled = bool(game.get("stage_active"))

class VictorySpark:
    extends Control
    var elapsed := 0.0
    var papers: Array[Dictionary] = []

    func _ready() -> void:
        mouse_filter = Control.MOUSE_FILTER_IGNORE
        process_mode = Node.PROCESS_MODE_ALWAYS
        var rng := RandomNumberGenerator.new()
        rng.seed = 218341
        var palette := [Color("ffd34a"),Color("42dcf4"),Color("ff777c"),Color("b898ff"),Color("57e7ae")]
        for index in range(26):
            papers.append({"velocity":Vector2(rng.randf_range(-330,330),rng.randf_range(-550,-190)),
                "delay":rng.randf_range(0,.16),"angle":rng.randf_range(-PI,PI),
                "spin":rng.randf_range(-7,7),"phase":rng.randf_range(0,TAU),
                "dimensions":Vector2(rng.randf_range(7,13),rng.randf_range(12,20)),
                "color":palette[index%palette.size()]})

    func _process(delta: float) -> void:
        elapsed += delta
        if elapsed >= 2.12:
            queue_free()
            return
        queue_redraw()

    func _draw() -> void:
        var center := size*Vector2(.5,.34)
        var glow := maxf(0,1.0-elapsed/1.05)
        if glow > 0:
            draw_circle(center,42.0+elapsed*55.0,Color(1,.78,.23,glow*.12))
            draw_arc(center,50.0+elapsed*72.0,0,TAU,48,Color(1,.87,.43,glow*.55),2.0,true)
            for ray in range(8):
                var direction := Vector2.from_angle(TAU*float(ray)/8.0+.15)
                draw_line(center+direction*(66+elapsed*50),center+direction*(79+elapsed*64),Color(1,.91,.58,glow*.75),3.0,true)
        for paper in papers:
            var t := elapsed-float(paper.delay)
            if t < 0:
                continue
            var at: Vector2 = center+paper.velocity*t+Vector2(0,350*t*t)
            var alpha := 1.0-clampf((t-1.24)/.76,0,1)
            var shade: Color = paper.color
            shade.a *= alpha
            var flip := maxf(.18,absf(cos(t*8.0+float(paper.phase))))
            draw_set_transform(at,float(paper.angle)+float(paper.spin)*t,Vector2(flip,1))
            draw_rect(Rect2(-paper.dimensions*.5,paper.dimensions),shade)
        draw_set_transform(Vector2.ZERO,0,Vector2.ONE)

static func celebrate(parent: Control) -> void:
    # Independent of game speed/pause; no modal, input target or audio state.
    if not is_instance_valid(parent) or not parent.is_inside_tree():
        return
    var previous := parent.get_node_or_null("VictorySpark")
    if previous != null:
        parent.remove_child(previous)
        previous.queue_free()
    var spark := VictorySpark.new()
    spark.name = "VictorySpark"
    spark.z_index = 100
    spark.mouse_filter = Control.MOUSE_FILTER_IGNORE
    spark.size = parent.size if parent.size.x > 1 and parent.size.y > 1 else Vector2(900,1440)
    parent.add_child(spark)

static func _shop(game) -> void:
    game.shop = _backdrop(game.ui)
    var card := panel(game,game.shop,Vector2(58,264),Vector2(784,912),PAPER,36,24)
    _label(game,card,"DIN HAMN",Vector2(32,24),Vector2(620,29),22,GOLD_INK,true)
    _label(game,card,"Lite mer plats.",Vector2(30,61),Vector2(660,60),43,INK,true)
    _label(game,card,"En ny kaj för nästa stora leverans.",Vector2(32,127),Vector2(713,37),25,MUTED)
    var close := _button(game,card,"",Vector2(690,26),Vector2(58,58),game._close_shop,false,"close")
    close.tooltip_text = "Stäng kajbutiken"
    var wallet := panel(game,card,Vector2(30,180),Vector2(724,62),Color("1b547f"),20,0)
    _image(wallet,Art.icon("coin"),Vector2(15,11),Vector2(40,40))
    game.shop_balance = _label(game,wallet,"120 spelmynt",Vector2(69,11),Vector2(630,40),28,GOLD_INK,true)
    for extra in range(2):
        var bay: int = 3+extra
        var tile := panel(game,card,Vector2(30+float(extra)*372,274),Vector2(352,382),Color("1b4c7d"),25,5)
        _label(game,tile,"KAJ 04" if extra == 0 else "KAJ 05",Vector2(20,15),Vector2(300,34),25,INK,true)
        _image(tile,Art.harbor_card(extra),Vector2(14,53),Vector2(324,154))
        var description := _label(game,tile,"En extra plats för\ndina leveranser.",Vector2(21,211),Vector2(311,65),25,MUTED)
        description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        var mark := _image(tile,Art.icon("coin"),Vector2(20,282),Vector2(31,31))
        game.shop_marks.append(mark)
        var price := _label(game,tile,"80 mynt" if extra == 0 else "140 mynt",Vector2(61,277),Vector2(266,39),29,GOLD_INK,true)
        game.shop_prices.append(price)
        var buy := _button(game,tile,"Öppna kaj",Vector2(17,324),Vector2(318,56),func(): game._buy_dock(bay),true,"",25)
        game.shop_buttons.append(buy)
    _label(game,card,"En utbyggnad att behålla.",Vector2(32,695),Vector2(720,39),28,INK,true)
    _label(game,card,"Kajerna finns kvar när du börjar om eller byter depå.",Vector2(32,741),Vector2(720,35),23,MUTED)
    _label(game,card,"Leveranser ger spelmynt. Inga riktiga köp.",Vector2(32,785),Vector2(720,33),23,MUTED)
    _button(game,card,"Tillbaka till hamnen",Vector2(30,840),Vector2(724,54),game._close_shop,false,"",25)
    game.shop.visible = false


static func _cargo_legend(game) -> void:
    var legend := _backdrop(game.ui)
    legend.name = "CargoValueLegend"
    legend.z_index = 12
    var card := panel(game,legend,Vector2(90,190),Vector2(720,1016),Color("123b68"),32,20)
    _image(card,Art.icon("coin"),Vector2(26,26),Vector2(55,55))
    _label(game,card,"Gods & spelmynt",Vector2(96,28),Vector2(590,51),37,INK,true)
    var description := _label(game,card,"Varje vara har ett myntvärde.
Mynten kommer när en full lastbil kör iväg.",Vector2(28,101),Vector2(664,85),25,MUTED)
    description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    var values: Dictionary = {}
    var locks: Dictionary = {}
    var cards: Dictionary = {}
    var symbols: Dictionary = {}
    var base_values := {"schakt":1,"timmer":2,"kyl":3,"frys":4,"adr":6,"bransle":8}
    var kinds := ["kyl","frys","schakt","timmer","adr","bransle"]
    for index in range(kinds.size()):
        var kind := str(kinds[index])
        var tile := panel(game,card,Vector2(27+float(index%2)*344,214+float(floori(float(index)/2.0))*205),Vector2(322,187),Color("1a4b7b"),20,3)
        var stripe := ColorRect.new()
        stripe.position = Vector2(15,16)
        stripe.size = Vector2(4,62)
        stripe.color = Color(str(L.COLORS[kind]))
        stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
        tile.add_child(stripe)
        var symbol := icon(tile,kind,Vector2(28,14),61)
        var title := _label(game,tile,str(L.NAMES[kind]),Vector2(104,20),Vector2(205,39),27,INK,true)
        title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
        var value := _label(game,tile,"%d mynt / vara" % int(base_values[kind]),Vector2(20,91),Vector2(285,40),27,GOLD_INK,true)
        var status := _label(game,tile,"Med på den här banan",Vector2(20,143),Vector2(285,29),20,MUTED)
        if kind in ["adr","bransle"]:
            status.text = "Låses upp på bana %d" % (3 if kind == "adr" else 5)
            symbol.modulate = Color(.62,.70,.82,.64)
        values[kind] = value
        locks[kind] = status
        cards[kind] = tile
        symbols[kind] = symbol
    var purpose := _label(game,card,"Spelmynt bygger ut din hamn mellan banorna.",Vector2(28,846),Vector2(664,42),23,Color("a8efd8"),true)
    purpose.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    var close := _button(game,card,"Tillbaka till skiftet",Vector2(28,919),Vector2(664,70),func(): game.call("_close_cargo_legend"),true,"play",27)
    legend.set_meta("values",values)
    legend.set_meta("locks",locks)
    legend.set_meta("cards",cards)
    legend.set_meta("symbols",symbols)
    legend.set_meta("subtitle",description)
    legend.set_meta("purpose",purpose)
    legend.set_meta("close",close)
    legend.set_meta("card",card)
    game.ui.set_meta("cargo_legend",legend)
    legend.visible = false
