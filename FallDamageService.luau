--[[
	FallDamageService
	Local: ServerScriptService > Services > FallDamageService   (ModuleScript, serviço com Init/Start)

	Dano de queda calculado no SERVIDOR pela velocidade real do impacto:
	  - abaixo de MinSpeed (~8 studs de altura): nenhum dano
	  - entre MinSpeed e LethalSpeed: dano proporcional (curva suave)
	  - em LethalSpeed ou mais: morte (~45 studs de queda)
	  - descer uma encosta correndo NÃO conta (o personagem não entra em queda livre)
	  - cair na água não causa dano
	  - um único dano por impacto (Cooldown)
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local FallDamageService = {}

local Config = {
	MinSpeed = 58,       -- studs/s de impacto (≈ queda de 8,5 studs)
	LethalSpeed = 138,   -- studs/s (≈ queda de 48 studs)
	Curve = 1.25,
	MaxDamage = 130,     -- passou do lethal = morte
	Cooldown = 0.7,
}

local states = setmetatable({}, { __mode = "k" })
local LANDING = {
	[Enum.HumanoidStateType.Landed] = true,
	[Enum.HumanoidStateType.Running] = true,
	[Enum.HumanoidStateType.RunningNoPhysics] = true,
	[Enum.HumanoidStateType.Climbing] = true,
	[Enum.HumanoidStateType.GettingUp] = true,
	[Enum.HumanoidStateType.Seated] = true,
}

local function damageFor(impact)
	if impact <= Config.MinSpeed then return 0 end
	if impact >= Config.LethalSpeed then return Config.MaxDamage end
	local t = (impact - Config.MinSpeed) / (Config.LethalSpeed - Config.MinSpeed)
	return (t ^ Config.Curve) * 100
end

local function hookCharacter(player, character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not humanoid or not root then return end

	local st = { Falling = false, FastestDown = 0, Last = 0, Root = root, Humanoid = humanoid }
	states[player] = st

	humanoid.StateChanged:Connect(function(_, new)
		if new == Enum.HumanoidStateType.Freefall then
			st.Falling = true
			st.FastestDown = 0
		elseif st.Falling then
			if new == Enum.HumanoidStateType.Swimming then
				st.Falling = false -- caiu na água: sem dano
			elseif LANDING[new] then
				st.Falling = false
				local impact = st.FastestDown
				st.FastestDown = 0
				local now = os.clock()
				if impact > Config.MinSpeed
					and humanoid.Health > 0
					and now - st.Last > Config.Cooldown
					and not player:GetAttribute("InWater") then
					st.Last = now
					humanoid:TakeDamage(damageFor(impact))
				end
			elseif new == Enum.HumanoidStateType.Jumping then
				st.Falling = false
			end
		end
	end)
end

function FallDamageService.Init()
end

function FallDamageService.Start()
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			hookCharacter(player, character)
		end)
	end)
	for _, player in Players:GetPlayers() do
		if player.Character then task.spawn(hookCharacter, player, player.Character) end
		player.CharacterAdded:Connect(function(character)
			hookCharacter(player, character)
		end)
	end

	-- só guarda a maior velocidade de descida durante a queda (leve: sem trabalho fora de queda)
	RunService.Heartbeat:Connect(function()
		for _, st in pairs(states) do
			if st.Falling and st.Root.Parent then
				local down = -st.Root.AssemblyLinearVelocity.Y
				if down > st.FastestDown then st.FastestDown = down end
			end
		end
	end)
end

return FallDamageService

