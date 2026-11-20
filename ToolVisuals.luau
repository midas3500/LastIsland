--[[
	ToolVisuals (ModuleScript)
	Local: ServerScriptService > Services > ToolVisuals   (arquivo NOVO)

	Modelos do machado e da picareta + animação do golpe. Tudo por código (sem assets).

	ToolVisuals.CreateTool(nomeDaFerramenta, nivel, dadosDoNivel) -> Tool
		Machado : cabo com empunhadura de couro, colar, lâmina que sai para BAIXO e "bigorna" atrás.
		Picareta: cabeça curva de duas pontas NO PLANO DO GOLPE (antes ficava de lado).
		Nível 1 = pedra amarrada com fibra | nível 2 = ferro com rebites | nível 3 = ouro com gema e brilho.
		Cada ferramenta tem um rastro (Trail) que só aparece durante o golpe.

	ToolVisuals.PlaySwing(tool, nomeDaFerramenta, humanoid, estado, aoImpactar) -> duração do ciclo
		Por padrão anima a ferramenta na mão (windup -> golpe -> pausa no impacto -> volta).
		Se houver AnimationId em ResourceConfig.ToolAnimation, usa a sua animação.
		"aoImpactar" é chamada no instante exato do impacto.

	Convenção da ferramenta: a CABEÇA fica no lado -Z do cabo; a mão segura perto do lado +Z.
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ResourceConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ResourceConfig"))

local ToolVisuals = {}

-- Valores padrão: funcionam mesmo se o ResourceConfig não tiver ToolAnimation/ToolVisual
local DEFAULT_ANIMATION = {
	Enabled = true, UseDefaultSlash = true, InvertSwing = false,
	Windup = 0.22, Strike = 0.09, HitStop = 0.04, Recover = 0.30,
	WindupAngle = 50, StrikeAngle = 28,
}

local baseGrips = setmetatable({}, { __mode = "k" })

local LEATHER = Color3.fromRGB(105, 72, 44)
local FIBER = Color3.fromRGB(120, 180, 90)
local GEM = Color3.fromRGB(255, 80, 90)

local function shade(color, factor)
	return Color3.new(
		math.clamp(color.R * factor, 0, 1),
		math.clamp(color.G * factor, 0, 1),
		math.clamp(color.B * factor, 0, 1)
	)
end

-- ===========================================================================
-- MODELOS
-- ===========================================================================

function ToolVisuals.CreateTool(toolName, tier, tierData)
	local visual = ResourceConfig.ToolVisual or {}
	local length = visual.HandleLength or 3.4

	local tool = Instance.new("Tool")
	tool.Name = tierData.Name
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.ManualActivationOnly = true
	tool.GripPos = visual.GripPos or Vector3.new(0, 0, 1.2)

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.3, 0.3, length)
	handle.Material = ResourceConfig.Visuals.Trunk.Material
	handle.Color = ResourceConfig.Visuals.Trunk.Color
	handle.CanCollide = false
	handle.CanQuery = false
	handle.Massless = true
	handle.Parent = tool

	local headColor = tierData.HeadColor
	local headMaterial = tierData.HeadMaterial
	local headReflectance = tierData.HeadReflectance or 0

	-- opts: { Shape, Material, Color, Reflectance }
	local function addPiece(name, size, offset, opts)
		opts = opts or {}
		local piece = Instance.new("Part")
		piece.Name = name
		piece.Size = size
		piece.Material = opts.Material or headMaterial
		piece.Color = opts.Color or headColor
		piece.Reflectance = opts.Reflectance or 0
		if opts.Shape then
			piece.Shape = opts.Shape
		end
		piece.CanCollide = false
		piece.CanQuery = false
		piece.Massless = true
		piece.CFrame = handle.CFrame * offset
		piece.Parent = tool

		local weld = Instance.new("Weld")
		weld.Part0 = handle
		weld.Part1 = piece
		weld.C0 = offset
		weld.Parent = piece
		return piece
	end

	-- anel/cilindro ao redor do cabo (eixo Z)
	local function addRing(name, thickness, diameter, z, opts)
		opts = opts or {}
		opts.Shape = Enum.PartType.Cylinder
		return addPiece(name, Vector3.new(thickness, diameter, diameter),
			CFrame.new(0, 0, z) * CFrame.Angles(0, math.pi / 2, 0), opts)
	end

	local front, back = -length / 2, length / 2
	local headZ = front + 0.4

	-- empunhadura e pomo
	addRing("Pommel", 0.22, 0.46, back - 0.05, { Material = Enum.Material.Wood, Color = shade(handle.Color, 0.7) })
	for i = 1, 3 do
		addRing("Wrap_" .. i, 0.16, 0.4, back - 0.45 - (i - 1) * 0.3, { Material = Enum.Material.Fabric, Color = LEATHER })
	end

	-- colar da cabeça
	addPiece("Collar", Vector3.new(0.46, 0.46, 0.7), CFrame.new(0, 0, headZ),
		{ Color = shade(headColor, tier == 1 and 0.65 or 0.82), Material = tier == 1 and Enum.Material.Wood or headMaterial })

	local edgePart, edgeAttachmentPos

	if toolName == "Axe" then
		-- lâmina para baixo (-Y), ponta de corte na frente (-Z), "bigorna" atrás
		addPiece("Blade", Vector3.new(0.16, 0.84, 0.85), CFrame.new(0, -0.65, headZ - 0.05), { Reflectance = headReflectance })
		edgePart = addPiece("Edge", Vector3.new(0.08, 0.16, 1.2), CFrame.new(0, -1.1, headZ - 0.12), {
			Color = shade(headColor, 1.15), Reflectance = headReflectance,
		})
		edgeAttachmentPos = Vector3.new(0, -0.05, -0.6)
		addPiece("Poll", Vector3.new(0.3, 0.34, 0.5), CFrame.new(0, 0.34, headZ + 0.05), { Color = shade(headColor, 0.85) })
		if tier == 1 then
			addPiece("Chip", Vector3.new(0.12, 0.5, 0.4), CFrame.new(0.09, -0.45, headZ - 0.35) * CFrame.Angles(math.rad(15), 0, math.rad(8)),
				{ Color = shade(headColor, 1.1) })
		end
	else
		-- picareta: barra no plano do golpe (eixo Y), pontas curvando para o lado do cabo (+Z)
		addPiece("Bar", Vector3.new(0.2, 1.0, 0.3), CFrame.new(0, 0, headZ), { Reflectance = headReflectance })
		for _, s in ipairs({ 1, -1 }) do
			addPiece(s == 1 and "ArmUp" or "ArmDown", Vector3.new(0.16, 0.7, 0.26),
				CFrame.new(0, 0.8 * s, headZ + 0.12) * CFrame.Angles(math.rad(22) * s, 0, 0), { Reflectance = headReflectance })
			local tip = addPiece(s == 1 and "TipUp" or "TipDown", Vector3.new(0.1, 0.5, 0.18),
				CFrame.new(0, 1.31 * s, headZ + 0.41) * CFrame.Angles(math.rad(40) * s, 0, 0), {
					Color = shade(headColor, 1.15), Reflectance = headReflectance,
				})
			if s == -1 then
				edgePart = tip
				edgeAttachmentPos = Vector3.new(0, -0.25, 0)
			end
		end
	end

	-- detalhes por nível
	if tier == 1 then
		for _, dz in ipairs({ 0.24, -0.24 }) do
			addRing("Lashing", 0.12, 0.54, headZ + dz, { Material = Enum.Material.Fabric, Color = FIBER })
		end
	elseif tier == 2 then
		addRing("Band", 0.12, 0.56, headZ, { Color = shade(headColor, 0.7) })
		for _, dz in ipairs({ 0.15, -0.15 }) do
			addPiece("Rivet", Vector3.new(0.1, 0.1, 0.1), CFrame.new(0.24, 0.05, headZ + dz), { Color = shade(headColor, 1.25) })
		end
	else
		addRing("GoldBand", 0.14, 0.58, headZ + 0.18, { Reflectance = 0.15 })
		addRing("GoldBand2", 0.14, 0.58, headZ - 0.18, { Reflectance = 0.15 })
		addPiece("Gem", Vector3.new(0.24, 0.24, 0.24), CFrame.new(0, 0, back + 0.2), {
			Shape = Enum.PartType.Ball, Material = Enum.Material.Neon, Color = GEM,
		})
	end

	-- brilho suave (nível 3)
	if tierData.GlowColor then
		local collar = tool:FindFirstChild("Collar")
		if collar then
			local light = Instance.new("PointLight")
			light.Color = tierData.GlowColor
			light.Range = 7
			light.Brightness = 0.7
			light.Shadows = false
			light.Parent = collar
		end
	end

	-- rastro do golpe (liga só durante a pancada)
	if edgePart then
		local a0 = Instance.new("Attachment")
		a0.Name = "TrailA"
		a0.Position = edgeAttachmentPos
		a0.Parent = edgePart

		local collar = tool:FindFirstChild("Collar")
		local a1 = Instance.new("Attachment")
		a1.Name = "TrailB"
		a1.Position = Vector3.new(0, 0, 0.35)
		a1.Parent = collar

		local trail = Instance.new("Trail")
		trail.Name = "SwingTrail"
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Lifetime = 0.18
		trail.MinLength = 0.05
		trail.LightEmission = 0.5
		trail.Color = ColorSequence.new(tierData.TrailColor or Color3.new(1, 1, 1))
		trail.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.25),
			NumberSequenceKeypoint.new(1, 1),
		})
		trail.WidthScale = NumberSequence.new(1, 0.2)
		trail.Enabled = false
		trail.Parent = edgePart
	end

	baseGrips[tool] = tool.Grip
	return tool
