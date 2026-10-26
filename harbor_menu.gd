extends RefCounted

# Campaign hub. All purchases and stage transitions remain in the controller.
const UI = preload("res://interface.gd")
const Art = preload("res://ui_assets.gd")
const Progression = preload("res://progression.gd")
const Layout = preload("res://layout.gd")
const Models = preload("res://models.gd")
const WHITE := Color("f3faff")
const MUTED := Color("bdd4ef")
const TITLES := {"fleet_kyl":"Kylbilar","fleet_frys":"Frysbilar","fleet_schakt":"Schaktbilar","fleet_timmer":"Timmerbilar","fleet_adr":"ADR-bilar","fleet_bransle":"Tankbilar","loader":"Snabbare lastning","belt":"Snabbare varuband","warehouse":"Finare varor","parking":"Fler lastplatser","campaign":"Nya leveranser"}
const COLORS := {"fleet":"285fd0","loader":"7650c7","belt":"077eac","warehouse":"c94e74","parking":"23866c","campaign":"344e91"}

class HarborView:
    extends Control
    func select_tab(tab_name: String) -> void:
        var selected := tab_name.to_lower()
        if selected == "hamnen": selected = "harbor"
        if selected == "lastbilar": selected = "trucks"
        var pages: Dictionary = get_meta("tab_panels",{})
        if not pages.has(selected): return
        var tabs: Dictionary = get_meta("tab_buttons",{})
        for key in pages:
            pages[key].visible = key == selected
            tabs[key].set_pressed_no_signal(key == selected)
        # Native Button text can retain an empty shaped line after its first
        # hidden-page layout. Rebuild that caption when the page becomes visible.
        for card in pages[selected].get_children():
            if card.has_meta("buy"):
                var button: Button = card.get_meta("buy")
                var caption := button.text
                button.text = ""
                button.text = caption
        set_meta("selected_tab",selected)
    func set_type_locked(kind: String, locked: bool, unlock_stage: int) -> void:
        var all_cards: Dictionary = get_meta("upgrade_cards",{})
        var key := "fleet_"+kind
        if not all_cards.has(key): return
        var card: Control = all_cards[key]
        card.get_meta("lock").visible = locked
        card.get_meta("lock").text = "Bana %d" % unlock_stage
        card.get_meta("price").visible = not locked
        card.get_meta("coin").visible = not locked
        if locked:
            card.get_meta("buy").disabled = true
            card.get_meta("buy").text = "Låst"

static func _label(game, parent: Node, text: String, position: Vector2, dimensions: Vector2, font_size: int, color := WHITE, bold := false) -> Label:
    return UI._label(game,parent,text,position,dimensions,font_size,color,bold)

static func _panel(parent: Node, position: Vector2, dimensions: Vector2, color: Color, radius := 24) -> Panel:
    var panel := Panel.new()
    panel.position = position
    panel.size = dimensions
    var box := UI._style(color,radius,8,color.lightened(.18))
    box.shadow_color = Color(.012,.027,.09,.72)
    box.shadow_offset = Vector2(0,6)
    box.set_border_width_all(1)
    box.border_width_top = 3
    panel.add_theme_stylebox_override("panel",box)
    parent.add_child(panel)
    return panel

static func _artwork(parent: Node, texture: Texture2D, position: Vector2, dimensions: Vector2) -> TextureRect:
    return UI._image(parent,texture,position,dimensions)

