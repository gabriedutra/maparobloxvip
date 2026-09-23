--[[
	Dados.lua
	Salva e carrega o progresso dos jogadores com DataStoreService.

	Como funciona:
	  • Cada jogador tem uma chave "Jogador_<UserId>".
	  • Trava de sessão: ao carregar, o servidor grava { JobId, Hora } em "Sessao".
	    Se outro servidor ainda estiver com a trava (o jogador acabou de trocar de
	    servidor), esperamos ele liberar. Assim um servidor não sobrescreve os
	    dados salvos por outro.
	  • Tudo usa UpdateAsync com várias tentativas (retry com espera crescente).
	  • Salva automaticamente a cada Config.Dados.IntervaloAutoSave segundos,
	    quando o jogador sai (liberando a trava) e no BindToClose (servidor fechando).
	  • No Studio sem acesso à API, o jogo roda em "modo teste" sem salvar.
]]

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Jogadores = require(script.Parent.Jogadores)

local Dados = {}

local VERSAO_DADOS = 1

type DadosJogador = Jogadores.DadosJogador

type Perfil = {
	Player: Player,
	Chave: string,
	Dados: DadosJogador?,
	Carregado: boolean,
	SemSalvar: boolean, -- modo teste (Studio sem DataStore)
	Salvando: boolean,
	Saindo: boolean,
	Liberado: boolean, -- trava de sessão já devolvida (não salva mais)
	SessaoPerdida: boolean, -- outro servidor assumiu os dados (não salva mais)
	SalvamentoAgendado: boolean,
}

local armazenamento: DataStore? = nil
local perfis: { [Player]: Perfil } = {}
local serializador: ((Player) -> { { Id: string, Slot: number } }?)? = nil
local salvamentosPendentes = 0
local fechando = false

-- ------------------------------------------------------------
-- Utilidades
-- ------------------------------------------------------------

local function obterArmazenamento(): DataStore?
	if armazenamento then
		return armazenamento
	end
	local ok, resultado = pcall(function()
		return DataStoreService:GetDataStore(Config.Dados.NomeDataStore)
	end)
	if ok then
		armazenamento = resultado
	else
		warn("[Dados] DataStore indisponível: " .. tostring(resultado))
	end
	return armazenamento
end

local function numeroValido(valor: any, minimo: number): boolean
	return type(valor) == "number" and valor == valor and valor >= minimo and valor < math.huge
end

local function listaDePerfis(): { Perfil }
	local lista = {}
	for _, perfil in perfis do
		table.insert(lista, perfil)
	end
	return lista
end

local function esperaRetry(tentativa: number): number
	if fechando then
		return 1
	end
	return math.min(2 ^ tentativa, 16)
end

-- Dados de um jogador novo
function Dados.modelo(): DadosJogador
	return {
		Versao = VERSAO_DADOS,
		Dinheiro = Config.Economia.DinheiroInicial,
		Coletor = 0,
		Rebirths = 0,
		Monstrinhos = {},
		ComprasProcessadas = {},
	}
end

-- Confere e corrige os dados vindos do DataStore (campos faltando ou inválidos)
function Dados.reconciliar(bruto: any): DadosJogador
	local dados = Dados.modelo()
	if type(bruto) ~= "table" then
		return dados
	end
	if numeroValido(bruto.Dinheiro, 0) then
		dados.Dinheiro = bruto.Dinheiro
	end
	if numeroValido(bruto.Coletor, 0) then
		dados.Coletor = bruto.Coletor
	end
	if numeroValido(bruto.Rebirths, 0) then
		dados.Rebirths = math.floor(bruto.Rebirths)
	end
	if type(bruto.Monstrinhos) == "table" then
		for _, item in bruto.Monstrinhos do
			if type(item) == "table" and type(item.Id) == "string" and numeroValido(item.Slot, 1) then
				table.insert(dados.Monstrinhos, { Id = item.Id, Slot = math.floor(item.Slot) })
			end
		end
	end
	if type(bruto.ComprasProcessadas) == "table" then
		for id, quando in bruto.ComprasProcessadas do
			if type(id) == "string" and type(quando) == "number" then
				dados.ComprasProcessadas[id] = quando
			end
		end
	end
	return dados
end

-- Foto dos dados no momento (é isso que vai para o DataStore)
local function criarSnapshot(perfil: Perfil): { [string]: any }
	local dados = perfil.Dados :: DadosJogador
	if serializador then
		local lista = serializador(perfil.Player)
		if lista then
			dados.Monstrinhos = lista
		end
	end
	local monstrinhos = {}
	for _, item in dados.Monstrinhos do
		table.insert(monstrinhos, { Id = item.Id, Slot = item.Slot })
	end
	return {
		Versao = VERSAO_DADOS,
		Dinheiro = if numeroValido(dados.Dinheiro, 0) then dados.Dinheiro else 0,
		Coletor = if numeroValido(dados.Coletor, 0) then dados.Coletor else 0,
		Rebirths = if numeroValido(dados.Rebirths, 0) then dados.Rebirths else 0,
		Monstrinhos = monstrinhos,
		ComprasProcessadas = table.clone(dados.ComprasProcessadas),
	}
