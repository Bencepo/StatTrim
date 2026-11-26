-- luacheck configuration for StatTrim (WoW Forever, Lua 5.1)
std = "lua51"
max_line_length = false
codes = true

-- Reading WoW API globals (113) is not reported: there are too many to list.
-- Writing globals is, so a typo cannot create a new global without notice.
ignore = { "113", "212/self" }

globals = {
	"StatTrimDB",
	"StatTrimCharDB",
	"SLASH_STATTRIM1",
	"SLASH_STATTRIM2",
	"SlashCmdList",
	"StatTrim_OnCompartmentClick",
}

exclude_files = { ".release/**", "Libs/**" }
