--[[
	Produtos.lua
	Developer Products (compras que podem ser feitas várias vezes) com
	MarketplaceService.ProcessReceipt, de forma IDEMPOTENTE:

	  1. Se o jogador não está no servidor ou os dados não carregaram
	     -> NotProcessedYet (o Roblox tenta de novo depois).
	  2. Se o PurchaseId já está em ComprasProcessadas -> PurchaseGranted
	     (já foi entregue antes; não entrega de novo).
	  3. Entrega o produto, registra o PurchaseId nos dados do jogador e salva
	     no DataStore. Só responde PurchaseGranted depois de salvar.
	     Se o salvamento falhar, responde NotProcessedYet: como o PurchaseId já
	     ficou registrado, a nova tentativa do Roblox não entrega em dobro.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Formatar = require(Shared:WaitForChild("Formatar"))
local Regras = require(Shared:WaitForChild("Regras"))
local Bases = require(script.Parent.Bases)
local Dados = require(script.Parent.Dados)
local Economia = require(script.Parent.Economia)
local Esteira = require(script.Parent.Esteira)
local Jogadores = require(script.Parent.Jogadores)
local Notificar = require(script.Parent.Notificar)

local Produtos = {}

local ESPERA_DADOS = 15 -- segundos esperando os dados carregarem

-- Entrega cada produto. Devolve true se entregou.
local entregas: { [string]: (Player) -> (boolean, string?) } = {
	TrancarAgora = function(player: Player)
		local ok, mensagem = Bases.trancar(player, true)
		if ok then
			Notificar.jogador(player, "🔒 Base trancada na hora! (" .. Config.Trancar.Duracao .. " s)", "sucesso")
		end
		return ok, mensagem
	end,
	SorteBoost = function(player: Player)
		Esteira.ativarSorte(player, Config.Sorte.Duracao)
		Notificar.jogador(player, "🍀 Obrigado! A sorte da esteira está ativa.", "sucesso")
		return true, nil
	end,
	PacoteDinheiro = function(player: Player)
		local valor = Regras.valorPacoteDinheiro(Economia.rendaPorSegundo(player))
		if not Economia.adicionar(player, valor) then
			return false, "não foi possível adicionar o dinheiro"
		end
		Notificar.jogador(player, "💰 Você recebeu " .. Formatar.dinheiro(valor) .. "!", "sucesso")
		return true, nil
	end,
}

local function chaveDoProduto(productId: number): string?
	local produtos = Config.Produtos :: { [string]: number }
	for chave, id in produtos do
		if type(id) == "number" and id > 0 and id == productId then
			return chave
		end
	end
	return nil
end

local function processarRecibo(recibo): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(recibo.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local chave = chaveDoProduto(recibo.ProductId)
	local entregar = chave and entregas[chave]
	if not chave or not entregar then
		warn("[Produtos] ProductId desconhecido: " .. tostring(recibo.ProductId) .. " (confira Config.Produtos)")
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- Espera os dados do jogador carregarem
	local limite = os.clock() + ESPERA_DADOS
	local estado = Jogadores.obterCarregado(player)
	while not estado and player.Parent and os.clock() < limite do
		task.wait(0.25)
		estado = Jogadores.obterCarregado(player)
	end
	if not estado or not player.Parent then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local purchaseId = tostring(recibo.PurchaseId)
	if Dados.compraJaProcessada(player, purchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	if estado.ProcessandoCompras[purchaseId] then
		-- O mesmo recibo já está sendo tratado em outra chamada
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	estado.ProcessandoCompras[purchaseId] = true

	local ok, entregou, mensagem = pcall(entregar, player)
	if not ok or not entregou then
		estado.ProcessandoCompras[purchaseId] = nil
		warn(("[Produtos] Falha ao entregar %s para %s: %s"):format(chave, player.Name, tostring(if ok then mensagem else entregou)))
		Notificar.jogador(player, "Não foi possível entregar sua compra agora. Tentaremos de novo automaticamente.", "erro")
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- Registra ANTES de salvar: evita entrega dupla em novas tentativas
	Dados.registrarCompra(player, purchaseId)
	local salvo = if Dados.salvaProgresso(player) then Dados.salvarAgora(player) else true
	estado.ProcessandoCompras[purchaseId] = nil
	if salvo then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

function Produtos.iniciar()
	MarketplaceService.ProcessReceipt = processarRecibo
end

-- Exposto para testes
Produtos._processarRecibo = processarRecibo

return Produtos
