extends Node

# Read-only geometry for browser accessibility/QA. It contains rendered bounds,
# never commands, puzzle advice, unlocked actions, or access to player saves.
var game: Node3D
var _clock := 0.0

func setup(source: Node3D) -> void:
    game = source
    process_mode = Node.PROCESS_MODE_ALWAYS

func _process(delta: float) -> void:
    _clock += delta
    if _clock < .3 or not OS.has_feature("web") or not is_instance_valid(game.ui): return
    _clock = 0
    var viewport_size := get_viewport().get_visible_rect().size
    var screen := "game"
    if game.harbor.visible: screen = "harbor"
    elif game.modal.visible: screen = "pause"
    elif game.shop.visible: screen = "shop"
    elif game.ui.get_meta("cargo_legend").visible: screen = "legend"
    var data := {"version":1,"viewport":{"w":viewport_size.x,"h":viewport_size.y},
        "safe_area":{"x":0,"y":0,"w":viewport_size.x,"h":viewport_size.y},
        "mode":"landscape" if viewport_size.x > viewport_size.y*1.25 else "portrait",
        "screen":screen,"controls":{},"regions":{},"vehicles":[],"cargo":[]}
    var controls: Dictionary = data.controls
    controls.harbor_play = _control(game.harbor.get_meta("play"),screen == "harbor")
    controls.pause = _control(game.pause_button,screen == "game")
    controls.rescue = _control(game.ui.get_meta("rescue_button"),screen == "game")
    controls.effects = _control(game.sound_button,screen == "pause")
    controls.music = _control(game.ui.get_meta("music_toggle"),screen == "pause")
    controls.modal_continue = _control(game.modal_action,screen == "pause")
    _buttons(game.ui,controls,screen)
    var view = game.readable_view
    if is_instance_valid(view):
        data.camera = {"zoom":game.zoom,"yard_size":view.yard_camera.size,"pan":[view._pan_offset.x,view._pan_offset.y]}
        data.regions = {"dock":_rect(view.dock_rect),"yard":_rect(view.yard_rect),"road":_rect(view.road_rect)}
        if screen == "pause": data.regions.modal = _rect(game.modal.get_meta("card").get_global_rect())
        for id in game.truck_nodes:
            if int(id) < 0 or int(id) >= game.state.trucks.size() or str(game.state.trucks[id].status) != "yard": continue
            var node: Node3D = game.truck_nodes[id]
            var length := float(game.state.trucks[id].len)*.9
            var bounds := _project_bounds(view,node,Vector3(-.4,.15,-length*.5),Vector3(.4,1.1,length*.5),"yard")
            var model: Node3D = node.get_meta("model")
            var badge: Node3D = model.get_meta("type_badge") if model.has_meta("type_badge") else null
            var center := badge.global_position if badge != null else node.global_position+Vector3.UP
            var pick: Vector2 = view.project(center,"yard")
            data.vehicles.append({"id":id,"rect":_rect(bounds),"pick":[pick.x,pick.y],
                "glyph_rect":_rect(_glyph_bounds(view,center,_badge_diameter(badge,.68),"yard"))})
        for id in game.cargo_nodes:
            var node: Node3D = game.cargo_nodes[id]
            if not is_instance_valid(node): continue
            var badge: Node3D = node.get_meta("type_badge") if node.has_meta("type_badge") else null
            var center := badge.global_position if badge != null else node.global_position+Vector3.UP*.6
            data.cargo.append({"kind":str(node.get_meta("kind","")),
                "rect":_rect(_project_bounds(view,node,Vector3(-.35,0,-.35),Vector3(.35,.4,.35),"dock")),
                "glyph_rect":_rect(_glyph_bounds(view,center,_badge_diameter(badge,.5*node.scale.x),"dock"))})
    var encoded := JSON.stringify(JSON.stringify(data))
    JavaScriptBridge.eval("(()=>{let e=document.getElementById('game-layout');if(!e){e=document.createElement('script');e.id='game-layout';e.type='application/json';document.body.appendChild(e);}e.textContent="+encoded+";})()",true)

func _buttons(node: Node, output: Dictionary, screen: String) -> void:
    for child in node.get_children():
        if child is Button:
            var shown: bool = (screen == "game" and not game.harbor.is_ancestor_of(child) and not game.modal.is_ancestor_of(child) and not game.shop.is_ancestor_of(child) and not game.ui.get_meta("cargo_legend").is_ancestor_of(child)) or (screen == "harbor" and game.harbor.is_ancestor_of(child)) or (screen == "pause" and game.modal.is_ancestor_of(child)) or (screen == "shop" and game.shop.is_ancestor_of(child)) or (screen == "legend" and game.ui.get_meta("cargo_legend").is_ancestor_of(child))
            output[str(child.get_path())] = _control(child,shown)
        _buttons(child,output,screen)

func _control(control: Control, shown: bool) -> Dictionary:
    var actual := control.get_global_rect()
    var clipped_to := Rect2(Vector2.ZERO,get_viewport().get_visible_rect().size)
    var parent := control.get_parent()
    while parent != null:
        if parent is Control and parent.clip_contents:
            clipped_to = clipped_to.intersection(parent.get_global_rect())
        parent = parent.get_parent()
    return {"rect":_rect(actual),"visible":shown and control.is_visible_in_tree() and actual.intersects(clipped_to),
        "clipped":not clipped_to.encloses(actual),
        "disabled":control.disabled if control is BaseButton else false,"text":control.text if control is Button else ""}

func _rect(value: Rect2) -> Array:
    return [value.position.x,value.position.y,value.size.x,value.size.y]

func _project_bounds(view, node: Node3D, low: Vector3, high: Vector3, section: String) -> Rect2:
    var result := Rect2(view.project(node.to_global(low),section),Vector2.ZERO)
    for x in [low.x,high.x]:
        for y in [low.y,high.y]:
            for z in [low.z,high.z]: result = result.expand(view.project(node.to_global(Vector3(x,y,z)),section))
    return result

func _glyph_bounds(view, center: Vector3, diameter: float, section: String) -> Rect2:
    var camera: Camera3D = view.dock_camera if section == "dock" else view.yard_camera
    var at: Vector2 = view.project(center,section)
    var radius: float = at.distance_to(view.project(center+camera.basis.x*diameter*.5,section))
    return Rect2(at-Vector2.ONE*radius,Vector2.ONE*radius*2)

func _badge_diameter(badge: Node3D, fallback: float) -> float:
    if badge == null or not badge.has_node("IconFace"): return fallback
    var face: Node3D = badge.get_node("IconFace")
    return face.scale.x*badge.global_transform.basis.x.length()
