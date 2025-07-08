---@class PlayerHook : ToolClass
PlayerHook = class()

dofile( "$SURVIVAL_DATA/Scripts/game/managers/RespawnManager.lua" )

local SAVEKEY = "38d8bd7e-e2d4-42cc-8f2b-5acb2b03fccd"
local SETTINGSPATH = "$CONTENT_DATA/presets.json"

local function loadPresets()
    if sm.json.fileExists(SETTINGSPATH) then
        return sm.json.open(SETTINGSPATH)
    end

    return {}
end

function sm.GetPlayerTeam(player)
    return (player.publicData or {}).survivalExtensionTeam
end

local function cl_GetPlayerTeam(player)
    return (player.clientPublicData or {}).survivalExtensionTeam
end

local function cl_GetPlayerTeamFull(player)
    local data = (player.clientPublicData or {})
    local team = data.survivalExtensionTeam
    if team then
        return ("[%s#ffffff] "):format(data.survivalExtensionTeamColour..team)
    end

    return ""
end

local function GetTeamData(team)
    return sm.SURVIVAL_EXTENSION.teams[team] or { colour = "#ffffff" }
end

local function savePreset(presets, name)
    presets[name] = sm.SURVIVAL_EXTENSION
    sm.json.save(presets, SETTINGSPATH)
end

sm.SURVIVAL_EXTENSION_ruleToSyncToPlayers = {
    hunger = true,
    thirst = true,
    respawnCooldown = true
}
function sm.SURVIVAL_EXTENSION_syncToPlayers(player)
    local data = {}
    for k, v in pairs(sm.SURVIVAL_EXTENSION_ruleToSyncToPlayers) do
        data[k] = sm.SURVIVAL_EXTENSION[k]
    end

    if player then
        sm.event.sendToPlayer(player, "sv_syncRules", data)
    else
        for k, v in pairs(sm.player.getAllPlayers()) do
            sm.event.sendToPlayer(v, "sv_syncRules", data)
        end
    end
end

function isAnyOf(is, off)
	for _, v in pairs(off) do
		if is == v then
			return true
		end
	end
	return false
end

--set to empty table before loading
sm.SURVIVAL_EXTENSION = sm.SURVIVAL_EXTENSION or {}

function PlayerHook:server_onCreate()
    if sm.PLAYERHOOK then return end --avoid multiple loads

    local saved = self.storage:load() --sm.storage.load(SAVEKEY)
    sm.SURVIVAL_EXTENSION = saved or {
        pvp = true,
        health_regen = true,
        hunger = true,
        thirst = true,
        breath = true,
        spawn_hp = 100,
        spawn_water = 100,
        spawn_food = 100,
        collisionTumble = true,
        collisionDamage = true,
        godMode = false,
        dropItems = true,
        playerSpawns = {},
        teams = {},
        friendlyFire = false,
        respawnCooldown = 40,
        unSeatOnDamage = true,
    }

    if not sm.SURVIVAL_EXTENSION.respawnCooldown then
        sm.SURVIVAL_EXTENSION.respawnCooldown = 40
    end

    if not sm.SURVIVAL_EXTENSION.unSeatOnDamage == nil then
        sm.SURVIVAL_EXTENSION.unSeatOnDamage = true
    end

    self:sv_saveSettings()

    sm.SURVIVAL_EXTENSION_syncToPlayers()

    g_respawnManager = RespawnManager()
	g_respawnManager:sv_onCreate( sm.world.getCurrentWorld() )
    sm.RESPAWNMANAGER = g_respawnManager

    sm.PLAYERHOOK = self.tool
end

function PlayerHook:sv_saveSettings()
    self.storage:save(sm.SURVIVAL_EXTENSION)
    --sm.storage.save(SAVEKEY, sm.SURVIVAL_EXTENSION)
end

function PlayerHook:sv_saveAndChat(msg)
    self:sv_saveSettings()
    self:sv_chatMessage(msg)
end

function PlayerHook:sv_saveAndChat_single(player, msg)
    if type(player) == "table" then
        player, msg = player[1], player[2]
    end
    self:sv_saveSettings()
    self.network:sendToClient(player, "cl_chatMessage", msg)
end

function PlayerHook:sv_chatMessage(msg)
    self.network:sendToClients("cl_chatMessage", msg)
end

