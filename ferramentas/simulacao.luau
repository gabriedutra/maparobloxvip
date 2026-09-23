--[[
	simulacao.luau — roda o SERVIDOR inteiro (Main.server.lua) num "mini Roblox"
	falso e joga partidas de verdade: entrar, comprar na esteira, coletar,
	trancar, roubar (com e sem sucesso), vender, Game Pass, Developer Product,
	rebirth, sair no meio do roubo, voltar ao jogo, fila de bases e BindToClose.

	Uso (na pasta do projeto):
	    lune run ferramentas/simulacao

	O tempo do jogo corre 50x mais rápido que o real.
]]

local process = require("@lune/process")
local task = require("@lune/task")
local Ambiente = require("./ambiente")
local Falso = require("./roblox_falso")
local roblox = Ambiente.roblox
local CFrame = roblox.CFrame
local Vector3 = roblox.Vector3

local VELOCIDADE = 50
Falso.Velocidade = VELOCIDADE

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

-- Espera em segundos do JOGO (simulados)
local function esperar(segundos: number)
	task.wait(segundos / VELOCIDADE)
end

local function esperarAte(condicao: () -> boolean, limiteSimulado: number?): boolean
	local fim = Falso.agora() + (limiteSimulado or 10)
	while Falso.agora() < fim do
		if condicao() then
			return true
		end
		task.wait(0.001)
	end
	return condicao()
end

-- ------------------------------------------------------------
-- Ambiente: tempo acelerado e serviços falsos
-- ------------------------------------------------------------

Ambiente.Task = setmetatable({
	wait = function(segundos: number?)
		return task.wait((segundos or 0) / VELOCIDADE)
	end,
	delay = function(segundos: number, funcao, ...)
		return task.delay((segundos or 0) / VELOCIDADE, funcao, ...)
	end,
}, { __index = task })
Ambiente.Os = setmetatable({ clock = Falso.agora }, { __index = os })
Ambiente.Instance = Falso.Instance

local Workspace = Falso.novo("Workspace")
Workspace.Name = "Workspace"
local Players = Falso.novo("Players")
Players.Name = "Players"

local pastaRemotos = Falso.novo("Folder")
pastaRemotos.Name = "Remotos"
for _, nome in { "PedirTrancar", "PedirRenascer", "Notificacao", "AvisoGlobal" } do
	local remote = Falso.novo("RemoteEvent")
	remote.Name = nome
	remote.Parent = pastaRemotos
end
Ambiente.Falsos["ReplicatedStorage/Remotos"] = pastaRemotos

local gruposColisao = { Default = true }
local naoColidem = {}
local Heartbeat = Falso.novoSinal()

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

local loja = { dados = {} :: { [string]: any } }
function loja:UpdateAsync(chave: string, transformar)
	task.wait(0.001)
	local novo = transformar(copiaProfunda(self.dados[chave]), nil)
	if novo == nil then
		return nil
	end
	self.dados[chave] = copiaProfunda(novo)
	return copiaProfunda(novo)
end

local Marketplace = {
	PromptGamePassPurchaseFinished = Falso.novoSinal(),
	UserOwnsGamePassAsync = function()
		return false
	end,
	ProcessReceipt = nil :: any,
}

local contadorGuid = 0
Ambiente.Servicos.Workspace = Workspace
Ambiente.Servicos.Players = Players
Ambiente.Servicos.PhysicsService = {
	IsCollisionGroupRegistered = function(_, nome)
		return gruposColisao[nome] == true
	end,
	RegisterCollisionGroup = function(_, nome)
		gruposColisao[nome] = true
	end,
	CollisionGroupSetCollidable = function(_, a, b, colide)
		naoColidem[a .. "|" .. b] = not colide
	end,
}
Ambiente.Servicos.RunService = {
	IsStudio = function()
		return false
	end,
	Heartbeat = Heartbeat,
}
Ambiente.Servicos.DataStoreService = {
	GetDataStore = function()
		return loja
	end,
}
Ambiente.Servicos.MarketplaceService = Marketplace
Ambiente.Servicos.HttpService = {
	GenerateGUID = function()
		contadorGuid += 1
		return "guid-" .. contadorGuid
	end,
}

-- Limite geral: se algo travar, encerra com erro em vez de ficar rodando para sempre
task.delay(300, function()
	print("\n✘ A simulação passou de 300 s reais e foi interrompida (travou?)")
	process.exit(2)
end)

