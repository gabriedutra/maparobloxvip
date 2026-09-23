--[[
	Economia.lua
	Toda a lógica de dinheiro fica no servidor:
	  • dinheiro, coletor e rebirths ficam em estado.Dados;
	  • o cliente só enxerga os valores pelos atributos do Player
	    (Dinheiro, RendaPorSegundo, Multiplicador, Rebirths) e pelo leaderstats.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Formatar = require(Shared:WaitForChild("Formatar"))
local Regras = require(Shared:WaitForChild("Regras"))
local Jogadores = require(script.Parent.Jogadores)
local Notificar = require(script.Parent.Notificar)
local Passes = require(script.Parent.Passes)

local Economia = {}

local LIMITE_LEADERSTATS = 9e18 -- IntValue guarda no máximo ~9,2 * 10^18

local function valorValido(valor: any): boolean
	return type(valor) == "number" and valor == valor and valor >= 0 and valor < math.huge
end

-- Cria o leaderstats e os atributos padrão (antes de os dados carregarem)
function Economia.prepararJogador(player: Player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"

	local dinheiro = Instance.new("IntValue")
	dinheiro.Name = "Dinheiro"
	dinheiro.Parent = leaderstats

	local rebirths = Instance.new("IntValue")
	rebirths.Name = "Rebirths"
	rebirths.Parent = leaderstats

	leaderstats.Parent = player

	player:SetAttribute("Carregado", false)
	player:SetAttribute("Dinheiro", 0)
	player:SetAttribute("RendaPorSegundo", 0)
	player:SetAttribute("Multiplicador", 1)
	player:SetAttribute("Rebirths", 0)
	player:SetAttribute("BaseIndice", 0)
	player:SetAttribute("TrancadaAte", 0)
	player:SetAttribute("RecargaAte", 0)
	player:SetAttribute("Carregando", "")
end

-- Copia os valores do servidor para os atributos e para o leaderstats
local function sincronizar(player: Player)
	local estado = Jogadores.obterCarregado(player)
	if not estado then
		return
	end
	local dados = estado.Dados :: Jogadores.DadosJogador
	player:SetAttribute("Dinheiro", dados.Dinheiro)
	player:SetAttribute("Rebirths", dados.Rebirths)

	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		local dinheiro = leaderstats:FindFirstChild("Dinheiro") :: IntValue?
		if dinheiro then
			dinheiro.Value = math.floor(math.min(dados.Dinheiro, LIMITE_LEADERSTATS))
		end
		local rebirths = leaderstats:FindFirstChild("Rebirths") :: IntValue?
		if rebirths then
			rebirths.Value = dados.Rebirths
		end
	end
end

-- ------------------------------------------------------------
-- Renda
-- ------------------------------------------------------------

function Economia.multiplicador(player: Player): number
	local estado = Jogadores.obterCarregado(player)
	local rebirths = if estado then (estado.Dados :: Jogadores.DadosJogador).Rebirths else 0
	return Regras.multiplicadorTotal(rebirths, Passes.possui(player, "VIP"), Passes.possui(player, "DinheiroDobrado"))
end

function Economia.rendaPorSegundo(player: Player): number
	local estado = Jogadores.obter(player)
	if not estado then
		return 0
	end
	return estado.RendaBase * Economia.multiplicador(player)
end

-- Atualiza os atributos de renda/multiplicador (chame quando algo mudar)
function Economia.atualizarRenda(player: Player)
	local estado = Jogadores.obter(player)
	if not estado then
		return
	end
	local multiplicador = Economia.multiplicador(player)
	player:SetAttribute("Multiplicador", multiplicador)
	player:SetAttribute("RendaPorSegundo", estado.RendaBase * multiplicador)
end

-- Soma da renda dos monstrinhos da base (sem multiplicador); definida pelo módulo Bases
function Economia.definirRendaBase(player: Player, valor: number)
	local estado = Jogadores.obter(player)
	if not estado then
		return
	end
	estado.RendaBase = math.max(0, valor)
	Economia.atualizarRenda(player)
end

-- ------------------------------------------------------------
-- Dinheiro
-- ------------------------------------------------------------

function Economia.obterDinheiro(player: Player): number
	local estado = Jogadores.obterCarregado(player)
	return if estado then (estado.Dados :: Jogadores.DadosJogador).Dinheiro else 0
end

function Economia.adicionar(player: Player, valor: number): boolean
	if not valorValido(valor) then
		warn("[Economia] Valor inválido em adicionar: " .. tostring(valor))
		return false
	end
	local estado = Jogadores.obterCarregado(player)
	if not estado then
		return false
	end
	local dados = estado.Dados :: Jogadores.DadosJogador
	dados.Dinheiro += valor
	sincronizar(player)
	return true
end

-- Tira dinheiro se o jogador tiver saldo. Devolve true se conseguiu.
function Economia.gastar(player: Player, valor: number): boolean
	if not valorValido(valor) then
		return false
	end
	local estado = Jogadores.obterCarregado(player)
	if not estado then
		return false
	end
	local dados = estado.Dados :: Jogadores.DadosJogador
	if dados.Dinheiro < valor then
		return false
	end
	dados.Dinheiro -= valor
	sincronizar(player)
	return true
end

-- ------------------------------------------------------------
-- Coletor da base
-- ------------------------------------------------------------

function Economia.adicionarColetor(player: Player, valor: number)
	if not valorValido(valor) then
		return
	end
	local estado = Jogadores.obterCarregado(player)
	if estado then
		local dados = estado.Dados :: Jogadores.DadosJogador
		dados.Coletor += valor
	end
end

function Economia.obterColetor(player: Player): number
	local estado = Jogadores.obterCarregado(player)
	return if estado then (estado.Dados :: Jogadores.DadosJogador).Coletor else 0
end

-- Passa o dinheiro do coletor para a carteira. Devolve quanto foi coletado.
function Economia.coletar(player: Player): number
	local estado = Jogadores.obterCarregado(player)
	if not estado then
		return 0
	end
	local dados = estado.Dados :: Jogadores.DadosJogador
	local valor = dados.Coletor
	if valor < 1 then
		return 0
	end
	dados.Coletor = 0
	dados.Dinheiro += valor
	sincronizar(player)
	Notificar.jogador(player, "+" .. Formatar.dinheiro(valor), "dinheiro")
	return valor
end

-- ------------------------------------------------------------
-- Outros
-- ------------------------------------------------------------

-- Aplica os valores carregados do DataStore nos atributos/leaderstats
function Economia.aplicarDados(player: Player)
	sincronizar(player)
	Economia.atualizarRenda(player)
end

-- Rebirth: +1 rebirth, dinheiro volta ao inicial e o coletor zera
function Economia.aplicarRebirth(player: Player): number
	local estado = Jogadores.obterCarregado(player)
	if not estado then
		return 0
	end
	local dados = estado.Dados :: Jogadores.DadosJogador
	dados.Rebirths += 1
	dados.Dinheiro = Config.Economia.DinheiroInicial
	dados.Coletor = 0
	sincronizar(player)
	Economia.atualizarRenda(player)
	return dados.Rebirths
end

return Economia
