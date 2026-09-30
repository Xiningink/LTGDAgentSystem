# Static content for the five distress signals the operator can recover.
#
# lat is degrees North, lon is degrees West (positive numbers).
# cache == true means the transmission carries the location of a reserve cell.

const LAT_MIN := 40.0
const LAT_MAX := 56.0
const LON_MIN := 8.0
const LON_MAX := 24.0

const STATION_NAME := "KESTREL-9"
const STATION_LAT := 52.0
const STATION_LON := 18.0

const SIGNALS := [
	{
		"id": 0,
		"freq": 91.6,
		"callsign": "MV GREYLING",
		"coords": "51.4 N / 19.2 W",
		"lat": 51.4,
		"lon": 19.2,
		"cache": true,
		"lines": [
			"MAYDAY MAYDAY MAYDAY",
			"THIS IS MV GREYLING, HULL BREACHED.",
			"WE ARE TAKING WATER FAST.",
			"POSITION 51.4 N / 19.2 W.",
			"CREW OF SIX. ...FIVE. FIVE OF US.",
			"THE RAFT STILL HAS A CELL. TAKE IT.",
			"SOMETHING KEEPS REPEATING OUR",
			"MESSAGE BACK AT US, A HEARTBEAT LATE."
		]
	},
	{
		"id": 1,
		"freq": 94.3,
		"callsign": "OUTPOST PELICAN",
		"coords": "47.8 N / 21.4 W",
		"lat": 47.8,
		"lon": 21.4,
		"cache": true,
		"lines": [
			"AUTOMATED BURST - RELAY 1 OF 1.",
			"RESERVE CELLS STORED LOCKER FOUR.",
			"GRID 47.8 N / 21.4 W.",
			"GENERATOR WENT DOWN ELEVEN DAYS AGO.",
			"ALL PERSONNEL ACCOUNTED FOR.",
			"ALL PERSONNEL ACCOUNTED FOR.",
			"ALL PERSONNEL ACCOUNTED FOR.",
			"PLEASE STOP KNOCKING ON THE DOOR."
		]
	},
	{
		"id": 2,
		"freq": 97.5,
		"callsign": "KESTREL-9 / ECHO",
		"coords": "54.6 N / 22.6 W",
		"lat": 54.6,
		"lon": 22.6,
		"cache": false,
		"lines": [
			"KESTREL-9. KESTREL-9. COME IN.",
			"THIS IS KESTREL-9 CALLING KESTREL-9.",
			"BEARING 54.6 N / 22.6 W.",
			"YOU ARE NOT THE OPERATOR.",
			"THE OPERATOR SIGNED OFF ON DAY TWO.",
			"YOU HAVE BEEN ALONE IN THAT ROOM",
			"ELEVEN DAYS. THE WINDOW IS NOT A WINDOW."
		]
	},
	{
		"id": 3,
		"freq": 101.2,
		"callsign": "TUG ARDENT",
		"coords": "49.3 N / 15.8 W",
		"lat": 49.3,
		"lon": 15.8,
		"cache": true,
		"lines": [
			"LAST TRANSMISSION OF TUG ARDENT.",
			"WE RAN AGROUND CHASING THE LIGHT.",
			"WRECK AT 49.3 N / 15.8 W.",
			"THE INTERFERENCE IS NOT WEATHER.",
			"IT LEARNS THE BAND SEGMENT YOU LOVE.",
			"IT HUMS ALONG WITH THE DIAL.",
			"CELLS INTACT AMIDSHIPS. TAKE THEM.",
			"DO NOT LET IT HEAR THE LOCK TONE."
		]
	},
	{
		"id": 4,
		"freq": 105.9,
		"callsign": "UNTITLED",
		"coords": "53.1 N / 17.5 W",
		"lat": 53.1,
		"lon": 17.5,
		"cache": false,
		"lines": [
			"FIVE BEARINGS. ONE ORIGIN.",
			"53.1 N / 17.5 W ON THE CHART.",
			"BUT THE BEARINGS DO NOT COME",
			"FROM THE WATER.",
			"THEY COME FROM UNDER THE DESK.",
			"FROM UNDER THE FLOOR.",
			"FROM BEHIND THE GLASS.",
			"IT IS ALREADY INSIDE THE STATION."
		]
	}
]

const WHISPERS := [
	"THE DIAL MOVED ON ITS OWN.",
	"SOMETHING IS BREATHING ON THE BAND.",
	"DON'T LOOK AT THE WINDOW.",
	"YOUR CALLSIGN IS NOT KESTREL-9.",
	"IT KNOWS THE FREQUENCY YOU LEFT.",
	"THE DESK IS WARM. YOU DID NOT WARM IT.",
	"COUNT THE PINS AGAIN.",
	"THE DOOR WAS UNLOCKED AN HOUR AGO."
]

const CACHE_LINES := [
	"RESERVE CELL RECOVERED.",
	"SUPPLY CACHE INTERCEPTED.",
	"CELL BANK REFILLED FROM WRECKAGE."
]
