--[[
	UIFxClient  (tipo: LocalScript)
	Local: StarterPlayer > StarterPlayerScripts > UIFxClient

	Liga o balanço suave (módulo UIFx) em TODOS os botões de TODAS as interfaces do jogador,
	inclusive os criados depois.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIFx = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UIFx"))
local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

UIFx.BindAll(playerGui)

