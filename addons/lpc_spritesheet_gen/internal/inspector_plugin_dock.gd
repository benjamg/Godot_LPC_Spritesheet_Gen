## Copyright (C) 2023 Denis Selensky - All Rights Reserved
## You may use, distribute and modify this code under the terms of the MIT license

@tool
extends VBoxContainer

var dst_base_path = "res://assets/lpc_sprites/"

# v2 LPC schema: each layer is served as a per-animation PNG, but the addon's
# blueprint expects a single unified sheet (832x2944) with all animations
# stacked at fixed Y offsets. This map covers every animation the unified
# sheet has a row for, keyed by the v2 JSON animation id. Values are the Y
# offset in the unified sheet. Source of truth: lpc_frames.tres regions.
# Note: keys are the v2 download ids (e.g. "spellcast"); the in-engine anim
# names in lpc_sprite.gd use a different prefix for cast ("cast" vs "spellcast")
# but both refer to the same Y=0 row.
const ANIMATION_ROW_MAP := {
	"spellcast": 0,
	"thrust": 256,
	"walk": 512,
	"slash": 768,
	"shoot": 1024,
	"hurt": 1280,
	"climb": 1344,
	"idle": 1408,
	"run": 1664,
	"jump": 1920,
	"sit": 2176,
	"emote": 2432,
	"combat_idle": 2688,
}
const UNIFIED_SHEET_W := 832
const UNIFIED_SHEET_H := 2944
# Path tokens that may appear as a directory segment or file stem in a layer
# fileName and must be detected so we can substitute the animation id.
const ANIMATION_TOKENS := [
	"spellcast", "thrust", "walk", "slash", "shoot", "hurt",
	"climb", "idle", "jump", "sit", "emote", "run", "combat_idle",
	"backslash", "halfslash", "watering", "combat",
]

var editor_interface : EditorInterface
var blueprint : LPCSpriteBlueprint : set=set_blueprint

@onready var http_node := $CanvasLayer/HTTPRequest

signal _web_files_downloaded()

func set_blueprint(_blueprint : LPCSpriteBlueprint):
	blueprint = _blueprint
	for sprite in $vpc/vp.get_children():
		(sprite as LPCSprite).sprite_frames = blueprint
		_set_animation($bodytypes/animation.text)
		(sprite as LPCSprite).play()
	_load_from_blueprint()

func _enter_tree():
	if !blueprint:
		set_blueprint(LPCSpriteBlueprint.new())

func _ready():
	# OptionButton has no static items in the .tscn; mirror LPCSprite.anim_names
	# so the dropdown stays in sync with whatever the runtime exposes.
	var btn : OptionButton = $bodytypes/animation
	btn.clear()
	for anim_name in LPCSprite.anim_names:
		btn.add_item(anim_name)

func _update_credits_text():
	var missing_text = "!MISSING LICENSE INFORMATION!"
	$CreditsLabel.text = blueprint.credits_txt
	$CreditsLabel.text = $CreditsLabel.text.replace(missing_text, "[color=red]" + missing_text + "[/color]")
	
	var licenses := {
			"CC0":"https://creativecommons.org/publicdomain/zero/1.0/",
			"CC-BY-SA 3.0":"https://creativecommons.org/licenses/by-sa/3.0",
			"CC BY 3.0":"https://creativecommons.org/licenses/by/3.0",
			"CC-BY 3.0":"https://creativecommons.org/licenses/by/3.0",
			"CC-BY 4.0":"https://creativecommons.org/licenses/by/4.0",
			"OGA-BY 3.0":"https://static.opengameart.org/OGA-BY-3.0.txt",
			"GPL 1.0":"https://www.gnu.org/licenses/gpl-1.0.en.html",
			"GPL 2.0":"https://www.gnu.org/licenses/gpl-2.0.en.html",
			"GPL 3.0":"https://www.gnu.org/licenses/gpl-3.0.en.html",
		}
		
	for lic in licenses:
		$CreditsLabel.text = $CreditsLabel.text.replace(lic, "[url="+licenses[lic]+"]"+lic+"[/url]")

func _on_meta_clicked(meta : String):
	if meta.begins_with("res://"):
		var path = ProjectSettings.globalize_path(meta)
		OS.shell_open(path)
	else:
		OS.shell_open(meta)

func _load_from_blueprint():
	$LayersList.text = "[table=3][cell]Z[/cell][cell]Type[/cell][cell]File path[/cell]"
	$CreditsLabel.text = ""
	if blueprint:
		_update_credits_text()
		for index in range(0, blueprint.layers.size()):
			var meta := (blueprint.layers[index] as LPCSpriteBlueprintLayer)
			var format_string = '[cell]{z}[/cell] [cell]{t}[/cell] [cell][url={url}]{rp}[/url][/cell]\n'
			$LayersList.text += format_string.format({"z":meta.zorder, "t":meta.type_name, "rp":meta.rel_path, "url":meta.rel_path})
			
	$LayersList.text += "[/table]"

