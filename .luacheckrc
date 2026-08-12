-- .luacheckrc
std = "lua51"
language = "en"

global = false

read_globals = {
   "UIParent", "DEFAULT_CHAT_FRAME", "ChatFrame1", "SlashCmdList", "GetLocale",
   "GetTime", "GetBuildInfo", "UnitName", "UnitClass", "GetItemInfo", "GetSpellInfo",
   "InterfaceOptionsFrame_OpenToCategory", "PlaySound", "SOUNDKIT",
   "LibStub", "AceLibrary", "ChatThrottleLib",
   "TSM", "TSMAPI"
}

exclude_files = {
   "TradeSkillMaster/Compat/**",
   "TradeSkillMaster/External/**"
}

max_line_length = false