function PlayerHook:sv_chatMessage_single(player, msg)
    if type(player) == "table" then
        player, msg = player[1], player[2]
    end
    self.network:sendToClient(player, "cl_chatMessage", msg)
end

function PlayerHook:sv_OnPlayerDeath(args)
    local attacker, victim = args.attacker, args.victim
    self.network:sendToClients(
        "cl_chatMessage",
        ("%s #ffffffkilled %s#ffffff!"):format(
            GetTeamData(sm.GetPlayerTeam(attacker)).colour..attacker:getName(),
            GetTeamData(sm.GetPlayerTeam(victim)).colour..victim:getName()
        )
    )
end



local charIdToName = {
    ["264a563a-e304-430f-a462-9963c77624e9"] = "Woc",
    ["04761b4a-a83e-4736-b565-120bc776edb2"] = "Tapebot",
    ["c3d31c47-0c9b-4b07-9bd4-8f022dc4333e"] = "Red Tapebot",
    ["9dbbd2fb-7726-4e8f-8eb4-0dab228a561d"] = "Tapebot",
    ["fcb2e8ce-ca94-45e4-a54b-b5acc156170b"] = "Tapebot",
    ["68d3b2f3-ed4b-4967-9d22-8ee6f555df63"] = "Tapebot",
    ["8984bdbf-521e-4eed-b3c4-2b5e287eb879"] = "Green Totebot",
    ["c8bfb8f3-7efc-49ac-875a-eb85ac0614db"] = "Haybot",
    ["9f4fde94-312f-4417-b13b-84029c5d6b52"] = "Farmbot",
    ["48c03f69-3ec8-454c-8d1a-fa09083363b1"] = "Glowbug"
}

function PlayerHook:sv_OnPlayerDeathByUnit(args)
    ---@type Player
    local victim = args.victim
    if not sm.exists(args.attacker) then
        self.network:sendToClients(
            "cl_chatMessage",
            ("%s #ffffffkilled %s#ffffff!"):format(
                "unknown",
                GetTeamData(sm.GetPlayerTeam(victim)).colour..victim:getName()
            )
        )

        return
    end

    ---@type Character
    local attacker = args.attacker.character
    self.network:sendToClients(
        "cl_chatMessage",
        ("#%s #ffffffkilled %s#ffffff!"):format(
            attacker.color:getHexStr():sub(1,6)..(charIdToName[tostring(attacker:getCharacterType())] or "unknown"),
            GetTeamData(sm.GetPlayerTeam(victim)).colour..victim:getName()
        )
    )
end

function PlayerHook:sv_handlePresetSave(args)
    local presets = loadPresets()
    local presetName = args[2]
    if presets[presetName] == nil then
        savePreset(presets, presetName)
        self:sv_chatMessage_single(args.player, ("SAVED '#df7f00%s#ffffff' PRESET"):format(presetName))
    else
        self.network:sendToClient(args.player, "cl_ConfirmOverwrite", presetName)
    end
end

