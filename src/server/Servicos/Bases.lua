--[[
	Bases.lua
	As bases dos jogadores:
	  • cada jogador recebe uma base livre ao entrar (fila de espera se todas estiverem ocupadas);
	  • slots onde ficam os monstrinhos (os extras exigem o Game Pass "+4 Slots");
	  • coletor: a renda se acumula nele e o dono pisa para coletar;
	  • trancar: a barreira de laser bloqueia a entrada por Config.Trancar.Duracao
	    segundos. O dono atravessa a barreira (grupos de colisão) e quem estiver
	    dentro sem ser o dono é expulso.
]]

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalogo = require(Shared:WaitForChild("Catalogo"))
local Config = require(Shared:WaitForChild("Config"))
local Formatar = require(Shared:WaitForChild("Formatar"))
local Regras = require(Shared:WaitForChild("Regras"))
local Remotos = require(Shared:WaitForChild("Remotos"))
local Dados = require(script.Parent.Dados)
local Economia = require(script.Parent.Economia)
local Jogadores = require(script.Parent.Jogadores)
local Limitador = require(script.Parent.Limitador)
local Mapa = require(script.Parent.Mapa)
local Monstrinho = require(script.Parent.Monstrinho)
local Notificar = require(script.Parent.Notificar)
local Passes = require(script.Parent.Passes)

local Bases = {}

export type Slot = {
	Indice: number,
	Parte: BasePart,
	Extra: boolean,
	Monstrinho: Monstrinho.Monstrinho?,
	Reservado: boolean, -- guardado para um monstrinho que está sendo roubado para cá
	Etiqueta: BillboardGui?,
}

export type Base = {
	Indice: number,
	Modelo: Model,
	Chao: BasePart,
	Barreira: BasePart,
	Coletor: BasePart,
	BotaoTrancar: BasePart,
	Spawn: SpawnLocation,
	Placa: BasePart,
	Slots: { Slot },
	PastaMonstrinhos: Folder,
	Dono: Player?,
	Trancada: boolean,
	TrancadaAte: number, -- workspace:GetServerTimeNow()
	RecargaAte: number,
	GrupoBarreira: string,
	GrupoDono: string,
	TitulosPlaca: { TextLabel },
	StatusPlaca: { TextLabel },
	TextoColetor: TextLabel,
	TextoBotao: TextLabel,
	ConexaoPersonagem: RBXScriptConnection?,
	ConexaoDescendentes: RBXScriptConnection?,
}

local VERDE = Color3.fromRGB(110, 240, 120)
local VERMELHO = Color3.fromRGB(255, 90, 90)
local CINZA = Color3.fromRGB(220, 220, 230)

local lista: { Base } = {}
local porJogador: { [Player]: Base } = {}
local filaEspera: { Player } = {}
local aoExpulsar: ((Player, Base) -> ())? = nil

-- ------------------------------------------------------------
-- Interface nas peças do mapa (textos)
-- ------------------------------------------------------------

local function novoTexto(pai: Instance, nome: string, texto: string, cor: Color3, posicaoY: number, altura: number): TextLabel
	local rotulo = Instance.new("TextLabel")
	rotulo.Name = nome
	rotulo.BackgroundTransparency = 1
	rotulo.Position = UDim2.fromScale(0.03, posicaoY)
	rotulo.Size = UDim2.fromScale(0.94, altura)
	rotulo.Text = texto
	rotulo.TextColor3 = cor
	rotulo.TextScaled = true
	rotulo.Font = Enum.Font.FredokaOne
	rotulo.TextStrokeColor3 = Color3.new(0, 0, 0)
	rotulo.TextStrokeTransparency = 0.2
	rotulo.Parent = pai
	return rotulo
end

local function removerSeExistir(pai: Instance, nome: string)
	local antigo = pai:FindFirstChild(nome)
	if antigo then
		antigo:Destroy()
	end
end

local function criarGuiPlaca(base: Base)
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local nome = "PlacaGui" .. face.Name
		removerSeExistir(base.Placa, nome)
		local gui = Instance.new("SurfaceGui")
		gui.Name = nome
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.LightInfluence = 0
		gui.Parent = base.Placa
		table.insert(base.TitulosPlaca, novoTexto(gui, "Titulo", "Base livre", Color3.new(1, 1, 1), 0.04, 0.56))
		table.insert(base.StatusPlaca, novoTexto(gui, "Status", "", CINZA, 0.62, 0.34))
	end