end

-- Salva um perfil (com retry). liberar = true devolve a trava de sessão (jogador saindo).
local function salvarPerfil(perfil: Perfil, liberar: boolean, snapshot: { [string]: any }?): boolean
	if perfil.SemSalvar or perfil.SessaoPerdida or not perfil.Dados then
		return false
	end
	local loja = obterArmazenamento()
	if not loja then
		return false
	end

	-- Um salvamento por vez para cada jogador (garante a ordem das gravações)
	while perfil.Salvando do
		task.wait(0.1)
	end
	if perfil.Liberado or perfil.SessaoPerdida then
		return false
	end
	perfil.Salvando = true

	local copia = snapshot or criarSnapshot(perfil)
	local sucesso = false
	for tentativa = 1, Config.Dados.Tentativas do
		local perdeuSessao = false
		local ok, erro = pcall(function()
			loja:UpdateAsync(perfil.Chave, function(atual)
				perdeuSessao = false
				if type(atual) == "table" and type(atual.Sessao) == "table" and atual.Sessao.JobId ~= game.JobId then
					-- Outro servidor está com a trava: não sobrescreve os dados dele
					perdeuSessao = true
					return nil
				end
				local novo = table.clone(copia)
				if not liberar then
					novo.Sessao = { JobId = game.JobId, Hora = os.time() }
				end
				return novo
			end)
		end)
		if ok then
			if perdeuSessao then
				perfil.SessaoPerdida = true
				warn("[Dados] Outro servidor assumiu os dados de " .. perfil.Player.Name .. "; este servidor não vai mais salvá-los.")
			else
				sucesso = true
			end
			break
		end
		warn(("[Dados] Erro ao salvar %s (tentativa %d/%d): %s"):format(perfil.Player.Name, tentativa, Config.Dados.Tentativas, tostring(erro)))
		if tentativa < Config.Dados.Tentativas then
			task.wait(esperaRetry(tentativa))
		end
	end

	if sucesso and liberar then
		perfil.Liberado = true
	end
	perfil.Salvando = false
	return sucesso
end

-- ------------------------------------------------------------
-- API
-- ------------------------------------------------------------

-- Função que devolve a lista de monstrinhos da base do jogador (definida pelo módulo Bases).
-- Se devolver nil, os monstrinhos carregados continuam como estão.
function Dados.definirSerializador(funcao: (Player) -> { { Id: string, Slot: number } }?)
	serializador = funcao
end

-- Carrega os dados (pode demorar alguns segundos). Devolve false se falhar.
function Dados.carregar(player: Player): boolean
	local perfil: Perfil = {
		Player = player,
		Chave = "Jogador_" .. player.UserId,
		Dados = nil,
		Carregado = false,
		SemSalvar = false,
		Salvando = false,
		Saindo = false,
		Liberado = false,
		SessaoPerdida = false,
		SalvamentoAgendado = false,
	}
	perfis[player] = perfil

	local loja = obterArmazenamento()
	if not loja then
		if RunService:IsStudio() then
			perfil.SemSalvar = true
			perfil.Dados = Dados.modelo()
			warn("[Dados] Modo teste: DataStore indisponível no Studio. O progresso NÃO será salvo.")
		else
			perfis[player] = nil
			return false
		end
	end

	local tentativasErro, tentativasTrava = 0, 0
	while loja and not perfil.Dados do
		if player.Parent == nil then
			perfis[player] = nil
			return false
		end
		local bloqueado = false
		local ok, resultado = pcall(function()
			return loja:UpdateAsync(perfil.Chave, function(atual)
				bloqueado = false
				local dados = if type(atual) == "table" then atual else Dados.modelo() :: any
				local sessao = dados.Sessao
				if
					type(sessao) == "table"
					and sessao.JobId ~= game.JobId
					and type(sessao.Hora) == "number"
					and os.time() - sessao.Hora < Config.Dados.TempoTravaSessao
					and tentativasTrava < Config.Dados.TentativasTrava
				then
					-- Outro servidor ainda está usando estes dados: espera e tenta de novo
					bloqueado = true
					return nil
				end
				dados.Sessao = { JobId = game.JobId, Hora = os.time() }
				return dados
			end)
		end)

		if ok and bloqueado then
			tentativasTrava += 1
			task.wait(Config.Dados.EsperaTrava)
		elseif ok and type(resultado) == "table" then
			perfil.Dados = Dados.reconciliar(resultado)
		else
			tentativasErro += 1
			warn(("[Dados] Erro ao carregar %s (tentativa %d): %s"):format(player.Name, tentativasErro, tostring(resultado)))
			if RunService:IsStudio() then
				-- Normalmente: "Enable Studio Access to API Services" desligado
				perfil.SemSalvar = true
				perfil.Dados = Dados.modelo()
				warn("[Dados] Modo teste: ative 'Enable Studio Access to API Services' para salvar no Studio.")
			elseif tentativasErro >= Config.Dados.Tentativas then
				perfis[player] = nil
				return false
			else
				task.wait(esperaRetry(tentativasErro))
			end
		end
	end

	perfil.Carregado = true
	local estado = Jogadores.obter(player)
	if player.Parent == nil or not estado then
		-- Saiu enquanto carregava: devolve a trava sem perder nada
		if not perfil.SemSalvar then
			pcall(salvarPerfil, perfil, true)
		end
		perfis[player] = nil
		return false
	end

	estado.Dados = perfil.Dados
	estado.Carregado = true
	return true
