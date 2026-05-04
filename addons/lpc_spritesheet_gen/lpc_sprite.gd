## Copyright (C) 2023 Denis Selensky - All Rights Reserved
## You may use, distribute and modify this code under the terms of the MIT license

@tool
@icon("internal/lpc_icon.png")
class_name LPCSprite
extends AnimatedSprite2D
##
## This Class can be used to display an animated LPC character spritesheet
## It uses a LPCSpriteBlueprint as "frames" property
##
## Each layer is kept seperate and can be added/removed or animated at runtime
##


## This signal is emited when non-endless animations reach their 'climax' point
## Use this to deal the damage or loose the arrow. Implemented for
## - slash
## - thrust
## - shoot
## - cast
##
## Note: use animation_finished signal to react to a completed animation
signal animation_climax(animname)

# TODO: maybe better do everything with enums and use to the String name array 
# as workaround it's double
const dir_names = ["down","left","up","right"]
const anim_names = ["idle", "walk", "run", "cast", "slash", "thrust", "shoot", "hurt", "climb", "jump", "sit", "emote", "combat_idle"]

const dir_vectors = {
	"down" 	: Vector2(0, 1),
	"left" 	: Vector2(-1, 0),
	"up" 	: Vector2(0, -1),
	"right" : Vector2(1, 0),
}

@export_enum("down", "left", "up", "right") var dir: String = "down" : set=set_dir
@export_enum("idle", "walk", "run", "cast", "slash", "thrust", "shoot", "hurt", "climb", "jump", "sit", "emote", "combat_idle") var anim: String = "idle" : set=set_anim

var _last_frames


func _init():
	centered = false
	offset = Vector2(-32,-60)
	
# TODO: Test if this is needed
func _ready() -> void:
	_reload_animation_player()

# TODO: with Godot4 this it's not needed to connect the event
# but I get a recursive stack crash if I use the signal. Need
# to investivate this


func _process(delta):
	if _last_frames and _last_frames != sprite_frames:
		# reconnect if frames object changed (needed for editor)
		#_last_frames.changed.disconnect(_reload_layers_from_blueprint) # TODO
		#sprite_frames.changed.connect(_reload_layers_from_blueprint) # TODO
		call_deferred("_reload_layers_from_blueprint")
	_last_frames = sprite_frames
	_update_animation()

func _enter_tree():
	#if sprite_frames: # TODO
		#sprite_frames.changed.connect(_reload_layers_from_blueprint) # TODO
	frame_changed.connect(_on_LPCSprite_frame_changed)
	_reload_layers_from_blueprint()
	
func _exit_tree():
	#if sprite_frames: # TODO
		#sprite_frames.changed.disconnect(_reload_layers_from_blueprint) # TODO
	frame_changed.disconnect(_on_LPCSprite_frame_changed)

## This takes the first found LPCAnimationPlayer child if available 
## and creates all the needed animations
func _reload_animation_player():
	var animation_player = find_child("LPCAnimationPlayer")
	var animation_tree = find_child("LPCAnimationTree")
#
	if animation_player is LPCAnimationPlayer and animation_tree is LPCAnimationTree:
		for anim_element in anim_names:
			
			var blend2d_node: LPCAnimationNodeBlendSpace2D = animation_tree.create_animation_blend2d(anim_element)
			
			if anim_element != "idle":
				animation_tree.create_animation_transition("idle", anim_element)
				
			for dir_element in dir_names:
				var animation = animation_player.create_animation_resource(anim_element, dir_element)
				
				blend2d_node.create_animation_blend_point(anim_element, dir_element, dir_vectors[dir_element])
				
		animation_player.set_autoplay("idle_down")
				

func _get_configuration_warning() -> String:
	if not (sprite_frames as LPCSpriteBlueprint):
		return "'frames' property must be of type LPCSpriteBlueprint"
	return ""

func set_animation_tree(direction: Vector2):
	var animation_tree = find_child("LPCAnimationTree")
	
	if animation_tree is LPCAnimationTree:
		for anim_element in anim_names:
			var parameter = "parameters/" + anim_element + "/blend_position"
			animation_tree.set(parameter, direction)

## Set direction by providing either:
## - Vector2 (any direction)
## - String (down, up, left, right)
##
func set_dir(direction):
	if typeof(direction) == TYPE_VECTOR2:
		# Vector2.ZERO.angle() is 0, which _angle_to_dir treats as "right" —
		# so stopping always snapped facing to right regardless of where the
		# character was actually moving. Preserve the current dir when the
		# velocity collapses to zero (idle keeps the last walking facing).
		if direction == Vector2.ZERO:
			return
		# Cardinal snap by component magnitude: whichever axis is larger
		# wins. Ties go to horizontal (covers the player's exact-45° diagonal
		# input where |x| == |y| — that should read as left/right). For an
		# arbitrary heading angle this means up/down get a 90° wedge each
		# centred on the vertical poles, and left/right get the wider 90°
		# wedges to either side.
		if absf(direction.x) >= absf(direction.y):
			direction = "right" if direction.x > 0 else "left"
		else:
			direction = "down" if direction.y > 0 else "up"
	dir = direction
	_update_animation()