func _set_animation(animname : String):
	for sprite in $vpc/vp.get_children():
		var suffix = sprite.name.split('_')[1]
		(sprite as LPCSprite).set_dir(suffix)
		(sprite as LPCSprite).set_anim(animname)

func _on_animation_item_selected(index):
	var animname = $bodytypes/animation.get_item_text(index)
	_set_animation(animname)

func _find_anim_token_index(file_name : String) -> int:
	# Walk path segments + file stem looking for a known LPC animation token.
	# Returns the segment index, or -1 if none found. We need this to know
	# which segment to substitute when deriving per-animation file paths.
	var parts : PackedStringArray = file_name.split("/")
	# Inspect every segment except the bare extension (the last "." part of
	# the final segment is the extension and never an anim token).
	for i in parts.size():
		var seg : String = parts[i]
		if i == parts.size() - 1 and seg.contains("."):
			seg = seg.get_basename()
		if seg in ANIMATION_TOKENS:
			return i
	return -1

func _derive_per_anim_path(file_name : String, anim_id : String) -> String:
	# Substitute the animation token in a fileName with anim_id. Handles both
	# forms: token as a directory segment ("hat/cloth/.../spellcast/black.png")
	# and token as the file stem ("body/bodies/male/spellcast.png").
	var idx := _find_anim_token_index(file_name)
	if idx < 0:
		return file_name
	var parts : PackedStringArray = file_name.split("/")
	var last_idx : int = parts.size() - 1
	if idx == last_idx:
		var ext := parts[idx].get_extension()
		parts[idx] = anim_id + "." + ext
	else:
		parts[idx] = anim_id
	return "/".join(parts)

func _unified_path_for_layer(layer : Dictionary) -> String:
	# Composite output goes alongside the per-animation PNGs, named uniquely
	# by itemId so multiple imports never collide.
	var file_name : String = layer["fileName"]
	var idx := _find_anim_token_index(file_name)
	var parts : PackedStringArray = file_name.split("/")
	var base_dir := ""
	if idx > 0:
		var head : PackedStringArray = parts.slice(0, idx)
		base_dir = "/".join(head)
	else:
		base_dir = file_name.get_base_dir()
	var item_id : String = layer.get("itemId", "layer")
	return "%s/__unified_%s.png" % [base_dir, item_id]

func _composite_layer_to_unified(layer : Dictionary) -> bool:
	# Build a 832x1344 RGBA blank, blit each per-animation PNG at its row
	# offset, save to disk. Returns true on success.
	var unified := Image.create(UNIFIED_SHEET_W, UNIFIED_SHEET_H, false, Image.FORMAT_RGBA8)
	unified.fill(Color(0, 0, 0, 0))
	var supported : Array = layer.get("supportedAnimations", [])
	var blits := 0
	for anim_id in ANIMATION_ROW_MAP.keys():
		if not (anim_id in supported):
			continue
		var src_rel : String = _derive_per_anim_path(layer["fileName"], anim_id)
		var src_abs : String = ProjectSettings.globalize_path(dst_base_path + src_rel)
		if not FileAccess.file_exists(dst_base_path + src_rel):
			continue
		var src := Image.load_from_file(src_abs)
		if src == null:
			push_warning("LPC composite: could not load %s" % src_abs)
			continue
		var w : int = min(src.get_width(), UNIFIED_SHEET_W)
		var y : int = ANIMATION_ROW_MAP[anim_id]
		var h : int = min(src.get_height(), UNIFIED_SHEET_H - y)
		unified.blit_rect(src, Rect2i(0, 0, w, h), Vector2i(0, y))
		blits += 1
	if blits == 0:
		return false
	var unified_rel := _unified_path_for_layer(layer)
	var unified_abs := ProjectSettings.globalize_path(dst_base_path + unified_rel)
	DirAccess.make_dir_recursive_absolute((dst_base_path + unified_rel).get_base_dir())
	var err := unified.save_png(unified_abs)
	if err != OK:
		push_error("LPC composite: save_png failed for %s (err %d)" % [unified_abs, err])
		return false
	# Rewrite the layer's fileName so the rest of the import flow loads the
	# unified composite instead of the single-animation PNG.
	layer["fileName"] = unified_rel
	return true

