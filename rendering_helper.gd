extends RefCounted
## Optional draw-call reduction for parked, unanimated truck models.
## Capture after load visibility and poses are set. Detach a model BEFORE any
## animation, load change, or other visual mutation. Colliders stay untouched.

static func build(parent: Node3D, models: Array[Node3D]) -> YardBatch:
    var batch := YardBatch.new()
    batch.name = "ParkedTruckBatch"
    parent.add_child(batch)
    batch.capture(models)
    return batch

class YardBatch:
    extends Node3D

    var _groups: Dictionary = {}
    var _originals: Dictionary = {}

    func capture(models: Array[Node3D]) -> void:
        restore()
        var source_count: int = 0
        var inverse: Transform3D = global_transform.affine_inverse()
        for model in models:
            if not is_instance_valid(model) or not model.is_inside_tree():
                continue
            var model_id: int = model.get_instance_id()
            if _originals.has(model_id):
                continue
            var saved: Array[Dictionary] = []
            var meshes: Array[MeshInstance3D] = []
            _collect(model,meshes)
            for mesh_node in meshes:
                if mesh_node.mesh == null or not mesh_node.is_visible_in_tree():
                    continue
                # Model batches have one surface and an explicit material. Leave
                # unusual external geometry on its normal renderer path.
                if mesh_node.mesh.get_surface_count() != 1 or mesh_node.material_override == null:
                    continue
                var key: String = "%d/%d/%d/%d" % [mesh_node.mesh.get_instance_id(),mesh_node.material_override.get_instance_id(),int(mesh_node.cast_shadow),mesh_node.layers]
                if not _groups.has(key):
                    _groups[key] = {"mesh":mesh_node.mesh,"material":mesh_node.material_override,"shadows":mesh_node.cast_shadow,"layers":mesh_node.layers,"members":[]}
                var group: Dictionary = _groups[key]
                group.members.append({"model_id":model_id,"transform":inverse*mesh_node.global_transform})
                saved.append({"node":mesh_node,"visible":mesh_node.visible})
                mesh_node.visible = false
                source_count += 1
            _originals[model_id] = saved
        for key in _groups:
            var group: Dictionary = _groups[key]
            var multi := MultiMesh.new()
            multi.transform_format = MultiMesh.TRANSFORM_3D
            multi.mesh = group.mesh
            multi.instance_count = group.members.size()
            multi.visible_instance_count = group.members.size()
            for index in range(group.members.size()):
                multi.set_instance_transform(index,group.members[index].transform)
            var instance := MultiMeshInstance3D.new()
            instance.name = "ParkedParts"
            instance.multimesh = multi
            instance.material_override = group.material
            instance.cast_shadow = group.shadows
            instance.layers = group.layers
            add_child(instance)
            group["instance"] = instance
        set_meta("model_count",_originals.size())
        set_meta("source_mesh_count",source_count)
        set_meta("draw_group_count",_groups.size())

    func contains(model: Node3D) -> bool:
        return is_instance_valid(model) and _originals.has(model.get_instance_id())

    func detach(model: Node3D) -> void:
        if not is_instance_valid(model):
            return
        var model_id: int = model.get_instance_id()
        if not _originals.has(model_id):
            return
        for key in _groups:
            var group: Dictionary = _groups[key]
            var members: Array = group.members
            var multi: MultiMesh = group.instance.multimesh
            var index: int = 0
            while index < members.size():
                if int(members[index].model_id) != model_id:
                    index += 1
                    continue
                var last: int = members.size()-1
                if index != last:
                    members[index] = members[last]
                    multi.set_instance_transform(index,members[index].transform)
                members.pop_back()
            multi.visible_instance_count = members.size()
        _restore_model(model_id)
        set_meta("model_count",_originals.size())

    func restore() -> void:
        for model_id in _originals.keys():
            _restore_model(int(model_id))
        for child in get_children():
            child.free()
        _groups.clear()
        set_meta("model_count",0)
        set_meta("source_mesh_count",0)
        set_meta("draw_group_count",0)

    func _restore_model(model_id: int) -> void:
        var saved: Array = _originals.get(model_id,[])
        for entry in saved:
            if is_instance_valid(entry.node):
                entry.node.visible = bool(entry.visible)
        _originals.erase(model_id)

    func _exit_tree() -> void:
        for model_id in _originals.keys():
            _restore_model(int(model_id))

    func _collect(parent: Node3D, meshes: Array[MeshInstance3D]) -> void:
        for child in parent.get_children():
            if child is MeshInstance3D:
                meshes.append(child)
            if child is Node3D:
                _collect(child,meshes)