end

local function criarGuiColetor(base: Base)
	removerSeExistir(base.Coletor, "ColetorGui")
	local gui = Instance.new("BillboardGui")
	gui.Name = "ColetorGui"
	gui.Size = UDim2.fromScale(7, 2.6)
	gui.StudsOffset = Vector3.new(0, 3.2, 0)
	gui.MaxDistance = 90
	gui.LightInfluence = 0
	gui.Parent = base.Coletor
	novoTexto(gui, "Titulo", "💰 COLETAR", Color3.fromRGB(255, 225, 90), 0, 0.45)
	base.TextoColetor = novoTexto(gui, "Valor", "$0", VERDE, 0.45, 0.55)
end

local function criarGuiBotao(base: Base)
	removerSeExistir(base.BotaoTrancar, "BotaoGui")
	local gui = Instance.new("BillboardGui")
	gui.Name = "BotaoGui"
	gui.Size = UDim2.fromScale(6, 1.6)
	gui.StudsOffset = Vector3.new(0, 2.6, 0)
	gui.MaxDistance = 90
	gui.LightInfluence = 0
	gui.Parent = base.BotaoTrancar
	base.TextoBotao = novoTexto(gui, "Texto", "", Color3.fromRGB(255, 200, 200), 0, 1)
end

local function criarEtiquetaExtra(parte: BasePart): BillboardGui
	removerSeExistir(parte, "EtiquetaExtra")
	local gui = Instance.new("BillboardGui")
	gui.Name = "EtiquetaExtra"
	gui.Size = UDim2.fromScale(5, 1.8)
	gui.StudsOffset = Vector3.new(0, 2.2, 0)
	gui.MaxDistance = 60
	gui.LightInfluence = 0
	gui.Parent = parte
	novoTexto(gui, "Titulo", "🔒 +" .. Config.Base.SlotsExtras .. " SLOTS", Color3.fromRGB(255, 215, 80), 0, 0.55)
	novoTexto(gui, "Sub", "Game Pass na Loja", Color3.new(1, 1, 1), 0.55, 0.45)
	return gui
end

-- ------------------------------------------------------------
-- Atualizações visuais
-- ------------------------------------------------------------

local function atualizarPlaca(base: Base)
	local agora = workspace:GetServerTimeNow()
	local titulo = if base.Dono then "Base de " .. base.Dono.DisplayName else "Base livre"
	local status, cor
	if base.Trancada then
		status, cor = "🔒 Trancada • " .. Formatar.tempo(base.TrancadaAte - agora), VERMELHO
	elseif base.Dono then
		status, cor = "🔓 Aberta", VERDE
	else
		status, cor = "Esperando um dono...", CINZA
	end
	for _, rotulo in base.TitulosPlaca do
		rotulo.Text = titulo
	end
	for _, rotulo in base.StatusPlaca do
		rotulo.Text = status
		rotulo.TextColor3 = cor
	end

	local textoBotao = ""
	if base.Dono then
		if base.Trancada then
			textoBotao = "🔒 " .. Formatar.tempo(base.TrancadaAte - agora)
		elseif agora < base.RecargaAte then
			textoBotao = "⏳ " .. Formatar.tempo(base.RecargaAte - agora)
		else
			textoBotao = "🔒 TRANCAR"
		end
	end
	base.TextoBotao.Text = textoBotao
end

local function atualizarColetor(base: Base)
	local valor = if base.Dono then Economia.obterColetor(base.Dono) else 0
	base.TextoColetor.Text = Formatar.dinheiro(valor)
end

local function atualizarSlotsExtras(base: Base)
	local liberado = base.Dono ~= nil and Passes.possui(base.Dono, "SlotsExtras")
	for _, slot in base.Slots do
		if slot.Extra then
			slot.Parte.Transparency = if liberado then 0 else 0.55
			if slot.Etiqueta then
				slot.Etiqueta.Enabled = not liberado
			end
		end
	end
end

