--[[
	UI.lua
	Funções auxiliares para montar a interface: criar instâncias, cantos
	arredondados, bordas, botões com animação e escala automática para
	telas pequenas (celular) e grandes.
]]

local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local UI = {}

UI.Fonte = Enum.Font.FredokaOne

UI.Cores = {
	Fundo = Color3.fromRGB(24, 22, 40),
	FundoClaro = Color3.fromRGB(42, 38, 68),
	Texto = Color3.fromRGB(255, 255, 255),
	TextoSuave = Color3.fromRGB(205, 205, 225),
	Dinheiro = Color3.fromRGB(255, 214, 70),
	Renda = Color3.fromRGB(110, 235, 120),
	Multiplicador = Color3.fromRGB(125, 200, 255),
	Rebirth = Color3.fromRGB(205, 150, 255),
	Loja = Color3.fromRGB(60, 140, 255),
	Trancar = Color3.fromRGB(235, 70, 80),
	Renascer = Color3.fromRGB(165, 90, 255),
	Desativado = Color3.fromRGB(95, 95, 115),
	Sucesso = Color3.fromRGB(60, 190, 95),
	Erro = Color3.fromRGB(225, 65, 75),
	Info = Color3.fromRGB(65, 135, 235),
	Alerta = Color3.fromRGB(240, 150, 35),
}

-- Cria uma instância com propriedades e filhos. "Parent" é aplicado por último.
function UI.criar(classe: string, propriedades: { [string]: any }?, filhos: { Instance }?): any
	local instancia = Instance.new(classe)
	local pai: Instance? = nil
	if propriedades then
		for chave, valor in propriedades do
			if chave == "Parent" then
				pai = valor
			else
				(instancia :: any)[chave] = valor
			end
		end
	end
	if filhos then
		for _, filho in filhos do
			filho.Parent = instancia
		end
	end
	if pai then
		instancia.Parent = pai
	end
	return instancia
end

function UI.cantos(pai: Instance, raio: number?): UICorner
	return UI.criar("UICorner", { CornerRadius = UDim.new(0, raio or 12), Parent = pai })
end

function UI.borda(pai: Instance, cor: Color3, espessura: number?, transparencia: number?): UIStroke
	return UI.criar("UIStroke", {
		Color = cor,
		Thickness = espessura or 2,
		Transparency = transparencia or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = pai,
	})
end

function UI.espacamento(pai: Instance, pixels: number)
	UI.criar("UIPadding", {
		PaddingTop = UDim.new(0, pixels),
		PaddingBottom = UDim.new(0, pixels),
		PaddingLeft = UDim.new(0, pixels),
		PaddingRight = UDim.new(0, pixels),
		Parent = pai,
	})
end

-- Texto com contorno (legível sobre qualquer fundo)
function UI.texto(propriedades: { [string]: any }): TextLabel
	local padrao: { [string]: any } = {
		BackgroundTransparency = 1,
		Font = UI.Fonte,
		TextColor3 = UI.Cores.Texto,
		TextScaled = true,
		TextStrokeTransparency = 0.4,
		TextStrokeColor3 = Color3.new(0, 0, 0),
		TextXAlignment = Enum.TextXAlignment.Center,
	}
	for chave, valor in propriedades do
		if chave ~= "TamanhoMaximo" then
			padrao[chave] = valor
		end
	end
	local rotulo = UI.criar("TextLabel", padrao)
	UI.criar("UITextSizeConstraint", { MaxTextSize = propriedades.TamanhoMaximo or 40, Parent = rotulo })
	return rotulo
end

-- Botão colorido com cantos arredondados e animação ao passar o mouse / clicar
function UI.botao(propriedades: { [string]: any }): TextButton
	local cor = propriedades.BackgroundColor3 or UI.Cores.Loja
	local padrao: { [string]: any } = {
		AutoButtonColor = false,
		BackgroundColor3 = cor,
		Font = UI.Fonte,
		TextColor3 = UI.Cores.Texto,
		TextScaled = true,
		TextStrokeTransparency = 0.5,
		TextStrokeColor3 = Color3.new(0, 0, 0),
	}
	for chave, valor in propriedades do
		if chave ~= "TamanhoMaximo" then
			padrao[chave] = valor
		end
	end
	local botao: TextButton = UI.criar("TextButton", padrao)
	UI.cantos(botao, 12)
	UI.borda(botao, Color3.new(1, 1, 1), 2, 0.75)
	UI.criar("UITextSizeConstraint", { MaxTextSize = propriedades.TamanhoMaximo or 26, Parent = botao })
	local escala: UIScale = UI.criar("UIScale", { Parent = botao })

	local info = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	botao.MouseEnter:Connect(function()
		TweenService:Create(escala, info, { Scale = 1.05 }):Play()
	end)
	botao.MouseLeave:Connect(function()
		TweenService:Create(escala, info, { Scale = 1 }):Play()
	end)
	botao.MouseButton1Down:Connect(function()
		TweenService:Create(escala, info, { Scale = 0.94 }):Play()
	end)
	botao.MouseButton1Up:Connect(function()
		TweenService:Create(escala, info, { Scale = 1 }):Play()
	end)
	return botao
end

-- Pulsinho de destaque (ex.: quando o dinheiro muda)
function UI.pulsar(objeto: GuiObject)
	local escala = (objeto:FindFirstChild("Pulso") :: UIScale?) or UI.criar("UIScale", { Name = "Pulso", Parent = objeto })
	escala.Scale = 1.12
	TweenService:Create(escala, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

-- Escala automática: 1280x720 = 100%; celulares ficam menores, telas grandes maiores
local escalas: { UIScale } = {}

local function calcularEscala(): number
	local camera = Workspace.CurrentCamera
	if not camera then
		return 1
	end
	local tamanho = camera.ViewportSize
	return math.clamp(math.min(tamanho.X / 1280, tamanho.Y / 720), 0.55, 1.3)
end

local function atualizarEscalas()
	local valor = calcularEscala()
	for _, escala in escalas do
		escala.Scale = valor
	end
end

function UI.escalaAutomatica(objeto: GuiObject)
	local escala: UIScale = UI.criar("UIScale", { Name = "EscalaTela", Parent = objeto })
	table.insert(escalas, escala)
	escala.Scale = calcularEscala()
end

local function conectarCamera()
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(atualizarEscalas)
	end
	atualizarEscalas()
end
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(conectarCamera)
conectarCamera()

return UI
