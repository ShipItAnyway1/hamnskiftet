extends SceneTree
## Responsive menu geometry and real callback bindings; no main/profile/audio.
const Menu = preload("res://harbor_menu.gd")
const P = preload("res://progression.gd")
const FORMATS := [Vector2(900,1947),Vector2(900,1440),Vector2(900,900),Vector2(1100,900),Vector2(1450,900),Vector2(1947,900)]

class Fixture:
    extends Node3D
    var font: Font = ThemeDB.fallback_font
    var heading: Font = ThemeDB.fallback_font
    var harbor: Control
    var purchases: Array[String] = []
    var starts := 0
    var resumes := 0
    func _start_stage() -> void: starts += 1
    func _close_harbor() -> void: resumes += 1
    func _buy_upgrade(key: String) -> void: purchases.append(key)

var failures: Array[String] = []
var checks := 0

func check(value: bool, message: String) -> void:
    checks += 1
    if not value:
        failures.append(message)
        push_error(message)

func _initialize() -> void:
    _run.call_deferred()

func _run() -> void:
    var game := Fixture.new()
    root.add_child(game)
    game.harbor = Menu.build(game)
    game.add_child(game.harbor)
    Menu.reflow(game)
    check(game.harbor.size == game.get_viewport().get_visible_rect().size.max(Vector2(900,900)),"Public reflow reads actual logical viewport dimensions")
    var menu: Control = game.harbor
    var cards: Dictionary = menu.get_meta("upgrade_cards")
    var buttons: Dictionary = menu.get_meta("buttons")
    var scroll: ScrollContainer = menu.get_meta("scroll")
    for card in cards.values():
        check(card.mouse_filter == Control.MOUSE_FILTER_PASS,"Finger drags over a card reach the menu scroller")
    for dimensions in FORMATS:
        for with_resume in [true,false]:
            menu.get_meta("resume").visible = with_resume
            # Explicit target dimensions exercise exactly the same layout path
            # without relying on a display server or a physical native window.
            Menu._reflow(menu,dimensions)
            await process_frame
            var bounds := Rect2(Vector2.ZERO,dimensions)
            var context := "%s resume=%s" % [dimensions,with_resume]
            check(menu.get_meta("background").get_global_rect() == bounds,"Full-screen backdrop: "+context)
            for key in ["wallet","hero","scroll","footer"]:
                check(bounds.encloses(menu.get_meta(key).get_global_rect()),"Visible region "+key+": "+context)
            check(menu.get_meta("wallet").get_global_rect().encloses(menu.get_meta("balance").get_global_rect()),"Balance remains inside visible header wallet: "+context)
            for key in ["play","resume"]:
                var button: Button = menu.get_meta(key)
                if button.visible:
                    check(bounds.encloses(button.get_global_rect()) and button.size.y >= 112,"On-screen touch action "+key+": "+context)
            var play: Button = menu.get_meta("play")
            check(dimensions.y-play.get_global_rect().end.y <= 40,"Primary stage action stays at bottom: "+context)
            check(not scroll.get_global_rect().intersects(menu.get_meta("footer").get_global_rect()),"Sticky actions never cover scrolling purchases: "+context)
            for tab in ["harbor","trucks"]:
                menu.get_meta("tab_buttons")[tab].pressed.emit()
                var page: Control = menu.get_meta("tab_panels")[tab]
                check(page.visible and menu.get_meta("selected_tab") == tab,"Real tab callback selects page: "+context)
                check(bounds.encloses(menu.get_meta("tab_buttons")[tab].get_global_rect()) and menu.get_meta("tab_buttons")[tab].size.y >= 112,"Tab has visible mobile touch target: "+context)
                var last: Control = page.get_children()[-1]
                scroll.scroll_vertical = 99999
                await process_frame
                check(last.get_global_rect().end.y <= scroll.get_global_rect().end.y+1,"Last card is reachable: "+tab+context)
                for key in P.KEYS:
                    var card: Panel = cards[key]
                    if card.get_parent() != page: continue
                    var buy: Button = card.get_meta("buy")
                    check(buttons[key] == buy and card.size.x >= 370 and buy.size.y >= 112,"Card registry and usable purchase target survive reflow: "+key+context)
                    # Scroll each actual purchase button fully into view. A
                    # reachable card bottom alone would miss clipped buttons.
                    var target: Rect2 = buy.get_global_rect()
                    var visible: Rect2 = scroll.get_global_rect()
                    if target.position.y < visible.position.y:
                        scroll.scroll_vertical += floori(target.position.y-visible.position.y)-4
                    elif target.end.y > visible.end.y:
                        scroll.scroll_vertical += ceili(target.end.y-visible.end.y)+4
                    await process_frame
                    check(scroll.get_global_rect().grow(1).encloses(buy.get_global_rect()),"Actual purchase button can be fully scrolled into view: "+key+context)
    # Signal emission checks binding identity, not affordability/unlock policy;
    # those belong to the real campaign controller tests.
    for key in P.KEYS:
        buttons[key].pressed.emit()
    check(game.purchases == P.KEYS,"All ten original purchase callbacks retain the correct resource key")
    menu.get_meta("play").pressed.emit()
    menu.get_meta("resume").pressed.emit()
    check(game.starts == 1 and game.resumes == 1,"Sticky actions retain real start/resume callbacks")
    game.queue_free()
    await process_frame
    if failures.is_empty():
        print("MOBILE_HARBOR_TESTS_OK: %d checks; six formats, header/balance, 112-unit touch actions, sticky footer, both scroll pages, every reachable purchase and retained bindings" % checks)
    quit(0 if failures.is_empty() else 1)
