--[[
	UIFx
	Local: ReplicatedStorage > Modules > UIFx   (ModuleScript)

	Efeito nos botões: ao passar o mouse (ou tocar/clicar) o botão balança de leve e cresce um
	pouquinho, tudo com suavização. Ao tirar o mouse / soltar, o balanço desacelera e PARA.

	  UIFx.Bind(botao)            -> liga o efeito em UM botão
	  UIFx.BindAll(container)     -> liga em todos os botões de um container, inclusive os que
	                                 forem criados depois
	Para deixar um botão de fora: botao:SetAttribute("NoFx", true)
]]

local RunService = game:GetService("RunService")

local UIFx = {}

local SWAY_DEGREES = 1.8  -- inclinação máxima do balanço
local SWAY_SPEED = 10     -- velocidade do balanço (rad/s)
local HOVER_SCALE = 1.045
local PRESS_SCALE = 0.97

local states = setmetatable({}, { __mode = "k" }) -- [botão] = estado (some sozinho quando o botão é destruído)
local active = {}                                -- botões animando agora
local loop = nil

local function step(dt)
	local any = false
	for button, st in active do
		if not button.Parent then
			active[button] = nil
		else
			local on = st.hover or st.press
			st.phase += dt * SWAY_SPEED
			st.pulse = math.max(0, st.pulse - dt * 4)

			local targetRot = on and math.sin(st.phase) * SWAY_DEGREES or 0
			local targetScale = st.press and PRESS_SCALE or (on and HOVER_SCALE or 1)
			targetScale += st.pulse * 0.08

			local k = 1 - math.exp(-dt * 14) -- suavização (começa e para devagar)
			st.rot += (targetRot - st.rot) * k
			st.scale += (targetScale - st.scale) * k

			button.Rotation = st.baseRotation + st.rot
			st.uiScale.Scale = st.baseScale * st.scale

			if not on and st.pulse <= 0 and math.abs(st.rot) < 0.02 and math.abs(st.scale - 1) < 0.002 then
				button.Rotation = st.baseRotation
				st.uiScale.Scale = st.baseScale
				st.rot, st.scale, st.phase = 0, 1, 0
				active[button] = nil
			else
				any = true
			end
		end
	end
	if not any and loop then
		loop:Disconnect()
		loop = nil
	end
end

local function wake(button)
	active[button] = states[button]
	if not loop then
		loop = RunService.RenderStepped:Connect(step)
	end
end

function UIFx.Bind(button)
	if states[button] or button:GetAttribute("NoFx") then return end
	if not (button:IsA("TextButton") or button:IsA("ImageButton")) then return end

	local uiScale = button:FindFirstChildOfClass("UIScale")
	if not uiScale then
		uiScale = Instance.new("UIScale")
		uiScale.Name = "UIFxScale"
		uiScale.Parent = button
	end

	local st = {
		hover = false,
		press = false,
		phase = 0,
		pulse = 0,
		rot = 0,
		scale = 1,
		baseRotation = button.Rotation,
		baseScale = uiScale.Scale,
		uiScale = uiScale,
	}
	states[button] = st

	button.MouseEnter:Connect(function()
		st.hover = true
		wake(button)
	end)
	button.MouseLeave:Connect(function()
		st.hover = false
		st.press = false
		wake(button)
	end)
	button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			st.press = true
			wake(button)
		end
	end)
	button.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			st.press = false
			if input.UserInputType == Enum.UserInputType.Touch then
				st.hover = false -- no celular não existe "passar o mouse"
			end
			wake(button)
		end
	end)
	button.Activated:Connect(function()
		st.pulse = 1
		wake(button)
	end)
	button.SelectionGained:Connect(function()
		st.hover = true
		wake(button)
	end)
	button.SelectionLost:Connect(function()
		st.hover = false
		wake(button)
	end)
end

function UIFx.BindAll(container)
	for _, d in container:GetDescendants() do
		UIFx.Bind(d)
	end
	container.DescendantAdded:Connect(function(d)
		-- espera um frame: quem cria o botão ainda está ajustando propriedades
		task.defer(UIFx.Bind, d)
	end)
end

return UIFx

