--[[
	Main (Script)
	Local: ServerScriptService > Main

	Único script "solto" do servidor. Ele:
	1. Impede o spawn automático até o mapa existir
	2. Cria os Remotes
	3. Carrega os serviços na ordem do GameConfig (Init de todos, depois Start de todos)
	4. Libera o spawn dos jogadores
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- Ninguém nasce antes de o mapa estar pronto (evita cair no vazio)
Players.CharacterAutoLoads = false

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameConfig = require(Modules:WaitForChild("GameConfig"))
local ServicesFolder = ServerScriptService:WaitForChild("Services")

print(string.format("[Main] %s v%s iniciando...", GameConfig.GameName, GameConfig.Version))

-- 1) REMOTES --------------------------------------------------------------
local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
if not remotesFolder then
	remotesFolder = Instance.new("Folder")
	remotesFolder.Name = "Remotes"
	remotesFolder.Parent = ReplicatedStorage
end

for _, remoteName in ipairs(GameConfig.Remotes.Events) do
	if not remotesFolder:FindFirstChild(remoteName) then
		local remote = Instance.new("RemoteEvent")
		remote.Name = remoteName
		remote.Parent = remotesFolder
	end
end

for _, remoteName in ipairs(GameConfig.Remotes.Functions) do
	if not remotesFolder:FindFirstChild(remoteName) then
		local remote = Instance.new("RemoteFunction")
		remote.Name = remoteName
		remote.Parent = remotesFolder
	end
end

-- 2) CARREGAR SERVIÇOS -----------------------------------------------------
local entries = {}

for _, serviceName in ipairs(GameConfig.ServiceLoadOrder) do
	local moduleScript = ServicesFolder:FindFirstChild(serviceName)
	if moduleScript and moduleScript:IsA("ModuleScript") then
		local ok, serviceOrError = pcall(require, moduleScript)
		if ok and type(serviceOrError) == "table" then
			table.insert(entries, { Name = serviceName, Service = serviceOrError, Failed = false })
		else
			warn(string.format("[Main] ERRO ao carregar '%s': %s", serviceName, tostring(serviceOrError)))
		end
	else
		warn(string.format("[Main] Serviço '%s' não encontrado em ServerScriptService > Services (ou não é ModuleScript).", serviceName))
	end
end

-- 3) INIT (prepara, sem depender dos outros) --------------------------------
for _, entry in ipairs(entries) do
	if type(entry.Service.Init) == "function" then
		local ok, err = xpcall(entry.Service.Init, debug.traceback)
		if not ok then
			entry.Failed = true
			warn(string.format("[Main] ERRO no Init de '%s':\n%s", entry.Name, tostring(err)))
		end
	end
end

-- 4) START (liga tudo) -----------------------------------------------------
for _, entry in ipairs(entries) do
	if not entry.Failed and type(entry.Service.Start) == "function" then
		local ok, err = xpcall(entry.Service.Start, debug.traceback)
		if not ok then
			entry.Failed = true
			warn(string.format("[Main] ERRO no Start de '%s':\n%s", entry.Name, tostring(err)))
		elseif GameConfig.Debug then
			print(string.format("[Main] Serviço '%s' iniciado.", entry.Name))
		end
	end
end

-- 5) LIBERAR SPAWN ---------------------------------------------------------
Players.CharacterAutoLoads = true
for _, player in ipairs(Players:GetPlayers()) do
	if not player.Character then
		task.spawn(function()
			local ok, err = pcall(function()
				player:LoadCharacter()
			end)
			if not ok then
				warn("[Main] Falha ao criar personagem de " .. player.Name .. ": " .. tostring(err))
			end
		end)
	end
end

print("[Main] Inicialização concluída.")