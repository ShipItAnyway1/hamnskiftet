extends RefCounted

# One responsive contract for presentation and pointer projection. All regions
# use logical canvas units, independent of the browser's device pixel ratio.
static func areas(canvas: Vector2) -> Dictionary:
    var width := canvas.x
    var height := canvas.y
    var landscape := width > height*1.25
    var margin := 12.0
    var road_height := 112.0 if landscape else 130.0
    var road := Rect2(margin,height-road_height-margin,width-margin*2,road_height)
    var context := Rect2(margin,road.position.y-84,width-margin*2,68)
    var dock: Rect2
    var yard: Rect2
    if landscape or height < 1100:
        var top := 236.0
        var split := floorf(width*.42)
        dock = Rect2(margin,top,split-margin*2,context.position.y-top-18)
        yard = Rect2(split+margin,top,width-split-margin*2,context.position.y-top-18)
    else:
        var dock_height := clampf(height*.285,320,560)
        dock = Rect2(margin,200,width-margin*2,dock_height)
        var yard_top := dock.end.y+52
        yard = Rect2(margin,yard_top,width-margin*2,context.position.y-yard_top-18)
    return {"mode":"landscape" if landscape else "portrait","dock":dock,"yard":yard,"road":road,"context":context}
