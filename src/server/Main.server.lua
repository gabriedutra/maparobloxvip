--[[
	Main.server.lua — ponto de entrada do servidor de "Roube o Monstrinho".
	Inicia os serviços na ordem certa e cuida da entrada/saída dos jogadores.
]]

local Players = game:GetService("Players")

local Servicos = script.Parent:WaitForChild("Servicos")
local Bases = require(Servicos:WaitForChild("Bases"))
local Dados = require(Servicos:WaitForChild("Dados"))
local Economia = require(Servicos:WaitForChild("Economia"))
local Esteira = require(Servicos:WaitForChild("Esteira"))
local Interacoes = require(Servicos:WaitForChild("Interacoes"))
local Jogadores = require(Servicos:WaitForChild("Jogadores"))
local Limitador = require(Servicos:WaitForChild("Limitador"))
local Mapa = require(Servicos:WaitForChild("Mapa"))
local Notificar = require(Servicos:WaitForChild("Notificar"))
local Passes = require(Servicos:WaitForChild("Passes"))
local Produtos = require(Servicos:WaitForChild("Produtos"))
local Renascer = require(Servicos:WaitForChild("Renascer"))
local Roubo = require(Servicos:WaitForChild("Roubo"))

-- 1) Mapa e serviços
local mapa = Mapa.iniciar()
Passes.iniciar()
Bases.iniciar(mapa)
Esteira.iniciar(mapa)
Roubo.iniciar()
Interacoes.iniciar()
Renascer.iniciar()
Produtos.iniciar()
Dados.definirSerializador(Bases.serializar)
Dados.iniciar()

-- Game Pass novo: atualiza multiplicador, slots extras e velocidade de carregar
Passes.aoAdquirir(function(player: Player, _nome: string)
	Economia.atualizarRenda(player)
	Bases.aoMudarPasses(player)
	Roubo.aoMudarPasses(player)
end)

-- 2) Jogadores
local function aoEntrar(player: Player)
	if Jogadores.obter(player) then
		return -- já tratado (PlayerAdded + GetPlayers podem coincidir)
	end
	Jogadores.criar(player)
	Economia.prepararJogador(player)
	Bases.atribuir(player) -- sem esperar nada: define o spawn antes do personagem nascer

	Passes.verificar(player)
	if not player.Parent then
		return
	end

	local ok = Dados.carregar(player)
	if not ok then
		if player.Parent then
			player:Kick("Não foi possível carregar seus dados agora. Tente entrar de novo em alguns instantes.")
		end
		return
	end

	Economia.aplicarDados(player)
	Bases.restaurar(player)
	player:SetAttribute("Carregado", true)
	Notificar.jogador(player, "Bem-vindo(a) ao Roube o Monstrinho! Compre monstrinhos na esteira e proteja sua base! 🎉", "info")
	if not Dados.salvaProgresso(player) then
		Notificar.jogador(player, "Modo teste: o progresso não será salvo (DataStore indisponível no Studio).", "alerta")
	end
end

local function aoSair(player: Player)
	-- A ordem importa: devolve os roubos, tira a "foto" dos dados e só então limpa a base
	Roubo.cancelarEnvolvendo(player, "ladraoSaiu", "vitimaSaiu")
	Dados.aoSair(player)
	Bases.liberar(player)
	Limitador.limpar(player)
	Jogadores.remover(player)
end

Players.PlayerAdded:Connect(aoEntrar)
Players.PlayerRemoving:Connect(aoSair)
for _, player in Players:GetPlayers() do
	task.spawn(aoEntrar, player)
end

print("[Roube o Monstrinho] Servidor iniciado!")
