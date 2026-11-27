extends GutTest


func test_found_guild_tile_names_your_guild() -> void:
	var tile := {"type": "create_guild", "name": "Guild Charter"}
	assert_eq(TileInteract.verb(tile, "AdminsOnly"), "Your Guild: AdminsOnly")


func test_found_guild_tile_without_a_guild_keeps_its_prompt() -> void:
	var tile := {"type": "create_guild", "name": "Guild Charter"}
	assert_eq(TileInteract.verb(tile), "Use Guild Charter")


func test_create_dialog_refusal_names_the_guild() -> void:
	assert_eq(CreateGuildDialog.already_in("AdminsOnly"), "You are already in AdminsOnly.")
	assert_eq(CreateGuildDialog.already_in(""), "You are already in a guild.")


func test_roster_standing_line() -> void:
	assert_eq(GuildRosterPanel.standing("Owner", 1), "You are Owner   -   1 member")
	assert_eq(GuildRosterPanel.standing("Officer", 4), "You are Officer   -   4 members")


func test_guild_shelf_prompt_and_title() -> void:
	assert_eq(TileInteract.verb({"type": "guild_potion_storage"}), "Open Guild Potion Storage")
	assert_eq(ItemStorePanel.title(ItemStore.KIND_GUILD_POTION), "GUILD POTION STORAGE")
	assert_eq(ItemStorePanel.title(ItemStore.KIND_POTION), "POTION STORAGE")