end

-- Chamado quando o jogador sai: tira a "foto" dos dados agora (antes de a base
-- ser limpa) e salva em segundo plano, liberando a trava de sessão.
function Dados.aoSair(player: Player)
	local perfil = perfis[player]
	if not perfil or not perfil.Carregado or perfil.Saindo then
		return
	end
	perfil.Saindo = true
	if perfil.SemSalvar then
		perfis[player] = nil
		return
	end

	local snapshot = criarSnapshot(perfil)
	salvamentosPendentes += 1
	task.spawn(function()
		local ok, salvo = pcall(salvarPerfil, perfil, true, snapshot)
		if not ok or not salvo then
			warn("[Dados] Não foi possível salvar os dados de " .. player.Name .. " ao sair.")
		end
		salvamentosPendentes -= 1
		if perfis[player] == perfil then
			perfis[player] = nil
		end
	end)
end

-- Salva agora e espera terminar (usado depois de compras com Robux)
function Dados.salvarAgora(player: Player): boolean
	local perfil = perfis[player]
	if not perfil or not perfil.Carregado or perfil.Saindo then
		return false
	end
	local ok, salvo = pcall(salvarPerfil, perfil, false)
	return ok and salvo == true
end

-- Agenda um salvamento para daqui a alguns segundos (junta vários pedidos em um só)
function Dados.solicitarSalvamento(player: Player)
	local perfil = perfis[player]
	if not perfil or not perfil.Carregado or perfil.Saindo or perfil.SemSalvar or perfil.SalvamentoAgendado then
		return
	end
	perfil.SalvamentoAgendado = true
	task.delay(Config.Dados.AtrasoSalvamento, function()
		perfil.SalvamentoAgendado = false
		if perfis[player] == perfil and not perfil.Saindo then
			pcall(salvarPerfil, perfil, false)
		end
	end)
end

-- true se o progresso deste jogador é salvo (false no modo teste do Studio)
function Dados.salvaProgresso(player: Player): boolean
	local perfil = perfis[player]
	return perfil ~= nil and not perfil.SemSalvar
end

-- Recibos de Developer Products já entregues (idempotência do ProcessReceipt)
function Dados.compraJaProcessada(player: Player, purchaseId: string): boolean
	local estado = Jogadores.obterCarregado(player)
	return estado ~= nil and (estado.Dados :: DadosJogador).ComprasProcessadas[purchaseId] ~= nil
end

function Dados.registrarCompra(player: Player, purchaseId: string)
	local estado = Jogadores.obterCarregado(player)
	if not estado then
		return
	end
	local compras = (estado.Dados :: DadosJogador).ComprasProcessadas
	compras[purchaseId] = os.time()

	-- Guarda só os recibos mais recentes (o atual nunca é apagado)
	local outras = {}
	for id, quando in compras do
		if id ~= purchaseId then
			table.insert(outras, { Id = id, Quando = quando })
		end
	end
	local excesso = (#outras + 1) - Config.Dados.MaxComprasRegistradas
	if excesso > 0 then
		table.sort(outras, function(a, b)
			return a.Quando < b.Quando
		end)
		for i = 1, math.min(excesso, #outras) do
			compras[outras[i].Id] = nil
		end
	end
end

function Dados.iniciar()
	-- Salvamento automático
	task.spawn(function()
		while true do
			task.wait(Config.Dados.IntervaloAutoSave)
			for _, perfil in listaDePerfis() do
				if perfil.Carregado and not perfil.Saindo and not perfil.SemSalvar and not perfil.SessaoPerdida then
					task.spawn(function()
						pcall(salvarPerfil, perfil, false)
					end)
					task.wait(0.5) -- espalha as requisições
				end
			end
		end
	end)

	-- Servidor fechando: salva todo mundo e espera terminar (o Roblox dá até 30 s)
	game:BindToClose(function()
		fechando = true
		for _, perfil in listaDePerfis() do
			Dados.aoSair(perfil.Player)
		end
		local limite = os.clock() + 25
		while salvamentosPendentes > 0 and os.clock() < limite do
			task.wait(0.1)
		end
	end)
end

return Dados
