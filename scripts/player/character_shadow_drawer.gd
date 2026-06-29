class_name CharacterShadowDrawer
extends Node2D
## Draws a procedural drop-shadow of the climber figure.
## Created and managed by the CharacterBody2D (character.gd).

var owner_ref: Node2D = null

func _draw() -> void:
	if owner_ref == null:
		return
	var o = owner_ref
	var light: Dictionary = o._get_light_info()
	var intensity: float = light["intensity"] as float
	if intensity <= 0.01:
		modulate.a = 0.0
		return

	modulate.a = clamp(intensity * 0.30, 0.0, 0.30)

	var light_dir: Vector2 = light["direction"] as Vector2
	var off: Vector2 = Vector2(-light_dir.x * 8.0, light_dir.y * 5.0)

	var lhd = o.lh.node.position   + o.lh.shake_offset + o.lh.visual_offset + off
	var rhd = o.rh.node.position   + o.rh.shake_offset + o.rh.visual_offset + off
	var lfd = o.lf.node.position   + o.lf.shake_offset + o.lf.visual_offset + off
	var rfd = o.rf.node.position   + o.rf.shake_offset + o.rf.visual_offset + off
	var lhj = o._lh_joint.position + off
	var rhj = o._rh_joint.position + off
	var lfj = o._lf_joint.position + off
	var rfj = o._rf_joint.position + off

	var head_pos  = Vector2(0.0, o.HEAD_OFFSET)        + off
	var left_sh   = Vector2(-o.SHOULDER_OFFSET, 0.0)   + off
	var right_sh  = Vector2( o.SHOULDER_OFFSET, 0.0)   + off
	var left_hip  = Vector2(-o.HIP_OFFSET, o.HIP_DOWN) + off
	var right_hip = Vector2( o.HIP_OFFSET, o.HIP_DOWN) + off
	var hip_pos   = Vector2(0.0, o.HIP_DOWN)           + off
	var left_sl   = left_sh.lerp(lhj,  0.35)
	var right_sl  = right_sh.lerp(rhj, 0.35)

	var sc = Color(0.0, 0.0, 0.0, 1.0)

	draw_line(left_hip,  lfj,  sc, 12.0); draw_line(lfj, lfd, sc, 11.0)
	draw_circle(lfj, 5, sc); draw_circle(lfd, 9, sc)
	draw_line(right_hip, rfj, sc, 12.0); draw_line(rfj, rfd, sc, 11.0)
	draw_circle(rfj, 5, sc); draw_circle(rfd, 9, sc)
	draw_line(left_hip,  right_hip,                         sc, 17.0)
	draw_line(hip_pos,   Vector2.ZERO + off,                 sc, 19.0)
	draw_line(Vector2.ZERO + off, head_pos + Vector2(0, 16), sc, 17.0)
	draw_circle(left_sh,  5, sc); draw_circle(right_sh, 5, sc)
	draw_line(left_sh,  left_sl,  sc, 12.0); draw_line(left_sl,  lhj, sc, 12.0)
	draw_circle(lhj, 5, sc); draw_line(lhj, lhd, sc, 10.0); draw_circle(lhd, 8, sc)
	draw_line(right_sh, right_sl, sc, 12.0); draw_line(right_sl, rhj, sc, 12.0)
	draw_circle(rhj, 5, sc); draw_line(rhj, rhd, sc, 10.0); draw_circle(rhd, 8, sc)
	draw_line(head_pos + Vector2(0, 14), head_pos + Vector2(0, 4), sc, 10.0)
	draw_circle(head_pos, 16, sc)
