extends SceneTree

## Regression harness for Puzzle Magnet Lab.
##
## Replays the BFS-shortest solution for every chamber through the *shipped*
## GDScript simulation and asserts the core reaches the airlock in exactly the
## published par. Run it with:
##
##   Godot_v4.6.2-stable_win64_console.exe --headless --path output/game \
##       --script output/dev/selftest.gd
##
## Keep the SOLUTIONS table in sync with output/dev/solve.py.

const SOLUTIONS := {
	"1-1": "RRRDDDRR",
	"1-2": "LUURDRRRR",
	"1-3": "URRDDRDLRRR",
	"1-4": "RURURRRRDDDDDR",
	"2-1": "RRRRRR",
	"2-2": "URUUDDDRURRUUDDDRDD",
	"2-3": "RRRRDDDDRRR",
	"2-4": "RRRRRDDDDDRR",
	"3-1": "RRRDDDDRRRR",
	"3-2": "UURULLLDDDDRRRRRD",
	"3-3": "RRRRRDDRUUDDDDDRR",
	"3-4": "URUURRRRDLURULDDDDRRDD",
	"4-1": "URUURRRRRDLUURDDDDRDD",
	"4-2": "RRRRDDRRRDD",
	"4-3": "UULLURRRRRRDLUURDDDDDDRR",
	"4-4": "ULLURRRRRURDRULDDDLDDRUDDRR",
}

const DIRS := {
	"U": Vector2i(0, -1),
	"D": Vector2i(0, 1),
	"L": Vector2i(-1, 0),
	"R": Vector2i(1, 0),
}

var failures: int = 0


func _initialize() -> void:
	var sim_script: GDScript = load("res://scripts/sim.gd")
	var levels_script: GDScript = load("res://scripts/levels.gd")
	if sim_script == null or levels_script == null:
		push_error("selftest: cannot load project scripts (is --path correct?)")
		quit(2)
		return

	var data: Dictionary = levels_script.data()
	var levels: Array = data.get("levels", [])
	print("Puzzle Magnet Lab - self test (%d chambers)" % levels.size())
	for level in levels:
		_check(sim_script, level)

	# Sanity checks that do not depend on a solution.
	_check_rule_isolation(sim_script)
	_check_hazard_neutralisation(sim_script)
	_check_gate_pairing(levels_script, levels)
	await _check_ui_flow(levels)

	if failures == 0:
		print("ALL CHECKS PASSED")
	else:
		print("%d CHECK(S) FAILED" % failures)
	quit(1 if failures > 0 else 0)


## Drive the real Main scene through the first chamber and the retry path.
func _check_ui_flow(levels: Array) -> void:
	var packed: PackedScene = load("res://Main.tscn")
	if packed == null:
		_fail("ui", "Main.tscn could not be loaded")
		return
	var save := root.get_node_or_null("Save")
	if save == null:
		_fail("ui", "Save autoload missing")
		return
	var backup_best: Dictionary = save.best_moves.duplicate()
	var backup_unlocked: int = save.unlocked

	var main := packed.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	main.play_level(0)
	await process_frame
	var screen = main.get_node("GameplayScreen")
	var board = screen.get_child(0) if false else screen._board
	if board == null or board.sim == null:
		_fail("ui", "gameplay screen did not open a chamber")
		main.queue_free()
		return
	if board.moves != 0 or board.sim.player == Vector2i.ZERO:
		_fail("ui", "chamber 1 did not initialise cleanly")

	var path := String(SOLUTIONS["1-1"])
	for i in range(path.length()):
		board._busy = 0.0
		if not board.try_move(DIRS[path.substr(i, 1)]):
			_fail("ui", "move %d rejected while replaying chamber 1" % (i + 1))
			break
	await process_frame
	if not board.sim.solved():
		_fail("ui", "chamber 1 did not reach the airlock")
	elif int(board.moves) != int(levels[0].get("par", -1)):
		_fail("ui", "move counter reads %d" % board.moves)
	elif not screen._victory_visible():
		_fail("ui", "victory overlay did not appear")
	elif not save.best_moves.has("1-1"):
		_fail("ui", "result was not recorded")
	elif save.unlocked < 2:
		_fail("ui", "next chamber was not unlocked")
	else:
		print("  [ ok ] ui      chamber 1 solves, overlay opens, progress saves")

	# Retry must hand control back to the player.
	board.reset_level()
	await process_frame
	if not board.input_enabled or board.moves != 0 or board.sim.solved():
		_fail("ui", "reset did not restore a playable chamber")
	else:
		print("  [ ok ] ui      reset restores a playable chamber")

	board._busy = 0.0
	board.try_move(Vector2i(1, 0))
	if not board.can_undo():
		_fail("ui", "undo stack stayed empty after a move")
	else:
		board._busy = 0.0
		board.undo()
		if board.moves != 0 or board.sim.items.size() == 0:
			_fail("ui", "undo did not restore the previous state")
		else:
			print("  [ ok ] ui      undo restores the previous state")

	save.best_moves = backup_best
	save.unlocked = backup_unlocked
	save.save_data()
	main.queue_free()
	await process_frame