-- Heartbeat a cada ~2 ms reais
local rodando = true
task.spawn(function()
	local ultimo = Falso.agora()
	while rodando do
		task.wait(0.002)
		local agora = Falso.agora()
		Heartbeat:Fire(agora - ultimo)
		ultimo = agora
	end
end)

-- ------------------------------------------------------------
-- Sobe o servidor
-- ------------------------------------------------------------

local Config = Ambiente.carregar("ReplicatedStorage/Shared/Config")
Config.GamePasses.VIP = 555
Config.GamePasses.SlotsExtras = 556
Config.GamePasses.CarregarRapido = 557
Config.Produtos.TrancarAgora = 222

local okServidor, erroServidor = pcall(Ambiente.carregar, "ServerScriptService/Servidor/Main")
if not okServidor then
	print("\n✘ O servidor não conseguiu iniciar:\n" .. tostring(erroServidor))
	process.exit(1)
end
local Economia = Ambiente.carregar("ServerScriptService/Servidor/Servicos/Economia")
local Catalogo = Ambiente.carregar("ReplicatedStorage/Shared/Catalogo")
local Regras = Ambiente.carregar("ReplicatedStorage/Shared/Regras")

local Mapa = Workspace:FindFirstChild("Mapa")
local Bases = Mapa and Mapa:FindFirstChild("Bases")
local Esteira = Workspace:FindFirstChild("MonstrinhosEsteira")

-- ------------------------------------------------------------
-- Ajudantes de jogador
-- ------------------------------------------------------------

local proximoId = 100

local function criarPersonagem(player, posicao: Vector3)
	local personagem = Falso.novo("Model")
	personagem.Name = player.Name
	local raiz = Falso.novo("Part")
	raiz.Name = "HumanoidRootPart"
	raiz.Size = Vector3.new(2, 2, 1)
	raiz.CFrame = CFrame.new(posicao)
	raiz.Parent = personagem
	local cabeca = Falso.novo("Part")
	cabeca.Name = "Head"
	cabeca.CFrame = CFrame.new(posicao + Vector3.new(0, 1.5, 0))
	cabeca.Parent = personagem
	local humanoide = Falso.novo("Humanoid")
	humanoide.Parent = personagem
	personagem.PrimaryPart = raiz
	personagem.Parent = Workspace
	player.Character = personagem
	player.CharacterAdded:Fire(personagem)
	return personagem
end

local function entrar(nome: string, userId: number?)
	if not userId then
		proximoId += 1
	end
	local player = Falso.novo("Player")
	player.Name = nome
	player.DisplayName = nome
	player.UserId = userId or proximoId
	player.Parent = Players
	Players.PlayerAdded:Fire(player)
	return player
end

local function sair(player)
	Players.PlayerRemoving:Fire(player)
	task.wait(0.001)
	if player.Character then
		player.Character:Destroy()
	end
	player.Parent = nil
end

local function raizDe(player)
	return player.Character and player.Character:FindFirstChild("HumanoidRootPart")
end

local function teleportar(player, posicao: Vector3)
	player.Character:PivotTo(CFrame.new(posicao))
end

-- Anda até o destino em passos pequenos (respeita o anti-teleporte)
local function andar(player, destino: Vector3)
	local raiz = raizDe(player)
	local inicio = raiz.Position
	local distancia = (destino - inicio).Magnitude
	local passos = math.max(1, math.ceil(distancia / 2))
	for i = 1, passos do
		player.Character:PivotTo(CFrame.new(inicio:Lerp(destino, i / passos)))
		esperar(0.06)
	end
end

local function notificacoes(player): { string }
	local lista = {}
	for _, envio in Falso.enviados(pastaRemotos.Notificacao) do
		if envio.Para == player then
			table.insert(lista, envio.Args[1])
		end
	end
	return lista
end

local function recebeuMensagem(player, trecho: string): boolean
	for _, texto in notificacoes(player) do
		if string.find(texto, trecho, 1, true) then
			return true
		end
	end
	return false
end

local function baseDe(player)
	local indice = player:GetAttribute("BaseIndice")
	return indice and indice > 0 and Bases:FindFirstChild("Base" .. indice)
end

local function monstrinhosDaBase(base): { any }
	return base:FindFirstChild("Monstrinhos"):GetChildren()
end