static func build(game) -> Control:
    var menu := HarborView.new()
    menu.name = "HarborCampaign"
    menu.size = Vector2(900,1440)
    menu.mouse_filter = Control.MOUSE_FILTER_STOP
    var background := TextureRect.new()
    background.texture = Art.menu_background()
    background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    background.stretch_mode = TextureRect.STRETCH_SCALE
    background.size = menu.size
    background.mouse_filter = Control.MOUSE_FILTER_IGNORE
    menu.add_child(background)
    _artwork(menu,Art.icon("truck"),Vector2(29,28),Vector2(67,67))
    var logo := _label(game,menu,"HAMNSKIFTET",Vector2(112,24),Vector2(494,49),38,WHITE,true)
    logo.add_theme_color_override("font_shadow_color",Color("071c3c"))
    logo.add_theme_constant_override("shadow_offset_y",3)
    _label(game,menu,"DIN HAMN. NÄSTA STORA LEVERANS.",Vector2(114,77),Vector2(490,24),16,Color("77d5f1"),true)
    var wallet := _panel(menu,Vector2(651,31),Vector2(220,65),Color("133f72"),22)
    _artwork(wallet,Art.icon("coin"),Vector2(10,9),Vector2(47,47))
    var balance := _label(game,wallet,"120",Vector2(63,6),Vector2(139,49),35,Color("ffe891"),true)
    balance.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    menu.set_meta("balance",balance)

    var hero := _panel(menu,Vector2(28,125),Vector2(844,318),Color("185881"),28)
    var artwork := TextureRect.new()
    artwork.texture = Art.harbor_card(1)
    artwork.position = Vector2(3,3)
    artwork.size = Vector2(838,312)
    artwork.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    artwork.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
    artwork.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var shader := Shader.new()
    shader.code = """shader_type canvas_item;
varying vec2 panel_uv;
void vertex(){ panel_uv=VERTEX/vec2(838.0,312.0); }
void fragment(){
    vec2 p=panel_uv*vec2(838.0,312.0); vec2 half_size=vec2(419.0,156.0);
    vec2 q=abs(p-half_size)-(half_size-vec2(25.0));
    float d=length(max(q,vec2(0.0)))+min(max(q.x,q.y),0.0)-25.0;
    vec4 source=texture(TEXTURE,UV);
    float shade=smoothstep(0.25,0.94,panel_uv.y)*0.92;
    COLOR=vec4(mix(source.rgb,vec3(0.025,0.075,0.17),shade),source.a*(1.0-smoothstep(-1.0,1.0,d)));
}
"""
    var material := ShaderMaterial.new()
    material.shader = shader
    artwork.material = material
    hero.add_child(artwork)
    menu.set_meta("artwork",artwork)
    var stage_pill := _panel(hero,Vector2(22,20),Vector2(160,40),Color("0c376a"),14)
    _label(game,stage_pill,"DIN HAMN VÄXER",Vector2(13,8),Vector2(139,25),15,Color("a3eaff"),true)
    var stage := _label(game,hero,"Bana 1 · Morgonskiftet",Vector2(25,224),Vector2(793,43),34,WHITE,true)
    var subtitle := _label(game,hero,"Lasta, leverera och bygg vidare på din hamn.",Vector2(27,273),Vector2(790,31),21,Color("cdeaff"))
    menu.set_meta("stage",stage)
    menu.set_meta("subtitle",subtitle)
    var tabs: Dictionary = {}
    var pages: Dictionary = {}
    for index in range(2):
        var key := "harbor" if index == 0 else "trucks"
        var page := Control.new()
        page.position = Vector2(0,535)
        page.size = Vector2(900,690)
        page.mouse_filter = Control.MOUSE_FILTER_IGNORE
        menu.add_child(page)
        pages[key] = page
        var tab := UI._button(game,menu,"Hamnen" if index == 0 else "Lastbilar",Vector2(28+float(index)*432,465),Vector2(412,56),func(): menu.select_tab(key),false,"harbor" if index == 0 else "truck",27)
        tab.toggle_mode = true
        tab.add_theme_stylebox_override("pressed",UI._style(Color("38cce7"),16,4,Color("9bf4ff")))
        tab.add_theme_color_override("font_pressed_color",Color("12365a"))
        tabs[key] = tab
    menu.set_meta("tab_buttons",tabs)
    menu.set_meta("tab_panels",pages)
    var cards: Dictionary = {}
    var effects: Dictionary = {}
    var next_effects: Dictionary = {}
    var prices: Dictionary = {}
    var buttons: Dictionary = {}
    for key_value in Progression.KEYS:
        var key := str(key_value)
        var fleet := key.begins_with("fleet_")
        var index: int = Progression.FLEET_KEYS.find(key) if fleet else Progression.GENERAL_KEYS.find(key)
        var page: Control = pages["trucks" if fleet else "harbor"]
        var card := _upgrade_card(game,page,key,Vector2(28+float(index%2)*432,float(floori(float(index)/2.0))*234))
        cards[key] = card
        effects[key] = card.get_meta("effect")
        next_effects[key] = card.get_meta("next_effect")
        prices[key] = card.get_meta("price")
        buttons[key] = card.get_meta("buy")
    var campaign := _upgrade_card(game,pages.harbor,"campaign",Vector2(28,474))
    campaign.size = Vector2(844,214)
    campaign.get_meta("title").position = Vector2(210,17)
    campaign.get_meta("title").size = Vector2(530,38)
    campaign.get_meta("title").add_theme_font_size_override("font_size",28)
    campaign.get_meta("illustration").position = Vector2(18,40)
    campaign.get_meta("illustration").size = Vector2(176,146)
    campaign.get_meta("rank").position = Vector2(697,23)
    campaign.get_meta("rank").size = Vector2(126,27)
    campaign.get_meta("effect").position = Vector2(210,69)
    campaign.get_meta("effect").size = Vector2(610,35)
    campaign.get_meta("next_effect").position = Vector2(210,110)
    campaign.get_meta("next_effect").size = Vector2(610,43)
    campaign.get_meta("status_mark").position = Vector2(210,168)
    campaign.get_meta("status").position = Vector2(248,166)
    campaign.get_meta("status").size = Vector2(566,33)
    cards.campaign = campaign
    effects.campaign = campaign.get_meta("effect")
    next_effects.campaign = campaign.get_meta("next_effect")
    prices.campaign = campaign.get_meta("price")
    buttons.campaign = campaign.get_meta("buy")
    menu.set_meta("upgrade_cards",cards)
    menu.set_meta("effects",effects)
    menu.set_meta("next_effects",next_effects)
    menu.set_meta("prices",prices)
    menu.set_meta("buttons",buttons)
    menu.select_tab("harbor")
    menu.set_type_locked("adr",true,3)
    menu.set_type_locked("bransle",true,5)
    var play := UI._button(game,menu,"Spela bana 1",Vector2(28,1258),Vector2(844,86),func(): game.call("_start_stage"),true,"play",34)
    menu.set_meta("play",play)
    var resume := UI._button(game,menu,"Tillbaka till pågående bana",Vector2(154,1361),Vector2(592,54),func(): game.call("_close_harbor"),false,"",23)
    menu.set_meta("resume",resume)
    return menu

