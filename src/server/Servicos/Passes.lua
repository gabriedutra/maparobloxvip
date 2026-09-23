--[[
	Passes.lua
	Game Passes: verifica quais o jogador possui ao entrar e entrega na hora
	quando ele compra dentro do jogo. Os IDs ficam em Config.GamePasses.

	Quando um pass é concedido:
	  • estado.Passes[nome] = true
	  • atributo "Pass_<nome>" no Player (a loja do cliente mostra "Comprado")
	  • VIP também liga o atributo "VIP" (tag no chat)
	  • avisa os outros módulos (multiplicador, slots extras, velocidade)
]]

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Jogadores = require(script.Parent.Jogadores)
local Notificar = require(script.Parent.Notificar)

local Passes = {}

local aoAdquirirFuncoes: { (Player, string) -> () } = {}
local GAME_PASSES = Config.GamePasses :: { [string]: number }

local function nomeDaLoja(chave: string): string
	for _, item in Config.Loja.GamePasses do
		if item.Chave == chave then
			return item.Nome
		end
	end
	return chave
end

-- Registra uma função chamada sempre que um jogador ganha um pass
function Passes.aoAdquirir(funcao: (Player, string) -> ())
	table.insert(aoAdquirirFuncoes, funcao)
end

function Passes.possui(player: Player?, nome: string): boolean
	if not player then
		return false
	end
	local estado = Jogadores.obter(player)
	return estado ~= nil and estado.Passes[nome] == true
end

local function conceder(player: Player, nome: string)
	local estado = Jogadores.obter(player)
	if not estado or estado.Passes[nome] then
		return
	end
	estado.Passes[nome] = true
	player:SetAttribute("Pass_" .. nome, true)
	if nome == "VIP" then
		player:SetAttribute("VIP", true)
	end
	for _, funcao in aoAdquirirFuncoes do
		task.spawn(funcao, player, nome)
	end
end

-- Consulta o Roblox para cada Game Pass configurado (pode demorar um pouco)
function Passes.verificar(player: Player)
	for nome, id in GAME_PASSES do
		if type(id) == "number" and id > 0 then
			local ok, possui = false, false
			for tentativa = 1, 3 do
				ok, possui = pcall(function()
					return MarketplaceService:UserOwnsGamePassAsync(player.UserId, id)
				end)
				if ok then
					break
				end
				task.wait(tentativa)
			end
			if not ok then
				warn("[Passes] Não foi possível verificar o Game Pass " .. nome .. " de " .. player.Name)
			elseif possui and player.Parent then
				conceder(player, nome)
			end
		end
	end
end

function Passes.iniciar()
	-- Compra feita dentro do jogo: entrega na hora
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, gamePassId: number, comprou: boolean)
		if not comprou then
			return
		end
		for nome, id in GAME_PASSES do
			if id ~= 0 and id == gamePassId then
				conceder(player, nome)
				Notificar.jogador(player, "Obrigado por comprar " .. nomeDaLoja(nome) .. "! 🎉", "sucesso")
			end
		end
	end)
end

return Passes
