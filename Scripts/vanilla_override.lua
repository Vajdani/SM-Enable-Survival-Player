g_survivalDev = false

g_survivalHud = g_survivalHud or sm.gui.createSurvivalHudGui()

dofile( "$GAME_DATA/Scripts/game/BasePlayer.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/SurvivalPlayer.lua" )

local StatsTickRate = 40

local PerSecond = StatsTickRate / 40
local PerMinute = StatsTickRate / ( 40 * 60 )

local FoodRecoveryThreshold = 5 -- Recover hp when food is above this value
local FastFoodRecoveryThreshold = 50 -- Recover hp fast when food is above this value
local HpRecovery = 50 * PerMinute
local FastHpRecovery = 75 * PerMinute
local FoodCostPerHpRecovery = 0.2
local FastFoodCostPerHpRecovery = 0.2

local FoodCostPerStamina = 0.02
local WaterCostPerStamina = 0.1
local SprintStaminaCost = 0.7 / 40 -- Per tick while sprinting
local CarryStaminaCost = 1.4 / 40 -- Per tick while carrying

local FoodLostPerSecond = 100 / 3.5 / 24 / 60
local WaterLostPerSecond = 100 / 2.5 / 24 / 60

local BreathLostPerTick = ( 100 / 60 ) / 40

local FatigueDamageHp = 1 * PerSecond
local FatigueDamageWater = 2 * PerSecond
local DrownDamage = 5
local DrownDamageCooldown = 40

local RespawnTimeout = 60 * 40

local RespawnFadeDuration = 0.45
local RespawnEndFadeDuration = 0.45

local RespawnFadeTimeout = 5.0
local RespawnDelay = RespawnFadeDuration * 40
local RespawnEndDelay = 1.0 * 40



local MaxTumbleImpulseSpeed = 35

function SurvivalPlayer.sv_n_tryRespawn( self )
	if sm.game.getServerTick() - self.sv.saved.deathTick < sm.SURVIVAL_EXTENSION.respawnCooldown then return end

	if not self.sv.saved.isConscious and not self.sv.respawnDelayTimer and not self.sv.respawnInteractionAttempted then
		self.sv.respawnInteractionAttempted = true
		self.sv.respawnEndTimer = nil;
		self.network:sendToClient( self.player, "cl_n_startFadeToBlack", { duration = RespawnFadeDuration, timeout = RespawnFadeTimeout } )
		
		self.sv.respawnDelayTimer = Timer()
		self.sv.respawnDelayTimer:start( RespawnDelay )
	end
end

function SurvivalPlayer.sv_e_respawn( self )
	if self.sv.spawnparams.respawn then
		if not self.sv.respawnTimeoutTimer then
			self.sv.respawnTimeoutTimer = Timer()
			self.sv.respawnTimeoutTimer:start( RespawnTimeout )
		end
		return
	end
	if not self.sv.saved.isConscious then
		if sm.game.getLimitedInventory() and sm.SURVIVAL_EXTENSION.dropItems then
			sm.RESPAWNMANAGER:sv_performItemLoss( self.player )
		end
		self.sv.spawnparams.respawn = true

		--sm.event.sendToGame( "sv_e_respawn", { player = self.player } )
		self:sv_e_onSpawnCharacter()
	else
		print( "SurvivalPlayer must be unconscious to respawn" )
	end
end

