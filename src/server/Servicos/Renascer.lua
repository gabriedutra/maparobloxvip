--[[
	Renascer.lua
	Rebirth: com dinheiro suficiente, o jogador reseta (dinheiro volta ao
	inicial e, se Config.Rebirth.ResetarMonstrinhos, perde os monstrinhos)
	e ganha +Config.Rebirth.BonusPorRebirth de multiplicador permanente.
	O cliente só pede pelo RemoteEvent PedirRenascer; o servidor decide.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Formatar = require(Shared:WaitForChild("Formatar"))
local Regras = require(Shared:WaitForChild("Regras"))
local Remotos = require(Shared:WaitForChild("Remotos"))
local Bases = require(script.Parent.Bases)
local Dados = require(script.Parent.Dados)
local Economia = require(script.Parent.Economia)
local Jogadores = require(script.Parent.Jogadores)
local Limitador = require(script.Parent.Limitador)
local Notificar = require(script.Parent.Notificar)
local Roubo = require(script.Parent.Roubo)

local Renascer = {}

function Renascer.tentar(player: Player)
	if not Limitador.permitir(player, "Renascer", 2) then
		return
	end
	local estado = Jogadores.obterCarregado(player)
	if not estado then
		return
	end
	local dados = estado.Dados :: Jogadores.DadosJogador
	local custo = Regras.custoRebirth(dados.Rebirths)
	if dados.Dinheiro < custo then
		Notificar.jogador(player, "Você precisa de " .. Formatar.dinheiro(custo) .. " para renascer.", "erro")
		return
	end
	if Roubo.estaCarregando(player) then
		Notificar.jogador(player, "Termine o roubo antes de renascer!", "erro")
		return
	end

	-- Monstrinhos deste jogador que estão sendo roubados voltam antes de limpar a base
	Roubo.cancelarEnvolvendo(player, "rebirth", "rebirth")
	if Config.Rebirth.ResetarMonstrinhos then
		Bases.limparMonstrinhos(player)
	end
	local total = Economia.aplicarRebirth(player)
	Dados.solicitarSalvamento(player)

	local novoMultiplicador = Formatar.multiplicador(Regras.multiplicadorRebirth(total))
	Notificar.jogador(player, "♻️ Você renasceu! Bônus de renda permanente: " .. novoMultiplicador, "sucesso")
	Notificar.todos("♻️ " .. player.DisplayName .. " renasceu! (Rebirth " .. total .. ")", "info")
end

function Renascer.iniciar()
	Remotos.PedirRenascer.OnServerEvent:Connect(function(player: Player)
		Renascer.tentar(player)
	end)
end

return Renascer
