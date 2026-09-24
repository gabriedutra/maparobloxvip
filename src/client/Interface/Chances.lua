--[[
	Chances.lua
	Janela "Chances da Esteira": a chance (%) de cada raridade e de cada
	monstrinho aparecer na esteira, sem e com a Sorte na Esteira (Developer
	Product "SorteBoost").

	O Roblox exige que itens pagos que mudam chances (boosts de sorte)
	mostrem o efeito em números ANTES da compra e que as chances mostradas
	acompanhem o boost enquanto ele estiver ativo. Por isso:
	  • o botão "Comprar" da Sorte (loja) abre esta janela, com a compra embaixo;
	  • a coluna que vale no momento fica marcada e a janela se atualiza sozinha.
	As porcentagens vêm do Catalogo.lua, a mesma conta do sorteio do servidor.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalogo = require(Shared:WaitForChild("Catalogo"))
local Config = require(Shared:WaitForChild("Config"))
local Formatar = require(Shared:WaitForChild("Formatar"))
local UI = require(script.Parent.UI)

local Chances = {}

local COR_APAGADA = Color3.fromRGB(150, 150, 170)

local jogador = Players.LocalPlayer
local janela: Frame? = nil
local atualizar: (() -> ())? = nil
local mostrarCompra: ((idProduto: number?) -> ())? = nil

-- Segundos de sorte que ainda faltam na esteira (0 = sem sorte)
local function sorteRestante(): number
	local sorteAte = Workspace:GetAttribute("SorteAte")
	if type(sorteAte) ~= "number" then
		return 0
	end
	return math.max(0, sorteAte - Workspace:GetServerTimeNow())
end

-- 600 -> "10 min"; 90 -> "1:30"
local function textoDuracao(segundos: number): string
	if segundos % 60 == 0 then
		return math.floor(segundos / 60) .. " min"
	end
	return Formatar.tempo(segundos)
end

-- "Cada um: 11% normal · 6,8536% com sorte — Bolotinha, Fofucho, ..."
-- (monstrinho por monstrinho se os Pesos forem diferentes)
local function textoMonstrinhos(opcoes: { Catalogo.Monstrinho }, normal: { [string]: number }, comSorte: { [string]: number }): string
	local mesmoPeso = true
	for _, m in opcoes do
		if (m.Peso or 1) ~= (opcoes[1].Peso or 1) then
			mesmoPeso = false
		end
	end
	if mesmoPeso and #opcoes > 1 then
		local nomes = {}
		for _, m in opcoes do
			table.insert(nomes, m.Nome)
		end
		local primeiro = opcoes[1].Id
		return "Cada um: "
			.. Formatar.chance(normal[primeiro])
			.. " normal · "
			.. Formatar.chance(comSorte[primeiro])
			.. " com sorte — "
			.. table.concat(nomes, ", ")
	end
	local partes = {}
	for _, m in opcoes do
		table.insert(partes, m.Nome .. ": " .. Formatar.chance(normal[m.Id]) .. " normal / " .. Formatar.chance(comSorte[m.Id]) .. " com sorte")
	end
	return table.concat(partes, " · ")
end

-- Abre a janela. Com o ID da Sorte na Esteira, mostra o botão de compra embaixo da tabela.
function Chances.abrir(idProduto: number?)
	if not janela then
		return
	end
	if mostrarCompra then
		mostrarCompra(idProduto)
	end
	if atualizar then
		atualizar()
	end
	janela.Visible = true
end

function Chances.fechar()
	if janela then
		janela.Visible = false
	end
end

function Chances.alternar()
	if janela and janela.Visible then
		Chances.fechar()
	else
		Chances.abrir()
	end
end

function Chances.iniciar(tela: ScreenGui)
	local fundo: Frame = UI.criar("Frame", {
		Name = "Chances",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(720, 500),
		BackgroundColor3 = UI.Cores.Fundo,
		BackgroundTransparency = 0.04,
		Visible = false,
		ZIndex = 20, -- por cima da loja
		Parent = tela,
	})
	UI.cantos(fundo, 18)
	UI.borda(fundo, UI.Cores.Chances, 3)
	UI.escalaAutomatica(fundo)

	UI.texto({
		Name = "Titulo",
		Position = UDim2.fromOffset(20, 12),
		Size = UDim2.new(1, -100, 0, 46),
		Text = "🎲 Chances da Esteira",
		TextColor3 = UI.Cores.Chances,
		TextXAlignment = Enum.TextXAlignment.Left,
		TamanhoMaximo = 40,
		Parent = fundo,
	})
	local fechar = UI.botao({
		Name = "Fechar",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 12),
		Size = UDim2.fromOffset(48, 48),
		Text = "✖",
		BackgroundColor3 = UI.Cores.Erro,
		Parent = fundo,
	})
	fechar.Activated:Connect(Chances.fechar)

	local estado = UI.texto({
		Name = "Estado",
		Position = UDim2.fromOffset(20, 62),
		Size = UDim2.new(1, -40, 0, 32),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		TamanhoMaximo = 19,
		Parent = fundo,
	})

	-- Cabeçalho (mesma largura das linhas da lista, que têm 12 px de folga para a barra de rolagem)
	local cabecalho: Frame = UI.criar("Frame", {
		Name = "Cabecalho",
		Position = UDim2.fromOffset(14, 100),
		Size = UDim2.new(1, -40, 0, 28),
		BackgroundTransparency = 1,
		Parent = fundo,
	})
	UI.texto({
		Name = "Raridade",
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.new(0.4, -12, 1, 0),
		Text = "Raridade",
		TextColor3 = UI.Cores.TextoSuave,
		TextXAlignment = Enum.TextXAlignment.Left,
		TamanhoMaximo = 20,
		Parent = cabecalho,
	})
	local cabecalhoNormal = UI.texto({
		Name = "Normal",
		Position = UDim2.fromScale(0.4, 0),
		Size = UDim2.fromScale(0.3, 1),
		Text = "Normal",
		TamanhoMaximo = 20,
		Parent = cabecalho,
	})
	local cabecalhoSorte = UI.texto({
		Name = "ComSorte",
		Position = UDim2.fromScale(0.7, 0),
		Size = UDim2.new(0.3, -12, 1, 0),
		Text = "Com Sorte 🍀",
		TamanhoMaximo = 20,
		Parent = cabecalho,
	})

	local lista: ScrollingFrame = UI.criar("ScrollingFrame", {
		Name = "Lista",
		Position = UDim2.fromOffset(14, 132),
		Size = UDim2.new(1, -28, 1, -180),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = fundo,
	})
	UI.criar("UIListLayout", {
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = lista,
	})
	UI.criar("UIPadding", { PaddingRight = UDim.new(0, 12), Parent = lista })

	-- Uma linha por raridade, com os monstrinhos dela embaixo
	local normal = Catalogo.chances(nil)
	local comSorte = Catalogo.chances(Config.Sorte.Multiplicadores)
	local normalMonstrinhos = Catalogo.chancesMonstrinhos(nil)
	local sorteMonstrinhos = Catalogo.chancesMonstrinhos(Config.Sorte.Multiplicadores)
	local celulasNormal: { TextLabel } = {}
	local celulasSorte: { TextLabel } = {}

	for ordem, raridade in Catalogo.Raridades do
		local opcoes = Catalogo.PorRaridade[raridade.Id]
		if #opcoes == 0 then
			continue -- raridade sem monstrinhos nunca aparece
		end
		local linha: Frame = UI.criar("Frame", {
			Name = raridade.Id,
			Size = UDim2.new(1, 0, 0, 76),
			BackgroundColor3 = UI.Cores.FundoClaro,
			LayoutOrder = ordem,
			Parent = lista,
		})
		UI.cantos(linha, 12)
		UI.borda(linha, raridade.Cor, 2, 0.3)
		UI.texto({
			Name = "Nome",
			Position = UDim2.fromOffset(12, 6),
			Size = UDim2.new(0.4, -12, 0, 30),
			Text = raridade.Nome,
			TextColor3 = raridade.Cor,
			TextXAlignment = Enum.TextXAlignment.Left,
			TamanhoMaximo = 24,
			Parent = linha,
		})
		table.insert(
			celulasNormal,
			UI.texto({
				Name = "Normal",
				Position = UDim2.new(0.4, 0, 0, 6),
				Size = UDim2.new(0.3, 0, 0, 30),
				Text = Formatar.chance(normal[raridade.Id]),
				TamanhoMaximo = 24,
				Parent = linha,
			})
		)
		table.insert(
			celulasSorte,
			UI.texto({
				Name = "ComSorte",
				Position = UDim2.new(0.7, 0, 0, 6),
				Size = UDim2.new(0.3, -12, 0, 30),
				Text = Formatar.chance(comSorte[raridade.Id]),
				TamanhoMaximo = 24,
				Parent = linha,
			})
		)
		UI.texto({
			Name = "Monstrinhos",
			Position = UDim2.fromOffset(12, 38),
			Size = UDim2.new(1, -24, 0, 32),
			Text = textoMonstrinhos(opcoes, normalMonstrinhos, sorteMonstrinhos),
			TextColor3 = UI.Cores.TextoSuave,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextWrapped = true,
			TextStrokeTransparency = 1,
			TamanhoMaximo = 15,
			Parent = linha,
		})
	end

	local rodape = UI.texto({
		Name = "Rodape",
		Position = UDim2.new(0, 20, 1, -44),
		Size = UDim2.new(1, -40, 0, 36),
		Text = "Chance de cada monstrinho que aparece na esteira. Cada compra da Sorte soma "
			.. textoDuracao(Config.Sorte.Duracao)
			.. " para o servidor todo. Porcentagens arredondadas: a soma pode não dar exatamente 100%.",
		TextColor3 = UI.Cores.TextoSuave,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		TextStrokeTransparency = 1,
		TamanhoMaximo = 14,
		Parent = fundo,
	})

	-- Compra da Sorte (só aparece quando a janela foi aberta pelo botão Comprar da loja)
	local comprar = UI.botao({
		Name = "Comprar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.fromOffset(380, 48),
		Text = "🍀 Comprar Sorte na Esteira",
		BackgroundColor3 = UI.Cores.Sucesso,
		Visible = false,
		Parent = fundo,
	})
	local idCompra: number? = nil
	comprar.Activated:Connect(function()
		if idCompra and idCompra > 0 then
			MarketplaceService:PromptProductPurchase(jogador, idCompra)
		end
	end)

	mostrarCompra = function(idProduto: number?)
		idCompra = idProduto
		local comBotao = idProduto ~= nil and idProduto > 0
		comprar.Visible = comBotao
		lista.Size = UDim2.new(1, -28, 1, if comBotao then -236 else -180)
		rodape.Position = UDim2.new(0, 20, 1, if comBotao then -100 else -44)
	end

	-- Destaca a coluna que vale agora (muda sozinho quando alguém compra a Sorte ou ela acaba)
	local function atualizarJanela()
		local restante = sorteRestante()
		local ativa = restante > 0
		if ativa then
			estado.Text = "🍀 Sorte ativa! Agora valem as chances COM SORTE (acaba em " .. Formatar.tempo(restante) .. ")."
			estado.TextColor3 = UI.Cores.Renda
		else
			estado.Text = "Agora valem as chances NORMAIS. Com a Sorte na Esteira, valem as da coluna Com Sorte por "
				.. textoDuracao(Config.Sorte.Duracao)
				.. "."
			estado.TextColor3 = UI.Cores.Texto
		end
		cabecalhoNormal.Text = if ativa then "Normal" else "✅ Normal (agora)"
		cabecalhoSorte.Text = if ativa then "✅ Com Sorte 🍀 (agora)" else "Com Sorte 🍀"
		cabecalhoNormal.TextColor3 = if ativa then COR_APAGADA else UI.Cores.Texto
		cabecalhoSorte.TextColor3 = if ativa then UI.Cores.Renda else UI.Cores.Chances
		for _, celula in celulasNormal do
			celula.TextColor3 = if ativa then COR_APAGADA else UI.Cores.Texto
		end
		for _, celula in celulasSorte do
			celula.TextColor3 = if ativa then UI.Cores.Renda else COR_APAGADA
		end
	end
	atualizar = atualizarJanela

	Workspace:GetAttributeChangedSignal("SorteAte"):Connect(function()
		if fundo.Visible then
			atualizarJanela()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.5)
			if fundo.Visible then
				atualizarJanela()
			end
		end
	end)

	janela = fundo
	atualizarJanela()
end

return Chances
