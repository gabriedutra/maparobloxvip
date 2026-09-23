--[[
	MapaConstrutor.lua
	Constrói o mapa inteiro só com Parts (sem assets externos):
	gramado, praça, esteira com portais, 8 bases com paredes, slots,
	coletor, botão de trancar, spawn e decoração (árvores, postes, flores).

	É usado de dois jeitos:
	  1) Pela ferramenta "ferramentas/gerar_mapa.luau" (Lune), que salva
	     mapa/Mapa.rbxmx — é esse mapa que você vê ao abrir o jogo no Studio;
	  2) Pelo servidor (Mapa.lua), se o mapa não existir no Workspace ou
	     estiver diferente do Config.lua.

	Por isso este módulo NÃO usa serviços do Roblox: só Instance.new e tipos básicos.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local MapaConstrutor = {}

-- Aumente este número se mudar a geometria deste arquivo (força o servidor a reconstruir o mapa)
MapaConstrutor.VERSAO = 1

export type PosicaoSlot = { X: number, Z: number, Extra: boolean }

local BRANCO = Color3.new(1, 1, 1)
local PRETO = Color3.new(0, 0, 0)

-- ------------------------------------------------------------
-- Utilidades
-- ------------------------------------------------------------

local function textoCor(c: Color3): string
	return string.format("%d,%d,%d", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

local function corDaBase(indice: number): Color3
	local cores = Config.Base.Cores
	return cores[((indice - 1) % #cores) + 1]
end

local function novaParte(
	pai: Instance,
	nome: string,
	tamanho: Vector3,
	cframe: CFrame,
	cor: Color3,
	material: Enum.Material?,
	forma: Enum.PartType?
): Part
	local parte = Instance.new("Part")
	parte.Name = nome
	parte.Anchored = true
	if forma then
		parte.Shape = forma
	end
	parte.Size = tamanho
	parte.CFrame = cframe
	parte.Color = cor
	parte.Material = material or Enum.Material.SmoothPlastic
	parte.TopSurface = Enum.SurfaceType.Smooth
	parte.BottomSurface = Enum.SurfaceType.Smooth
	parte.Parent = pai
	return parte
end

-- Deixa a parte brilhante (Neon) e sem sombra
local function neon(parte: Part): Part
	parte.Material = Enum.Material.Neon
	parte.CastShadow = false
	return parte
end

-- Deixa a parte "fantasma" (sem colisão nem toque) — usada em decoração e marcadores
local function semColisao(parte: Part): Part
	parte.CanCollide = false
	parte.CanTouch = false
	parte.CanQuery = false
	return parte
end

-- Coloca um texto (SurfaceGui) em uma face da parte
local function textoNaParte(parte: BasePart, face: Enum.NormalId, titulo: string, corTitulo: Color3, subtitulo: string?)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Texto" .. face.Name
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0
	gui.Parent = parte

	local rotulo = Instance.new("TextLabel")
	rotulo.Name = "Titulo"
	rotulo.BackgroundTransparency = 1
	rotulo.Size = UDim2.fromScale(1, if subtitulo then 0.62 else 1)
	rotulo.Text = titulo
	rotulo.TextColor3 = corTitulo
	rotulo.TextScaled = true
	rotulo.FontFace = Font.fromEnum(Enum.Font.FredokaOne)
	rotulo.TextStrokeColor3 = PRETO
	rotulo.TextStrokeTransparency = 0.2
	rotulo.Parent = gui

	if subtitulo then
		local sub = Instance.new("TextLabel")
		sub.Name = "Subtitulo"
		sub.BackgroundTransparency = 1
		sub.Position = UDim2.fromScale(0.05, 0.62)
		sub.Size = UDim2.fromScale(0.9, 0.34)
		sub.Text = subtitulo
		sub.TextColor3 = BRANCO
		sub.TextScaled = true
		sub.FontFace = Font.fromEnum(Enum.Font.FredokaOne)
		sub.TextStrokeColor3 = PRETO
		sub.TextStrokeTransparency = 0.3
		sub.Parent = gui
	end
	return gui
end

-- ------------------------------------------------------------
-- Layout
-- ------------------------------------------------------------

-- Texto que resume o layout do Config. O servidor compara com o atributo
-- "AssinaturaLayout" do mapa salvo para saber se precisa reconstruir.
function MapaConstrutor.assinatura(): string
	local b, m = Config.Base, Config.Mapa
	local partes: { any } = {
		"v" .. MapaConstrutor.VERSAO,
		b.Quantidade,
		b.Largura,
		b.Profundidade,
		b.AlturaParede,
		b.LarguraEntrada,
		b.SlotsIniciais,
		b.SlotsExtras,
		m.ComprimentoEsteira,
		m.LarguraEsteira,
		m.LarguraPraca,
		m.EspacoEntreBases,
		textoCor(m.CorGrama),
		textoCor(m.CorPraca),
		textoCor(m.CorEsteira),
		textoCor(m.CorTrilho),
		textoCor(m.CorPortalEntrada),
		textoCor(m.CorPortalSaida),
	}
	for i = 1, b.Quantidade do
		table.insert(partes, textoCor(corDaBase(i)))
	end
	local textos = {}
	for i, valor in partes do
		textos[i] = tostring(valor)
	end
	return table.concat(textos, "|")
end

-- Posições dos slots em coordenadas locais da base (origem = centro do chão,
-- -Z = frente/entrada). Slots normais em duas colunas nas laterais; slots
-- extras (Game Pass) em uma fileira no fundo.
function MapaConstrutor.posicoesSlots(): { PosicaoSlot }
	local b = Config.Base
	local L, P = b.Largura, b.Profundidade
	local lista: { PosicaoSlot } = {}

	local n = b.SlotsIniciais
	local porColuna = math.ceil(n / 2)
	local zInicio, zFim = -P / 2 + 14, P / 2 - 10
	local xColuna = L / 2 - 7
	for i = 1, n do
		local esquerda = i <= porColuna
		local linha = if esquerda then i else i - porColuna
		local totalNaColuna = if esquerda then porColuna else n - porColuna
		local z = if totalNaColuna <= 1
			then (zInicio + zFim) / 2
			else zInicio + (linha - 1) * (zFim - zInicio) / (totalNaColuna - 1)
		table.insert(lista, { X = if esquerda then -xColuna else xColuna, Z = z, Extra = false })
	end

	local extras = b.SlotsExtras
	local xMaximo = L / 2 - 13
	for i = 1, extras do
		local x = if extras <= 1 then 0 else -xMaximo + (i - 1) * (2 * xMaximo) / (extras - 1)
		table.insert(lista, { X = x, Z = P / 2 - 5.5, Extra = true })
	end
	return lista
end

-- Centro (CFrame) de cada base: -Z (LookVector) aponta para a esteira
function MapaConstrutor.cframesBases(): { CFrame }
	local b, m = Config.Base, Config.Mapa
	local porLado = math.ceil(b.Quantidade / 2)
	local passoX = b.Largura + m.EspacoEntreBases
	local zCentro = m.LarguraPraca / 2 + b.Profundidade / 2
	local lista = {}
	for i = 1, b.Quantidade do
		local norte = i <= porLado
		local coluna = if norte then i else i - porLado
		local x = (coluna - (porLado + 1) / 2) * passoX
		local z = if norte then -zCentro else zCentro
		-- Bases do norte giram 180° para a frente (-Z local) apontar para +Z (a esteira).
		-- (Usa CFrame.Angles em vez de CFrame.lookAt para dar o mesmo resultado no Lune e no Roblox.)
		table.insert(lista, CFrame.new(x, 0.5, z) * CFrame.Angles(0, if norte then math.pi else 0, 0))
	end
	return lista
end

-- ------------------------------------------------------------
-- Partes do mapa
-- ------------------------------------------------------------

local function construirPortal(pai: Instance, nome: string, x: number, cor: Color3, larguraEsteira: number): Model
	local portal = Instance.new("Model")
	portal.Name = nome
	portal.Parent = pai

	local escuro = cor:Lerp(PRETO, 0.55)
	local zPilar = larguraEsteira / 2 + 3
	for _, lado in { -1, 1 } do
		novaParte(portal, "Pilar", Vector3.new(2.5, 16, 2.5), CFrame.new(x, 8, lado * zPilar), escuro)
		neon(novaParte(portal, "Faixa", Vector3.new(2.7, 12, 0.6), CFrame.new(x, 8, lado * (zPilar - 1)), cor))
	end
	novaParte(portal, "Topo", Vector3.new(2.5, 3, 2 * zPilar + 2.5), CFrame.new(x, 17.5, 0), escuro)
	neon(novaParte(portal, "TopoFaixa", Vector3.new(2.7, 0.7, 2 * zPilar + 2.7), CFrame.new(x, 16.2, 0), cor))

	local membrana = semColisao(neon(novaParte(portal, "Membrana", Vector3.new(0.4, 14, 2 * zPilar - 2.5), CFrame.new(x, 8, 0), cor)))
	membrana.Transparency = 0.45
	local luz = Instance.new("PointLight")
	luz.Color = cor
	luz.Range = 22
	luz.Brightness = 2
	luz.Parent = membrana
	return portal
end

local function construirArvore(pai: Instance, posicao: Vector3, altura: number, tamanhoCopa: number, corCopa: Color3)
	local arvore = Instance.new("Model")
	arvore.Name = "Arvore"
	arvore.Parent = pai
	novaParte(
		arvore,
		"Tronco",
		Vector3.new(altura, 1.8, 1.8),
		CFrame.new(posicao + Vector3.new(0, altura / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(120, 80, 50),
		Enum.Material.Wood,
		Enum.PartType.Cylinder
	)
	local topo = posicao + Vector3.new(0, altura, 0)
	novaParte(arvore, "Copa", Vector3.new(tamanhoCopa, tamanhoCopa, tamanhoCopa), CFrame.new(topo), corCopa, Enum.Material.Grass, Enum.PartType.Ball)
	local menor = tamanhoCopa * 0.7
	novaParte(
		arvore,
		"Copa2",
		Vector3.new(menor, menor, menor),
		CFrame.new(topo + Vector3.new(tamanhoCopa * 0.35, -tamanhoCopa * 0.15, tamanhoCopa * 0.2)),
		corCopa:Lerp(BRANCO, 0.12),
		Enum.Material.Grass,
		Enum.PartType.Ball
	)
end

local function construirPoste(pai: Instance, posicao: Vector3)
	local poste = Instance.new("Model")
	poste.Name = "Poste"
	poste.Parent = pai
	novaParte(
		poste,
		"Haste",
		Vector3.new(9, 0.7, 0.7),
		CFrame.new(posicao + Vector3.new(0, 4.5, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(60, 60, 75),
		Enum.Material.Metal,
		Enum.PartType.Cylinder
	)
	local lampada = neon(
		novaParte(
			poste,
			"Lampada",
			Vector3.new(1.8, 1.8, 1.8),
			CFrame.new(posicao + Vector3.new(0, 9.4, 0)),
			Color3.fromRGB(255, 236, 170),
			nil,
			Enum.PartType.Ball
		)
	)
	local luz = Instance.new("PointLight")
	luz.Color = Color3.fromRGB(255, 225, 160)
	luz.Range = 20
	luz.Brightness = 1.2
	luz.Parent = lampada
end

local function construirBase(pai: Instance, indice: number, cf: CFrame): Model
	local b = Config.Base
	local L, P, H, E = b.Largura, b.Profundidade, b.AlturaParede, b.LarguraEntrada
	local cor = corDaBase(indice)
	local corEscura = cor:Lerp(PRETO, 0.35)
	local corClara = cor:Lerp(BRANCO, 0.6)

	local modelo = Instance.new("Model")
	modelo.Name = "Base" .. indice
	modelo:SetAttribute("Indice", indice)
	modelo.Parent = pai

	local chao = novaParte(modelo, "Chao", Vector3.new(L, 1, P), cf, corClara)
	modelo.PrimaryPart = chao

	-- "topo" = centro da superfície do chão da base
	local topo = cf * CFrame.new(0, 0.5, 0)
	local function em(x: number, y: number, z: number): CFrame
		return topo * CFrame.new(x, y, z)
	end

	-- Tapete do caminho de entrada
	novaParte(modelo, "Tapete", Vector3.new(E - 2, 0.1, 16), em(0, 0.05, -P / 2 + 8), cor:Lerp(BRANCO, 0.3))

	-- Paredes: parte de baixo sólida, parte de cima translúcida e um friso neon
	local function parede(nome: string, largura: number, profundidade: number, x: number, z: number)
		local alturaSolida = 4
		novaParte(modelo, nome, Vector3.new(largura, alturaSolida, profundidade), em(x, alturaSolida / 2, z), corEscura)
		local vidro = novaParte(
			modelo,
			nome .. "Vidro",
			Vector3.new(largura, H - alturaSolida, profundidade),
			em(x, alturaSolida + (H - alturaSolida) / 2, z),
			cor
		)
		vidro.Transparency = 0.65
		vidro.CastShadow = false
		neon(novaParte(modelo, nome .. "Friso", Vector3.new(largura, 0.5, profundidade + 0.1), em(x, H + 0.25, z), cor))
	end
	parede("ParedeFundo", L, 1, 0, P / 2 - 0.5)
	parede("ParedeEsquerda", 1, P - 1, -(L / 2 - 0.5), -0.5)
	parede("ParedeDireita", 1, P - 1, L / 2 - 0.5, -0.5)
	local segmento = (L - E) / 2 - 1
	parede("ParedeFrenteA", segmento, 1, -(E / 2 + segmento / 2), -(P / 2 - 0.5))
	parede("ParedeFrenteB", segmento, 1, E / 2 + segmento / 2, -(P / 2 - 0.5))

	-- Colunas neon na entrada
	for _, lado in { -1, 1 } do
		neon(novaParte(modelo, "ColunaEntrada", Vector3.new(1.2, H + 1, 1.4), em(lado * (E / 2 + 0.6), (H + 1) / 2, -(P / 2 - 0.5)), cor))
	end

	-- Barreira de laser (fica invisível e sem colisão até a base ser trancada)
	local barreira = novaParte(
		modelo,
		"Barreira",
		Vector3.new(E, H, 0.6),
		em(0, H / 2, -(P / 2 - 0.5)),
		Color3.fromRGB(255, 45, 60),
		Enum.Material.Neon
	)
	barreira.Transparency = 1
	barreira.CanCollide = false
	barreira.CanTouch = false
	barreira.CastShadow = false

	-- Placa com o nome do dono (o texto é criado pelo servidor)
	local placa = novaParte(modelo, "Placa", Vector3.new(E + 12, 5, 0.8), em(0, H + 3, -(P / 2 - 0.5)), corEscura)
	placa.CastShadow = false

	-- Coletor de dinheiro (o dono pisa para coletar)
	local xColetor, zFrente = -(L / 2 - 10), -(P / 2 - 7)
	novaParte(modelo, "ColetorBase", Vector3.new(8, 0.3, 8), em(xColetor, 0.15, zFrente), corEscura)
	local coletor = neon(novaParte(modelo, "Coletor", Vector3.new(6.5, 0.3, 6.5), em(xColetor, 0.45, zFrente), Color3.fromRGB(60, 230, 110)))
	coletor.CastShadow = false

	-- Botão de trancar (o dono pisa para trancar)
	local xBotao = L / 2 - 10
	novaParte(modelo, "BotaoTrancarBase", Vector3.new(6, 0.3, 6), em(xBotao, 0.15, zFrente), corEscura)
	neon(
		novaParte(
			modelo,
			"BotaoTrancar",
			Vector3.new(0.4, 4.6, 4.6),
			em(xBotao, 0.5, zFrente) * CFrame.Angles(0, 0, math.rad(90)),
			Color3.fromRGB(255, 70, 80),
			nil,
			Enum.PartType.Cylinder
		)
	)

	-- Spawn do dono
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(6, 0.4, 6)
	spawn.CFrame = em(0, 0.2, -6)
	spawn.Color = cor
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.BottomSurface = Enum.SurfaceType.Smooth
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Enabled = true
	spawn.Parent = modelo

	-- Slots (pódios redondos). Os extras (Game Pass) são dourados.
	local pastaSlots = Instance.new("Folder")
	pastaSlots.Name = "Slots"
	pastaSlots.Parent = modelo
	for s, p in MapaConstrutor.posicoesSlots() do
		local corSlot = if p.Extra then Color3.fromRGB(255, 205, 60) else cor
		local slot = novaParte(
			pastaSlots,
			"Slot" .. s,
			Vector3.new(0.6, 5, 5),
			em(p.X, 0.3, p.Z) * CFrame.Angles(0, 0, math.rad(90)),
			corSlot,
			if p.Extra then Enum.Material.Neon else Enum.Material.SmoothPlastic,
			Enum.PartType.Cylinder
		)
		slot:SetAttribute("Indice", s)
		slot:SetAttribute("Extra", p.Extra)
		novaParte(
			slot,
			"Anel",
			Vector3.new(0.4, 5.8, 5.8),
			em(p.X, 0.2, p.Z) * CFrame.Angles(0, 0, math.rad(90)),
			corEscura,
			nil,
			Enum.PartType.Cylinder
		)
	end
	return modelo
end

-- ------------------------------------------------------------
-- Construção completa
-- ------------------------------------------------------------

function MapaConstrutor.construir(): Model
	local b, m = Config.Base, Config.Mapa
	local C, W = m.ComprimentoEsteira, m.LarguraEsteira
	local porLado = math.ceil(b.Quantidade / 2)
	local larguraFileira = porLado * (b.Largura + m.EspacoEntreBases) - m.EspacoEntreBases
	local comprimentoUtil = math.max(C, larguraFileira)
	local zFundoBases = m.LarguraPraca / 2 + b.Profundidade

	local mapa = Instance.new("Model")
	mapa.Name = "Mapa"
	mapa:SetAttribute("AssinaturaLayout", MapaConstrutor.assinatura())

	-- Gramado
	local tamanhoX = comprimentoUtil + 90
	local tamanhoZ = 2 * zFundoBases + 70
	novaParte(mapa, "Grama", Vector3.new(tamanhoX, 2, tamanhoZ), CFrame.new(0, -1, 0), m.CorGrama, Enum.Material.Grass)

	-- Praça entre as fileiras de bases
	local praca = Instance.new("Model")
	praca.Name = "Praca"
	praca.Parent = mapa
	novaParte(praca, "Piso", Vector3.new(comprimentoUtil + 30, 0.2, m.LarguraPraca), CFrame.new(0, 0.1, 0), m.CorPraca)
	for _, lado in { -1, 1 } do
		neon(
			novaParte(
				praca,
				"Faixa",
				Vector3.new(comprimentoUtil + 30, 0.25, 0.8),
				CFrame.new(0, 0.12, lado * (m.LarguraPraca / 2 - 0.4)),
				Color3.fromRGB(255, 255, 255)
			)
		)
	end

	-- Esteira
	local esteira = Instance.new("Model")
	esteira.Name = "Esteira"
	esteira.Parent = mapa
	novaParte(esteira, "Correia", Vector3.new(C, 1, W), CFrame.new(0, 0.5, 0), m.CorEsteira)
	local quantidadeListras = math.floor(C / 8)
	for i = 0, quantidadeListras - 1 do
		local x = -C / 2 + 4 + i * 8
		semColisao(novaParte(esteira, "Listra", Vector3.new(0.8, 0.06, W - 1.5), CFrame.new(x, 1.03, 0), m.CorEsteira:Lerp(BRANCO, 0.15)))
	end
	for _, lado in { -1, 1 } do
		neon(novaParte(esteira, "Trilho", Vector3.new(C, 1.4, 0.8), CFrame.new(0, 0.7, lado * (W / 2 + 0.4)), m.CorTrilho))
	end
	-- Marcadores invisíveis: onde os monstrinhos nascem e somem
	local inicio = semColisao(novaParte(esteira, "Inicio", Vector3.new(1, 1, 1), CFrame.new(-C / 2 + 2, 1, 0), BRANCO))
	inicio.Transparency = 1
	local fim = semColisao(novaParte(esteira, "Fim", Vector3.new(1, 1, 1), CFrame.new(C / 2 - 2, 1, 0), BRANCO))
	fim.Transparency = 1

	construirPortal(esteira, "PortalEntrada", -C / 2, m.CorPortalEntrada, W)
	construirPortal(esteira, "PortalSaida", C / 2, m.CorPortalSaida, W)
	local placaEntrada = novaParte(esteira, "PlacaEntrada", Vector3.new(1, 5, W + 10), CFrame.new(-C / 2, 22, 0), m.CorPortalEntrada:Lerp(PRETO, 0.6))
	textoNaParte(placaEntrada, Enum.NormalId.Right, "PORTAL DOS MONSTRINHOS", Color3.fromRGB(235, 200, 255))
	local placaSaida = novaParte(esteira, "PlacaSaida", Vector3.new(1, 5, W + 10), CFrame.new(C / 2, 22, 0), m.CorPortalSaida:Lerp(PRETO, 0.6))
	textoNaParte(placaSaida, Enum.NormalId.Left, "SAÍDA", Color3.fromRGB(255, 200, 200))

	-- Letreiro flutuante com o nome do jogo (visível dos dois lados)
	local letreiro = novaParte(mapa, "Letreiro", Vector3.new(50, 10, 1), CFrame.new(0, 36, 0), Color3.fromRGB(35, 25, 60))
	letreiro.CastShadow = false
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		textoNaParte(letreiro, face, "ROUBE O MONSTRINHO", Color3.fromRGB(255, 215, 70), "Compre na esteira • Roube dos amigos • Tranque sua base!")
	end
	neon(novaParte(mapa, "LetreiroMoldura", Vector3.new(51, 11, 0.6), CFrame.new(0, 36, 0), Color3.fromRGB(255, 120, 200)))

	-- Bases
	local pastaBases = Instance.new("Folder")
	pastaBases.Name = "Bases"
	pastaBases.Parent = mapa
	for indice, cf in MapaConstrutor.cframesBases() do
		construirBase(pastaBases, indice, cf)
	end

	-- Spawn central (usado só por quem ainda não tem base)
	local spawnCentral = Instance.new("SpawnLocation")
	spawnCentral.Name = "SpawnCentral"
	spawnCentral.Anchored = true
	spawnCentral.Size = Vector3.new(6, 0.4, 6)
	spawnCentral.CFrame = CFrame.new(0, 0.4, 15)
	spawnCentral.Color = Color3.fromRGB(255, 255, 255)
	spawnCentral.Material = Enum.Material.SmoothPlastic
	spawnCentral.TopSurface = Enum.SurfaceType.Smooth
	spawnCentral.BottomSurface = Enum.SurfaceType.Smooth
	spawnCentral.Neutral = true
	spawnCentral.Duration = 0
	spawnCentral.Parent = mapa

	-- Decoração
	local decoracao = Instance.new("Folder")
	decoracao.Name = "Decoracao"
	decoracao.Parent = mapa

	-- Postes de luz entre as bases
	local passoX = b.Largura + m.EspacoEntreBases
	for coluna = 1, porLado - 1 do
		local x = (coluna + 0.5 - (porLado + 1) / 2) * passoX
		for _, lado in { -1, 1 } do
			construirPoste(decoracao, Vector3.new(x, 0.2, lado * (m.LarguraPraca / 2 - 2.5)))
		end
	end

	-- Árvores e flores fora da área de jogo (posições "aleatórias" fixas)
	local semente = 20240917
	local function aleatorio(): number
		semente = (semente * 16807) % 2147483647
		return semente / 2147483647
	end
	local limiteX, limiteZ = tamanhoX / 2 - 5, tamanhoZ / 2 - 5
	local areaX, areaZ = comprimentoUtil / 2 + 14, zFundoBases + 4
	local function posicaoLivre(): Vector3?
		for _ = 1, 30 do
			local x = (aleatorio() * 2 - 1) * limiteX
			local z = (aleatorio() * 2 - 1) * limiteZ
			if math.abs(x) > areaX or math.abs(z) > areaZ then
				return Vector3.new(x, 0, z)
			end
		end
		return nil
	end
	local verdes = {
		Color3.fromRGB(70, 160, 70),
		Color3.fromRGB(95, 185, 80),
		Color3.fromRGB(60, 140, 90),
		Color3.fromRGB(120, 190, 70),
	}
	for _ = 1, 38 do
		local posicao = posicaoLivre()
		if posicao then
			local altura = 6 + aleatorio() * 5
			local copa = 7 + aleatorio() * 4
			construirArvore(decoracao, posicao, altura, copa, verdes[math.floor(aleatorio() * #verdes) + 1])
		end
	end
	local coresFlores = {
		Color3.fromRGB(255, 90, 120),
		Color3.fromRGB(255, 220, 70),
		Color3.fromRGB(180, 110, 255),
		Color3.fromRGB(90, 200, 255),
		Color3.fromRGB(255, 150, 60),
	}
	for _ = 1, 45 do
		local posicao = posicaoLivre()
		if posicao then
			local flor = semColisao(
				neon(
					novaParte(
						decoracao,
						"Flor",
						Vector3.new(0.9, 0.9, 0.9),
						CFrame.new(posicao + Vector3.new(0, 0.45, 0)),
						coresFlores[math.floor(aleatorio() * #coresFlores) + 1],
						nil,
						Enum.PartType.Ball
					)
				)
			)
			flor.CastShadow = false
		end
	end

	return mapa
end

return MapaConstrutor