end

-- ===========================================================================
-- ANIMAÇÃO DO GOLPE
-- ===========================================================================

local function easeOutCubic(x)
	return 1 - (1 - x) ^ 3
end

local function easeInQuad(x)
	return x * x
end

local function easeInOut(x)
	return x < 0.5 and 2 * x * x or 1 - ((-2 * x + 2) ^ 2) / 2
end

-- estado = tabela da sessão (guarda a animação própria carregada, se houver)
function ToolVisuals.PlaySwing(tool, toolName, humanoid, state, onImpact)
	local cfg = ResourceConfig.ToolAnimation or DEFAULT_ANIMATION
	if not cfg or not cfg.Enabled or not tool or not tool.Parent then
		return nil
	end
	local toolCfg = cfg[toolName] or {}
	local timing = setmetatable({}, { __index = DEFAULT_ANIMATION })
	for key, value in pairs(cfg) do timing[key] = value end

	-- 1) animação própria (AnimationId preenchido): o Animator do servidor replica para todos
	if type(toolCfg.AnimationId) == "string" and toolCfg.AnimationId ~= "" and humanoid then
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if animator then
			if not state.Track then
				local animation = Instance.new("Animation")
				animation.AnimationId = toolCfg.AnimationId
				local ok, track = pcall(function()
					return animator:LoadAnimation(animation)
				end)
				if ok and track then
					track.Priority = Enum.AnimationPriority.Action
					state.Track = track
				end
			end
			if state.Track then
				state.Track:Play(0.05)
				task.delay(toolCfg.ImpactTime or 0.3, onImpact)
				local length = state.Track.Length
				return length > 0 and length or 0.8
			end
		end
	end

	-- 2) animação por código: gira a ferramenta em torno da mão (Tool.Grip)
	local base = baseGrips[tool] or tool.Grip
	local windup, strike, stop, recover = timing.Windup, timing.Strike, timing.HitStop, timing.Recover
	local total = windup + strike + stop + recover
	local direction = timing.InvertSwing and -1 or 1
	local windupAngle = math.rad(timing.WindupAngle)
	local strikeAngle = math.rad(timing.StrikeAngle)
	local trail = tool:FindFirstChild("SwingTrail", true)

	task.spawn(function()
		local startedAt = os.clock()
		local impacted = false

		while true do
			local t = os.clock() - startedAt
			if t >= total or not tool.Parent then
				break
			end

			local angle
			if t < windup then
				angle = -windupAngle * easeOutCubic(t / windup)
			elseif t < windup + strike then
				local a = easeInQuad((t - windup) / strike)
				angle = -windupAngle + (strikeAngle + windupAngle) * a
				if trail and not trail.Enabled then
					trail.Enabled = true
				end
			elseif t < windup + strike + stop then
				angle = strikeAngle
				if not impacted then
					impacted = true
					task.spawn(onImpact)
				end
			else
				local a = easeInOut((t - windup - strike - stop) / recover)
				angle = strikeAngle * (1 - a)
				if trail and trail.Enabled then
					trail.Enabled = false
				end
			end

			tool.Grip = base * CFrame.Angles(angle * direction, 0, 0)
			RunService.Heartbeat:Wait()
		end

		if trail then
			trail.Enabled = false
		end
		if tool.Parent then
			tool.Grip = base
		end
	end)

	return total
end

return ToolVisuals