local function aplicarTrava(base: Base, trancada: boolean)
	base.Trancada = trancada
	base.Barreira.Transparency = if trancada then 0.35 else 1
	base.Barreira.CanCollide = trancada
	base.Modelo:SetAttribute("Trancada", trancada)
	for _, slot in base.Slots do
		local m = slot.Monstrinho
		if m then
			m.Modelo:SetAttribute("Trancado", trancada)
		end
	end
	local dono = base.Dono
	if dono then
		dono:SetAttribute("TrancadaAte", if trancada then base.TrancadaAte else 0)
		dono:SetAttribute("RecargaAte", base.RecargaAte)
	end
	atualizarPlaca(base)
end

-- ------------------------------------------------------------
-- Posições
-- ------------------------------------------------------------

-- true se a posição está dentro da área da base (folga negativa = mais para dentro)
function Bases.dentroDaBase(base: Base, posicao: Vector3, folga: number?): boolean
	local relativo = base.Chao.CFrame:PointToObjectSpace(posicao)
	local margem = folga or 0
	return math.abs(relativo.X) <= base.Chao.Size.X / 2 + margem
		and math.abs(relativo.Z) <= base.Chao.Size.Z / 2 + margem
		and relativo.Y >= -3
		and relativo.Y <= Config.Base.AlturaParede + 10
end

-- true se o personagem do jogador está em cima da peça
local function estaSobre(player: Player, parte: BasePart): boolean
	local personagem = player.Character
	local raiz = personagem and personagem:FindFirstChild("HumanoidRootPart")
	if not raiz or not raiz:IsA("BasePart") then
		return false
	end
	local relativo = parte.CFrame:PointToObjectSpace(raiz.Position)
	return math.abs(relativo.X) <= parte.Size.X / 2 + 0.5 and math.abs(relativo.Z) <= parte.Size.Z / 2 + 0.5 and relativo.Y >= 0 and relativo.Y <= 6
end

local function topoDoSlot(slot: Slot): Vector3
	local parte = slot.Parte
	local meiaAltura = if parte:IsA("Part") and parte.Shape == Enum.PartType.Cylinder then parte.Size.X / 2 else parte.Size.Y / 2
	return parte.Position + Vector3.new(0, meiaAltura, 0)
end

-- CFrame do monstrinho em cima do slot, olhando para a entrada da base
local function cframeNoSlot(base: Base, slot: Slot, m: Monstrinho.Monstrinho): CFrame
	local posicao = topoDoSlot(slot) + Vector3.new(0, m.AlturaBase, 0)
	local entrada = base.Chao.CFrame:PointToWorldSpace(Vector3.new(0, 0, -base.Chao.Size.Z / 2))
	return CFrame.lookAt(posicao, Vector3.new(entrada.X, posicao.Y, entrada.Z))
end

local function pontoDeExpulsao(base: Base): CFrame
	return base.Chao.CFrame * CFrame.new(0, 3.5, -(base.Chao.Size.Z / 2 + 7))
end

-- ------------------------------------------------------------
-- Consultas
-- ------------------------------------------------------------

function Bases.obterBase(player: Player): Base?
	return porJogador[player]
end

function Bases.todas(): { Base }
	return lista
end

function Bases.estaTrancada(base: Base): boolean
	return base.Trancada
end

-- Primeiro slot livre que o dono pode usar (extras só com o Game Pass)
function Bases.slotLivre(base: Base): Slot?
	local temExtras = Passes.possui(base.Dono, "SlotsExtras")
	for _, slot in base.Slots do
		if slot.Monstrinho == nil and not slot.Reservado and (not slot.Extra or temExtras) then
			return slot
		end
	end
	return nil
end

-- Função chamada quando alguém é expulso de uma base trancada (o módulo Roubo usa)
function Bases.definirAoExpulsar(funcao: (Player, Base) -> ())
	aoExpulsar = funcao
end

-- ------------------------------------------------------------
-- Monstrinhos na base
-- ------------------------------------------------------------

function Bases.recalcularRenda(base: Base)
	local dono = base.Dono
	if not dono then
		return
	end
	local soma = 0
	for _, slot in base.Slots do
		local m = slot.Monstrinho
		if m and not m.SendoRoubado then
			soma += m.Info.Renda
		end
	end
	Economia.definirRendaBase(dono, soma)
