--[[
	MonstrinhoModelo.lua
	Monta o visual de um monstrinho só com Parts: corpo (bola, cubo ou
	cilindro), olhos, boca, bochechas, pés e acessórios (orelhas, chifres,
	antena, coroa, asas...). A raridade define tamanho, luz e efeitos.
	Também cria o BillboardGui com nome, raridade, renda/s e preço.

	Estrutura do Model criado:
	  Raiz (Part invisível e ancorada, PrimaryPart) — todas as outras peças
	  são soldadas nela, então basta mover a Raiz (ou usar PivotTo).
	  Atributos: MonstrinhoId, Raridade, AlturaBase (distância da Raiz até o
	  chão), AlturaTopo (da Raiz até o topo da cabeça).

	Não usa serviços do Roblox (dá para testar no Lune).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalogo = require(Shared:WaitForChild("Catalogo"))
local Formatar = require(Shared:WaitForChild("Formatar"))

local MonstrinhoModelo = {}

local BRANCO = Color3.new(1, 1, 1)
local PRETO = Color3.fromRGB(20, 20, 28)
local COR_BOCA = Color3.fromRGB(70, 25, 40)
local COR_BOCHECHA = Color3.fromRGB(255, 140, 170)
local COR_OURO = Color3.fromRGB(255, 205, 50)

local ARCO_IRIS = {
	Color3.fromRGB(255, 70, 70),
	Color3.fromRGB(255, 165, 50),
	Color3.fromRGB(255, 235, 60),
	Color3.fromRGB(80, 220, 100),
	Color3.fromRGB(70, 160, 255),
	Color3.fromRGB(170, 90, 255),
}

local function sequenciaArcoIris(): ColorSequence
	local pontos = {}
	for i, cor in ARCO_IRIS do
		table.insert(pontos, ColorSequenceKeypoint.new((i - 1) / (#ARCO_IRIS - 1), cor))
	end
	return ColorSequence.new(pontos)
end

local function temExtra(info: Catalogo.Monstrinho, nome: string): boolean
	return table.find(info.Extras, nome) ~= nil
end

-- Superfície do corpo (em unidades do diâmetro D)
local function frenteZ(forma: string, x: number, y: number): number
	if forma == "Bola" then
		return -math.sqrt(math.max(0, 0.25 - x * x - y * y))
	elseif forma == "Cubo" then
		return -0.5
	end
	return -math.sqrt(math.max(0, 0.2025 - x * x)) -- cilindro (raio 0,45)
end

local function topoY(forma: string): number
	if forma == "Bola" then
		return 0.5
	elseif forma == "Cubo" then
		return 0.45
	end
	return 0.55
end

local function lateralX(forma: string): number
	return if forma == "Cilindro" then 0.45 else 0.5
end

-- Altura da superfície de cima em uma posição z (para espinhos)
local function topoEmZ(forma: string, z: number): number
	if forma == "Bola" then
		return math.sqrt(math.max(0, 0.25 - z * z))
	end
	return topoY(forma)
end

function MonstrinhoModelo.construir(info: Catalogo.Monstrinho): (Model, BasePart)
	local raridade = Catalogo.raridadeDe(info)
	local D = raridade.Tamanho
	local forma = info.Forma

	local modelo = Instance.new("Model")
	modelo.Name = info.Nome
	modelo:SetAttribute("MonstrinhoId", info.Id)
	modelo:SetAttribute("Raridade", raridade.Id)

	local raiz = Instance.new("Part")
	raiz.Name = "Raiz"
	raiz.Size = Vector3.new(1, 1, 1)
	raiz.CFrame = CFrame.new()
	raiz.Transparency = 1
	raiz.Anchored = true
	raiz.CanCollide = false
	raiz.CanTouch = false
	raiz.CanQuery = false
	raiz.Massless = true
	raiz.Parent = modelo
	modelo.PrimaryPart = raiz

	-- Cria uma peça soldada na Raiz. cfLocal é relativo à Raiz (que está na origem).
	local function peca(
		nome: string,
		formaPeca: Enum.PartType?,
		tamanho: Vector3,
		cfLocal: CFrame,
		cor: Color3,
		material: Enum.Material?,
		transparencia: number?
	): Part
		local parte = Instance.new("Part")
		parte.Name = nome
		if formaPeca then
			parte.Shape = formaPeca
		end
		parte.Size = tamanho
		parte.CFrame = cfLocal
		parte.Color = cor
		parte.Material = material or Enum.Material.SmoothPlastic
		parte.Transparency = transparencia or 0
		parte.TopSurface = Enum.SurfaceType.Smooth
		parte.BottomSurface = Enum.SurfaceType.Smooth
		parte.Anchored = false
		parte.CanCollide = false
		parte.CanTouch = false
		parte.CanQuery = false
		parte.Massless = true
		parte.Parent = modelo

		local solda = Instance.new("Weld")
		solda.Name = "Solda"
		solda.Part0 = raiz
		solda.Part1 = parte
		solda.C0 = cfLocal
		solda.C1 = CFrame.new()
		solda.Parent = parte
		return parte
	end

	local function esfera(nome: string, diametro: number, posicao: Vector3, cor: Color3, material: Enum.Material?, transparencia: number?): Part
		return peca(nome, Enum.PartType.Ball, Vector3.new(diametro, diametro, diametro), CFrame.new(posicao), cor, material, transparencia)
	end

	-- Cilindro em pé (eixo vertical), com inclinação opcional (graus) no plano X/Y
	local function cilindro(nome: string, comprimento: number, diametro: number, centro: Vector3, cor: Color3, inclinacao: number?, material: Enum.Material?): Part
		return peca(
			nome,
			Enum.PartType.Cylinder,
			Vector3.new(comprimento, diametro, diametro),
			CFrame.new(centro) * CFrame.Angles(0, 0, math.rad(90 + (inclinacao or 0))),
			cor,
			material
		)
	end

	local detalheIndice = 0
	local function corDetalhe(): Color3
		detalheIndice += 1
		if info.Arcoiris then
			return ARCO_IRIS[((detalheIndice - 1) % #ARCO_IRIS) + 1]
		end
		return info.CorDetalhe
	end
	local materialDetalhe = if raridade.Particulas then Enum.Material.Neon else Enum.Material.SmoothPlastic

	-- Corpo
	local materialCorpo = info.Material or Enum.Material.SmoothPlastic
	local corpo: Part
	if forma == "Bola" then
		corpo = peca("Corpo", Enum.PartType.Ball, Vector3.new(D, D, D), CFrame.new(), info.Cor, materialCorpo, info.Transparencia)
	elseif forma == "Cubo" then
		corpo = peca("Corpo", Enum.PartType.Block, Vector3.new(D, D * 0.9, D), CFrame.new(), info.Cor, materialCorpo, info.Transparencia)
	else
		corpo = peca(
			"Corpo",
			Enum.PartType.Cylinder,
			Vector3.new(D * 1.1, D * 0.9, D * 0.9),
			CFrame.Angles(0, 0, math.rad(90)),
			info.Cor,
			materialCorpo,
			info.Transparencia
		)
	end

	-- Olhos (a frente do monstrinho é -Z)
	local function olho(nome: string, x: number, y: number, tamanho: number)
		local z = frenteZ(forma, x, y) * D
		local centro = Vector3.new(x * D, y * D, z + tamanho * 0.25)
		esfera(nome, tamanho, centro, BRANCO)
		local pupila = tamanho * 0.5
		esfera(nome .. "Pupila", pupila, centro + Vector3.new(0, 0, -(tamanho * 0.5 - pupila * 0.35)), PRETO)
		esfera(nome .. "Brilho", pupila * 0.35, centro + Vector3.new(tamanho * 0.12, tamanho * 0.12, -(tamanho * 0.5 + pupila * 0.05)), BRANCO, Enum.Material.Neon)
	end
	if info.Olhos == 1 then
		olho("Olho", 0, 0.1, D * 0.42)
	elseif info.Olhos == 3 then
		olho("OlhoEsquerdo", -0.22, 0.05, D * 0.22)
		olho("OlhoDireito", 0.22, 0.05, D * 0.22)
		olho("OlhoCentral", 0, 0.27, D * 0.22)
	else
		olho("OlhoEsquerdo", -0.19, 0.1, D * 0.28)
		olho("OlhoDireito", 0.19, 0.1, D * 0.28)
	end

	-- Boca e bochechas
	local zBoca = frenteZ(forma, 0, -0.15) * D
	peca("Boca", nil, Vector3.new(D * 0.26, D * 0.05, D * 0.05), CFrame.new(0, -0.15 * D, zBoca + D * 0.015), COR_BOCA)
	for _, lado in { -1, 1 } do
		local x, y = 0.3 * lado, -0.06
		local zBochecha = frenteZ(forma, x, y) * D
		esfera("Bochecha", D * 0.12, Vector3.new(x * D, y * D, zBochecha + D * 0.03), COR_BOCHECHA, nil, 0.25)
	end

	-- Pés ou tentáculos
	local alturaBase = 0.6 * D
	if temExtra(info, "Tentaculos") then
		local i = 0
		for _, lx in { -1, 1 } do
			for _, lz in { -1, 1 } do
				i += 1
				-- inclinado para a ponta de baixo abrir para fora
				cilindro("Tentaculo" .. i, D * 0.42, D * 0.14, Vector3.new(lx * 0.22 * D, -0.52 * D, lz * 0.14 * D), corDetalhe(), lx * 12)
			end
		end
		alturaBase = 0.74 * D
	else
		for _, lado in { -1, 1 } do
			esfera("Pe", D * 0.3, Vector3.new(lado * 0.2 * D, -0.45 * D, -0.05 * D), corDetalhe())
		end
	end

	local topo = topoY(forma)
	local alturaTopo = topo * D

	if temExtra(info, "Orelhas") then
		for _, lado in { -1, 1 } do
			esfera("Orelha", D * 0.3, Vector3.new(lado * 0.28 * D, topo * 0.92 * D, 0), corDetalhe())
		end
		alturaTopo = math.max(alturaTopo, (topo * 0.92 + 0.15) * D)
	end

	if temExtra(info, "Chifres") then
		local comprimento = 0.42
		for _, lado in { -1, 1 } do
			local inclinacao = 22 * lado
			local direcao = Vector3.new(math.sin(math.rad(inclinacao)), math.cos(math.rad(inclinacao)), 0)
			local base = Vector3.new(lado * 0.22 * D, topo * 0.85 * D, 0)
			cilindro("Chifre", D * comprimento, D * 0.13, base + direcao * (D * comprimento / 2), corDetalhe(), -inclinacao)
		end
		alturaTopo = math.max(alturaTopo, (topo * 0.85 + comprimento) * D)
	end

	if temExtra(info, "Antena") then
		cilindro("Antena", D * 0.5, D * 0.06, Vector3.new(0, (topo + 0.2) * D, 0), PRETO)
		esfera("AntenaPonta", D * 0.18, Vector3.new(0, (topo + 0.47) * D, 0), corDetalhe(), Enum.Material.Neon)
		alturaTopo = math.max(alturaTopo, (topo + 0.56) * D)
	end

	if temExtra(info, "Chapeu") then
		cilindro("Chapeu", D * 0.22, D * 1.25, Vector3.new(0, (topo + 0.03) * D, 0), corDetalhe())
		for i = 1, 3 do
			local angulo = math.rad(120 * i)
			esfera("Pinta", D * 0.14, Vector3.new(math.cos(angulo) * 0.35 * D, (topo + 0.13) * D, math.sin(angulo) * 0.35 * D), BRANCO)
		end
		alturaTopo = math.max(alturaTopo, (topo + 0.2) * D)
	end

	if temExtra(info, "Coroa") then
		local yCoroa = (topo + 0.02) * D
		cilindro("Coroa", D * 0.2, D * 0.56, Vector3.new(0, yCoroa, 0), COR_OURO, 0, Enum.Material.Neon)
		for i = 1, 5 do
			local angulo = math.rad(72 * i)
			peca(
				"CoroaPonta",
				nil,
				Vector3.new(D * 0.1, D * 0.1, D * 0.1),
				CFrame.new(math.cos(angulo) * 0.22 * D, yCoroa + 0.14 * D, math.sin(angulo) * 0.22 * D) * CFrame.Angles(0, 0, math.rad(45)),
				COR_OURO,
				Enum.Material.Neon
			)
		end
		esfera("Joia", D * 0.1, Vector3.new(0, yCoroa, -0.28 * D), Color3.fromRGB(255, 50, 90), Enum.Material.Neon)
		alturaTopo = math.max(alturaTopo, yCoroa + 0.2 * D)
	end

	if temExtra(info, "Aureola") then
		local yAureola = (math.max(topo, alturaTopo / D) + 0.18) * D
		cilindro("Aureola", D * 0.05, D * 0.62, Vector3.new(0, yAureola, 0), Color3.fromRGB(255, 240, 170), 0, Enum.Material.Neon)
		alturaTopo = yAureola + 0.05 * D
	end

	if temExtra(info, "Asas") then
		local lateral = lateralX(forma)
		for _, lado in { -1, 1 } do
			peca(
				"Asa",
				nil,
				Vector3.new(D * 0.06, D * 0.5, D * 0.7),
				CFrame.new(lado * (lateral + 0.12) * D, 0.12 * D, 0.12 * D) * CFrame.Angles(0, 0, math.rad(-25 * lado)),
				corDetalhe(),
				materialDetalhe,
				0.1
			)
		end
	end

	if temExtra(info, "Espinhos") then
		for i, z in { -0.22, 0, 0.22 } do
			local y = topoEmZ(forma, z)
			peca(
				"Espinho" .. i,
				nil,
				Vector3.new(D * 0.18, D * 0.18, D * 0.18),
				CFrame.new(0, y * D, z * D) * CFrame.Angles(0, 0, math.rad(45)),
				corDetalhe()
			)
		end
		alturaTopo = math.max(alturaTopo, (topo + 0.1) * D)
	end

	if temExtra(info, "Cauda") then
		esfera("Cauda", D * 0.24, Vector3.new(0, -0.18 * D, (lateralX(forma) + 0.06) * D), corDetalhe())
	end

	-- Efeitos de raridade
	if raridade.Luz > 0 then
		local luz = Instance.new("PointLight")
		luz.Color = raridade.Cor
		luz.Brightness = raridade.Luz
		luz.Range = 6 + D * 1.5
		luz.Shadows = false
		luz.Parent = corpo
	end
	if raridade.Particulas then
		local particulas = Instance.new("ParticleEmitter")
		particulas.Name = "Faiscas"
		particulas.Color = if raridade.ArcoIris then sequenciaArcoIris() else ColorSequence.new(raridade.Cor)
		particulas.LightEmission = 1
		particulas.Rate = if raridade.ArcoIris then 14 elseif raridade.Estrelas then 9 else 5
		particulas.Lifetime = NumberRange.new(1, 1.8)
		particulas.Speed = NumberRange.new(0.6, 1.6)
		particulas.SpreadAngle = Vector2.new(180, 180)
		particulas.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.12 * D),
			NumberSequenceKeypoint.new(1, 0),
		})
		particulas.Parent = corpo
	end
	if raridade.Estrelas then
		local estrelas = Instance.new("Sparkles")
		estrelas.SparkleColor = raridade.Cor
		estrelas.Parent = corpo
	end
	if raridade.Aura then
		local aura = esfera("Aura", D * 1.4, Vector3.new(0, 0, 0), raridade.Cor, Enum.Material.ForceField)
		aura.CastShadow = false
	end

	-- Placa flutuante: nome, raridade, renda/s e preço
	local gui = Instance.new("BillboardGui")
	gui.Name = "Info"
	gui.Size = UDim2.fromScale(8, 3)
	gui.StudsOffset = Vector3.new(0, alturaTopo + 1.8, 0)
	gui.MaxDistance = 70
	gui.LightInfluence = 0
	gui.Parent = raiz

	local function rotulo(nome: string, texto: string, cor: Color3, y: number, altura: number): TextLabel
		local label = Instance.new("TextLabel")
		label.Name = nome
		label.BackgroundTransparency = 1
		label.Position = UDim2.fromScale(0, y)
		label.Size = UDim2.fromScale(1, altura)
		label.Text = texto
		label.TextColor3 = cor
		label.TextScaled = true
		label.FontFace = Font.fromEnum(Enum.Font.FredokaOne)
		label.TextStrokeColor3 = Color3.new(0, 0, 0)
		label.TextStrokeTransparency = 0.15
		label.Parent = gui
		return label
	end
	rotulo("Nome", info.Nome, BRANCO, 0, 0.32)
	local rotuloRaridade = rotulo("Raridade", raridade.Nome, raridade.Cor, 0.32, 0.24)
	if raridade.ArcoIris then
		rotuloRaridade.TextColor3 = BRANCO
		local gradiente = Instance.new("UIGradient")
		gradiente.Color = sequenciaArcoIris()
		gradiente.Parent = rotuloRaridade
	end
	rotulo("Renda", Formatar.renda(info.Renda), Color3.fromRGB(110, 240, 120), 0.56, 0.22)
	rotulo("Preco", "💰 " .. Formatar.dinheiro(info.Preco), Color3.fromRGB(255, 220, 80), 0.78, 0.22)

	modelo:SetAttribute("AlturaBase", alturaBase)
	modelo:SetAttribute("AlturaTopo", alturaTopo)
	return modelo, raiz
end

return MonstrinhoModelo
