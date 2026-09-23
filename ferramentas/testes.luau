--[[
	testes.luau — testes automáticos que rodam fora do Roblox (Lune).

	Uso (na pasta do projeto):
	    lune run ferramentas/testes

	Cobre: Config/Catálogo (validação e sorteio), Formatar, Regras,
	construção do mapa e dos monstrinhos, DataStore (trava de sessão,
	tentativas, saída, BindToClose) e ProcessReceipt idempotente.
	O DataStore, o MarketplaceService etc. são falsos (simulados).
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local task = require("@lune/task")
local Ambiente = require("./ambiente")
local roblox = Ambiente.roblox

-- ------------------------------------------------------------
-- Mini framework
-- ------------------------------------------------------------

local total, falhas = 0, {}

local function teste(nome: string, funcao: () -> ())
	total += 1
	local ok, erro = pcall(funcao)
	if ok then
		print("  ✔ " .. nome)
	else
		table.insert(falhas, nome)
		print("  ✘ " .. nome .. "\n      " .. tostring(erro))
	end
end

local function secao(nome: string)
	print("\n" .. nome)
end

local function afirmar(condicao: any, mensagem: string?)
	if not condicao then
		error(mensagem or "afirmação falhou", 2)
	end
end

local function igual(obtido: any, esperado: any, mensagem: string?)
	if obtido ~= esperado then
		error(("%s: esperado %s, obtido %s"):format(mensagem or "valor diferente", tostring(esperado), tostring(obtido)), 2)
	end
end

local function perto(obtido: number, esperado: number, tolerancia: number, mensagem: string?)
	if math.abs(obtido - esperado) > tolerancia then
		error(("%s: esperado %s (±%s), obtido %s"):format(mensagem or "valor fora da faixa", tostring(esperado), tostring(tolerancia), tostring(obtido)), 2)
	end
end

-- Espera uma condição ficar verdadeira (tempo real)
local function esperarAte(condicao: () -> boolean, limite: number?): boolean
	local fim = os.clock() + (limite or 5)
	while os.clock() < fim do
		if condicao() then
			return true
		end
		task.wait(0.01)
	end
	return condicao()
end

-- ------------------------------------------------------------
-- Serviços falsos
-- ------------------------------------------------------------

local function novoSinal()
	local sinal = { conexoes = {} :: { (...any) -> () } }
	function sinal:Connect(funcao)
		table.insert(self.conexoes, funcao)
		return {
			Disconnect = function() end,
		}
	end
	function sinal:Fire(...)
		for _, funcao in self.conexoes do
			funcao(...)
		end
	end
	return sinal
end

local function remoteFalso(nome: string)
	local remote = { Name = nome, enviados = {}, OnServerEvent = novoSinal(), OnClientEvent = novoSinal() }
	function remote:FireClient(player, ...)
		table.insert(self.enviados, { Para = player, Args = { ... } })
	end
	function remote:FireAllClients(...)
		table.insert(self.enviados, { Para = "todos", Args = { ... } })
	end
	return remote
end

local remotos = {
	PedirTrancar = remoteFalso("PedirTrancar"),
	PedirRenascer = remoteFalso("PedirRenascer"),
	Notificacao = remoteFalso("Notificacao"),
	AvisoGlobal = remoteFalso("AvisoGlobal"),
}
Ambiente.Falsos["ReplicatedStorage/Remotos"] = {
	WaitForChild = function(_, nome)
		return remotos[nome]
	end,
	FindFirstChild = function(_, nome)
		return remotos[nome]
	end,
}

local function copiaProfunda(valor: any): any
	if type(valor) ~= "table" then
		return valor
	end
	local copia = {}
	for chave, item in valor do
		copia[chave] = copiaProfunda(item)
	end
	return copia
end

-- DataStore falso com a mesma ideia do UpdateAsync do Roblox
local loja = {
	dados = {} :: { [string]: any },
	falhasRestantes = 0,
	chamadas = 0,
	aoAtualizar = nil :: (() -> ())?,
}
function loja:UpdateAsync(chave: string, transformar: (any, any) -> any)
	self.chamadas += 1
	task.wait(0.002)
	if self.aoAtualizar then
		self.aoAtualizar()
	end
	if self.falhasRestantes > 0 then
		self.falhasRestantes -= 1
		error("502: API Services rejected request (falha simulada)")
	end
	local novo = transformar(copiaProfunda(self.dados[chave]), nil)
	if novo == nil then
		return nil
	end
	self.dados[chave] = copiaProfunda(novo)
	return copiaProfunda(novo)
end

local modoStudio = false
local jogadoresPorId: { [number]: any } = {}

local PlayersFalso = {
	PlayerAdded = novoSinal(),
	PlayerRemoving = novoSinal(),
}
function PlayersFalso:GetPlayerByUserId(id: number)
	local p = jogadoresPorId[id]
	return if p and p.Parent then p else nil
end
function PlayersFalso:GetPlayers()
	local lista = {}
	for _, p in jogadoresPorId do
		if p.Parent then
			table.insert(lista, p)
		end
	end
	return lista
end

local atributosWorkspace = {}
local contadorGuid = 0
Ambiente.Servicos.Players = PlayersFalso
Ambiente.Servicos.RunService = {
	IsStudio = function()
		return modoStudio
	end,
	Heartbeat = novoSinal(),
}
Ambiente.Servicos.DataStoreService = {
	GetDataStore = function()
		return loja
	end,
}
Ambiente.Servicos.MarketplaceService = {
	PromptGamePassPurchaseFinished = novoSinal(),
	UserOwnsGamePassAsync = function()
		return false
	end,
}
Ambiente.Servicos.HttpService = {
	GenerateGUID = function()
		contadorGuid += 1
		return "guid-" .. contadorGuid
	end,
}
Ambiente.Servicos.Workspace = {
	GetServerTimeNow = function()
		return os.clock()
	end,
	SetAttribute = function(_, chave, valor)
		atributosWorkspace[chave] = valor
	end,
	GetAttribute = function(_, chave)
		return atributosWorkspace[chave]
	end,
}

-- "task" acelerada (50x) para os módulos do servidor: esperas de segundos viram milissegundos
Ambiente.Task = setmetatable({
	wait = function(segundos: number?)
		return task.wait((segundos or 0) / 50)
	end,
	delay = function(segundos: number, funcao, ...)
		return task.delay(segundos / 50, funcao, ...)
	end,
}, { __index = task })

local function novoJogador(id: number)
	local atributos = {}
	local jogador = {
		UserId = id,
		Name = "Jogador" .. id,
		DisplayName = "Jogador" .. id,
		Parent = PlayersFalso,
		Character = nil,
		Chutado = nil :: string?,
	}
	function jogador:SetAttribute(chave, valor)
		atributos[chave] = valor
	end
	function jogador:GetAttribute(chave)
		return atributos[chave]
	end
	function jogador:FindFirstChild()
		return nil
	end
	function jogador:Kick(mensagem)
		self.Chutado = mensagem
	end
	jogadoresPorId[id] = jogador
	return jogador
end

-- ------------------------------------------------------------
-- Módulos
-- ------------------------------------------------------------

local Config = Ambiente.carregar("ReplicatedStorage/Shared/Config")
local Catalogo = Ambiente.carregar("ReplicatedStorage/Shared/Catalogo")
local Formatar = Ambiente.carregar("ReplicatedStorage/Shared/Formatar")
local Regras = Ambiente.carregar("ReplicatedStorage/Shared/Regras")

-- ------------------------------------------------------------
secao("Config e Catálogo")
-- ------------------------------------------------------------

teste("todas as raridades têm pelo menos um monstrinho", function()
	for _, raridade in Catalogo.Raridades do
		afirmar(#Catalogo.PorRaridade[raridade.Id] > 0, "raridade sem monstrinhos: " .. raridade.Id)
	end
end)

teste("chances decrescentes (Comum > ... > Mítico)", function()
	for i = 2, #Catalogo.Raridades do
		afirmar(Catalogo.Raridades[i].Chance < Catalogo.Raridades[i - 1].Chance, "chance não decrescente em " .. Catalogo.Raridades[i].Id)
	end
end)

teste("preço e renda crescem com a raridade", function()
	local maiorPrecoAnterior, maiorRendaAnterior = 0, 0
	for _, raridade in Catalogo.Raridades do
		local menorPreco, menorRenda, maiorPreco, maiorRenda = math.huge, math.huge, 0, 0
		for _, m in Catalogo.PorRaridade[raridade.Id] do
			menorPreco = math.min(menorPreco, m.Preco)
			menorRenda = math.min(menorRenda, m.Renda)
			maiorPreco = math.max(maiorPreco, m.Preco)
			maiorRenda = math.max(maiorRenda, m.Renda)
		end
		afirmar(menorPreco > maiorPrecoAnterior, "preço de " .. raridade.Id .. " não é maior que o da raridade anterior")
		afirmar(menorRenda > maiorRendaAnterior, "renda de " .. raridade.Id .. " não é maior que a da raridade anterior")
		maiorPrecoAnterior, maiorRendaAnterior = maiorPreco, maiorRenda
	end
end)

teste("todos os IDs de monetização são números (0 = não configurado)", function()
	for _, tabela in { Config.GamePasses, Config.Produtos } do
		for chave, id in tabela do
			afirmar(type(id) == "number" and id >= 0 and id == math.floor(id), "ID inválido em " .. chave)
		end
	end
	for _, item in Config.Loja.GamePasses do
		afirmar(Config.GamePasses[item.Chave] ~= nil, "Loja.GamePasses tem chave desconhecida: " .. item.Chave)
	end
	for _, item in Config.Loja.Produtos do
		afirmar(Config.Produtos[item.Chave] ~= nil, "Loja.Produtos tem chave desconhecida: " .. item.Chave)
	end
end)

teste("sorteio segue as chances do Config", function()
	local aleatorio = Ambiente.Random.new(12345)
	local contagem = {}
	local N = 200000
	for _ = 1, N do
		local r = Catalogo.sortearRaridade(function()
			return aleatorio:NextNumber()
		end, nil)
		contagem[r.Id] = (contagem[r.Id] or 0) + 1
	end
	local esperadas = Catalogo.chances(nil)
	for id, esperado in esperadas do
		local obtido = (contagem[id] or 0) / N * 100
		perto(obtido, esperado, math.max(0.25, esperado * 0.12), "chance de " .. id)
	end
end)

teste("boost de sorte aumenta as chances raras", function()
	local normal = Catalogo.chances(nil)
	local comSorte = Catalogo.chances(Config.Sorte.Multiplicadores)
	afirmar(comSorte.Mitico > normal.Mitico * 3, "Mítico deveria ficar bem mais comum com sorte")
	afirmar(comSorte.Lendario > normal.Lendario * 2, "Lendário deveria ficar mais comum com sorte")
	afirmar(comSorte.Comum < normal.Comum, "Comum deveria ficar menos comum com sorte")
	local soma = 0
	for _, valor in comSorte do
		soma += valor
	end
	perto(soma, 100, 1e-6, "soma das chances")
end)

teste("sortear devolve monstrinhos da raridade sorteada", function()
	local aleatorio = Ambiente.Random.new(7)
	for _ = 1, 2000 do
		local m = Catalogo.sortear(function()
			return aleatorio:NextNumber()
		end, nil)
		afirmar(Catalogo.obter(m.Id) == m)
	end
end)

-- ------------------------------------------------------------
secao("Formatar")
-- ------------------------------------------------------------

teste("números abreviados (padrão brasileiro)", function()
	igual(Formatar.numero(0), "0")
	igual(Formatar.numero(999), "999")
	igual(Formatar.numero(999.9), "999")
	igual(Formatar.numero(1000), "1K")
	igual(Formatar.numero(1500), "1,5K")
	igual(Formatar.numero(12345), "12,3K")
	igual(Formatar.numero(999999), "999K")
	igual(Formatar.numero(1e6), "1M")
	igual(Formatar.numero(2.5e9), "2,5B")
	igual(Formatar.numero(1e15), "1Qa")
	igual(Formatar.numero(-1500), "-1,5K")
	igual(Formatar.numero(0 / 0), "0")
	igual(Formatar.dinheiro(25), "$25")
end)

teste("renda, multiplicador e tempo", function()
	igual(Formatar.renda(1.5), "$1,5/s")
	igual(Formatar.renda(2), "$2/s")
	igual(Formatar.renda(1234), "$1,23K/s")
	igual(Formatar.multiplicador(1), "x1")
	igual(Formatar.multiplicador(1.5), "x1,5")
	igual(Formatar.multiplicador(2.25), "x2,25")
	igual(Formatar.tempo(0), "0s")
	igual(Formatar.tempo(45), "45s")
	igual(Formatar.tempo(59.2), "1:00")
	igual(Formatar.tempo(65), "1:05")
	igual(Formatar.tempo(3661), "1:01:01")
end)

-- ------------------------------------------------------------
secao("Regras")
-- ------------------------------------------------------------

teste("custo e bônus de rebirth", function()
	igual(Regras.custoRebirth(0), Config.Rebirth.CustoBase)
	igual(Regras.custoRebirth(2), Config.Rebirth.CustoBase * Config.Rebirth.CrescimentoCusto ^ 2)
	igual(Regras.multiplicadorRebirth(0), 1)
	igual(Regras.multiplicadorRebirth(2), 1 + 2 * Config.Rebirth.BonusPorRebirth)
end)

teste("multiplicador com VIP e 2x Dinheiro", function()
	igual(Regras.multiplicadorTotal(0, false, false), 1)
	igual(Regras.multiplicadorTotal(0, true, false), Config.Bonus.VIPMultiplicador)
	igual(Regras.multiplicadorTotal(0, false, true), Config.Bonus.DinheiroDobradoMultiplicador)
	igual(
		Regras.multiplicadorTotal(2, true, true),
		(1 + 2 * Config.Rebirth.BonusPorRebirth) * Config.Bonus.VIPMultiplicador * Config.Bonus.DinheiroDobradoMultiplicador
	)
end)

teste("venda, slots, pacote de dinheiro e velocidade", function()
	igual(Regras.precoVenda({ Preco = 25 }), math.floor(25 * Config.Venda.Percentual))
	igual(Regras.slotsDisponiveis(false), Config.Base.SlotsIniciais)
	igual(Regras.slotsDisponiveis(true), Config.Base.SlotsIniciais + Config.Base.SlotsExtras)
	igual(Regras.valorPacoteDinheiro(0), Config.PacoteDinheiro.Minimo)
	igual(Regras.valorPacoteDinheiro(1000), 1000 * 60 * Config.PacoteDinheiro.MinutosDeRenda)
	afirmar(Regras.velocidadeCarregando(true) > Regras.velocidadeCarregando(false))
	afirmar(Regras.velocidadeCarregando(false) < Config.Roubo.VelocidadeNormal, "carregar deveria deixar mais lento")
end)

-- ------------------------------------------------------------
secao("Mapa")
-- ------------------------------------------------------------

local MapaConstrutor = Ambiente.carregar("ServerScriptService/Servidor/Servicos/MapaConstrutor")
local mapa = MapaConstrutor.construir()

teste("tem todas as peças que o servidor procura (Mapa.lua)", function()
	local esteira = mapa:FindFirstChild("Esteira")
	afirmar(esteira and esteira:FindFirstChild("Inicio") and esteira:FindFirstChild("Fim"), "Esteira/Inicio/Fim")
	local bases = mapa:FindFirstChild("Bases")
	afirmar(bases, "pasta Bases")
	local total = Config.Base.SlotsIniciais + Config.Base.SlotsExtras
	for i = 1, Config.Base.Quantidade do
		local base = bases:FindFirstChild("Base" .. i)
		afirmar(base, "Base" .. i)
		for _, nome in { "Chao", "Barreira", "Coletor", "BotaoTrancar", "Placa" } do
			afirmar(base:FindFirstChild(nome) and base:FindFirstChild(nome):IsA("BasePart"), nome .. " na Base" .. i)
		end
		local spawn = base:FindFirstChild("Spawn")
		afirmar(spawn and spawn:IsA("SpawnLocation") and spawn.Neutral, "Spawn neutro na Base" .. i)
		local slots = base:FindFirstChild("Slots")
		for s = 1, total do
			local slot = slots:FindFirstChild("Slot" .. s)
			afirmar(slot, "Slot" .. s .. " na Base" .. i)
			igual(slot:GetAttribute("Indice"), s, "atributo Indice")
			igual(slot:GetAttribute("Extra"), s > Config.Base.SlotsIniciais, "atributo Extra do Slot" .. s)
		end
	end
end)

teste("entradas das bases viradas para a esteira", function()
	for _, base in mapa.Bases:GetChildren() do
		local chao = base:FindFirstChild("Chao")
		local placa = base:FindFirstChild("Placa")
		afirmar(math.abs(placa.CFrame.Position.Z) < math.abs(chao.CFrame.Position.Z), base.Name .. ": a entrada não está do lado da esteira")
		-- A frente (LookVector) aponta para z = 0
		local frente = chao.CFrame.LookVector
		afirmar(frente.Z * -chao.CFrame.Position.Z > 0.99 * math.abs(chao.CFrame.Position.Z), base.Name .. ": LookVector não aponta para a esteira")
	end
end)

teste("slots dentro do chão e afastados entre si", function()
	for _, base in mapa.Bases:GetChildren() do
		local chao = base:FindFirstChild("Chao")
		local posicoes = {}
		for _, slot in base.Slots:GetChildren() do
			local relativo = chao.CFrame:PointToObjectSpace(slot.CFrame.Position)
			afirmar(math.abs(relativo.X) < chao.Size.X / 2 - 3 and math.abs(relativo.Z) < chao.Size.Z / 2 - 3, slot.Name .. " fora do chão")
			table.insert(posicoes, slot.CFrame.Position)
		end
		for i = 1, #posicoes do
			for j = i + 1, #posicoes do
				afirmar((posicoes[i] - posicoes[j]).Magnitude >= 5.5, base.Name .. ": slots muito próximos")
			end
		end
	end
end)

teste("slots longe o bastante das paredes (não dá para roubar de fora)", function()
	local distanciaPrompt = Config.Roubo.DistanciaPrompt
	for _, base in mapa.Bases:GetChildren() do
		local chao = base:FindFirstChild("Chao")
		for _, slot in base.Slots:GetChildren() do
			local relativo = chao.CFrame:PointToObjectSpace(slot.CFrame.Position)
			-- distância até o lado de fora das paredes laterais/fundo (+1 stud do personagem)
			local ateLateral = chao.Size.X / 2 - math.abs(relativo.X) + 1
			local ateFundo = chao.Size.Z / 2 - relativo.Z + 1
			afirmar(ateLateral > distanciaPrompt, slot.Name .. " perto demais da parede lateral")
			afirmar(ateFundo > distanciaPrompt, slot.Name .. " perto demais da parede do fundo")
		end
	end
end)

teste("esteira vai do portal de entrada até a saída", function()
	local inicio = mapa.Esteira.Inicio.CFrame.Position
	local fim = mapa.Esteira.Fim.CFrame.Position
	afirmar(fim.X - inicio.X > 100, "esteira curta demais")
end)

teste("assinatura estável e mapa gerado (mapa/Mapa.rbxmx) atualizado", function()
	igual(mapa:GetAttribute("AssinaturaLayout"), MapaConstrutor.assinatura())
	local salvo = roblox.deserializeModel(fs.readFile("mapa/Mapa.rbxmx"))[1]
	igual(
		salvo:GetAttribute("AssinaturaLayout"),
		MapaConstrutor.assinatura(),
		"mapa/Mapa.rbxmx desatualizado — rode: lune run ferramentas/gerar_mapa"
	)
end)

-- ------------------------------------------------------------
secao("Monstrinhos (modelos)")
-- ------------------------------------------------------------

local MonstrinhoModelo = Ambiente.carregar("ServerScriptService/Servidor/Servicos/MonstrinhoModelo")

-- menor e maior Y de uma peça (considerando a rotação)
local function extensaoY(parte): (number, number)
	if parte.Shape == roblox.Enum.PartType.Ball then
		local r = parte.Size.X / 2
		return parte.CFrame.Position.Y - r, parte.CFrame.Position.Y + r
	end
	local menor, maior = math.huge, -math.huge
	for _, dx in { -1, 1 } do
		for _, dy in { -1, 1 } do
			for _, dz in { -1, 1 } do
				local ponto = parte.CFrame:PointToWorldSpace(roblox.Vector3.new(dx * parte.Size.X / 2, dy * parte.Size.Y / 2, dz * parte.Size.Z / 2))
				menor = math.min(menor, ponto.Y)
				maior = math.max(maior, ponto.Y)
			end
		end
	end
	return menor, maior
end

teste("todos os monstrinhos são montados corretamente", function()
	for _, info in Catalogo.Lista do
		local modelo, raiz = MonstrinhoModelo.construir(info)
		igual(modelo.PrimaryPart, raiz, info.Id .. ": PrimaryPart")
		afirmar(raiz.Anchored and raiz.Transparency == 1, info.Id .. ": Raiz ancorada e invisível")
		igual(modelo:GetAttribute("MonstrinhoId"), info.Id)
		local alturaBase = modelo:GetAttribute("AlturaBase")
		local alturaTopo = modelo:GetAttribute("AlturaTopo")
		afirmar(type(alturaBase) == "number" and alturaBase > 0, info.Id .. ": AlturaBase")
		local menorY, maiorY = math.huge, -math.huge
		for _, parte in modelo:GetDescendants() do
			if parte:IsA("BasePart") and parte ~= raiz then
				afirmar(not parte.Anchored and not parte.CanCollide and parte.Massless, info.Id .. "/" .. parte.Name .. ": física")
				local solda = parte:FindFirstChild("Solda")
				afirmar(solda and solda:IsA("Weld") and solda.Part0 == raiz and solda.Part1 == parte, info.Id .. "/" .. parte.Name .. ": solda")
				if parte.Name ~= "Aura" then
					local a, b = extensaoY(parte)
					menorY = math.min(menorY, a)
					maiorY = math.max(maiorY, b)
				end
			end
		end
		-- os pés tocam o chão (y = -AlturaBase) e nada passa muito do topo
		perto(menorY, -alturaBase, 0.12 * Catalogo.raridadeDe(info).Tamanho, info.Id .. ": pés no chão")
		afirmar(maiorY <= alturaTopo + 0.1, info.Id .. ": AlturaTopo menor que a peça mais alta")
		local gui = raiz:FindFirstChild("Info")
		afirmar(gui and gui:IsA("BillboardGui"), info.Id .. ": BillboardGui")
		for _, nome in { "Nome", "Raridade", "Renda", "Preco" } do
			afirmar(gui:FindFirstChild(nome), info.Id .. ": rótulo " .. nome)
		end
		igual(gui.Nome.Text, info.Nome)
		igual(gui.Raridade.Text, Catalogo.raridadeDe(info).Nome)
	end
end)

-- ------------------------------------------------------------
secao("Dados (DataStore simulado)")
-- ------------------------------------------------------------

Config.Dados.MaxComprasRegistradas = 3

local Jogadores = Ambiente.carregar("ServerScriptService/Servidor/Servicos/Jogadores")
local Dados = Ambiente.carregar("ServerScriptService/Servidor/Servicos/Dados")
Dados.iniciar()

local function jogadorCarregado(id: number)
	local p = novoJogador(id)
	Jogadores.criar(p)
	assert(Dados.carregar(p), "carregar falhou para " .. id)
	return p, Jogadores.obterCarregado(p)
end

teste("jogador novo recebe os dados iniciais e a trava de sessão", function()
	local _, estado = jogadorCarregado(1)
	igual(estado.Dados.Dinheiro, Config.Economia.DinheiroInicial)
	igual(estado.Dados.Rebirths, 0)
	igual(loja.dados["Jogador_1"].Sessao.JobId, Ambiente.Jogo.JobId)
end)

teste("salvarAgora grava dinheiro e monstrinhos (serializador)", function()
	local p = jogadoresPorId[1]
	local estado = Jogadores.obterCarregado(p)
	estado.Dados.Dinheiro = 12345
	Dados.definirSerializador(function(player)
		if player == p then
			return { { Id = "bolotinha", Slot = 2 } }
		end
		return nil
	end)
	afirmar(Dados.salvarAgora(p))
	igual(loja.dados["Jogador_1"].Dinheiro, 12345)
	igual(#loja.dados["Jogador_1"].Monstrinhos, 1)
	igual(loja.dados["Jogador_1"].Monstrinhos[1].Slot, 2)
	igual(loja.dados["Jogador_1"].Sessao.JobId, Ambiente.Jogo.JobId, "trava continua deste servidor")
end)

teste("ao sair, salva e libera a trava de sessão", function()
	local p = jogadoresPorId[1]
	Jogadores.obterCarregado(p).Dados.Dinheiro = 777
	Dados.aoSair(p)
	p.Parent = nil
	afirmar(
		esperarAte(function()
			return loja.dados["Jogador_1"].Sessao == nil
		end),
		"trava não foi liberada"
	)
	igual(loja.dados["Jogador_1"].Dinheiro, 777)
end)

teste("espera a trava de outro servidor e assume depois das tentativas", function()
	loja.dados["Jogador_2"] = { Dinheiro = 500, Sessao = { JobId = "outro-servidor", Hora = os.time() } }
	local antes = loja.chamadas
	local _, estado = jogadorCarregado(2)
	igual(estado.Dados.Dinheiro, 500)
	igual(loja.chamadas - antes, Config.Dados.TentativasTrava + 1, "número de tentativas")
	igual(loja.dados["Jogador_2"].Sessao.JobId, Ambiente.Jogo.JobId)
end)

teste("trava abandonada (antiga) é assumida na hora", function()
	loja.dados["Jogador_3"] = { Dinheiro = 42, Sessao = { JobId = "outro-servidor", Hora = os.time() - 100000 } }
	local antes = loja.chamadas
	local _, estado = jogadorCarregado(3)
	igual(estado.Dados.Dinheiro, 42)
	igual(loja.chamadas - antes, 1)
end)

teste("carrega assim que o outro servidor libera a trava", function()
	loja.dados["Jogador_4"] = { Dinheiro = 7, Sessao = { JobId = "outro-servidor", Hora = os.time() } }
	task.delay(0.03, function()
		loja.dados["Jogador_4"] = { Dinheiro = 8 } -- o outro servidor salvou e liberou
	end)
	local antes = loja.chamadas
	local _, estado = jogadorCarregado(4)
	igual(estado.Dados.Dinheiro, 8)
	afirmar(loja.chamadas - antes <= Config.Dados.TentativasTrava, "deveria carregar antes de forçar")
end)

teste("se outro servidor assumir os dados, este não sobrescreve", function()
	local p, estado = jogadorCarregado(5)
	loja.dados["Jogador_5"].Sessao = { JobId = "outro-servidor", Hora = os.time() }
	loja.dados["Jogador_5"].Dinheiro = 999
	estado.Dados.Dinheiro = 1
	afirmar(not Dados.salvarAgora(p), "não deveria salvar")
	igual(loja.dados["Jogador_5"].Dinheiro, 999)
end)

teste("erros temporários do DataStore: tenta de novo", function()
	loja.falhasRestantes = 2
	local _, estado = jogadorCarregado(6)
	afirmar(estado ~= nil)
	igual(loja.falhasRestantes, 0)
end)

teste("DataStore fora do ar (servidor real): carregar falha", function()
	loja.falhasRestantes = 1000
	local p = novoJogador(7)
	Jogadores.criar(p)
	afirmar(not Dados.carregar(p), "deveria falhar")
	loja.falhasRestantes = 0
end)

teste("Studio sem acesso à API: modo teste sem salvar", function()
	modoStudio = true
	loja.falhasRestantes = 1
	local p = novoJogador(8)
	Jogadores.criar(p)
	afirmar(Dados.carregar(p))
	afirmar(not Dados.salvaProgresso(p))
	modoStudio = false
	loja.falhasRestantes = 0
end)

teste("saiu enquanto carregava: a trava é devolvida", function()
	local p = novoJogador(9)
	Jogadores.criar(p)
	loja.aoAtualizar = function()
		p.Parent = nil -- sai no meio da requisição
		loja.aoAtualizar = nil
	end
	afirmar(not Dados.carregar(p))
	afirmar(
		esperarAte(function()
			local salvo = loja.dados["Jogador_9"]
			return salvo ~= nil and salvo.Sessao == nil
		end),
		"trava ficou presa"
	)
end)

teste("dados corrompidos são corrigidos (reconciliar)", function()
	local dados = Dados.reconciliar({
		Dinheiro = 0 / 0,
		Coletor = -5,
		Rebirths = 2.7,
		Monstrinhos = { { Id = "bolotinha", Slot = 1 }, "lixo", { Id = 3, Slot = 1 }, { Id = "pingo", Slot = 0 } },
		ComprasProcessadas = { abc = 1, [5] = 2 },
	})
	igual(dados.Dinheiro, Config.Economia.DinheiroInicial)
	igual(dados.Coletor, 0)
	igual(dados.Rebirths, 2)
	igual(#dados.Monstrinhos, 1)
	igual(dados.ComprasProcessadas.abc, 1)
	igual(dados.ComprasProcessadas[5 :: any], nil)
end)

teste("recibos registrados têm limite", function()
	local p = jogadorCarregado(10)
	for i = 1, 6 do
		Dados.registrarCompra(p, "recibo-" .. i)
	end
	local total = 0
	for _ in Jogadores.obterCarregado(p).Dados.ComprasProcessadas do
		total += 1
	end
	igual(total, Config.Dados.MaxComprasRegistradas)
	afirmar(Dados.compraJaProcessada(p, "recibo-6"), "o recibo mais novo precisa ficar")
end)

teste("BindToClose salva todos e libera as travas", function()
	local p11, e11 = jogadorCarregado(11)
	local p12, e12 = jogadorCarregado(12)
	e11.Dados.Dinheiro = 111
	e12.Dados.Dinheiro = 222
	local aoFechar = Ambiente.aoFechar
	afirmar(aoFechar, "BindToClose não registrado")
	aoFechar()
	igual(loja.dados["Jogador_11"].Dinheiro, 111)
	igual(loja.dados["Jogador_12"].Dinheiro, 222)
	afirmar(loja.dados["Jogador_11"].Sessao == nil and loja.dados["Jogador_12"].Sessao == nil, "travas não liberadas")
	p11.Parent = nil
	p12.Parent = nil
end)

-- ------------------------------------------------------------
secao("ProcessReceipt (Developer Products)")
-- ------------------------------------------------------------

Config.Produtos.PacoteDinheiro = 111
Config.Produtos.TrancarAgora = 222
Config.Produtos.SorteBoost = 333
local Economia = Ambiente.carregar("ServerScriptService/Servidor/Servicos/Economia")
local Produtos = Ambiente.carregar("ServerScriptService/Servidor/Servicos/Produtos")
Produtos.iniciar()
local Decisao = roblox.Enum.ProductPurchaseDecision

teste("ProcessReceipt foi registrado", function()
	afirmar(Ambiente.Servicos.MarketplaceService.ProcessReceipt == Produtos._processarRecibo)
end)

teste("entrega uma vez só (idempotente)", function()
	local p = jogadorCarregado(20)
	local recibo = { PlayerId = 20, ProductId = 111, PurchaseId = "compra-1", CurrencySpent = 10 }
	local antes = Economia.obterDinheiro(p)
	igual(Produtos._processarRecibo(recibo), Decisao.PurchaseGranted)
	local depois = Economia.obterDinheiro(p)
	igual(depois - antes, Regras.valorPacoteDinheiro(0), "valor do pacote")
	igual(Produtos._processarRecibo(recibo), Decisao.PurchaseGranted)
	igual(Economia.obterDinheiro(p), depois, "entregou duas vezes!")
	afirmar(loja.dados["Jogador_20"].ComprasProcessadas["compra-1"] ~= nil, "recibo não foi salvo no DataStore")
end)

teste("falha ao salvar: NotProcessedYet, sem entregar em dobro depois", function()
	local p = jogadoresPorId[20]
	local recibo = { PlayerId = 20, ProductId = 111, PurchaseId = "compra-2", CurrencySpent = 10 }
	loja.falhasRestantes = 1000
	igual(Produtos._processarRecibo(recibo), Decisao.NotProcessedYet)
	local depois = Economia.obterDinheiro(p)
	loja.falhasRestantes = 0
	igual(Produtos._processarRecibo(recibo), Decisao.PurchaseGranted)
	igual(Economia.obterDinheiro(p), depois, "entregou duas vezes!")
end)

teste("jogador fora do servidor ou produto desconhecido: NotProcessedYet", function()
	igual(Produtos._processarRecibo({ PlayerId = 99999, ProductId = 111, PurchaseId = "x1" }), Decisao.NotProcessedYet)
	igual(Produtos._processarRecibo({ PlayerId = 20, ProductId = 424242, PurchaseId = "x2" }), Decisao.NotProcessedYet)
end)

teste("Trancar Agora sem base: não entrega e não registra", function()
	local p = jogadoresPorId[20]
	igual(Produtos._processarRecibo({ PlayerId = 20, ProductId = 222, PurchaseId = "tranca-1" }), Decisao.NotProcessedYet)
	afirmar(not Dados.compraJaProcessada(p, "tranca-1"), "não deveria registrar")
end)

teste("Sorte na esteira: ativa para o servidor e avisa todo mundo", function()
	local avisosAntes = #remotos.AvisoGlobal.enviados
	igual(Produtos._processarRecibo({ PlayerId = 20, ProductId = 333, PurchaseId = "sorte-1" }), Decisao.PurchaseGranted)
	afirmar((atributosWorkspace.SorteAte or 0) > os.clock(), "SorteAte não foi definido")
	afirmar(#remotos.AvisoGlobal.enviados > avisosAntes, "aviso global não enviado")
end)

-- ------------------------------------------------------------

print(("\n%d testes, %d falha(s)"):format(total, #falhas))
process.exit(if #falhas == 0 then 0 else 1)