end

function Bases.colocarMonstrinho(base: Base, slot: Slot, m: Monstrinho.Monstrinho)
	local dono = base.Dono
	if not dono then
		m:destruir()
		return
	end
	slot.Monstrinho = m
	slot.Reservado = false
	m.Base = base
	m.Slot = slot
	m.SendoRoubado = false
	m.Modelo:SetAttribute("SendoRoubado", false)
	m.Modelo:SetAttribute("Trancado", base.Trancada)
	m:modoBase(dono)
	m.Raiz.Anchored = true
	m.Modelo.Parent = base.PastaMonstrinhos
	m:posicionar(cframeNoSlot(base, slot, m))
	Bases.recalcularRenda(base)
end

-- Tira o monstrinho do slot (não destrói)
function Bases.retirarMonstrinho(base: Base, slot: Slot): Monstrinho.Monstrinho?
	local m = slot.Monstrinho
	slot.Monstrinho = nil
	if m then
		m.Base = nil
		m.Slot = nil
	end
	Bases.recalcularRenda(base)
	return m
end

-- Vender um monstrinho da própria base
function Bases.vender(player: Player, m: Monstrinho.Monstrinho)
	if not Config.Venda.Ativa then
		return
	end
	local base: Base? = m.Base
	local slot: Slot? = m.Slot
	if not base or not slot or base.Dono ~= player or m.SendoRoubado or m.Modo ~= "Base" then
		return
	end
	if not Limitador.permitir(player, "Vender", 0.5) then
		return
	end
	local valor = Regras.precoVenda(m.Info)
	Bases.retirarMonstrinho(base, slot)
	m:destruir()
	Economia.adicionar(player, valor)
	Notificar.jogador(player, "Você vendeu " .. m.Info.Nome .. " por " .. Formatar.dinheiro(valor) .. "!", "sucesso")
	Dados.solicitarSalvamento(player)
end

-- Remove todos os monstrinhos (rebirth)
function Bases.limparMonstrinhos(player: Player)
	local base = porJogador[player]
	if not base then
		return
	end
	for _, slot in base.Slots do
		local m = slot.Monstrinho
		if m then
			m:destruir()
			slot.Monstrinho = nil
		end
	end
	local estado = Jogadores.obter(player)
	if estado then
		table.clear(estado.Excedentes)
	end
	Bases.recalcularRenda(base)
end

-- Lista para salvar no DataStore. nil = ainda não restaurou (mantém os dados carregados).
function Bases.serializar(player: Player): { { Id: string, Slot: number } }?
	local estado = Jogadores.obter(player)
	local base = porJogador[player]
	if not estado or not estado.MonstrinhosRestaurados or not base then
		return nil
	end
	local salvos = {}
	for _, slot in base.Slots do
		local m = slot.Monstrinho
		if m and not m.Destruido then
			table.insert(salvos, { Id = m.Id, Slot = slot.Indice })
		end
	end
	for _, item in estado.Excedentes do
		table.insert(salvos, { Id = item.Id, Slot = item.Slot })
	end
	return salvos
end

-- Coloca na base os monstrinhos salvos (depois que os dados carregam e a base existe)
function Bases.restaurar(player: Player)
	local estado = Jogadores.obterCarregado(player)
	local base = porJogador[player]
	if not estado or not base or estado.MonstrinhosRestaurados then
		return
	end
	estado.MonstrinhosRestaurados = true
	local dados = estado.Dados :: Jogadores.DadosJogador

	local pendentes = {}
	for _, item in dados.Monstrinhos do
		if not Catalogo.obter(item.Id) then
			-- Monstrinho que não existe mais no Config: guarda para não perder
			warn("[Bases] Monstrinho salvo desconhecido: " .. tostring(item.Id) .. " (guardado)")
			table.insert(estado.Excedentes, { Id = item.Id, Slot = item.Slot })
		else
			local slot = base.Slots[item.Slot]
			if slot and slot.Monstrinho == nil and not slot.Reservado then
				Bases.colocarMonstrinho(base, slot, Monstrinho.novo(item.Id))
			else
				table.insert(pendentes, item)
			end
		end
	end
	-- Os que estavam em slots inválidos/repetidos vão para qualquer slot vazio
	for _, item in pendentes do
		local livre: Slot? = nil
		for _, slot in base.Slots do
			if slot.Monstrinho == nil and not slot.Reservado then
				livre = slot
				break
			end
		end
		if livre then
			Bases.colocarMonstrinho(base, livre, Monstrinho.novo(item.Id))
		else
			table.insert(estado.Excedentes, { Id = item.Id, Slot = item.Slot })
		end
	end
	if #estado.Excedentes > 0 then
		Notificar.jogador(player, "Alguns monstrinhos não couberam na base e ficaram guardados.", "alerta")
	end
	Bases.recalcularRenda(base)
	atualizarColetor(base)
