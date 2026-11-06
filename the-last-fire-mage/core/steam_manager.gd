extends Node
## Steam init + lobbies + SteamMultiplayerPeer. Hands the peer to NetworkManager.
## Change APP_ID / GAME_KEY when you get your own Steam app.

signal lobby_list_updated(lobbies: Array) ## [{id, name, members}]
signal status_changed(text: String)

const APP_ID := 480 ## Spacewar test app. Replace with your own app ID later.
const GAME_KEY := "lastfiremage_spike" ## lobby filter so we only see our lobbies on app 480

var available := false
var init_message := "Not initialized"
var steam_id := 0
var persona_name := ""
var lobby_id := 0


func _ready() -> void:
	if NetworkManager.args.has("no-steam"):
		init_message = "Disabled (--no-steam)"
		print("[Steam] ", init_message)
		return
	OS.set_environment("SteamAppId", str(APP_ID))
	OS.set_environment("SteamGameId", str(APP_ID))
	var res: Dictionary = Steam.steamInitEx(APP_ID, true) # true = GodotSteam runs callbacks itself
	print("[Steam] init: ", res)
	if int(res.get("status", 1)) != 0:
		init_message = "Steam not available: %s (is Steam running and logged in?)" % res.get("verbal", "?")
		return
	available = true
	steam_id = Steam.getSteamID()
	persona_name = Steam.getPersonaName()
	init_message = "Logged in as %s" % persona_name
	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_joined.connect(_on_lobby_joined)
	Steam.lobby_match_list.connect(_on_lobby_match_list)
	Steam.join_requested.connect(_on_join_requested)
	_check_command_line_invite()


func host_lobby() -> void:
	if not available:
		return
	status_changed.emit("Creating Steam lobby...")
	Steam.createLobby(Steam.LOBBY_TYPE_PUBLIC, NetworkManager.MAX_PLAYERS)


func request_lobby_list() -> void:
	if not available:
		return
	Steam.addRequestLobbyListDistanceFilter(Steam.LOBBY_DISTANCE_FILTER_WORLDWIDE)
	Steam.addRequestLobbyListStringFilter("game", GAME_KEY, Steam.LOBBY_COMPARISON_EQUAL)
	Steam.requestLobbyList()
	status_changed.emit("Searching lobbies...")


func join_lobby(id: int) -> void:
	if not available:
		return
	if NetworkManager.mode != NetworkManager.Mode.OFFLINE:
		NetworkManager.leave("Switching lobby")
	status_changed.emit("Joining lobby %d ..." % id)
	Steam.joinLobby(id)


func invite_friends() -> void:
	if available and lobby_id != 0:
		Steam.activateGameOverlayInviteDialog(lobby_id)


func leave_lobby() -> void:
	if available and lobby_id != 0:
		Steam.leaveLobby(lobby_id)
	lobby_id = 0


# ---------------------------------------------------------------- callbacks

func _on_lobby_created(result: int, id: int) -> void:
	if result != 1: # k_EResultOK
		status_changed.emit("Lobby creation failed (result %d)" % result)
		NetworkManager.connection_failed.emit("Steam lobby creation failed")
		return
	lobby_id = id
	Steam.setLobbyJoinable(id, true)
	Steam.setLobbyData(id, "game", GAME_KEY)
	Steam.setLobbyData(id, "name", "%s's game" % persona_name)
	var peer := SteamMultiplayerPeer.new()
	var err := peer.create_host(0)
	if err != OK:
		NetworkManager.connection_failed.emit("SteamMultiplayerPeer.create_host failed (%d)" % err)
		return
	print("[Steam] Lobby created ", id)
	NetworkManager.start_host_with_peer(peer, NetworkManager.Mode.STEAM)


func _on_lobby_joined(id: int, _permissions: int, _locked: bool, response: int) -> void:
	if response != 1: # k_EChatRoomEnterResponseSuccess
		status_changed.emit("Could not join lobby (response %d)" % response)
		NetworkManager.connection_failed.emit("Could not join Steam lobby")
		return
	lobby_id = id
	var owner_id := Steam.getLobbyOwner(id)
	if owner_id == steam_id:
		return # we are the host; already set up in _on_lobby_created
	var peer := SteamMultiplayerPeer.new()
	var err := peer.create_client(owner_id, 0)
	if err != OK:
		NetworkManager.connection_failed.emit("SteamMultiplayerPeer.create_client failed (%d)" % err)
		return
	print("[Steam] Joined lobby ", id, " owner ", owner_id)
	status_changed.emit("Connecting to host via Steam...")
	NetworkManager.start_client_with_peer(peer, NetworkManager.Mode.STEAM)


func _on_lobby_match_list(lobbies: Array) -> void:
	var out := []
	for id in lobbies:
		out.append({
			"id": id,
			"name": Steam.getLobbyData(id, "name"),
			"members": Steam.getNumLobbyMembers(id),
		})
	status_changed.emit("Found %d lobbies" % out.size())
	lobby_list_updated.emit(out)


func _on_join_requested(id: int, _friend_id: int) -> void:
	join_lobby(id) # accepted an invite / "Join game" from the Steam overlay or friends list


func _check_command_line_invite() -> void:
	# Launched from a Steam invite while the game was closed: `+connect_lobby <id>`
	var a := OS.get_cmdline_args()
	var i := a.find("+connect_lobby")
	if i >= 0 and i + 1 < a.size() and int(a[i + 1]) > 0:
		join_lobby.call_deferred(int(a[i + 1]))
