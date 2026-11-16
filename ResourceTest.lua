--[[
	ResourceTest (Script TEMPORÁRIO)
	Local: ServerScriptService > ResourceTest   (apague depois da aprovação da etapa)

	Simula pedidos "tortos" de coleta direto no servidor, como um jogador mal-intencionado faria,
	e confere se o servidor bloqueia.
]]

local ServerScriptService = game:GetService("ServerScriptService")
local Services = ServerScriptService:WaitForChild("Services")

local IslandService = require(Services:WaitForChild("IslandService"))
local ResourceService = require(Services:WaitForChild("ResourceService"))

local ran = false

IslandService.OnAssigned(function(player, info)
	if ran then
		return
	end
	ran = true
	task.wait(4)

	local ownFar, other
	for _, node in ipairs(ResourceService.GetNodes()) do
		if node.IslandIndex == info.Index and not ownFar then
			ownFar = node
		end
		if node.IslandIndex ~= info.Index and node.IslandIndex > 0 and not other then
			other = node
		end
	end

	print("[TESTE] ---- Validações de coleta (" .. player.Name .. ") ----")

	if other then
		local ok, reason = ResourceService.Debug_TryGather(player, other.Model)
		print("[TESTE] Recurso de OUTRA ilha:", ok and "PERMITIDO (FALHOU)" or ("BLOQUEADO (OK): " .. tostring(reason)))
	end

	if ownFar then
		local ok, reason = ResourceService.Debug_TryGather(player, ownFar.Model)
		print("[TESTE] Recurso da sua ilha, LONGE:", ok and "PERMITIDO (FALHOU)" or ("BLOQUEADO (OK): " .. tostring(reason)))
	end

	print("[TESTE] Agora chegue perto de um recurso da SUA ilha, aperte E (ou toque no botão) e acompanhe a barra.")
end)