end

-- ------------------------------------------------------------
-- Trancar
-- ------------------------------------------------------------

local function expulsarIntrusos(base: Base)
	for _, player in Players:GetPlayers() do
		if player ~= base.Dono then
			local personagem = player.Character
			local raiz = personagem and personagem:FindFirstChild("HumanoidRootPart")
			if personagem and raiz and raiz:IsA("BasePart") and Bases.dentroDaBase(base, raiz.Position, -0.5) then
				if aoExpulsar then
					aoExpulsar(player, base)
				end
				personagem:PivotTo(pontoDeExpulsao(base))
				Notificar.jogador(player, "🔒 Essa base está trancada!", "erro")
			end
		end
	end
end

-- Tranca a base do jogador. viaProduto = comprou "Trancar Agora" (ignora o cooldown
-- e, se já estiver trancada, soma mais tempo).
function Bases.trancar(player: Player, viaProduto: boolean): (boolean, string?)
	local base = porJogador[player]
	if not base then
		return false, "Você ainda não tem uma base."
	end
	local agora = workspace:GetServerTimeNow()
	if base.Trancada then
		if viaProduto then
			base.TrancadaAte += Config.Trancar.Duracao
			aplicarTrava(base, true)
			return true, nil
		end
		return false, "Sua base já está trancada!"
	end
	if not viaProduto and agora < base.RecargaAte then
		return false, "Aguarde " .. Formatar.tempo(base.RecargaAte - agora) .. " para trancar de novo."
	end
	base.TrancadaAte = agora + Config.Trancar.Duracao
	aplicarTrava(base, true)
	expulsarIntrusos(base)
	return true, nil
end

-- Pedido do botão da interface (RemoteEvent PedirTrancar)
function Bases.pedirTrancar(player: Player)
	if not Limitador.permitir(player, "PedirTrancar", 1) then
		return
	end
	local ok, mensagem = Bases.trancar(player, false)
	if ok then
		Notificar.jogador(player, "🔒 Base trancada por " .. Config.Trancar.Duracao .. " segundos!", "sucesso")
	elseif mensagem then
		Notificar.jogador(player, mensagem, "erro")
	end
end

-- ------------------------------------------------------------
-- Donos
-- ------------------------------------------------------------

-- O dono atravessa a própria barreira: as peças do personagem entram no grupo "DonoBaseN"
local function aplicarGrupoPersonagem(base: Base, personagem: Model)
	local function aplicar(instancia: Instance)
		if instancia:IsA("BasePart") then
			instancia.CollisionGroup = base.GrupoDono
		end
	end
	for _, descendente in personagem:GetDescendants() do
		aplicar(descendente)
	end
	if base.ConexaoDescendentes then
		base.ConexaoDescendentes:Disconnect()
	end
	base.ConexaoDescendentes = personagem.DescendantAdded:Connect(aplicar)
end

-- Garante que o personagem apareça na base (caso o spawn não tenha funcionado)
local function levarParaBase(base: Base, personagem: Model)
	task.delay(0.3, function()
		if base.Dono == nil or personagem.Parent == nil then
			return
		end
		local raiz = personagem:FindFirstChild("HumanoidRootPart")
		if raiz and raiz:IsA("BasePart") and (raiz.Position - base.Spawn.Position).Magnitude > 15 then
			personagem:PivotTo(base.Spawn.CFrame * CFrame.new(0, 4, 0))
		end
	end)
