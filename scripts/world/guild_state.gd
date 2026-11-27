class_name GuildState
extends RefCounted

## The player's guild: the roster the hall panel shows, the dialog the nexus
## tile opens, and the invite another member can send. Account-wide, so it is
## kept across realms (never cleared on a realm reset), like account progress.
##
## The server is the authority on every rank rule; the controls here are only
## shown when the local rank could use them, and the server re-checks each one.

const RANKS := ["Owner", "Leader", "Officer", "Member", "Initiate"]
const RANK_OWNER := 0
const RANK_LEADER := 1
const RANK_OFFICER := 2
const RANK_INITIATE := 4

var version := 0

var in_guild := false
var guild_id := ""
var guild_name := ""
var your_rank := RANK_INITIATE
var can_edit_hall := false
var members: Array = []          # [{ "name": String, "rank": int }, ...]

# The nexus "found a guild" dialog.
var create_open := false
var create_fame := 0
var create_in_guild := false

# The hall roster panel.
var roster_open := false


# One-shot editor hand-off: a token to open the scoped hall editor with.
var editor_token := ""


func apply_create_dialog(data: Dictionary, local_id: int) -> void:
	if int(data.get("playerId", 0)) != local_id:
		return
	create_fame = int(data.get("accountFame", 0))
	create_in_guild = bool(data.get("inGuild", false))
	create_open = true
	version += 1


func apply_info(data: Dictionary, local_id: int) -> void:
	if int(data.get("playerId", 0)) != local_id:
		return
	in_guild = bool(data.get("inGuild", false))
	guild_id = String(data.get("guildId", ""))
	guild_name = String(data.get("guildName", ""))
	your_rank = int(data.get("yourRank", RANK_INITIATE))
	can_edit_hall = bool(data.get("canEditHall", false))
	members = []
	for row in data.get("members", []):
		members.append({ "name": String(row.get("name", "?")), "rank": int(row.get("rank", RANK_INITIATE)) })
	if not in_guild:
		roster_open = false
		create_open = false
	elif bool(data.get("openRoster", false)):
		roster_open = true
	version += 1


func apply_editor(data: Dictionary) -> void:
	editor_token = String(data.get("token", ""))
	version += 1


func close_create() -> void:
	create_open = false
	version += 1


func close_roster() -> void:
	roster_open = false
	version += 1


## Hand out the pending editor token once; "" when there is none waiting.
func take_editor_token() -> String:
	var token := editor_token
	editor_token = ""
	return token


static func rank_name(rank: int) -> String:
	return RANKS[rank] if rank >= 0 and rank < RANKS.size() else "Member"


func is_owner() -> bool:
	return in_guild and your_rank == RANK_OWNER


func can_invite() -> bool:
	return in_guild and your_rank <= RANK_OFFICER


## Whether the local player could remove / rank a member of `target_rank`:
## Owner over any non-owner, Leader over Officer and below, Officer over Initiate.
func can_moderate(target_rank: int) -> bool:
	if not in_guild or target_rank == RANK_OWNER or your_rank >= target_rank:
		return false
	match your_rank:
		RANK_OWNER, RANK_LEADER:
			return true
		RANK_OFFICER:
			return target_rank == RANK_INITIATE
		_:
			return false


## Only Owner/Leader reassign ranks, and only for members they outrank.
func can_rank(target_rank: int) -> bool:
	return in_guild and your_rank <= RANK_LEADER and your_rank < target_rank and target_rank != RANK_OWNER