local function pontoDentro(base, x: number, z: number): Vector3
	return (base.Chao.CFrame * CFrame.new(x, 3.5, z)).Position
end

-- Ponto a 3 studs do monstrinho, na direção do centro da base (na altura do personagem)
local function pertoDoMonstrinho(base, modelo): Vector3
	local pos = modelo.Raiz.Position
	local centro = base.Chao.Position
	local direcao = Vector3.new(centro.X - pos.X, 0, centro.Z - pos.Z).Unit
	return Vector3.new(pos.X, 3.5, pos.Z) + direcao * 3
end

local function pontoFora(base, distancia: number): Vector3
	return (base.Chao.CFrame * CFrame.new(0, 3.5, -(base.Chao.Size.Z / 2 + distancia))).Position
end

-- Compra um monstrinho da esteira para o jogador (dá o dinheiro antes)
local function comprarDaEsteira(player)
	local modelo = Esteira:GetChildren()[1]
	assert(modelo, "esteira vazia")
	local raiz = modelo:FindFirstChild("Raiz")
	local info = Catalogo.obter(modelo:GetAttribute("MonstrinhoId"))
	Economia.adicionar(player, info.Preco)
	teleportar(player, raiz.Position + Vector3.new(0, 0, 7))
	raiz.PromptComprar.Triggered:Fire(player)
	esperar(0.2)
	return modelo, info
end

-- Segura o prompt pelo tempo certo e aciona
local function segurarPrompt(prompt, player)
	prompt.PromptButtonHoldBegan:Fire(player)
	esperar(prompt.HoldDuration + 0.1)
	prompt.Triggered:Fire(player)
	esperar(0.2)
end

-- ------------------------------------------------------------
-- Cenários
-- ------------------------------------------------------------

print("\nServidor")