end

function Bases.atribuir(player: Player): Base?
	local existente = porJogador[player]
	if existente then
		return existente
	end
	for _, base in lista do
		if base.Dono == nil then
			base.Dono = player
			porJogador[player] = base
			base.TrancadaAte = 0
			base.RecargaAte = 0
			player.RespawnLocation = base.Spawn
			player:SetAttribute("BaseIndice", base.Indice)
			aplicarTrava(base, false)

			if base.ConexaoPersonagem then
				base.ConexaoPersonagem:Disconnect()
			end
			base.ConexaoPersonagem = player.CharacterAdded:Connect(function(personagem)
				aplicarGrupoPersonagem(base, personagem)
				levarParaBase(base, personagem)
			end)
			local personagem = player.Character
			if personagem then
				aplicarGrupoPersonagem(base, personagem)
				levarParaBase(base, personagem)
			end

			atualizarSlotsExtras(base)
			atualizarColetor(base)
			Bases.restaurar(player) -- só faz algo se os dados já tiverem carregado
			return base
		end
	end
	if not table.find(filaEspera, player) then
		table.insert(filaEspera, player)
	end
	Notificar.jogador(player, "Todas as bases estão ocupadas! Assim que uma vagar, ela será sua.", "alerta")
	return nil
end

-- Jogador saiu: limpa a base e passa para o próximo da fila
function Bases.liberar(player: Player)
	local naFila = table.find(filaEspera, player)
	if naFila then
		table.remove(filaEspera, naFila)
	end
	local base = porJogador[player]
	if not base then
		return
	end
	porJogador[player] = nil
	for _, slot in base.Slots do
		local m = slot.Monstrinho
		if m then
			m:destruir()
			slot.Monstrinho = nil
		end
		slot.Reservado = false
	end
	base.Dono = nil
	if base.ConexaoPersonagem then
		base.ConexaoPersonagem:Disconnect()
		base.ConexaoPersonagem = nil
	end
	if base.ConexaoDescendentes then
		base.ConexaoDescendentes:Disconnect()
		base.ConexaoDescendentes = nil
	end
	base.TrancadaAte = 0
	base.RecargaAte = 0
	aplicarTrava(base, false)
	atualizarSlotsExtras(base)
	atualizarColetor(base)

	while #filaEspera > 0 do
		local proximo = table.remove(filaEspera, 1)
		if proximo and proximo.Parent then
			if Bases.atribuir(proximo) then
				Notificar.jogador(proximo, "Uma base vagou e agora é sua! 🏠", "sucesso")
			end
			break
		end
	end
end

-- Game Pass comprado/verificado: atualiza slots extras e renda
function Bases.aoMudarPasses(player: Player)
	local base = porJogador[player]
	if base then
		atualizarSlotsExtras(base)
		Bases.recalcularRenda(base)
	end
end

-- ------------------------------------------------------------
-- Toques no coletor e no botão
-- ------------------------------------------------------------

local function donoTocou(base: Base, parte: BasePart): Player?
	local dono = base.Dono
	local personagem = dono and dono.Character
	if dono and personagem and parte:IsDescendantOf(personagem) then
		return dono
	end
	return nil
end

local function aoTocarColetor(base: Base, parte: BasePart)
	local dono = donoTocou(base, parte)
	if not dono or not Limitador.permitir(dono, "Coletar", 0.5) then
		return
	end
	if Economia.coletar(dono) > 0 then
		atualizarColetor(base)
	end
end

local function aoTocarBotao(base: Base, parte: BasePart)
	local dono = donoTocou(base, parte)
	if not dono or base.Trancada or not Limitador.permitir(dono, "BotaoTrancar", 2) then
		return
	end
	local ok, mensagem = Bases.trancar(dono, false)
	if ok then
		Notificar.jogador(dono, "🔒 Base trancada por " .. Config.Trancar.Duracao .. " segundos!", "sucesso")
	elseif mensagem then
		Notificar.jogador(dono, mensagem, "erro")
	end
end

-- ------------------------------------------------------------
-- Loops
-- ------------------------------------------------------------

