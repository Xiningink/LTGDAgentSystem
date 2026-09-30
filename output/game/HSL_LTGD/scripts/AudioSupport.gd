extends RefCounted
# Runtime audio capability check.
#
# The Dummy audio driver (used by --headless and by scripted frame captures)
# never runs a mix step, so stopped AudioStreamPlayback objects are never
# released and the engine reports leaked instances at exit. Nothing can be
# heard through a dummy device anyway, so the game simply runs its sound bed
# in a "silent" mode when that driver is in use.

static func is_silent() -> bool:
	var driver := AudioServer.get_driver_name()
	if driver.is_empty():
		return true
	return driver.to_lower() == "dummy"