func _download_spritesheets_from_web(base_url : String, layers : Array):
	# Ensure the destination dir exists before opening it. If it doesn't,
	# DirAccess.open returns null, then make_dir_recursive errors silently
	# and the await below never fires — UI hangs forever.
	if not DirAccess.dir_exists_absolute(dst_base_path):
		DirAccess.make_dir_recursive_absolute(dst_base_path)
	var downloaded_files = []
	for layer in layers:
		# v2 schema: download every per-animation PNG the addon's unified
		# sheet has a row for. The legacy single-fileName download is a
		# fallback if the layer lacks supportedAnimations metadata.
		var supported : Array = layer.get("supportedAnimations", [])
		var anims_to_fetch : Array = []
		for anim_id in ANIMATION_ROW_MAP.keys():
			if anim_id in supported:
				anims_to_fetch.append(anim_id)
		if anims_to_fetch.is_empty():
			var fallback_name : String = layer.get("fileName", "")
			anims_to_fetch = [fallback_name.get_basename().get_file()]

		for anim_id in anims_to_fetch:
			var rel_path : String
			if supported.is_empty():
				rel_path = layer["fileName"]
			else:
				rel_path = _derive_per_anim_path(layer["fileName"], anim_id)
			var local_path : String = dst_base_path + rel_path
			if FileAccess.file_exists(local_path):
				continue
			var dir = DirAccess.open(dst_base_path)
			if dir == null:
				push_error("LPC import: could not open '%s' — bailing out." % dst_base_path)
				emit_signal("_web_files_downloaded")
				return
			dir.make_dir_recursive(local_path.get_base_dir())
			http_node.download_file = local_path
			http_node.request(base_url + rel_path)
			var result = await http_node.request_completed
			# result is [result_code, response_code, headers, body]
			if result.size() >= 2 and result[1] == 404:
				DirAccess.remove_absolute(ProjectSettings.globalize_path(local_path))
				continue
			downloaded_files.push_back(local_path)

		# After all per-animation files for this layer are on disk,
		# composite them into a single unified sheet and rewrite fileName.
		_composite_layer_to_unified(layer)

	await get_tree().process_frame
	if downloaded_files.size() > 0:
		var filesystem := EditorInterface.get_resource_filesystem()
		print("Rescan..")
		filesystem.scan()
		await filesystem.resources_reimported
		print(".. rescan finished!")
		await get_tree().process_frame

	emit_signal("_web_files_downloaded")

func _on_ButtonImport_pressed():
	var clipboard_content := DisplayServer.clipboard_get()
	var json = JSON.new()
	var jsonResult := json.parse(clipboard_content)
	if jsonResult == Error.OK and json.data is Dictionary:
		var data : Dictionary = json.data

		# Schema compat: LPC generator's clipboard JSON format has drifted.
		# Old schema had top-level "spritesheets" (base URL), "bodyTypeName",
		# and per-layer "parentName". New (v2+) schema drops those — base URL
		# is implicit, body type renamed to "bodyType", per-layer category
		# must be derived from the "selections" dictionary by itemId match.
		var base_url: String = data.get("spritesheets", "https://liberatedpixelcup.github.io/Universal-LPC-Spritesheet-Character-Generator/spritesheets/")
		var body_type: String = data.get("bodyTypeName", data.get("bodyType", ""))
		if not data.has("spritesheets") and data.has("selections"):
			var item_to_category := {}
			for category in data["selections"]:
				var sel = data["selections"][category]
				if sel is Dictionary and sel.has("itemId"):
					item_to_category[sel["itemId"]] = category
			for layer in data["layers"]:
				if not layer.has("parentName"):
					layer["parentName"] = item_to_category.get(layer.get("itemId", ""), layer.get("itemId", ""))

		_download_spritesheets_from_web(base_url, data["layers"])
		print("Wait for downlaods..")
		await _web_files_downloaded

		print(".. download finished!")
		var new_layers = []
		for layer in data["layers"]:
			var local_path = dst_base_path + layer["fileName"]
			var new_layer := LPCSpriteBlueprintLayer.new()
			new_layer.zorder = int(layer["zPos"])
			new_layer.rel_path = layer["fileName"]
			new_layer.abs_path = local_path
			new_layer.body = body_type
			new_layer.type_name = layer["parentName"]
			new_layer.name = layer["name"]
			new_layer.variant = layer["variant"]
			if layer.has("custom_animation"):
				match(layer["custom_animation"]):
					"slash_oversize":
						new_layer.oversize_animation = "slash"
					"thrust_oversize":
						new_layer.oversize_animation = "thrust"
					_:
						print("custom_animation '" + str(layer["custom_animation"]) + "' not supported!")
				
			new_layers.append(new_layer)
			new_layer.load_texture()
			
		blueprint.layers.clear()
		blueprint.add_layers(new_layers)
		await get_tree().process_frame
		blueprint.source_url = data["url"]
		blueprint.credits_txt = str(data["credits"])

	_load_from_blueprint()

func _on_ButtonOpen_pressed():
	if blueprint.source_url != "":
		OS.shell_open(blueprint.source_url)
	else:
		OS.shell_open("https://sanderfrenken.github.io/Universal-LPC-Spritesheet-Character-Generator/")

func _on_LayersList_meta_clicked(meta):
	var tween = get_tree().create_tween()
	tween.set_parallel()
	for sprite in $vpc/vp.get_children():
		var layers = sprite.get_layers()
		for layer in layers:
			var bp_layer = ((layer as LPCSpriteLayer).blueprint_layer as LPCSpriteBlueprintLayer)
			if bp_layer.rel_path == meta:
				tween.tween_method(layer.set_highlight, Color(1,1,1,1), Color(0,0,0,0), 0.5)
				tween.tween_method(layer.set_outline, Color(1,0,0,1), Color(1,0,0,0), 0.5)


func _on_ReplayButton_pressed():
	for sprite in $vpc/vp.get_children():
		sprite.frame = 0

func _on_ReloadButton_pressed():
	if blueprint:
		_load_from_blueprint()
		blueprint.emit_changed()