function SurvivalPlayer.sv_e_onSpawnCharacter( self )
	if self.sv.saved.isNewPlayer then
		-- Intro cutscene for new player
		if not g_survivalDev then
			--self:sv_e_startLocalCutscene( "camera_approach_crash" )
		end
	elseif self.sv.spawnparams.respawn then
		local playerBed = sm.RESPAWNMANAGER:sv_getPlayerBed( self.player )
		if playerBed and playerBed.shape and sm.exists( playerBed.shape ) and playerBed.shape.body:getWorld() == self.player.character:getWorld() then
			-- Attempt to seat the respawned character in a bed
			self.network:sendToClient( self.player, "cl_seatCharacter", { shape = playerBed.shape  } )
		else
			local spawn = sm.SURVIVAL_EXTENSION.playerSpawns[self.player.id]
			if not spawn then
				local pos = sm.vec3.new(0,0,1000)
				local hit, result = sm.physics.raycast(pos, -pos)
				spawn = result.pointWorld + sm.vec3.new(0,0,1)
			end

			self.player:setCharacter(sm.character.createCharacter(self.player, sm.world.getCurrentWorld(), spawn))

			-- Respawned without a bed
			--self:sv_e_startLocalCutscene( "camera_wakeup_ground" )
		end

		self.sv.respawnEndTimer = Timer()
		self.sv.respawnEndTimer:start( RespawnEndDelay )
	end

	if self.sv.saved.isNewPlayer or self.sv.spawnparams.respawn then
		print( "SurvivalPlayer", self.player.id, "spawned" )
		if self.sv.saved.isNewPlayer then
			self.sv.saved.stats.hp = self.sv.saved.stats.maxhp
			self.sv.saved.stats.food = self.sv.saved.stats.maxfood
			self.sv.saved.stats.water = self.sv.saved.stats.maxwater
		else
			self.sv.saved.stats.hp = sm.SURVIVAL_EXTENSION.spawn_hp --30
			self.sv.saved.stats.food = sm.SURVIVAL_EXTENSION.spawn_food --30
			self.sv.saved.stats.water = sm.SURVIVAL_EXTENSION.spawn_water --30
		end
		self.sv.saved.isConscious = true
		self.sv.saved.hasRevivalItem = false
		self.sv.saved.isNewPlayer = false
		self.storage:save( self.sv.saved )
		self.network:setClientData( self.sv.saved )

		self.player.character:setTumbling( false )
		self.player.character:setDowned( false )
		self.sv.damageCooldown:start( 40 )
	else
		-- SurvivalPlayer rejoined the game
		if self.sv.saved.stats.hp <= 0 or not self.sv.saved.isConscious then
			self.player.character:setTumbling( true )
			self.player.character:setDowned( true )
		end
	end

	self.sv.respawnInteractionAttempted = false
	self.sv.respawnDelayTimer = nil
	self.sv.respawnTimeoutTimer = nil
	self.sv.spawnparams = {}

	sm.event.sendToGame( "sv_e_onSpawnPlayerCharacter", self.player )
end