static func _upgrade_card(game, parent: Control, key: String, position: Vector2) -> Panel:
    var fleet := key.begins_with("fleet_")
    var kind := key.trim_prefix("fleet_") if fleet else ""
    var base := Color(str(Layout.COLORS[kind])).darkened(.55) if fleet else Color(str(COLORS[key]))
    var card := _panel(parent,position,Vector2(412,222),base,22)
    var title := _label(game,card,str(TITLES[key]),Vector2(55 if fleet else 17,12),Vector2(260 if fleet else 294,34),24,WHITE,true)
    if fleet:
        _artwork(card,Models.icon(kind),Vector2(16,14),Vector2(29,29))
        card.set_meta("cargo_kind",kind)
    var rank := _label(game,card,"0 / %d" % Progression.max_rank(key),Vector2(322,17),Vector2(73,27),17,Color("dcecff"),true)
    rank.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    var illustration := _artwork(card,Art.upgrade_illustration(key),Vector2(0,42),Vector2(156,132))
    var current_text := Progression.effect_text(key,0)
    var next_text := "→ "+Progression.next_effect_text(key,0)
    if key == "campaign":
        rank.text = "KAMPANJ"
        rank.position.x = 294
        rank.size.x = 100
        current_text = "ADR på bana 3"
        next_text = "Bränsle på bana 5"
    var effect := _label(game,card,current_text,Vector2(159,56),Vector2(236,35),20,Color("dcecff"))
    effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    var next_effect := _label(game,card,next_text,Vector2(159,98),Vector2(236,56),22,WHITE,true)
    next_effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    var coin := _artwork(card,Art.icon("coin"),Vector2(17,180),Vector2(28,28))
    var price := _label(game,card,str(Progression.cost(key,0)),Vector2(53,176),Vector2(153,35),26,Color("ffe995"),true)
    var buy: Button
    if key != "campaign":
        buy = UI._button(game,card,"Uppgradera",Vector2(216,158),Vector2(179,58),func(): game.call("_buy_upgrade",key),true,"",21)
    else:
        price.text = "Gratis"
        buy = Button.new()
        buy.visible = false
        buy.disabled = true
        card.add_child(buy)
        price.visible = false
        coin.visible = false
        var status_mark := _artwork(card,Art.icon("check"),Vector2(17,181),Vector2(28,28))
        card.set_meta("status_mark",status_mark)
        var status := _label(game,card,"Låses upp när du spelar",Vector2(53,178),Vector2(342,33),20,Color("b9f5dd"),true)
        card.set_meta("status",status)
    var lock := _label(game,card,"",Vector2(18,176),Vector2(180,35),23,Color("ffe5a0"),true)
    lock.visible = false
    card.set_meta("lock",lock)
    card.set_meta("coin",coin)
    card.set_meta("title",title)
    card.set_meta("illustration",illustration)
    card.set_meta("effect",effect)
    card.set_meta("next_effect",next_effect)
    card.set_meta("rank",rank)
    card.set_meta("price",price)
    card.set_meta("buy",buy)
    return card
