extends SceneTree
## Real interface fixture, no main startup, player's save or audio. Portrait,
## landscape, browser chrome-height changes and short/square overlay scrolling.
const UI = preload("res://interface.gd")
const Existing = preload("res://tests/test_v7_view_ui.gd")
var failures: Array[String] = []
var checks := 0
func check(ok: bool,message: String) -> void:
    checks += 1
    if not ok:
        failures.append(message)
        push_error(message)
func _initialize() -> void: call_deferred("run")
func settle() -> void:
    await process_frame
    await process_frame
func contained(inner: Rect2,outer: Rect2,tolerance: float = 1.5) -> bool:
    return outer.grow(tolerance).encloses(inner)
func buttons(parent: Node) -> Array[Button]:
    var result: Array[Button] = []
    for child in parent.get_children():
        if child is Button: result.append(child)
        result.append_array(buttons(child))
    return result
func active_pause(game) -> Array[Button]:
    return [game.modal_action,game.modal.get_meta("paid_undo"),game.modal.get_meta("rescue_button"),game.modal.get_meta("pause_help").get_meta("restart"),game.sound_button,game.ui.get_meta("music_toggle"),game.modal.get_meta("test_toggle"),game.modal.get_meta("pause_harbor")]
func reachable(overlay: Control,actions: Array[Button],label: String) -> void:
    var scroll: ScrollContainer = overlay.get_meta("mobile_scroll")
    for action in actions:
        check(action.size.x >= 110 and action.size.y >= 110,label+": physical action retains44CSSpx target at360px width")
        scroll.ensure_control_visible(action)
        await settle()
        check(contained(action.get_global_rect(),scroll.get_global_rect()),label+": action is reachable wholly inside viewport after scroll/focus")
    scroll.scroll_vertical = 0
func run() -> void:
    var game = Existing.Fixture.new()
    root.add_child(game)
    UI.build(game)
    for viewport in [Vector2(900,1440),Vector2(900,1948),Vector2(900,2100),Vector2(1948,900),Vector2(900,900),Vector2(900,1440)]:
        root.size = Vector2i(viewport)
        await settle()
        UI.configure_modal(game,false)
        UI.reflow(game,viewport)
        await settle()
        var bounds := Rect2(Vector2.ZERO,viewport)
        var top: Control = game.ui.get_meta("top_hud")
        check(is_equal_approx(top.size.x,viewport.x-36),"HUD expands across the actual logical viewport width")
        check(contained(top.get_global_rect(),bounds),"HUD fits the viewport in both orientations")
        for action in [game.pause_button,game.ui.get_meta("rescue_button"),game.ui.get_meta("cargo_legend_button")]:
            check(action.size.x >= 110 and action.size.y >= 110 and contained(action.get_global_rect(),top.get_global_rect()),"HUD touch target is large, fully inside its card")
        check(game.ui.get_meta("mission_label").get_global_rect().end.y < 190 and game.progress_bar.get_global_rect().end.y < 190,"Readable order/progress stays above the200px world boundary")
        var actions := active_pause(game)
        game.modal.visible = true
        var modal_scroll: ScrollContainer = game.modal.get_meta("mobile_scroll")
        check(contained(modal_scroll.get_global_rect(),bounds),"Pause scroller fits the available screen height")
        for i in range(actions.size()):
            for j in range(i+1,actions.size()):
                check(not actions[i].get_global_rect().intersects(actions[j].get_global_rect()),"Pause buttons never overlap")
        await reachable(game.modal,actions,"pause")
        if viewport.x > 1100:
            check(modal_scroll.size.y >= game.modal.get_meta("card").size.y,"Wide landscape exposes every pause action without scrolling")
        UI.configure_modal(game,true)
        await settle()
        check(not game.modal.get_meta("pause_help").visible,"Victory does not expose pause-only actions")
        await reachable(game.modal,[game.modal_action],"victory")
        game.modal.visible = false
        game.shop.visible = true
        await reachable(game.shop,buttons(game.shop),"shop")
        check(contained(game.shop.get_meta("mobile_scroll").get_global_rect(),bounds),"Shop scroll frame stays on screen")
        game.shop.visible = false
        var legend: Control = game.ui.get_meta("cargo_legend")
        legend.visible = true
        await reachable(legend,[legend.get_meta("close")],"goods legend")
        check(contained(legend.get_meta("mobile_scroll").get_global_rect(),bounds),"Goods scroll frame stays on screen")
        legend.visible = false
        # Repeated resizing must never inflate a child card or its hit geometry.
        var old_width: float = game.shop.get_meta("card").size.x
        UI.reflow(game,viewport)
        await settle()
        check(is_equal_approx(game.shop.get_meta("card").size.x,old_width),"Repeated reflow does not accumulate card width")
    game.queue_free()
    await settle()
    print("MOBILE_LAYOUT_TESTS_OK: %d checks, portrait1440/1948/2100, landscape1948x900, square900;112px targets, no overlapping pause controls, responsive header, reachable scroll actions and resize stability" % checks if failures.is_empty() else "MOBILE_LAYOUT_TESTS_FAILED: %d" % failures.size())
    quit(0 if failures.is_empty() else 1)
