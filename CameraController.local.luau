
-- CameraController V3
-- Local: StarterPlayer > StarterPlayerScripts

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local mouseFree = false

--------------------------------------------------
-- INTERFACE
--------------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "CameraInterface"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 100
screenGui.Parent = playerGui

-- MIRA CENTRAL (X)

local crosshair = Instance.new("TextLabel")
crosshair.Name = "Crosshair"
crosshair.Size = UDim2.fromOffset(24, 24)
crosshair.Position = UDim2.fromScale(0.5, 0.5)
crosshair.AnchorPoint = Vector2.new(0.5, 0.5)
crosshair.BackgroundTransparency = 1
crosshair.Text = "×"
crosshair.TextColor3 = Color3.fromRGB(255, 255, 255)
crosshair.TextSize = 25
crosshair.Font = Enum.Font.GothamBold
crosshair.TextStrokeTransparency = 0.35
crosshair.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
crosshair.Parent = screenGui

-- TEXTO INFERIOR ESQUERDO

local hint = Instance.new("TextLabel")
hint.Name = "MouseHint"
hint.Size = UDim2.fromOffset(230, 30)
hint.Position = UDim2.new(0, 15, 1, -45)
hint.BackgroundTransparency = 1
hint.Text = "Clique ALT para alternar o Mouse"
hint.TextColor3 = Color3.fromRGB(255, 255, 255)
hint.TextSize = 13
hint.Font = Enum.Font.GothamMedium
hint.TextXAlignment = Enum.TextXAlignment.Left
hint.TextStrokeTransparency = 0.4
hint.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
hint.Parent = screenGui

--------------------------------------------------
-- CÂMERA
--------------------------------------------------

local function updateCamera()

	if mouseFree then

		player.CameraMode = Enum.CameraMode.Classic

		UserInputService.MouseBehavior =
			Enum.MouseBehavior.Default

		UserInputService.MouseIconEnabled = true

	else

		player.CameraMode = Enum.CameraMode.LockFirstPerson

		UserInputService.MouseBehavior =
			Enum.MouseBehavior.LockCenter

		UserInputService.MouseIconEnabled = false

	end
end

--------------------------------------------------
-- ALTERNAR ALT
--------------------------------------------------

UserInputService.InputBegan:Connect(function(input)

	if input.KeyCode == Enum.KeyCode.LeftAlt
		or input.KeyCode == Enum.KeyCode.RightAlt then

		mouseFree = not mouseFree

		updateCamera()

		print(
			"[CameraController] Mouse:",
			mouseFree and "LIVRE" or "TRAVADO"
		)
	end
end)

--------------------------------------------------
-- PERSONAGEM
--------------------------------------------------

player.CharacterAdded:Connect(function()

	task.wait(0.5)

	updateCamera()

end)

--------------------------------------------------
-- CONTROLE DO MOUSE
--------------------------------------------------

RunService:BindToRenderStep(
	"CameraMouseController",
	Enum.RenderPriority.Last.Value,
	function()

		if mouseFree then

			UserInputService.MouseBehavior =
				Enum.MouseBehavior.Default

			UserInputService.MouseIconEnabled = true

		else

			UserInputService.MouseBehavior =
				Enum.MouseBehavior.LockCenter

			UserInputService.MouseIconEnabled = false

		end
	end
)

--------------------------------------------------
-- INICIAR
--------------------------------------------------

updateCamera()

print("[CameraController] Interface e câmera iniciadas.")
