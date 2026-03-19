extends Node
## Reddit API singleton — mirrors the GameMaker reddit_demo_server_api functions.
## Register as autoload named "Api".
##
## Usage:
##   Api.load_state(func(ok, data): ...)
##   Api.save_state(level, data, func(ok, result): ...)
##   Api.submit_score(score, func(ok, result): ...)
##   Api.get_leaderboard(limit, func(ok, entries): ...)

var _base_url: String = ""
var _token: String = ""

# Populated after init
var post_id: String = ""
var username: String = ""
var snoovatar: String = ""
var day_number: int = 0

func _ready() -> void:
	_parse_url_params()
	_call_init()

## Set base URL from engine args (passed by main.ts) or fallback for local debug
func _parse_url_params() -> void:
	var args: PackedStringArray = OS.get_cmdline_args()
	for i in range(args.size()):
		if args[i] == "--base-url" and i + 1 < args.size():
			_base_url = args[i + 1]
			print("[api] Base URL from args: ", _base_url)
			return
	# Local debug fallback
	_base_url = "http://localhost:8000"
	print("[api] Base URL fallback: ", _base_url)

## Call /api/init to get post context
func _call_init() -> void:
	var http := HTTPRequest.new()
	http.accept_gzip = false
	add_child(http)
	http.request_completed.connect(func(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		if code == 200:
			var json: Variant = JSON.parse_string(body.get_string_from_utf8())
			if json:
				post_id = json.get("postId", "")
				username = json.get("username", "")
				snoovatar = json.get("snoovatar", "")
				day_number = json.get("dayNumber", 0)
		http.queue_free()
	)
	http.request(_base_url + "/api/init")

## GET /api/state — load player state
func load_state(callback: Callable) -> void:
	var http := HTTPRequest.new()
	http.accept_gzip = false
	add_child(http)
	http.request_completed.connect(func(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		var ok := code == 200
		var data: Variant = null
		if ok:
			data = JSON.parse_string(body.get_string_from_utf8())
		callback.call(ok, data)
		http.queue_free()
	)
	http.request(_base_url + "/api/state")

## POST /api/state — save player state
func save_state(level: int, data: Dictionary, callback: Callable) -> void:
	var http := HTTPRequest.new()
	http.accept_gzip = false
	add_child(http)
	http.request_completed.connect(func(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		var ok := code == 200
		var result: Variant = null
		if ok:
			result = JSON.parse_string(body.get_string_from_utf8())
		callback.call(ok, result)
		http.queue_free()
	)
	var payload := JSON.stringify({"level": level, "data": data})
	var headers := PackedStringArray(["Content-Type: application/json"])
	http.request(_base_url + "/api/state", headers, HTTPClient.METHOD_POST, payload)

## POST /api/score — submit score to leaderboard
func submit_score(score: int, callback: Callable) -> void:
	var http := HTTPRequest.new()
	http.accept_gzip = false
	add_child(http)
	http.request_completed.connect(func(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		var ok := code == 200
		var result: Variant = null
		if ok:
			result = JSON.parse_string(body.get_string_from_utf8())
		callback.call(ok, result)
		http.queue_free()
	)
	var payload := JSON.stringify({"score": score})
	var headers := PackedStringArray(["Content-Type: application/json"])
	http.request(_base_url + "/api/score", headers, HTTPClient.METHOD_POST, payload)

## GET /api/leaderboard — fetch top scores
func get_leaderboard(limit: int, callback: Callable) -> void:
	var http := HTTPRequest.new()
	http.accept_gzip = false
	add_child(http)
	http.request_completed.connect(func(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		var ok := code == 200
		var entries: Variant = null
		if ok:
			entries = JSON.parse_string(body.get_string_from_utf8())
		callback.call(ok, entries)
		http.queue_free()
	)
	http.request(_base_url + "/api/leaderboard?limit=%d" % limit)