function PlayerHook:sv_handlePresetLoad(args)
    local presets = loadPresets()
    local presetName = args[2]
    if presets[presetName] == nil then
        self:sv_chatMessage_single(args.player, ("#ff0000NO PRESET BY THE NAME OF '#ffffff%s#ff0000' FOUND"):format(presetName))
    else
        local preset = presets[presetName]
        preset.playerSpawns = preset.playerSpawns or {}
        preset.teams = preset.teams or {}
        for k, v in pairs(preset.teams) do
            v.players = v.players or {}
        end

        sm.SURVIVAL_EXTENSION = preset
        local text = ("LOADED '#df7f00%s#ffffff' PRESET:"):format(presetName)
        for name, setting in pairs(sm.SURVIVAL_EXTENSION) do
            local append = ""
            if name == "teams" then
                for team, teamData in pairs(setting) do
                    local members = ""
                    local players = teamData.players
                    if #players == 0 then
                        members = "No members"
                    else
                        for k, member in pairs(players) do
                            members = members..(k == #players and "%s" or "%s, "):format(member)
                        end
                    end

                    append = append..("\n\t\t%s%s#ffffff:\n\t\t%s"):format(teamData.colour, team, members)
                end
            else
                append = setting
            end

            text = text..("#ffffff\n\t%s: #df7f00%s"):format(name, append)
        end

        local players = {}
        for k, v in pairs(sm.player.getAllPlayers()) do
            players[v:getName()] = v
        end

        for team, data in pairs(sm.SURVIVAL_EXTENSION.teams) do
            for k, member in pairs(data.players) do
                if players[member] then
                    self:sv_setPlayerTeam({players[member], team, data.colour})
                end
            end
        end

        if sm.SURVIVAL_EXTENSION.nameDisplayModeOverride then
            self:sv_setNameDisplayMode({ "hi", sm.SURVIVAL_EXTENSION.nameDisplayModeOverride, true })
        else
            self:sv_setNameDisplayMode({ "hi", 4, true })
        end

        self:sv_chatMessage_single(args.player, text)
        self:sv_saveSettings()
    end
end

function PlayerHook:sv_setPlayerTeam(args)
    self.network:sendToClients("cl_setPlayerTeam", args)
end

function PlayerHook:sv_setNameDisplayMode(args)
    local mode = args[2]

    if args[3] == true and mode ~= 4 then
        sm.SURVIVAL_EXTENSION.nameDisplayModeOverride = mode
    else
        sm.SURVIVAL_EXTENSION.nameDisplayModeOverride = nil
    end

    self:sv_saveSettings()

    if args[3] == true then
        self.network:sendToClients("cl_setNameDisplayMode", { mode, true })
    else
        if g_cl_nameDisplayModeOverrideActive then
            self:sv_chatMessage_single(args[1], "#ff0000HOST HAS OVERRIDEN THE NAME DISPLAY MODE")
        else
            self.network:sendToClient(args[1], "cl_setNameDisplayMode", { mode, false })
        end
    end
end

function PlayerHook:sv_requestDataUpdate(_, caller)
    sm.SURVIVAL_EXTENSION_syncToPlayers(caller)

    local name = caller:getName()
    for k, v in pairs(sm.SURVIVAL_EXTENSION.teams) do
        if isAnyOf(name, v.players) then
            self:sv_setPlayerTeam({caller, k, GetTeamData(k).colour})
            break
        end
    end

    if sm.SURVIVAL_EXTENSION.nameDisplayModeOverride then
        self:sv_setNameDisplayMode({ caller, sm.SURVIVAL_EXTENSION.nameDisplayModeOverride, true })
    end
end



local nameDisplayModes = {
    "ALL", "TEAM", "NONE"
}
local overrideNameDisplayModes = {
    "ALL", "TEAM", "NONE", "NO OVERRIDE"
}
function PlayerHook:client_onCreate()
    if sm.PLAYERHOOKCLIENT then return end --avoid multiple loads

    if g_respawnManager == nil then
		assert( not sm.isHost )
		g_respawnManager = RespawnManager()
	end
	g_respawnManager:cl_onCreate()

    sm.PLAYERHOOKCLIENT = self.tool

    self.nameDisplayMode = 1

    g_cl_nameDisplayModeOverrideActive = false

    self.network:sendToServer("sv_requestDataUpdate")
end

function PlayerHook:client_onFixedUpdate()
    if self.tool ~= sm.PLAYERHOOKCLIENT then return end

    local localPlayer = sm.localPlayer.getPlayer()
    local localPlayerTeam = cl_GetPlayerTeam(localPlayer)
    local displayMode = self.nameDisplayModeOverride or self.nameDisplayMode
    for k, v in pairs(sm.player.getAllPlayers()) do
        local char = v.character
        if sm.exists(char) then
            if v == localPlayer or displayMode == 3 then
                char:setNameTag("")
                goto continue
            end

            local name = v:getName()
            if displayMode == 1 then
                char:setNameTag(name)
            else
                char:setNameTag(localPlayerTeam == cl_GetPlayerTeam(v) and cl_GetPlayerTeamFull(v)..name or "")
            end
        end

        ::continue::
    end
end

function PlayerHook:cl_chatMessage(msg)
    sm.gui.chatMessage(msg)
end

function PlayerHook:cl_ConfirmOverwrite(name)
    self.presetName = name
    self.confirmGui = sm.gui.createGuiFromLayout( "$GAME_DATA/Gui/Layouts/PopUp/PopUp_YN.layout" )
    self.confirmGui:setButtonCallback( "Yes", "cl_onConfirmButtonClick" )
    self.confirmGui:setButtonCallback( "No", "cl_onConfirmButtonClick" )
    self.confirmGui:setText( "Title", "#{MENU_YN_TITLE_ARE_YOU_SURE}" )
    self.confirmGui:setText( "Message", ("This will overwrite the existing '#df7f00%s#919191' preset."):format(name) )
    self.confirmGui:open()
end

function PlayerHook.cl_onConfirmButtonClick( self, name )
	if name == "Yes" then
        savePreset(loadPresets(), self.presetName)
	end

    self.confirmGui:close()
	self.confirmGui = nil
    self.presetName = nil
end

function PlayerHook:cl_setPlayerTeam(args)
    ---@type Player
    local player, team, teamColour = args[1], args[2], args[3]

    player.clientPublicData = player.clientPublicData or {}
    player.clientPublicData.survivalExtensionTeam = team
    player.clientPublicData.survivalExtensionTeamColour = teamColour

    if player == sm.localPlayer.getPlayer() then return end

    local name = player:getName()
    if team == nil then
        player.character:setNameTag(name)
        return
    end

    player.character:setNameTag(("[%s#ffffff] %s"):format(teamColour..team, name))
end

function PlayerHook:cl_setNameDisplayMode(args)
    local mode, override = args[1], args[2]

    g_cl_nameDisplayModeOverrideActive = override and mode ~= 4
    if g_cl_nameDisplayModeOverrideActive then
        self.nameDisplayModeOverride = mode
        self:cl_chatMessage("#ff0000ENFORCED#ffffff NAME DISPLAY MODE: #df7f00"..nameDisplayModes[mode])
    else
        if self.nameDisplayModeOverride or mode == 4 then
            self:cl_chatMessage("OVERRIDE CLEARED, NAME DISPLAY MODE: #df7f00"..nameDisplayModes[self.nameDisplayMode])
            self.nameDisplayModeOverride = nil
        else
            self.nameDisplayMode = mode
            self:cl_chatMessage("NAME DISPLAY MODE: #df7f00"..nameDisplayModes[mode])
        end
    end
end


--[[local gameHooked = false
local oldHud = sm.gui.createSurvivalHudGui
function hudHook()
    if not gameHooked then
        gameHooked = true
        dofile("$CONTENT_a929f1de-4824-456c-b3ac-da6c47a4b4a2/Scripts/vanilla_override.lua")
    end

	return oldHud()
end
sm.gui.createSurvivalHudGui = hudHook]]


local commands = {
    { name = "pvp",                 description = "Toggle pvp",
        args = {
            { "bool", "enable", true },
        }
    },
    { name = "healthRegeneration",  description = "Toggle health regeneration",
        args = {
            { "bool", "enable", true },
        }
    },
    { name = "hunger",              description = "Toggle hunger",
        args = {
            { "bool", "enable", true },
        }
    },
    { name = "thirst",              description = "Toggle thirst",
        args = {
            { "bool", "enable", true },
        }
    },
    { name = "breathLoss",          description = "Toggle breath loss underwater",
        args = {
            { "bool", "enable", true },
        }
    },
    { name = "respawnStats",        description = "Set the stats that the player receives upon respawning",
        args = {
            { "number", "hp", false },
            { "number", "water", false },
            { "number", "food", false }
        }
    },
    { name = "creativeInventory",   description = "Toggles the creative inventory",
        args = {
            { "bool", "enable", true },
        }
    },
    { name = "collisionTumble",     description = "Toggles collision tumble",
        args = {
            { "bool", "enable", true },
        }
    },
    { name = "collisionDamage",     description = "Toggles collision damage",
        args = {
            { "bool", "enable", true },
        }
    },
    { name = "godMode",             description = "Toggles god mode",
        args = {
            { "bool", "enable", true },
        }
    },
    { name = "savePreset",          description = "Saves the settings to a preset",
        args = {
            { "string", "presetName", false },
        }
    },
    { name = "loadPreset",          description = "Loads the settings from a preset",
        args = {
            { "string", "presetName", false },
        }
    },
    { name = "dropItems",           description = "Toggles whether or not items are dropped upon death",
        args = {
            { "bool", "enable", true },
        }
    },
    { name = "ammoConsumption",     description = "Toggles the ammo consumption",
        args = {
            { "bool", "enable", true },
        }
    },
    { name = "setSpawnPoint",       description = "Sets the spawn point(beds override it)", all = true },
    { name = "clearSpawnPoint",     description = "Clears the spawn point", all = true },
    { name = "createTeam",          description = "Creates a team",
        args = {
            { "string", "teamName", false },
            { "string", "teamColor(hex code)", true },
        }
    },
    { name = "deleteTeam",          description = "Deletes a team",
        args = {
            { "string", "teamName", false }
        }
    },
    { name = "setTeam",             description = "Sets your team",
        args = {
            { "string", "teamName", false },
        },
        all = true
    },
    { name = "clearTeam",           description = "Clears your team",
        args = {},
        all = true
    },
    { name = "listTeams",           description = "Lists all the available teams",
        args = {},
        all = true
    },
    { name = "friendlyFire",        description = "Toggles friendly fire",
        args = {
            { "bool", "enable", true },
        }
    },
    { name = "displayNames",        description = "Sets the display mode of player names",
        args = {
            { "int", "mode(1-all/2-team/3-none)", true },
        },
        all = true
    },
    { name = "overrideDisplayNames",description = "Sets the display mode of player names for all palyers",
        args = {
            { "int", "mode(1-all/2-team/3-none/4-no override)", true },
        },
        all = false
    },
    { name = "setRespawnCooldown",  description = "Sets the respawn cooldown",
        args = {
            { "int", "cooldown(seconds)", false },
        }
    },
    { name = "unSeatOnDamage",      description = "Toggles whether the player gets knocked out of their seat upon taking damage",
        args = {
            { "bool", "enable", true },
        }
    },
}

oldBind = oldBind or sm.game.bindChatCommand
function bindHook(command, params, callback, help)
    if not gameHooked then
        gameHooked = true

        for k, v in pairs(commands) do
            if v.all or sm.isHost then
                oldBind( "/"..v.name:lower(), v.args or {}, "cl_onChatCommand", v.description )
            end
        end

        dofile("$CONTENT_a929f1de-4824-456c-b3ac-da6c47a4b4a2/Scripts/vanilla_override.lua")
    end

	return oldBind(command, params, callback, help)
end
sm.game.bindChatCommand = bindHook



local function toggleRule(rule, msg, value)
    local new = not sm.SURVIVAL_EXTENSION[rule]
    if value ~= nil then
        new = value
    end

    sm.SURVIVAL_EXTENSION[rule] = new

    if sm.SURVIVAL_EXTENSION_ruleToSyncToPlayers[rule] == true then
        sm.SURVIVAL_EXTENSION_syncToPlayers()
    end

    sm.event.sendToTool(sm.PLAYERHOOK, "sv_saveAndChat", msg..(new and "#00ff00ON" or "#ff0000OFF"))
end

oldWorldEvent = oldWorldEvent or sm.event.sendToWorld
function worldEventHook(world, callback, args)
    --sm.log.warning("WORLD EVENT HOOK:", world, callback, args)

    if callback == "sv_e_onChatCommand" then
        local command = args[1]
        if command == "/pvp" then
            toggleRule("pvp", "PLAYER VS PLAYER: ", args[2])
        elseif command == "/healthregeneration" then
            toggleRule("health_regen", "HEALTH REGENERATION: ", args[2])
        elseif command == "/hunger" then
            toggleRule("hunger", "HUNGER: ", args[2])
        elseif command == "/thirst" then
            toggleRule("thirst", "THIRST: ", args[2])
        elseif command == "/breathloss" then
            toggleRule("breath", "BREATH LOSS: ", args[2])
        elseif command == "/respawnstats" then
            local hp, water, food = args[2], args[3], args[4]
            sm.SURVIVAL_EXTENSION.spawn_hp = hp
            sm.SURVIVAL_EXTENSION.spawn_water = water
            sm.SURVIVAL_EXTENSION.spawn_food = food
            sm.event.sendToTool(sm.PLAYERHOOK, "sv_saveAndChat", ("RESPAWN STATS: \n\tHP: #df7f00%s #ffffff\n\tWATER: #df7f00%s #ffffff\n\tFOOD: #df7f00%s"):format(hp, water, food))
        elseif command == "/creativeinventory" then
            local new = not sm.game.getLimitedInventory()
            sm.game.setLimitedInventory(new)
            sm.event.sendToTool(sm.PLAYERHOOK, "sv_chatMessage", "CREATIVE INVENTORY: "..(not new and "#00ff00ON" or "#ff0000OFF"))
        elseif command == "/collisiontumble" then
            toggleRule("collisionTumble", "COLLISION TUMBLE: ", args[2])
        elseif command == "/collisiondamage" then
            toggleRule("collisionDamage", "COLLISION DAMAGE: ", args[2])
        elseif command == "/godmode" then
            toggleRule("godMode", "GOD MODE: ", args[2])
        elseif command == "/savepreset" then
            sm.event.sendToTool(sm.PLAYERHOOK, "sv_handlePresetSave", args)
        elseif command == "/loadpreset" then
            sm.event.sendToTool(sm.PLAYERHOOK, "sv_handlePresetLoad", args)
        elseif command == "/dropitems" then
            toggleRule("dropItems", "DROP ITEMS UPON DEATH: ", args[2])
        elseif command == "/ammoconsumption" then
            local new = not sm.game.getEnableAmmoConsumption()
            sm.game.setEnableAmmoConsumption(new)
            sm.event.sendToTool(sm.PLAYERHOOK, "sv_chatMessage", "AMMO CONSUMPTION: "..(new and "#00ff00ON" or "#ff0000OFF"))
        elseif command == "/setspawnpoint" then
            local player = args.player
            local worldPos = player.character.worldPosition
            sm.SURVIVAL_EXTENSION.playerSpawns[player.id] = worldPos
            sm.event.sendToTool(sm.PLAYERHOOK, "sv_saveAndChat_single", { player, ("SET SPAWN POINT TO: \n\t#ffffffx: #df7f00%s \n\t#ffffffy: #df7f00%s \n\t#ffffffz: #df7f00%s"):format(worldPos.x, worldPos.y, worldPos.z) })
        elseif command == "/clearspawnpoint" then
            local player = args.player
            sm.SURVIVAL_EXTENSION.playerSpawns[player.id] = nil
            sm.event.sendToTool(sm.PLAYERHOOK, "sv_saveAndChat_single", { player, "CLEARED SPAWN POINT" })
        elseif command == "/createteam" then
            ---@type string, string
            local teamName, teamColour = args[2], args[3]
            local finalColour = teamColour
            if teamColour then
                local start = teamColour:sub(1,1)
                if start ~= "#" then
                    finalColour = "#"..teamColour
                end

                finalColour = finalColour..string.rep(0, math.max(7 - #finalColour, 0))
            else
                finalColour = "#888888"
            end

            if sm.SURVIVAL_EXTENSION.teams[teamName] ~= nil then
                sm.event.sendToTool(sm.PLAYERHOOK, "sv_chatMessage_single", { args.player, ("#ff0000TEAM '%s%s#ff0000' ALREADY EXISTS"):format(finalColour, teamName) })
                return
            end

            sm.SURVIVAL_EXTENSION.teams[teamName] = { colour = finalColour, players = {} }
            sm.event.sendToTool(sm.PLAYERHOOK, "sv_saveAndChat", ("CREATED TEAM %s%s"):format(finalColour, teamName))
        elseif command == "/deleteteam" then
            local teamName = args[2]
            if sm.SURVIVAL_EXTENSION.teams[teamName] == nil then
                sm.event.sendToTool(sm.PLAYERHOOK, "sv_chatMessage_single", { args.player, ("#ff0000TEAM '#ffffff%s#ff0000' DOESN'T EXIST"):format(teamName) })
                return
            end

            for k, v in pairs(sm.player.getAllPlayers()) do
                if (v.publicData or {}).survivalExtensionTeam == teamName then
                    sm.event.sendToTool(sm.PLAYERHOOK, "sv_setPlayerTeam", { v } )
                end
            end

            sm.SURVIVAL_EXTENSION.teams[teamName] = nil
            sm.event.sendToTool(sm.PLAYERHOOK, "sv_saveAndChat", ("DELETED TEAM %s"):format(teamName))
        elseif command == "/setteam" then
            ---@type Player
            local player, team = args.player, args[2]
            local teamData = sm.SURVIVAL_EXTENSION.teams[team]
            if not teamData then
                sm.event.sendToTool(sm.PLAYERHOOK, "sv_chatMessage_single", { player, ("#ff0000TEAM '#ffffff%s#ff0000' DOESN'T EXIST"):format(team) })
                return
            end

            player.publicData = player.publicData or {}
            local prevTeam = player.publicData.survivalExtensionTeam

            if prevTeam == team then
                sm.event.sendToTool(sm.PLAYERHOOK, "sv_chatMessage_single", { player, "#ff0000YOU ARE ALREADY A MEMBER OF THIS TEAM" })
                return
            end

            local name = player:getName()
            if prevTeam then
                for i, v in pairs(sm.SURVIVAL_EXTENSION.teams[prevTeam].players) do
                    if v == name then
                        table.remove(sm.SURVIVAL_EXTENSION.teams[prevTeam].players, i)
                        break
                    end
                end
            end

            player.publicData.survivalExtensionTeam = team

            if not isAnyOf(name, sm.SURVIVAL_EXTENSION.teams[team].players) then
                table.insert(sm.SURVIVAL_EXTENSION.teams[team].players, name)
            end

            sm.event.sendToTool(sm.PLAYERHOOK, "sv_setPlayerTeam", { player, team, teamData.colour } )
            sm.event.sendToTool(sm.PLAYERHOOK, "sv_saveAndChat", ("%s JOINED TEAM '%s%s#ffffff'"):format(name, teamData.colour, team) )
        elseif command == "/clearteam" then
            local player = args.player
            local prevTeam = player.publicData.survivalExtensionTeam

            if not prevTeam then
                sm.event.sendToTool(sm.PLAYERHOOK, "sv_chatMessage_single", { args.player, "#ff0000NO TEAM SET" })
                return
            end

            player.publicData.survivalExtensionTeam = nil

            local name = player:getName()
            for i, v in pairs(sm.SURVIVAL_EXTENSION.teams[prevTeam].players) do
                if v == name then
                    table.remove(sm.SURVIVAL_EXTENSION.teams[prevTeam].players, i)
                    break
                end
            end

            sm.event.sendToTool(sm.PLAYERHOOK, "sv_setPlayerTeam", { player } )
            sm.event.sendToTool(sm.PLAYERHOOK, "sv_saveAndChat", ("%s LEFT '%s%s#ffffff'"):format(name, sm.SURVIVAL_EXTENSION.teams[prevTeam].colour, prevTeam) )
        elseif command == "/listteams" then
            local text = "AVAILABLE TEAMS:"
            for k, v in pairs(sm.SURVIVAL_EXTENSION.teams) do
                text = text..("\n\t%s"):format(v.colour..k)
            end

            sm.event.sendToTool(sm.PLAYERHOOK, "sv_chatMessage_single", { args.player, text })
        elseif command == "/friendlyfire" then
            toggleRule("friendlyFire", "FRIENDLY FIRE: ", args[2])
        elseif command == "/displaynames" then
            local mode = tonumber(args[2])
            if not mode or mode < 1 or mode > #nameDisplayModes then
                sm.event.sendToTool(sm.PLAYERHOOK, "sv_chatMessage_single", { args.player, ("#ff0000MODE ID MUST BE A NUMBER BETWEEN '#ffffff1#ff0000' and '#ffffff%s#ff0000'"):format(#nameDisplayModes) })
                return
            end

            sm.event.sendToTool(sm.PLAYERHOOK, "sv_setNameDisplayMode", { args.player, mode })
        elseif command == "/setrespawncooldown" then
            local seconds = args[2]
            sm.SURVIVAL_EXTENSION.respawnCooldown = seconds * 40
            sm.event.sendToTool(sm.PLAYERHOOK, "sv_saveAndChat", ("RESPAWN COOLDOWN SET TO: #df7f00%s seconds"):format(seconds))
            sm.SURVIVAL_EXTENSION_syncToPlayers()
        elseif command == "/unseatondamage" then
            toggleRule("unSeatOnDamage", "UNSEAT ON DAMAGE: ", args[2])
        elseif command == "/overridedisplaynames" then
            local mode = tonumber(args[2])
            if not mode or mode < 1 or mode > #overrideNameDisplayModes then
                sm.event.sendToTool(sm.PLAYERHOOK, "sv_chatMessage_single", { args.player, ("#ff0000MODE ID MUST BE A NUMBER BETWEEN '#ffffff1#ff0000' and '#ffffff%s#ff0000'"):format(#overrideNameDisplayModes) })
                return
            end

            sm.event.sendToTool(sm.PLAYERHOOK, "sv_setNameDisplayMode", { args.player, mode, true })
        end
    end

    return oldWorldEvent(world, callback, args)
end
sm.event.sendToWorld = worldEventHook