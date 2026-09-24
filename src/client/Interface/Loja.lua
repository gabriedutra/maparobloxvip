--[[
	Loja.lua
	Janela da loja com os Game Passes e Developer Products do Config.lua.
	O cliente só abre a janela de compra do Roblox; quem entrega o item é o
	servidor (Passes.lua e Produtos.lua / ProcessReceipt).
	A Sorte na Esteira mostra antes a janela de chances (Chances.lua), como o
	Roblox exige para itens pagos que mexem na sorte.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Avisos = require(script.Parent.Avisos)
local Chances = require(script.Parent.Chances)
local UI = require(script.Parent.UI)

local Loja = {}

type ItemLoja = { Chave: string, Nome: string, Emoji: string, Descricao: string, Cor: Color3 }
type TipoItem = "GamePass" | "Produto"

local jogador = Players.LocalPlayer
local janela: Frame? = nil

local function idDoItem(item: ItemLoja, tipo: TipoItem): number
	local tabela = (if tipo == "GamePass" then Config.GamePasses else Config.Produtos) :: { [string]: number }
	local id = tabela[item.Chave]
	return if type(id) == "number" then id else 0
end

local function criarCartao(pai: Instance, item: ItemLoja, tipo: TipoItem, ordem: number)
	local id = idDoItem(item, tipo)
	local configurado = id > 0

	local cartao: Frame = UI.criar("Frame", {
		Name = item.Chave,
		BackgroundColor3 = UI.Cores.FundoClaro,
		LayoutOrder = ordem,
		Parent = pai,
	})
	UI.cantos(cartao, 14)
	UI.borda(cartao, item.Cor, 2, 0.2)

	UI.texto({
		Name = "Icone",
		Position = UDim2.fromOffset(10, 10),
		Size = UDim2.fromOffset(56, 56),
		Text = item.Emoji,
		TamanhoMaximo = 48,
		Parent = cartao,
	})
	UI.texto({
		Name = "Nome",
		Position = UDim2.fromOffset(74, 10),
		Size = UDim2.new(1, -84, 0, 28),
		Text = item.Nome,
		TextColor3 = item.Cor,
		TextXAlignment = Enum.TextXAlignment.Left,
		TamanhoMaximo = 26,
		Parent = cartao,
	})
	UI.texto({
		Name = "Descricao",
		Position = UDim2.fromOffset(74, 40),
		Size = UDim2.new(1, -84, 0, 48),
		Text = item.Descricao,
		TextColor3 = UI.Cores.TextoSuave,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		TextStrokeTransparency = 1,
		TamanhoMaximo = 17,
		Parent = cartao,
	})
	local preco = UI.texto({
		Name = "Preco",
		Position = UDim2.new(0, 12, 1, -48),
		Size = UDim2.new(0.5, -16, 0, 38),
		Text = if configurado then "..." else "—",
		TextColor3 = UI.Cores.Dinheiro,
		TextXAlignment = Enum.TextXAlignment.Left,
		TamanhoMaximo = 22,
		Parent = cartao,
	})
	local botao = UI.botao({
		Name = "Comprar",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -10, 1, -10),
		Size = UDim2.new(0.5, -10, 0, 40),
		Text = "Comprar",
		BackgroundColor3 = UI.Cores.Sucesso,
		TamanhoMaximo = 22,
		Parent = cartao,
	})

	local function jaPossui(): boolean
		return tipo == "GamePass" and jogador:GetAttribute("Pass_" .. item.Chave) == true
	end

	local function atualizar()
		if not configurado then
			botao.Text = "Em breve"
			botao.BackgroundColor3 = UI.Cores.Desativado
		elseif jaPossui() then
			botao.Text = "✔ Comprado"
			botao.BackgroundColor3 = UI.Cores.Desativado
		else
			botao.Text = "Comprar"
			botao.BackgroundColor3 = UI.Cores.Sucesso
		end
	end
	if tipo == "GamePass" then
		jogador:GetAttributeChangedSignal("Pass_" .. item.Chave):Connect(atualizar)
	end
	atualizar()

	-- Preço em Robux (buscado no Roblox)
	if configurado then
		task.spawn(function()
			local ok, informacao = pcall(function()
				return MarketplaceService:GetProductInfo(id, if tipo == "GamePass" then Enum.InfoType.GamePass else Enum.InfoType.Product)
			end)
			if ok and type(informacao) == "table" and type(informacao.PriceInRobux) == "number" then
				preco.Text = informacao.PriceInRobux .. " Robux"
			else
				preco.Text = "Robux"
			end
		end)
	end

	botao.Activated:Connect(function()
		if not configurado then
			Avisos.notificar("Este item ainda não foi configurado (Config.lua).", "info")
			return
		end
		if tipo == "GamePass" then
			if jaPossui() then
				Avisos.notificar("Você já tem este Game Pass!", "info")
				return
			end
			MarketplaceService:PromptGamePassPurchase(jogador, id)
		elseif item.Chave == "SorteBoost" then
			Chances.abrir(id) -- mostra as chances; a compra fica embaixo da tabela
		else
			MarketplaceService:PromptProductPurchase(jogador, id)
		end
	end)
end

function Loja.abrir()
	if janela then
		janela.Visible = true
	end
end

function Loja.fechar()
	if janela then
		janela.Visible = false
	end
end

function Loja.alternar()
	if janela then
		janela.Visible = not janela.Visible
	end
end

function Loja.iniciar(tela: ScreenGui)
	local fundo: Frame = UI.criar("Frame", {
		Name = "Loja",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(720, 500),
		BackgroundColor3 = UI.Cores.Fundo,
		BackgroundTransparency = 0.04,
		Visible = false,
		ZIndex = 10,
		Parent = tela,
	})
	UI.cantos(fundo, 18)
	UI.borda(fundo, UI.Cores.Dinheiro, 3)
	UI.escalaAutomatica(fundo)

	UI.texto({
		Name = "Titulo",
		Position = UDim2.fromOffset(20, 12),
		Size = UDim2.new(1, -100, 0, 46),
		Text = "🛒 Loja",
		TextColor3 = UI.Cores.Dinheiro,
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
	fechar.Activated:Connect(Loja.fechar)

	local rolagem: ScrollingFrame = UI.criar("ScrollingFrame", {
		Name = "Itens",
		Position = UDim2.fromOffset(14, 68),
		Size = UDim2.new(1, -28, 1, -82),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = fundo,
	})
	UI.criar("UIListLayout", {
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = rolagem,
	})
	UI.criar("UIPadding", { PaddingRight = UDim.new(0, 12), Parent = rolagem })

	local function secao(titulo: string, ordem: number, itens: { ItemLoja }, tipo: TipoItem)
		UI.texto({
			Name = "Secao" .. tipo,
			Size = UDim2.new(1, 0, 0, 34),
			Text = titulo,
			TextXAlignment = Enum.TextXAlignment.Left,
			TamanhoMaximo = 28,
			LayoutOrder = ordem,
			Parent = rolagem,
		})
		local grade: Frame = UI.criar("Frame", {
			Name = "Grade" .. tipo,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			LayoutOrder = ordem + 1,
			Parent = rolagem,
		})
		UI.criar("UIGridLayout", {
			CellSize = UDim2.new(0.5, -6, 0, 150),
			CellPadding = UDim2.fromOffset(12, 12),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = grade,
		})
		for indice, item in itens do
			criarCartao(grade, item, tipo, indice)
		end
	end

	secao("⭐ Game Passes (para sempre)", 1, Config.Loja.GamePasses, "GamePass")
	secao("🎁 Produtos (compre quantas vezes quiser)", 3, Config.Loja.Produtos, "Produto")

	janela = fundo
end

return Loja