function SurvivalPlayer.server_onFixedUpdate( self, dt )
	BasePlayer.server_onFixedUpdate( self, dt )

	if g_survivalDev and not self.sv.saved.isConscious and not self.sv.saved.hasRevivalItem then
		if sm.container.canSpend( self.player:getInventory(), obj_consumable_longsandwich, 1 ) then
			if sm.container.beginTransaction() then
				sm.container.spend( self.player:getInventory(), obj_consumable_longsandwich, 1, true )
				if sm.container.endTransaction() then
					self.sv.saved.hasRevivalItem = true
					self.player:sendCharacterEvent( "baguette" )
					self.network:setClientData( self.sv.saved )
				end
			end
		end
	end

	-- Delays the respawn so clients have time to fade to black
	if self.sv.respawnDelayTimer then
		self.sv.respawnDelayTimer:tick()
		if self.sv.respawnDelayTimer:done() then
			self:sv_e_respawn()
			self.sv.respawnDelayTimer = nil
		end
	end

	-- End of respawn sequence
	if self.sv.respawnEndTimer then
		self.sv.respawnEndTimer:tick()
		if self.sv.respawnEndTimer:done() then
			self.network:sendToClient( self.player, "cl_n_endFadeToBlack", { duration = RespawnEndFadeDuration } )
			self.sv.respawnEndTimer = nil;
		end
	end

	-- If respawn failed, restore the character
	if self.sv.respawnTimeoutTimer then
		self.sv.respawnTimeoutTimer:tick()
		if self.sv.respawnTimeoutTimer:done() then
			self:sv_e_onSpawnCharacter()
		end
	end

	local character = self.player:getCharacter()
	-- Update breathing
	if character then
		if character:isDiving() and sm.SURVIVAL_EXTENSION.breath then
			self.sv.saved.stats.breath = math.max( self.sv.saved.stats.breath - BreathLostPerTick, 0 )
			if self.sv.saved.stats.breath == 0 then
				self.sv.drownTimer:tick()
				if self.sv.drownTimer:done() then
					if self.sv.saved.isConscious then
						print( "'SurvivalPlayer' is drowning!" )
						self:sv_takeDamage( DrownDamage, "drown" )
					end
					self.sv.drownTimer:start( DrownDamageCooldown )
				end
			end
		else
			self.sv.saved.stats.breath = self.sv.saved.stats.maxbreath
			self.sv.drownTimer:start( DrownDamageCooldown )
		end

		-- Spend stamina on sprinting
		if character:isSprinting() then
			self.sv.staminaSpend = self.sv.staminaSpend + SprintStaminaCost
		end

		-- Spend stamina on carrying
		if not self.player:getCarry():isEmpty() then
			self.sv.staminaSpend = self.sv.staminaSpend + CarryStaminaCost
		end
	end

	-- Update stamina, food and water stats
	if character and self.sv.saved.isConscious and not sm.SURVIVAL_EXTENSION.godMode then
		self.sv.statsTimer:tick()
		if self.sv.statsTimer:done() then
			self.sv.statsTimer:start( StatsTickRate )

			-- Recover health from food
			if self.sv.saved.stats.food > FoodRecoveryThreshold and sm.SURVIVAL_EXTENSION.health_regen then
				local fastRecoveryFraction = 0

				-- Fast recovery when food is above fast threshold
				if self.sv.saved.stats.food > FastFoodRecoveryThreshold then
					local recoverableHp = math.min( self.sv.saved.stats.maxhp - self.sv.saved.stats.hp, FastHpRecovery )
					local foodSpend = math.min( recoverableHp * FastFoodCostPerHpRecovery, math.max( self.sv.saved.stats.food - FastFoodRecoveryThreshold, 0 ) )
					local recoveredHp = foodSpend / FastFoodCostPerHpRecovery

					self.sv.saved.stats.hp = math.min( self.sv.saved.stats.hp + recoveredHp, self.sv.saved.stats.maxhp )
					self.sv.saved.stats.food = self.sv.saved.stats.food - foodSpend
					fastRecoveryFraction = ( recoveredHp ) / FastHpRecovery
				end

				-- Normal recovery
				local recoverableHp = math.min( self.sv.saved.stats.maxhp - self.sv.saved.stats.hp, HpRecovery * ( 1 - fastRecoveryFraction ) )
				local foodSpend = math.min( recoverableHp * FoodCostPerHpRecovery, math.max( self.sv.saved.stats.food - FoodRecoveryThreshold, 0 ) )
				local recoveredHp = foodSpend / FoodCostPerHpRecovery

				self.sv.saved.stats.hp = math.min( self.sv.saved.stats.hp + recoveredHp, self.sv.saved.stats.maxhp )
				self.sv.saved.stats.food = self.sv.saved.stats.food - foodSpend
			end

			-- Spend water and food on stamina usage
			-- Decrease food and water with time
			if sm.SURVIVAL_EXTENSION.hunger then
				self.sv.saved.stats.food = math.max( self.sv.saved.stats.food - self.sv.staminaSpend * FoodCostPerStamina, 0 )
				self.sv.saved.stats.food = math.max( self.sv.saved.stats.food - FoodLostPerSecond, 0 )
			end

			if sm.SURVIVAL_EXTENSION.thirst then
				self.sv.saved.stats.water = math.max( self.sv.saved.stats.water - self.sv.staminaSpend * WaterCostPerStamina, 0 )
				self.sv.saved.stats.water = math.max( self.sv.saved.stats.water - WaterLostPerSecond, 0 )
			end
			self.sv.staminaSpend = 0

			local fatigueDamageFromHp = false
			if self.sv.saved.stats.food <= 0 then
				self:sv_takeDamage( FatigueDamageHp, "fatigue" )
				fatigueDamageFromHp = true
			end
			if self.sv.saved.stats.water <= 0 then
				if not fatigueDamageFromHp then
					self:sv_takeDamage( FatigueDamageWater, "fatigue" )
				end
			end

			self.storage:save( self.sv.saved )
			self.network:setClientData( self.sv.saved )
		end
	end
end

function SurvivalPlayer.sv_e_staminaSpend( self, stamina )
	if not sm.SURVIVAL_EXTENSION.godMode then
		if stamina > 0 then
			self.sv.staminaSpend = self.sv.staminaSpend + stamina
		end
	end
end

