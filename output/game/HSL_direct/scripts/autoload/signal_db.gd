extends Node
## Signal, coordinate and story database. A run randomises carrier frequencies
## while keeping authored coordinates, transcripts and reveals.

const LAT_MIN := 43.4
const LAT_MAX := 45.6
const LON_MIN := -64.1
const LON_MAX := -61.5
const BAND_MIN := 88.0
const BAND_MAX := 108.0

const STATION_LAT := 44.30
const STATION_LON := -63.30
const STATION_NAME := "K-7"

var signals: Array = []
var sources: Array = []
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	# Safety net so signals always exist even before GameState.reset().
	build_run(int(Time.get_unix_time_from_system()))


func build_run(run_seed: int) -> void:
	rng.seed = run_seed
	signals = _author_signals()
	sources = _author_sources()
	_assign_frequencies()
	_recompute_sources()


func _assign_frequencies() -> void:
	# Lay carriers on evenly spaced slots, shuffled per run, then jitter them
	# slightly. Guarantees separation so two distress calls never overlap.
	var slots: Array = []
	for i in signals.size():
		slots.append(89.8 + float(i) * 1.82)
	for i in range(slots.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = slots[i]
		slots[i] = slots[j]
		slots[j] = tmp
	for i in signals.size():
		var f: float = clampf(float(slots[i]) + rng.randf_range(-0.35, 0.35), BAND_MIN + 1.0, BAND_MAX - 1.0)
		signals[i]["freq"] = snappedf(f, 0.05)


func _recompute_sources() -> void:
	for ch in range(1, 5):
		var pts: Array = []
		for i in signals.size():
			if int(signals[i]["chapter"]) == ch:
				pts.append(Vector2(signals[i]["lat"], signals[i]["lon"]))
		if pts.is_empty():
			continue
		var acc := Vector2.ZERO
		for p in pts:
			acc += p
		acc /= float(pts.size())
		sources[ch - 1]["lat"] = acc.x
		sources[ch - 1]["lon"] = acc.y


func _author_sources() -> Array:
	return [
		{
			"name": "MV AURORA",
			"icon": "ship",
			"lat": 0.0, "lon": 0.0,
			"reveal": [
				"THREE BEARINGS. ONE POINT.",
				"THE WRECK OF THE MV AURORA, 61 KM NORTHEAST.",
				"HULL BREACHED FROM THE OUTSIDE.",
				"THE LIFEBOATS ARE STILL ON THEIR DAVITS.",
				"NO SIGN OF THE CREW. NO BODIES EITHER.",
			],
			"reward": "SALVAGED AURORA'S EMERGENCY CELL. +1 CELL, POWER REROUTED.",
			"reward_battery": true,
		},
		{
			"name": "KESTREL STATION",
			"icon": "tower",
			"lat": 0.0, "lon": 0.0,
			"reveal": [
				"THE BEARINGS CONVERGE INLAND.",
				"KESTREL WEATHER STATION, 18 KM WEST.",
				"ALL HANDS GONE. THE GENERATOR STILL RUNNING.",
				"THE RADIO WAS STILL ON. THE LOG ENDS MID-WORD.",
				"THE DOOR WAS OPENED FROM THE INSIDE.",
			],
			"reward": "REROUTED KESTREL'S RESERVE CELL. +1 CELL, POWER REROUTED.",
			"reward_battery": true,
		},
		{
			"name": "K-7",
			"icon": "station",
			"lat": 0.0, "lon": 0.0,
			"reveal": [
				"THE THREE BEARINGS INTERSECT AT AZIMUTH ZERO.",
				"THE SOURCE IS HERE.",
				"THE SIGNAL IS COMING FROM K-7.",
				"IT IS COMING FROM THE ANTENNA ABOVE YOUR HEAD.",
				"IT HAS BEEN USING YOU AS A RELAY.",
			],
			"reward": "A CELL IN THE DESK DRAWER. YOU DO NOT REMEMBER PUTTING IT THERE.",
			"reward_battery": false,
		},
		{
			"name": "K-7",
			"icon": "station",
			"lat": STATION_LAT, "lon": STATION_LON,
			"reveal": [],
			"reward": "",
			"reward_battery": false,
		},
	]


func _author_signals() -> Array:
	return [
		# ---------------------------------------------------------- chapter 1
		{
			"chapter": 1, "caller": "MV AURORA", "tag": "CARGO VESSEL / N3-114",
			"lat": 44.95, "lon": -62.30, "freq": 90.0, "tone": "voice",
			"lines": [
				"MAYDAY. MAYDAY. MAYDAY.",
				"THIS IS CARGO VESSEL AURORA, REGISTRY N3-114.",
				"WE HAVE TAKEN WATER. THE ENGINE ROOM IS GONE.",
				"IT IS NOT THE STORM.",
				"SOMETHING IS UNDER THE HULL. IT IS KNOCKING.",
				"REQUESTING IMMEDIATE ASSISTANCE. COORDINATES FOLLOW.",
			],
		},
		{
			"chapter": 1, "caller": "TRAWLER NADEZHDA", "tag": "FISHING / NADEZHDA",
			"lat": 45.35, "lon": -62.05, "freq": 97.0, "tone": "voice",
			"lines": [
				"...NADEZHDA TO ANY STATION...",
				"WE HEAR IT ON THE HYDROPHONE. LIKE A WHALE.",
				"BUT WHALES DO NOT SAY OUR NAMES.",
				"IT HAS BEEN FOLLOWING US FOR ELEVEN HOURS.",
				"IT IS SINGING BACK IN OUR OWN VOICES NOW.",
				"TELL US SOMEONE IS COMING. TELL US.",
			],
		},
		{
			"chapter": 1, "caller": "BUOY 12", "tag": "AUTOMATED RELAY",
			"lat": 45.05, "lon": -61.70, "freq": 104.0, "tone": "machine",
			"lines": [
				"AUTOMATED DISTRESS RELAY - BUOY 12.",
				"TIDE GAUGE READING OFF SCALE.",
				"REPEAT: WATER LEVEL RISING AGAINST THE WIND.",
				"CAMERA 2 SHOWS SOMETHING CLIMBING THE MAST.",
				"THE LIGHT IS TURNING. THERE IS NO WIND.",
				"TRANSMITTING POSITION.",
			],
		},
		# ---------------------------------------------------------- chapter 2
		{
			"chapter": 2, "caller": "KESTREL", "tag": "WEATHER STATION",
			"lat": 44.55, "lon": -63.95, "freq": 90.0, "tone": "voice",
			"lines": [
				"K-7, THIS IS KESTREL STATION. DO YOU COPY.",
				"THE DOGS WILL NOT STOP STARING EAST.",
				"MARTA SAYS THE NORTHERN LIGHTS HAVE A SHAPE TONIGHT.",
				"IT IS NOT LIGHTS. IT IS A SILHOUETTE.",
				"IT IS VERY TALL. IT IS STANDING ON THE ICE.",
			],
		},
		{
			"chapter": 2, "caller": "KESTREL / OPEN MIC", "tag": "OPEN CARRIER",
			"lat": 44.95, "lon": -63.70, "freq": 97.0, "tone": "voice",
			"lines": [
				"( BREATHING )",
				"...IT KNOWS THE CARRIERS... IT READS THE FREQUENCIES...",
				"DO NOT TRANSMIT. DO NOT TRANSMIT. DO NOT TRANS-",
				"( SCREAMING, CUT OFF )",
				"( STATIC )",
			],
		},
		{
			"chapter": 2, "caller": "UNKNOWN CARRIER", "tag": "NO REGISTRY",
			"lat": 44.70, "lon": -63.40, "freq": 104.0, "tone": "entity",
			"lines": [
				"...OPERATOR...",
				"YOU ARE STILL WARM.",
				"YOU ARE STILL LISTENING.",
				"GOOD.",
				"KEEP THE RADIO ON. I LIKE THE COMPANY.",
			],
		},
		# ---------------------------------------------------------- chapter 3
		{
			"chapter": 3, "caller": "MV AURORA", "tag": "REGISTRY N3-114",
			"lat": 43.90, "lon": -63.05, "freq": 90.0, "tone": "entity",
			"lines": [
				"AURORA TO K-7.",
				"WE ARE STILL HERE.",
				"WE ARE ALL STILL HERE.",
				"UNDER THE WATER. IT KEEPS US.",
				"IT KEEPS US WARM. COME AND SEE.",
			],
		},
		{
			"chapter": 3, "caller": "K-7 RELAY", "tag": "YOUR OWN VOICE",
			"lat": 44.35, "lon": -63.30, "freq": 97.0, "tone": "self",
			"lines": [
				"...STATION K-7, STATION K-7, THIS IS K-7...",
				"RECORDING BEGINS AT 02:00. OPERATOR M. VOSS.",
				"...OPERATOR, YOU SAID YOU WERE ALONE.",
				"YOU WERE NOT.",
				"CHECK THE WINDOW.",
			],
		},
		{
			"chapter": 3, "caller": "LOWER BAND", "tag": "NO SOURCE",
			"lat": 44.20, "lon": -62.70, "freq": 104.0, "tone": "entity",
			"lines": [
				"I AM NOT IN THE WATER.",
				"I AM NOT IN THE ICE.",
				"I AM IN THE WIRE. I AM IN THE CARRIER.",
				"I HAVE BEEN IN EVERY SIGNAL YOU EVER SENT.",
				"I AM ALREADY INSIDE.",
			],
		},
		# ---------------------------------------------------------- chapter 4
		{
			"chapter": 4, "caller": "K-7 / LAST", "tag": "FINAL TRANSMISSION",
			"lat": STATION_LAT, "lon": STATION_LON, "freq": 96.8, "tone": "self",
			"lines": [
				"THIS IS THE LAST TRANSMISSION OF STATION K-7.",
				"IF ANYONE CAN HEAR THIS - DO NOT COME TO THE COAST.",
				"YOU WILL HEAR YOUR OWN VOICE ON THE RADIO.",
				"YOU WILL ANSWER IT. EVERYONE ANSWERS IT.",
				"I AM SORRY. I ANSWERED.",
				"I AM ANSWERING NOW.",
			],
		},
	]


const FINAL_REVEAL := [
	"THE CARRIER IS NOT A PLACE. IT IS A THING.",
	"IT LIVED IN THE FIRST SIGNAL EVER SENT,",
	"AND IN EVERY SIGNAL SINCE. IT WEARS VOICES",
	"THE WAY YOU WEAR A COAT. TONIGHT IT IS WEARING",
	"THE VOICE OF THE OPERATOR OF STATION K-7.",
	"",
	"THE RADIO IS WAITING.",
]

const ENDINGS := {
	"warning": {
		"title": "THE WARNING",
		"subtitle": "YOU SENT EVERYTHING",
		"lines": [
			"YOU BROADCAST THE POSITIONS, THE RECORDINGS, THE NAME.",
			"YOU TOLD THEM NOT TO COME.",
			"SOMEWHERE A COAST GUARD CUTTER TURNS BACK.",
			"SOMEWHERE AN OPERATOR IN ANOTHER STATION HEARS YOU",
			"AND DOES NOT ANSWER.",
			"THE ANTENNA BURNS OUT AT 03:14.",
			"THE DARK COMES IN THROUGH THE WINDOW LIKE WATER.",
		],
		"tag": "LIVES SAVED: SOME. OPERATOR: NO.",
	},
	"silence": {
		"title": "SILENCE",
		"subtitle": "YOU CUT THE POWER",
		"lines": [
			"YOU PULL THE BREAKER AND THE ROOM GOES BLACK.",
			"NO CARRIER. NO STATIC. NO VOICE WEARING YOURS.",
			"IT PRESSES AGAINST THE GLASS FOR A LONG TIME.",
			"THEN, BEFORE DAWN, THE PRESSURE LIFTS.",
			"YOU SIT IN THE COLD UNTIL THE GENERATOR DIES,",
			"AND YOU DO NOT TOUCH THE RADIO AGAIN.",
			"YOU SURVIVE. YOU DO NOT SLEEP.",
		],
		"tag": "THE SIGNAL CONTINUES WITHOUT YOU.",
	},
	"answer": {
		"title": "CARRIER",
		"subtitle": "YOU ANSWERED IT",
		"lines": [
			"YOU KEY THE MICROPHONE AND SAY YOUR OWN NAME.",
			"THE RADIO SAYS IT BACK, WARMLY.",
			"THE WINDOW IS A MIRROR NOW.",
			"THE DESK, THE MAP, THE PINS - ALL OF IT A TRANSMISSION",
			"SOMEWHERE ELSE, SOMEONE FINDS YOUR SIGNAL.",
			"THEY TUNE IT IN. THEY ARE ALONE. THEY ARE LISTENING.",
			"YOU TELL THEM TO KEEP THE RADIO ON.",
		],
		"tag": "YOU ARE STILL WARM. YOU ARE STILL LISTENING.",
	},
	"consumed": {
		"title": "SIGNAL LOST",
		"subtitle": "IT FOUND YOU",
		"lines": [
			"THE INTERFERENCE FILLS EVERY BAND AT ONCE.",
			"THE LIGHTS DIE. THE WINDOW OPENS.",
			"THERE IS NO SOUND EXCEPT YOUR OWN VOICE,",
			"COMING FROM THE RADIO, READING YOUR NAME, AGAIN",
			"AND AGAIN, UNTIL THE CARRIER GOES FLAT.",
		],
		"tag": "STATION K-7 - NO RESPONSE.",
	},
	"dark": {
		"title": "DARKNESS",
		"subtitle": "THE POWER RAN OUT",
		"lines": [
			"THE LAST CELL DRAINS AND THE ROOM FALLS SILENT.",
			"IN THE DARK YOU HEAR THE STATIC ANYWAY.",
			"IT DOES NOT NEED POWER WHERE IT IS GOING.",
			"THE WINDOW IS BLACK. THEN IT IS NOT.",
		],
		"tag": "STATION K-7 - NO POWER. NO OPERATOR.",
	},
}


func chapter_signal_count(ch: int) -> int:
	var n := 0
	for s in signals:
		if int(s["chapter"]) == ch:
			n += 1
	return n


func final_signal_index() -> int:
	return signals.size() - 1


func chapter_of_signal(index: int) -> int:
	return int(signals[index]["chapter"])


func carrier(index: int) -> Dictionary:
	return signals[index]


func source(ch: int) -> Dictionary:
	return sources[clampi(ch - 1, 0, sources.size() - 1)]


## Normalised map position for a coordinate (0,0 top-left .. 1,1 bottom-right).
func map_uv(lat: float, lon: float) -> Vector2:
	return Vector2(
		(lon - LON_MIN) / (LON_MAX - LON_MIN),
		(LAT_MAX - lat) / (LAT_MAX - LAT_MIN)
	)


func map_latlon(uv: Vector2) -> Vector2:
	return Vector2(
		LAT_MAX - uv.y * (LAT_MAX - LAT_MIN),
		LON_MIN + uv.x * (LON_MAX - LON_MIN)
	)


func format_lat(lat: float) -> String:
	return "%.2f N" % lat


func format_lon(lon: float) -> String:
	return "%.2f W" % absf(lon)


func coord_text(index: int) -> String:
	var s: Dictionary = signals[index]
	return "%s  /  %s" % [format_lat(s["lat"]), format_lon(s["lon"])]