-- Renda: a cada intervalo, a renda de cada dono cai no coletor da base
local function loopRenda()
	local ultimo = os.clock()
	while true do
		task.wait(Config.Economia.IntervaloRenda)
		local agora = os.clock()
		local passado = math.min(agora - ultimo, Config.Economia.IntervaloRenda * 5)
		ultimo = agora
		for _, base in lista do
			local dono = base.Dono
			if dono and Jogadores.obterCarregado(dono) then
				local renda = Economia.rendaPorSegundo(dono)
				if renda > 0 then
					Economia.adicionarColetor(dono, renda * passado)
				end
				if estaSobre(dono, base.Coletor) then
					Economia.coletar(dono)
				end
				atualizarColetor(base)
			end
		end
	end
end

-- Trava: destranca quando o tempo acaba, expulsa intrusos e atualiza as placas
local function loopTrava()
	local contador = 0
	while true do
		task.wait(0.25)
		contador += 1
		local agora = workspace:GetServerTimeNow()
		for _, base in lista do
			if base.Trancada then
				if agora >= base.TrancadaAte then
					base.RecargaAte = agora + Config.Trancar.Recarga
					aplicarTrava(base, false)
					Notificar.jogador(base.Dono, "🔓 Sua base foi destrancada!", "alerta")
				else
					expulsarIntrusos(base)
				end
			end
			if contador % 4 == 0 then
				atualizarPlaca(base)
			end
		end
	end
end

-- ------------------------------------------------------------
-- Início
-- ------------------------------------------------------------

local function registrarGrupo(nome: string)
	local ok, registrado = pcall(function()
		return PhysicsService:IsCollisionGroupRegistered(nome)
	end)
	if not (ok and registrado) then
		PhysicsService:RegisterCollisionGroup(nome)
	end
end

function Bases.iniciar(mapa: Mapa.MapaInfo)
	for _, info in mapa.Bases do
		local pasta = Instance.new("Folder")
		pasta.Name = "Monstrinhos"
		pasta.Parent = info.Modelo

		local base: Base = {
			Indice = info.Indice,
			Modelo = info.Modelo,
			Chao = info.Chao,
			Barreira = info.Barreira,
			Coletor = info.Coletor,
			BotaoTrancar = info.BotaoTrancar,
			Spawn = info.Spawn,
			Placa = info.Placa,
			Slots = {},
			PastaMonstrinhos = pasta,
			Dono = nil,
			Trancada = false,
			TrancadaAte = 0,
			RecargaAte = 0,
			GrupoBarreira = "BarreiraBase" .. info.Indice,
			GrupoDono = "DonoBase" .. info.Indice,
			TitulosPlaca = {},
			StatusPlaca = {},
			TextoColetor = nil :: any, -- criado logo abaixo
			TextoBotao = nil :: any,
			ConexaoPersonagem = nil,
			ConexaoDescendentes = nil,
		}

		-- Grupos de colisão: a barreira não colide com o dono da base
		registrarGrupo(base.GrupoBarreira)
		registrarGrupo(base.GrupoDono)
		PhysicsService:CollisionGroupSetCollidable(base.GrupoBarreira, base.GrupoDono, false)
		base.Barreira.CollisionGroup = base.GrupoBarreira

		for _, slotInfo in info.Slots do
			table.insert(base.Slots, {
				Indice = slotInfo.Indice,
				Parte = slotInfo.Parte,
				Extra = slotInfo.Extra,
				Monstrinho = nil,
				Reservado = false,
				Etiqueta = if slotInfo.Extra then criarEtiquetaExtra(slotInfo.Parte) else nil,
			})
		end

		criarGuiPlaca(base)
		criarGuiColetor(base)
		criarGuiBotao(base)

		base.Coletor.Touched:Connect(function(parte)
			aoTocarColetor(base, parte)
		end)
		base.BotaoTrancar.Touched:Connect(function(parte)
			aoTocarBotao(base, parte)
		end)

		aplicarTrava(base, false)
		atualizarSlotsExtras(base)
		atualizarColetor(base)
		table.insert(lista, base)
	end

	Remotos.PedirTrancar.OnServerEvent:Connect(function(player: Player)
		Bases.pedirTrancar(player)
	end)

	task.spawn(loopRenda)
	task.spawn(loopTrava)
end

return Bases