teste("servidor sobe: mapa, bases e esteira com monstrinhos", function()
	afirmar(Mapa, "Workspace.Mapa não foi criado")
	afirmar(Bases and #Bases:GetChildren() == Config.Base.Quantidade, "bases")
	afirmar(Esteira and #Esteira:GetChildren() >= 5, "esteira deveria começar cheia")
	for _, modelo in Esteira:GetChildren() do
		afirmar(modelo.Raiz:FindFirstChild("PromptComprar"), "monstrinho da esteira sem prompt Comprar")
	end
	afirmar(Marketplace.ProcessReceipt ~= nil, "ProcessReceipt não definido")
	afirmar(gruposColisao.BarreiraBase1 and gruposColisao.DonoBase1, "grupos de colisão")
	afirmar(naoColidem["BarreiraBase1|DonoBase1"], "dono deveria atravessar a própria barreira")
end)

teste("esteira anda, some no fim e continua gerando", function()
	local modelo = Esteira:GetChildren()[1]
	local x0 = modelo.Raiz.Position.X
	esperar(1)
	afirmar(modelo.Raiz.Position.X > x0 + 3, "monstrinho não andou na esteira")
	esperar(40)
	afirmar(modelo.Parent == nil, "monstrinho deveria sumir no fim da esteira")
	local quantidade = #Esteira:GetChildren()
	afirmar(quantidade >= 5 and quantidade <= Config.Esteira.MaximoNaEsteira, "quantidade na esteira: " .. quantidade)
end)

print("\nEntrada")

local Ana = entrar("Ana")
local Beto = entrar("Beto")

teste("jogadores recebem base, dados e leaderstats", function()
	afirmar(esperarAte(function()
		return Ana:GetAttribute("Carregado") == true and Beto:GetAttribute("Carregado") == true
	end), "dados não carregaram")
	igual(Ana:GetAttribute("BaseIndice"), 1)
	igual(Beto:GetAttribute("BaseIndice"), 2)
	igual(Ana.RespawnLocation, Bases.Base1.Spawn)
	igual(Ana:GetAttribute("Dinheiro"), Config.Economia.DinheiroInicial)
	igual(Ana.leaderstats.Dinheiro.Value, Config.Economia.DinheiroInicial)
	igual(Ana.leaderstats.Rebirths.Value, 0)
	igual(Bases.Base1.Placa.PlacaGuiFront.Titulo.Text, "Base de Ana")
	igual(Bases.Base3.Placa.PlacaGuiFront.Titulo.Text, "Base livre")
	afirmar(recebeuMensagem(Ana, "Bem-vindo"), "mensagem de boas-vindas")
end)

teste("personagem nasce na base e atravessa a própria barreira", function()
	criarPersonagem(Ana, Vector3.new(0, 3, 0)) -- nasce longe, deve ir para a base
	criarPersonagem(Beto, Vector3.new(0, 3, 0))
	esperar(0.6)
	afirmar((raizDe(Ana).Position - Bases.Base1.Spawn.Position).Magnitude < 10, "não foi levada para a base")
	igual(raizDe(Ana).CollisionGroup, "DonoBase1")
	igual(raizDe(Beto).CollisionGroup, "DonoBase2")
end)

print("\nEsteira e economia")

local compraAna, infoAna
teste("comprar na esteira: desconta, vai para o slot e gera renda", function()
	local dinheiroAntes = Economia.obterDinheiro(Ana)
	compraAna, infoAna = comprarDaEsteira(Ana)
	igual(compraAna.Parent, Bases.Base1.Monstrinhos, "monstrinho não foi para a base")
	igual(compraAna:GetAttribute("DonoUserId"), Ana.UserId)
	igual(Economia.obterDinheiro(Ana), dinheiroAntes, "preço cobrado errado")
	afirmar(compraAna.Raiz:FindFirstChild("PromptRoubar") and compraAna.Raiz:FindFirstChild("PromptVender"), "prompts de base")
	afirmar(not compraAna.Raiz:FindFirstChild("PromptComprar"), "prompt Comprar deveria sumir")
	igual(compraAna.Raiz.Info.Preco.Visible, false, "preço deveria sumir na base")
	igual(Ana:GetAttribute("RendaPorSegundo"), infoAna.Renda)
	local topoSlot = Bases.Base1.Slots.Slot1.Position.Y + 0.3
	afirmar(math.abs(compraAna.Raiz.Position.Y - (topoSlot + compraAna:GetAttribute("AlturaBase"))) < 0.01, "altura no slot")
	afirmar((Vector3.new(compraAna.Raiz.Position.X, 0, compraAna.Raiz.Position.Z) - Vector3.new(Bases.Base1.Slots.Slot1.Position.X, 0, Bases.Base1.Slots.Slot1.Position.Z)).Magnitude < 0.01, "posição no slot 1")
end)

teste("sem dinheiro não compra", function()
	local modelo = Esteira:GetChildren()[1]
	local info = Catalogo.obter(modelo:GetAttribute("MonstrinhoId"))
	local dinheiro = Economia.obterDinheiro(Beto)
	Economia.gastar(Beto, dinheiro) -- zera
	teleportar(Beto, modelo.Raiz.Position + Vector3.new(0, 0, 7))
	modelo.Raiz.PromptComprar.Triggered:Fire(Beto)
	esperar(0.3)
	afirmar(modelo.Parent == Esteira, "comprou sem dinheiro")
	afirmar(recebeuMensagem(Beto, "Dinheiro insuficiente"), "mensagem de saldo")
	Economia.adicionar(Beto, dinheiro)
	afirmar(info ~= nil)
end)

teste("longe demais não compra (anti-exploit)", function()
	local modelo = Esteira:GetChildren()[1]
	local info = Catalogo.obter(modelo:GetAttribute("MonstrinhoId"))
	Economia.adicionar(Beto, info.Preco)
	teleportar(Beto, modelo.Raiz.Position + Vector3.new(0, 0, 40))
	modelo.Raiz.PromptComprar.Triggered:Fire(Beto)
	esperar(0.3)
	afirmar(modelo.Parent == Esteira, "comprou de longe")
end)

teste("renda cai no coletor e o dono coleta pisando", function()
	esperar(3)
	local coletor = Economia.obterColetor(Ana)
	afirmar(coletor >= infoAna.Renda * 2, "coletor deveria ter ~3s de renda, tem " .. coletor)
	local antes = Economia.obterDinheiro(Ana)
	Bases.Base1.Coletor.Touched:Fire(raizDe(Ana))
	esperar(0.1)
	afirmar(Economia.obterDinheiro(Ana) >= antes + coletor, "não coletou")
	afirmar(Economia.obterColetor(Ana) < infoAna.Renda, "coletor não zerou")
	afirmar(recebeuMensagem(Ana, "+$"), "aviso de +$")
end)

teste("outro jogador pisando no coletor não coleta", function()
	esperar(2)
	local antes = Economia.obterColetor(Ana)
	Bases.Base1.Coletor.Touched:Fire(raizDe(Beto))
	esperar(0.1)
	afirmar(Economia.obterColetor(Ana) >= antes, "Beto coletou o dinheiro da Ana")
end)

print("\nRoubo")

local segundaAna
teste("roubo com sucesso: leva até a própria base", function()
	segundaAna = comprarDaEsteira(Ana)
	teleportar(Ana, Vector3.new(90, 3, 20)) -- dona longe
	local base1 = Bases.Base1
	teleportar(Beto, pontoDentro(base1, 0, -8))
	andar(Beto, pertoDoMonstrinho(base1, compraAna))
	local rendaAntes = Ana:GetAttribute("RendaPorSegundo")
	segurarPrompt(compraAna.Raiz.PromptRoubar, Beto)
	igual(Beto:GetAttribute("Carregando"), infoAna.Nome, "não começou o roubo")
	igual(compraAna:GetAttribute("SendoRoubado"), true)
	igual(Beto.Character.Humanoid.WalkSpeed, Config.Roubo.VelocidadeCarregando)
	afirmar(Ana:GetAttribute("RendaPorSegundo") < rendaAntes, "renda da vítima deveria cair")
	afirmar(recebeuMensagem(Ana, "está roubando"), "vítima não foi avisada")
	-- sai da base 1 e vai para a base 2
	andar(Beto, pontoDentro(base1, 0, -20))
	andar(Beto, pontoFora(base1, 4))
	andar(Beto, pontoFora(Bases.Base2, 4))
	andar(Beto, pontoDentro(Bases.Base2, 0, -10))
	afirmar(esperarAte(function()
		return compraAna.Parent == Bases.Base2.Monstrinhos
	end, 2), "monstrinho não foi entregue na base do ladrão")
	igual(compraAna:GetAttribute("DonoUserId"), Beto.UserId)
	igual(Beto:GetAttribute("Carregando"), "")
	igual(Beto.Character.Humanoid.WalkSpeed, Config.Roubo.VelocidadeNormal)
	igual(compraAna.Raiz.Anchored, true)
	afirmar(recebeuMensagem(Beto, "Você roubou"), "ladrão não foi avisado")
	afirmar(recebeuMensagem(Ana, "roubou seu"), "vítima não foi avisada do roubo")
	igual(Beto:GetAttribute("RendaPorSegundo"), infoAna.Renda)
end)

teste("roubo falha quando a dona encosta no ladrão", function()
	local base1 = Bases.Base1
	local alvo = segundaAna
	local pos = alvo.Raiz.Position
	teleportar(Ana, pontoDentro(base1, 0, 20)) -- dona dentro da base, longe do slot
	teleportar(Beto, pontoDentro(base1, 0, -8))
	andar(Beto, pertoDoMonstrinho(base1, alvo))
	esperar(3.2) -- recarga do roubo
	segurarPrompt(alvo.Raiz.PromptRoubar, Beto)
	igual(Beto:GetAttribute("Carregando"), alvo.Name, "não começou o roubo")
	-- a dona corre até o ladrão
	andar(Ana, raizDe(Beto).Position + Vector3.new(2, 0, 0))
	afirmar(esperarAte(function()
		return Beto:GetAttribute("Carregando") == ""
	end, 2), "roubo deveria falhar")
	igual(alvo.Parent, base1.Monstrinhos, "monstrinho deveria voltar")
	igual(alvo:GetAttribute("DonoUserId"), Ana.UserId)
	igual(alvo:GetAttribute("SendoRoubado"), false)
	igual(Beto.Character.Humanoid.WalkSpeed, Config.Roubo.VelocidadeNormal)
	afirmar(recebeuMensagem(Beto, "te pegou"), "ladrão deveria ser avisado")
	afirmar(recebeuMensagem(Ana, "recuperou"), "dona deveria ser avisada")
end)

teste("não dá para roubar de fora da base nem roubar o próprio", function()
	local alvo = segundaAna
	esperar(3.2)
	-- Beto do lado de fora da parede (dentro do alcance, mas fora da base)
	teleportar(Beto, pontoFora(Bases.Base1, 3))
	segurarPrompt(alvo.Raiz.PromptRoubar, Beto)
	igual(Beto:GetAttribute("Carregando"), "", "roubou de fora")
	-- dona tentando roubar o próprio monstrinho
	teleportar(Ana, alvo.Raiz.Position + Vector3.new(0, 0, 2))
	segurarPrompt(alvo.Raiz.PromptRoubar, Ana)
	igual(Ana:GetAttribute("Carregando"), "", "roubou o próprio")
end)

teste("segurar rápido demais não rouba (anti-exploit)", function()
	local alvo = segundaAna
	esperar(3.2)
	teleportar(Ana, Vector3.new(90, 3, 20))
	local pos = alvo.Raiz.Position
	teleportar(Beto, pontoDentro(Bases.Base1, 0, -8))
	andar(Beto, pertoDoMonstrinho(Bases.Base1, alvo))
	alvo.Raiz.PromptRoubar.PromptButtonHoldBegan:Fire(Beto)
	esperar(0.2)
	alvo.Raiz.PromptRoubar.Triggered:Fire(Beto)
	esperar(0.2)
	igual(Beto:GetAttribute("Carregando"), "", "roubou sem segurar")
end)

print("\nTrancar")

teste("trancar: barreira, expulsa intrusos e bloqueia roubo", function()
	-- Beto está dentro da base da Ana
	afirmar(Bases.Base1.Chao.CFrame:PointToObjectSpace(raizDe(Beto).Position).Z < 26, "pré-condição: Beto dentro")
	pastaRemotos.PedirTrancar.OnServerEvent:Fire(Ana)
	esperar(0.6)
	igual(Bases.Base1.Barreira.CanCollide, true)
	igual(Bases.Base1.Barreira.Transparency, 0.35)
	afirmar(Ana:GetAttribute("TrancadaAte") > Falso.agora(), "TrancadaAte")
	igual(segundaAna:GetAttribute("Trancado"), true)
	local relativo = Bases.Base1.Chao.CFrame:PointToObjectSpace(raizDe(Beto).Position)
	afirmar(relativo.Z < -26, "Beto deveria ser expulso para fora da entrada")
	afirmar(recebeuMensagem(Beto, "trancada"), "Beto deveria ser avisado")
	-- tentar roubar trancado
	teleportar(Beto, segundaAna.Raiz.Position + Vector3.new(2, 0, 0))
	segurarPrompt(segundaAna.Raiz.PromptRoubar, Beto)
	igual(Beto:GetAttribute("Carregando"), "", "roubou base trancada")
	-- trancar de novo
	pastaRemotos.PedirTrancar.OnServerEvent:Fire(Ana)
	esperar(0.2)
	afirmar(recebeuMensagem(Ana, "já está trancada"), "deveria avisar que já está trancada")
end)

teste("destranca sozinha e entra em recarga", function()
	afirmar(esperarAte(function()
		return Bases.Base1.Barreira.CanCollide == false
	end, Config.Trancar.Duracao + 5), "não destrancou")
	afirmar(Ana:GetAttribute("RecargaAte") > Falso.agora(), "recarga")
	esperar(1.1)
	pastaRemotos.PedirTrancar.OnServerEvent:Fire(Ana)
	esperar(0.2)
	afirmar(recebeuMensagem(Ana, "Aguarde"), "deveria pedir para aguardar")
	igual(Bases.Base1.Barreira.CanCollide, false)
end)

teste("Developer Product 'Trancar Agora' ignora a recarga", function()
	local decisao = Marketplace.ProcessReceipt({ PlayerId = Ana.UserId, ProductId = 222, PurchaseId = "tranca-1" })
	igual(decisao, roblox.Enum.ProductPurchaseDecision.PurchaseGranted)
	igual(Bases.Base1.Barreira.CanCollide, true)
	igual(Marketplace.ProcessReceipt({ PlayerId = Ana.UserId, ProductId = 222, PurchaseId = "tranca-1" }), roblox.Enum.ProductPurchaseDecision.PurchaseGranted)
	afirmar(esperarAte(function()
		return Bases.Base1.Barreira.CanCollide == false
	end, Config.Trancar.Duracao + 5), "não destrancou")
end)

print("\nVenda, Game Passes e Rebirth")

teste("vender: segura F e recebe metade do preço", function()
	local alvo = segundaAna
	local info = Catalogo.obter(alvo:GetAttribute("MonstrinhoId"))
	teleportar(Ana, alvo.Raiz.Position + Vector3.new(0, 0, 2))
	local antes = Economia.obterDinheiro(Ana)
	esperar(0.6)
	segurarPrompt(alvo.Raiz.PromptVender, Ana)
	afirmar(alvo.Parent == nil, "monstrinho não foi vendido")
	igual(Economia.obterDinheiro(Ana), antes + Regras.precoVenda(info))
end)

teste("Beto não consegue vender o monstrinho da Ana", function()
	local modelo = comprarDaEsteira(Ana)
	teleportar(Beto, modelo.Raiz.Position + Vector3.new(0, 0, 2))
	esperar(0.6)
	segurarPrompt(modelo.Raiz.PromptVender, Beto)
	igual(modelo.Parent, Bases.Base1.Monstrinhos, "Beto vendeu o monstrinho da Ana")
end)

teste("Game Pass VIP: tag no chat e renda x1.5", function()
	Marketplace.PromptGamePassPurchaseFinished:Fire(Ana, 555, true)
	esperar(0.3)
	igual(Ana:GetAttribute("VIP"), true)
	igual(Ana:GetAttribute("Pass_VIP"), true)
	igual(Ana:GetAttribute("Multiplicador"), Config.Bonus.VIPMultiplicador)
end)

teste("Game Pass +4 Slots libera os slots dourados", function()
	local extra = Bases.Base2.Slots["Slot" .. (Config.Base.SlotsIniciais + 1)]
	igual(extra.EtiquetaExtra.Enabled, true)
	Marketplace.PromptGamePassPurchaseFinished:Fire(Beto, 556, true)
	esperar(0.3)
	igual(extra.EtiquetaExtra.Enabled, false)
	igual(extra.Transparency, 0)
end)

teste("Game Pass Carregar Rápido deixa o ladrão mais rápido", function()
	Marketplace.PromptGamePassPurchaseFinished:Fire(Beto, 557, true)
	esperar(0.2)
	local alvo = Bases.Base1.Monstrinhos:GetChildren()[1]
	teleportar(Ana, Vector3.new(90, 3, 20))
	teleportar(Beto, pontoDentro(Bases.Base1, 0, -8))
	local pos = alvo.Raiz.Position
	andar(Beto, pertoDoMonstrinho(Bases.Base1, alvo))
	esperar(3.2)
	segurarPrompt(alvo.Raiz.PromptRoubar, Beto)
	igual(Beto.Character.Humanoid.WalkSpeed, Config.Roubo.VelocidadeCarregandoRapido)
	-- morre no caminho: o monstrinho volta
	Beto.Character.Humanoid.Health = 0
	Beto.Character.Humanoid.Died:Fire()
	afirmar(esperarAte(function()
		return Beto:GetAttribute("Carregando") == ""
	end, 1), "roubo deveria acabar quando o ladrão morre")
	igual(alvo.Parent, Bases.Base1.Monstrinhos, "monstrinho deveria voltar")
	Beto.Character:Destroy()
	criarPersonagem(Beto, Bases.Base2.Spawn.Position + Vector3.new(0, 3, 0))
	esperar(0.5)
end)

teste("rebirth: reseta dinheiro e monstrinhos e aumenta o multiplicador", function()
	local custo = Regras.custoRebirth(0)
	pastaRemotos.PedirRenascer.OnServerEvent:Fire(Ana)
	esperar(0.2)
	afirmar(recebeuMensagem(Ana, "para renascer"), "deveria recusar sem dinheiro")
	igual(Ana:GetAttribute("Rebirths"), 0)
	Economia.adicionar(Ana, custo)
	esperar(2.1)
	pastaRemotos.PedirRenascer.OnServerEvent:Fire(Ana)
	esperar(0.3)
	igual(Ana:GetAttribute("Rebirths"), 1)
	igual(Ana.leaderstats.Rebirths.Value, 1)
	igual(Economia.obterDinheiro(Ana), Config.Economia.DinheiroInicial)
	igual(#monstrinhosDaBase(Bases.Base1), 0, "monstrinhos deveriam sumir")
	local esperado = Regras.multiplicadorTotal(1, true, false)
	igual(Ana:GetAttribute("Multiplicador"), esperado)
end)

print("\nSair, voltar e fila")

local idBeto = Beto.UserId
local roubadosDoBeto
teste("ladrão sai no meio do roubo: o monstrinho volta e os dados são salvos", function()
	local alvo = comprarDaEsteira(Ana)
	teleportar(Ana, Vector3.new(90, 3, 20))
	teleportar(Beto, pontoDentro(Bases.Base1, 0, -8))
	local pos = alvo.Raiz.Position
	andar(Beto, pertoDoMonstrinho(Bases.Base1, alvo))
	esperar(3.2)
	segurarPrompt(alvo.Raiz.PromptRoubar, Beto)
	igual(Beto:GetAttribute("Carregando"), alvo.Name, "roubo não começou")
	roubadosDoBeto = #monstrinhosDaBase(Bases.Base2)
	sair(Beto)
	afirmar(esperarAte(function()
		return alvo.Parent == Bases.Base1.Monstrinhos and alvo:GetAttribute("SendoRoubado") == false
	end, 2), "monstrinho não voltou")
	afirmar(esperarAte(function()
		local salvo = loja.dados["Jogador_" .. idBeto]
		return salvo ~= nil and salvo.Sessao == nil
	end, 5), "dados do Beto não foram salvos/liberados")
	igual(#loja.dados["Jogador_" .. idBeto].Monstrinhos, roubadosDoBeto, "monstrinhos salvos do Beto")
	igual(Bases.Base2.Placa.PlacaGuiFront.Titulo.Text, "Base livre")
	igual(#monstrinhosDaBase(Bases.Base2), 0, "base do Beto deveria ser limpa")
	afirmar(recebeuMensagem(Ana, "ladrão saiu"), "Ana deveria ser avisada")
end)

teste("Beto volta: recupera dinheiro e monstrinhos nos mesmos slots", function()
	local salvo = loja.dados["Jogador_" .. idBeto]
	local Beto2 = entrar("Beto", idBeto)
	afirmar(esperarAte(function()
		return Beto2:GetAttribute("Carregado") == true
	end), "não carregou")
	local base = baseDe(Beto2)
	igual(#monstrinhosDaBase(base), #salvo.Monstrinhos)
	for _, item in salvo.Monstrinhos do
		local slot = base.Slots["Slot" .. item.Slot]
		local achou = false
		for _, modelo in monstrinhosDaBase(base) do
			local p = modelo.Raiz.Position
			if modelo:GetAttribute("MonstrinhoId") == item.Id and math.abs(p.X - slot.Position.X) < 0.01 and math.abs(p.Z - slot.Position.Z) < 0.01 then
				achou = true
			end
		end
		afirmar(achou, "monstrinho " .. item.Id .. " não voltou para o slot " .. item.Slot)
	end
	afirmar(math.abs(Economia.obterDinheiro(Beto2) - salvo.Dinheiro) < 1e-6, "dinheiro")
	Beto = Beto2
end)

teste("fila: com 8 bases ocupadas, o 9º espera uma vaga", function()
	local extras = {}
	for i = 1, Config.Base.Quantidade - 2 do
		table.insert(extras, entrar("Extra" .. i))
	end
	afirmar(esperarAte(function()
		for _, p in extras do
			if p:GetAttribute("Carregado") ~= true then
				return false
			end
		end
		return true
	end), "extras não carregaram")
	local nono = entrar("Nono")
	afirmar(esperarAte(function()
		return nono:GetAttribute("Carregado") == true
	end), "nono não carregou")
	igual(nono:GetAttribute("BaseIndice"), 0, "não deveria ter base")
	afirmar(recebeuMensagem(nono, "ocupadas"), "deveria avisar que as bases estão ocupadas")
	sair(extras[1])
	afirmar(esperarAte(function()
		return (nono:GetAttribute("BaseIndice") or 0) > 0
	end, 2), "nono deveria ganhar a base que vagou")
	afirmar(recebeuMensagem(nono, "vagou"), "aviso de base vagou")
end)

teste("BindToClose salva todo mundo e libera as travas", function()
	Economia.adicionar(Ana, 123)
	local fechar = Ambiente.aoFechar
	afirmar(fechar, "BindToClose")
	fechar()
	local salvoAna = loja.dados["Jogador_" .. Ana.UserId]
	igual(salvoAna.Sessao, nil, "trava da Ana")
	afirmar(math.abs(salvoAna.Dinheiro - Economia.obterDinheiro(Ana)) < 1e-6, "dinheiro salvo")
	igual(salvoAna.Rebirths, 1)
	afirmar(salvoAna.ComprasProcessadas["tranca-1"] ~= nil, "recibo salvo")
end)

rodando = false
print(("\n%d cenários, %d falha(s)"):format(total, #falhas))
process.exit(if #falhas == 0 then 0 else 1)