func _check(sim_script: GDScript, level: Dictionary) -> void:
	var id := String(level.get("id", "?"))
	var sim = sim_script.new()
	sim.load_level(level)
	var path := String(SOLUTIONS.get(id, ""))
	if path.is_empty():
		_fail(id, "no reference solution recorded")
		return
	var moves := 0
	for i in range(path.length()):
		var ch := path.substr(i, 1)
		var result: Dictionary = sim.try_move(DIRS[ch])
		if not bool(result.get("ok", false)):
			_fail(id, "move %d (%s) was rejected: %s" % [i + 1, ch, String(result.get("reason", ""))])
			return
		moves += 1
	if not sim.solved():
		_fail(id, "core never reached the airlock")
		return
	var par := int(level.get("par", -1))
	if moves != par:
		_fail(id, "solved in %d moves but par says %d" % [moves, par])
		return
	print("  [ ok ] %-4s %-18s par %-3d %s" % [id, String(level.get("name", "")), par, path])


func _check_rule_isolation(sim_script: GDScript) -> void:
	# A metal crate may shove metal, but never a magnet.
	var probe := {
		"map": [
			"#######",
			"#@CB..#",
			"#....E#",
			"#######",
		],
	}
	var sim = sim_script.new()
	sim.load_level(probe)
	var result: Dictionary = sim.try_move(Vector2i(1, 0))
	if bool(result.get("ok", false)):
		_fail("rule", "metal crate was allowed to shove a magnet")
	else:
		print("  [ ok ] rule    metal crates cannot shove magnets")


func _check_hazard_neutralisation(sim_script: GDScript) -> void:
	var probe := {
		"map": [
			"########",
			"#@.Cx.E#",
			"########",
		],
	}
	var sim = sim_script.new()
	sim.load_level(probe)
	sim.try_move(Vector2i(1, 0))
	sim.try_move(Vector2i(1, 0))
	if not bool(sim.inert.has(Vector2i(4, 1))):
		_fail("rule", "pushing a crate into a hazard did not short the hazard out")
		return
	if sim.items.size() != 0:
		_fail("rule", "the metal crate survived the hazard")
		return
	for i in range(3):
		sim.try_move(Vector2i(1, 0))
	if not sim.solved():
		_fail("rule", "core could not walk through the shorted hazard")
		return
	print("  [ ok ] rule    metal crate shorts out a hazard and is consumed")


func _check_gate_pairing(levels_script: GDScript, levels: Array) -> void:
	var sim_script: GDScript = load("res://scripts/sim.gd")
	for level in levels:
		var id := String(level.get("id", "?"))
		var sim = sim_script.new()
		sim.load_level(level)
		for letter in sim_script.GATE_LETTERS:
			var gates: Array = sim.gate_positions(letter)
			if gates.is_empty():
				continue
			var plates: Array = sim.plate_positions(letter.to_lower())
			if plates.is_empty():
				_fail(id, "gate %s has no matching plate" % letter)
			elif sim.gate_open(letter):
				_fail(id, "gate %s starts open" % letter)
	print("  [ ok ] gates   every gate has plates and starts sealed")


func _fail(id: String, message: String) -> void:
	failures += 1
	print("  [FAIL] %-4s %s" % [id, message])