function SurvivalPlayer.server_onCollision( self, other, collisionPosition, selfPointVelocity, otherPointVelocity, collisionNormal  )
	if not self.player.character or not sm.exists( self.player.character ) then
		return
	end

	if not self.sv.impactCooldown:done() then
		return
	end

	local collisionDamageMultiplier = 0.25
	local maxHp = 100
	if self.sv.saved.stats and self.sv.saved.stats.maxhp then
		maxHp = self.sv.saved.stats.maxhp
	end
	local damage, tumbleTicks, tumbleVelocity, impactReaction = CharacterCollision( self.player.character, other, collisionPosition, selfPointVelocity, otherPointVelocity, collisionNormal, maxHp / collisionDamageMultiplier, 24 )
	damage = damage * collisionDamageMultiplier
	if sm.SURVIVAL_EXTENSION.collisionDamage then
		if damage > 0 or tumbleTicks > 0 then
			self.sv.impactCooldown:start( 0.25 * 40 )
		end
		if damage > 0 then
			print("'Player' took", damage, "collision damage")
			self:sv_takeDamage( damage, "shock" )
		end
	end
	if sm.SURVIVAL_EXTENSION.collisionTumble then
		if tumbleTicks > 0 then
			if self:sv_startTumble( tumbleTicks ) then
				-- Limit tumble velocity
				if tumbleVelocity:length2() > MaxTumbleImpulseSpeed * MaxTumbleImpulseSpeed then
					tumbleVelocity = tumbleVelocity:normalize() * MaxTumbleImpulseSpeed
				end
				self.player.character:applyTumblingImpulse( tumbleVelocity * self.player.character.mass )
				if type( other ) == "Shape" and sm.exists( other ) and other.body:isDynamic() then
					sm.physics.applyImpulse( other.body, impactReaction * other.body.mass, true, collisionPosition - other.body.worldPosition )
				end
			end
		end
	end
end

function SurvivalPlayer:CanBeDamagedByPlayer(attacker)
	local teamAttacker = sm.GetPlayerTeam(attacker)
	local teamSelf = sm.GetPlayerTeam(self.player)
	if not teamSelf or not teamAttacker then
		return true
	end

	return sm.SURVIVAL_EXTENSION.pvp and (teamAttacker ~= teamSelf or sm.SURVIVAL_EXTENSION.friendlyFire)
end

function SurvivalPlayer.server_onProjectile( self, hitPos, hitTime, hitVelocity, _, attacker, damage, userData, hitNormal, projectileUuid )
	if type(attacker) ~= "Player" or self:CanBeDamagedByPlayer(attacker) then
		self:sv_takeDamage( damage, "shock", attacker )
	end
	if self.player.character:isTumbling() then
		ApplyKnockback( self.player.character, hitVelocity:normalize(), 2000 )
	end

	if projectileUuid == projectile_water  then
		self.network:sendToClient( self.player, "cl_n_fillWater" )
	end
end

function SurvivalPlayer.server_onMelee( self, hitPos, attacker, damage, power, hitDirection )
	if not sm.exists( attacker ) then
		return
	end

	print("'Player' took melee damage")
	local attackerType = type(attacker)
	if attackerType ~= "Player" or self:CanBeDamagedByPlayer(attacker) then
		self:sv_takeDamage( damage, "shock", attacker )
	end

	if attackerType ~= "Unit" then
		local playerCharacter = self.player.character
		if sm.exists( playerCharacter ) then
			self.network:sendToClients( "cl_n_onEvent", { event = "impact", pos = playerCharacter.worldPosition, damage = damage * 0.01 } )
		end
	end

	-- Melee impulse
	if attacker then
		ApplyKnockback( self.player.character, hitDirection, power )
	end
end

function SurvivalPlayer.sv_takeDamage( self, damage, source, attacker )
	if damage > 0 then
		damage = damage * GetDifficultySettings().playerTakeDamageMultiplier
		local character = self.player:getCharacter()
		local lockingInteractable = character:getLockingInteractable()
		if lockingInteractable and lockingInteractable:hasSeat() and sm.SURVIVAL_EXTENSION.unSeatOnDamage then
			lockingInteractable:setSeatCharacter( character )
		end

		if not sm.SURVIVAL_EXTENSION.godMode and self.sv.damageCooldown:done() then
			if self.sv.saved.isConscious then
				self.sv.saved.stats.hp = math.max( self.sv.saved.stats.hp - damage, 0 )

				print( "'SurvivalPlayer' took:", damage, "damage.", self.sv.saved.stats.hp, "/", self.sv.saved.stats.maxhp, "HP" )

				if source then
					self.network:sendToClients( "cl_n_onEvent", { event = source, pos = character:getWorldPosition(), damage = damage * 0.01 } )
				else
					self.player:sendCharacterEvent( "hit" )
				end

				if self.sv.saved.stats.hp <= 0 then
					print( "'SurvivalPlayer' knocked out!" )
					self.sv.respawnInteractionAttempted = false
					self.sv.saved.isConscious = false
					character:setTumbling( true )
					character:setDowned( true )

					local attackerType = type(attacker)
					if attackerType == "Player" then
						sm.event.sendToTool(sm.PLAYERHOOK, "sv_OnPlayerDeath", { attacker = attacker, victim = self.player })
					elseif attackerType == "Unit" then
						sm.event.sendToTool(sm.PLAYERHOOK, "sv_OnPlayerDeathByUnit", { attacker = attacker, victim = self.player })
					end

					self.sv.saved.deathTick = sm.game.getServerTick()
				end

				self.storage:save( self.sv.saved )
				self.network:setClientData( self.sv.saved )
			end
		else
			print( "'SurvivalPlayer' resisted", damage, "damage" )
		end
	end