## Set animation by name and play it, can be one of:
## - idle
## - walk
## - run
## - cast
## - slash
## - thrust
## - shoot
## - hurt
## - climb
## - jump
## - sit
## - emote
## - combat_idle
func set_anim(_animation_name : String):
	# Only reset frame/play on an actual animation change. Callers like
	# animate_movement() reassign `anim` every physics frame; an
	# unconditional `frame = 0` here pinned playback at frame 0 forever.
	if anim != _animation_name:
		frame = 0
		play()
		anim = _animation_name
		speed_scale = 1.0
	_update_animation()

# Takes velocity vector and chooses correct animation from it
# Note: walk threshold is 32px/s (1.0 speed_scale at 32). Speeds above 48px/s
# switch to the real LPC run animation.
func animate_movement(velocity : Vector2):
	set_dir(velocity)
	if velocity.length() > 0:
		var speed := velocity.length()
		if speed > 48:
			anim = "run"
		else:
			speed_scale = speed / 32
			anim = "walk"
	else:
		anim = "idle"
	_update_animation()

## Returns layers matching the optional "type" filter, layers are of type LPCSpriteLayer
## Some type string examples:
## - body
## - head
## - weapon
## - legs
## - hair
## - ...
## Hint: Check the 'type_name' property in the blueprint
func get_layers(type_filter : Array = []) -> Array:
	var layers_of_type = []
	for child in get_children():
		if child as LPCSpriteLayer:
			if type_filter.is_empty() or child.blueprint_layer.type_name in type_filter:
				layers_of_type.append(child)
	return layers_of_type

## Adds the Layers from an additional blueprint.
## This can be used to add e.g. Weapon, Gear, etc.
## Returns an array of added LPCSpriteLayer(s) for future manipulation
##
func add_blueprint(blueprint : LPCSpriteBlueprint) -> Array:
	return _add_layers(blueprint.layers)

func _add_layers(layers : Array) -> Array:
	var sprite_array := Array()
	for layer in layers:
		sprite_array.append(_add_layer_sprite(layer))
	_on_LPCSprite_frame_changed()
	return sprite_array


func _reload_layers_from_blueprint():
	for child in get_children():
		if child as LPCSpriteLayer:
			remove_child(child)
			child.queue_free()
	var blueprint : LPCSpriteBlueprint = sprite_frames
	if blueprint != null:
		var has_layers = false
		for layer in blueprint.layers:
			var sprite = _add_layer_sprite(layer)
			has_layers = true
		if has_layers:
			blueprint._set_atlas(null)
		_on_LPCSprite_frame_changed()


func _add_layer_sprite(layer : LPCSpriteBlueprintLayer) -> Sprite2D:
	var new_sprite = LPCSpriteLayer.new() if (layer.oversize_animation.is_empty()) else LPCSpriteLayerOversize.new()
	new_sprite.set_atlas(layer.texture)
	new_sprite.unique_name_in_owner = false
	new_sprite.set_name(layer.type_name)
	new_sprite.offset += self.offset
	new_sprite.centered = centered
	new_sprite.blueprint_layer = layer
	new_sprite.material = layer.material.duplicate()
	new_sprite.texture_filter = TextureFilter.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	add_child(new_sprite)
	(sprite_frames as LPCSpriteBlueprint)._set_atlas(null)
	return new_sprite


func _angle_to_dir(_angle):
	var seg1 = PI*2/8
	var seg2 = PI*6/8
	
	if _angle <= seg1 and _angle >= -seg1:
		return "right"
	elif _angle > seg1 and _angle < seg2:
		return "down"
	elif _angle <= -seg1 and _angle >= -seg2:
		return "up"
	else:
		return "left"


func _update_animation():
	var anim_name = anim + "_" + dir
	if animation != anim_name:
		# hurt and climb are 1-direction LPC anims (always shown facing down)
		if anim == "hurt" or anim == "climb":
			if dir != "down": # avoid recursion via dir setter
				dir = "down"
			anim_name = anim + "_down"
		if sprite_frames and sprite_frames.has_animation(anim_name):
			animation = anim_name
			_on_LPCSprite_frame_changed()


func _on_LPCSprite_frame_changed():
	var blueprint : LPCSpriteBlueprint = (sprite_frames as LPCSpriteBlueprint)
	if blueprint:
		var tex = blueprint.get_frame_texture(self.animation, self.frame)
		for child in get_children():
			if child as LPCSpriteLayer:
				child.copy_atlas_rects(tex)
		if anim == "slash" and self.frame == 4:
			emit_signal("animation_climax", anim)
		elif anim == "thrust" and self.frame == 5:
			emit_signal("animation_climax", anim)
		elif anim == "shoot" and self.frame == 9:
			emit_signal("animation_climax", anim)
		elif anim == "cast" and self.frame == 5:
			emit_signal("animation_climax", anim)
