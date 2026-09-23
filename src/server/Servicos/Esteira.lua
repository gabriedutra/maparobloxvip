--[[
	Esteira.lua
	A esteira central:
	  • gera um monstrinho a cada Config.Esteira.IntervaloSpawn segundos,
	    sorteando a raridade pelas chances do Config (ou com o boost de sorte);
	  • move os monstrinhos do portal de entrada até a saída (onde somem);
	  • compra: confere saldo e espaço na base, desconta e leva para um slot;
	  • Lendários e Míticos disparam um aviso para o servidor inteiro.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalogo = require(Shared:WaitForChild("Catalogo"))
local Config = require(Shared:WaitForChild("Config"))
local Formatar = require(Shared:WaitForChild("Formatar"))
local Bases = require(script.Parent.Bases)
local Dados = require(script.Parent.Dados)
local Economia = require(script.Parent.Economia)
local Jogadores = require(script.Parent.Jogadores)
local Mapa = require(script.Parent.Mapa)
local Monstrinho = require(script.Parent.Monstrinho)
local Notificar = require(script.Parent.Notificar)

local Esteira = {}

type Item = {
	M: Monstrinho.Monstrinho,
	Distancia: number, -- studs percorridos desde o início
	Angulo: number, -- rotação (graus)
}

local itens: { Item } = {}
local itemPorMonstrinho: { [Monstrinho.Monstrinho]: Item } = {}
local pasta: Folder? = nil
local inicio = Vector3.zero
local direcao = Vector3.xAxis
local comprimento = 0
local sorteAte = 0
local aleatorio = Random.new()

local function cframeDoItem(item: Item): CFrame
	local posicao = inicio + direcao * item.Distancia + Vector3.new(0, item.M.AlturaBase, 0)
	return CFrame.new(posicao) * CFrame.Angles(0, math.rad(item.Angulo), 0)
end

local function textoDuracao(segundos: number): string
	if segundos % 60 == 0 then
		local minutos = segundos // 60
		return minutos .. (if minutos == 1 then " minuto" else " minutos")
	end
	return Formatar.tempo(segundos)
end

local function removerItem(item: Item)
	local indice = table.find(itens, item)
	if indice then
		table.remove(itens, indice)
	end
	itemPorMonstrinho[item.M] = nil
end

function Esteira.sorteAtiva(): boolean
	return workspace:GetServerTimeNow() < sorteAte
end

-- Cria um monstrinho no início da esteira. idForcado (opcional) escolhe qual.
function Esteira.gerar(idForcado: string?, silencioso: boolean?): Monstrinho.Monstrinho?
	if #itens >= Config.Esteira.MaximoNaEsteira then
		return nil
	end
	local info = if idForcado then Catalogo.obter(idForcado) else nil
	if not info then
		local multiplicadores = if Esteira.sorteAtiva() then Config.Sorte.Multiplicadores else nil
		info = Catalogo.sortear(function()
			return aleatorio:NextNumber()
		end, multiplicadores)
	end
	assert(info, "sem monstrinho para gerar")

	local m = Monstrinho.novo(info.Id)
	m:modoEsteira()
	local item: Item = { M = m, Distancia = 0, Angulo = aleatorio:NextNumber(0, 360) }
	m.Modelo.Parent = pasta
	m:posicionar(cframeDoItem(item))
	table.insert(itens, item)
	itemPorMonstrinho[m] = item

	if m.Raridade.Anunciar and not silencioso then
		Notificar.avisoGlobal(
			"✨ " .. m.Raridade.Nome .. " na esteira! ✨",
			m.Info.Nome .. " apareceu! Corra para comprar por " .. Formatar.dinheiro(m.Info.Preco) .. "!",
			m.Raridade.Cor
		)
	end
	return m
end

-- Move todos os monstrinhos (roda a cada frame)
local function atualizar(dt: number)
	for i = #itens, 1, -1 do
		local item = itens[i]
		local m = item.M
		if m.Destruido or m.Modo ~= "Esteira" then
			table.remove(itens, i)
			itemPorMonstrinho[m] = nil
		else
			item.Distancia += Config.Esteira.Velocidade * dt
			item.Angulo = (item.Angulo + Config.Esteira.GiroPorSegundo * dt) % 360
			if item.Distancia >= comprimento then
				-- Chegou na saída sem ninguém comprar
				table.remove(itens, i)
				itemPorMonstrinho[m] = nil
				m:destruir()
			else
				m:posicionar(cframeDoItem(item))
			end
		end
	end
end

-- Compra (chamada pelo módulo Interacoes depois de validar distância/tempo)
function Esteira.comprar(player: Player, m: Monstrinho.Monstrinho)
	local item = itemPorMonstrinho[m]
	if not item or m.Modo ~= "Esteira" or m.Destruido then
		Notificar.jogador(player, "Esse monstrinho não está mais à venda.", "erro")
		return
	end
	if not Jogadores.obterCarregado(player) then
		Notificar.jogador(player, "Seus dados ainda estão carregando...", "info")
		return
	end
	local base = Bases.obterBase(player)
	if not base then
		Notificar.jogador(player, "Você ainda não tem uma base!", "erro")
		return
	end
	local slot = Bases.slotLivre(base)
	if not slot then
		Notificar.jogador(player, "Sua base está cheia! Venda um monstrinho (tecla F) ou compre +4 Slots na loja.", "erro")
		return
	end
	local preco = m.Info.Preco
	if not Economia.gastar(player, preco) then
		local falta = preco - Economia.obterDinheiro(player)
		Notificar.jogador(player, "Dinheiro insuficiente! Faltam " .. Formatar.dinheiro(math.max(falta, 1)) .. ".", "erro")
		return
	end

	removerItem(item)
	Bases.colocarMonstrinho(base, slot, m)
	Notificar.jogador(player, "Você comprou " .. m.Info.Nome .. "! 🎉", "sucesso")
	if m.Raridade.Anunciar then
		Notificar.todos(player.DisplayName .. " comprou " .. m.Info.Nome .. " (" .. m.Raridade.Nome .. ")!", "info")
	end
	Dados.solicitarSalvamento(player)
end

-- Boost de sorte para o servidor inteiro (Developer Product)
function Esteira.ativarSorte(player: Player, duracao: number)
	local agora = workspace:GetServerTimeNow()
	sorteAte = math.max(sorteAte, agora) + duracao
	workspace:SetAttribute("SorteAte", sorteAte)
	Notificar.avisoGlobal(
		"🍀 SORTE ATIVADA! 🍀",
		player.DisplayName .. " ativou sorte na esteira por " .. textoDuracao(duracao) .. " para todo o servidor!",
		Color3.fromRGB(80, 220, 110)
	)
end

function Esteira.iniciar(mapa: Mapa.MapaInfo)
	local novaPasta = Instance.new("Folder")
	novaPasta.Name = "MonstrinhosEsteira"
	novaPasta.Parent = workspace
	pasta = novaPasta

	inicio = mapa.Inicio.Position
	local vetor = mapa.Fim.Position - inicio
	comprimento = vetor.Magnitude
	direcao = if comprimento > 0 then vetor.Unit else Vector3.xAxis
	workspace:SetAttribute("SorteAte", 0)

	-- Começa com a esteira já cheia (para não ficar vazia quando o servidor abre)
	local espacamento = Config.Esteira.Velocidade * Config.Esteira.IntervaloSpawn
	if espacamento > 0 then
		local quantidade = math.min(math.floor(comprimento / espacamento), Config.Esteira.MaximoNaEsteira)
		for k = quantidade - 1, 1, -1 do
			local m = Esteira.gerar(nil, true)
			local item = m and itemPorMonstrinho[m]
			if m and item then
				item.Distancia = k * espacamento
				m:posicionar(cframeDoItem(item))
			end
		end
	end

	RunService.Heartbeat:Connect(atualizar)

	task.spawn(function()
		while true do
			task.wait(Config.Esteira.IntervaloSpawn)
			local ok, erro = pcall(Esteira.gerar)
			if not ok then
				warn("[Esteira] Erro ao gerar monstrinho: " .. tostring(erro))
			end
		end
	end)
end

return Esteira