end

function SurvivalPlayer:sv_syncRules(data)
	self.network:sendToClient(self.player, "cl_syncRules", data)
end



oldClientCreate = oldClientCreate or SurvivalPlayer.client_onCreate
function newClientCreate( self )
	oldClientCreate(self)

	g_survivalHud:setVisible("BindingPanel", false)
end
SurvivalPlayer.client_onCreate = newClientCreate

oldClientData = oldClientData or SurvivalPlayer.client_onClientDataUpdate
function newClientData( self, data )
	oldClientData(self, data)

	if sm.localPlayer.getPlayer() == self.player then
		self.cl.deathTick = data.deathTick
	end
end
SurvivalPlayer.client_onClientDataUpdate = newClientData

oldLocalUpdate = oldLocalUpdate or SurvivalPlayer.cl_localPlayerUpdate
function newLocalUpdate( self, dt )
	oldLocalUpdate(self, dt)

	if sm.localPlayer.getPlayer() ~= self.player
		or not self.cl.deathTick
		or not g_respawnCooldown then
		return
	end

	local time = ((g_respawnCooldown + self.cl.deathTick) - sm.game.getServerTick()) / 40
	if time < 0 then return end

	sm.gui.setInteractionText(("<p textShadow='false' bg='gui_keybinds_bg_white' color='#444444' spacing='9'>Respawn cooldown: %.0fs</p>"):format(time))
end
SurvivalPlayer.cl_localPlayerUpdate = newLocalUpdate

function SurvivalPlayer:cl_syncRules(data)
	g_survivalHud:setVisible("WaterBar", data.thirst)
    g_survivalHud:setVisible("FoodBar",  data.hunger)

	g_respawnCooldown = data.respawnCooldown
end



oldClass = oldClass or class
function newClass(_class)
    if _class then
		for k, v in pairs(BasePlayer) do
			if _class[k] ~= v then
				return oldClass(_class)
			end
		end

		return SurvivalPlayer
    end

    return oldClass()
end
class = newClass



worldsHooked = worldsHooked or false
if not worldsHooked then
	for k, v in pairs({ MenuWorld, ClassicCreativeTerrainWorld, CreativeCustomWorld, CreativeTerrainWorld, CreativeFlatWorld }) do
		local oldProjectile = v.server_onProjectile
		local function newProjectile( self, hitPos, hitTime, hitVelocity, _, attacker, damage, userData, hitNormal, target, projectileUuid )
			if oldProjectile then
				oldProjectile(self, hitPos, hitTime, hitVelocity, _, attacker, damage, userData, hitNormal, target, projectileUuid )
			end

			if userData and userData.lootUid then
				local normal = -hitVelocity:normalize()
				local zSignOffset = math.min( sign( normal.z ), 0 ) * 0.5
				local offset = sm.vec3.new( 0, 0, zSignOffset )
				local lootHarvestable = sm.harvestable.createHarvestable( sm.uuid.new("97fe0cf2-0591-4e98-9beb-9186f4fd83c8"), hitPos + offset, sm.vec3.getRotation( sm.vec3.new( 0, 1, 0 ), sm.vec3.new( 0, 0, 1 ) ) )
				lootHarvestable:setParams( { uuid = userData.lootUid, quantity = userData.lootQuantity, epic = userData.epic  } )
			end
		end
		v.server_onProjectile = newProjectile
	end

	worldsHooked = true
end