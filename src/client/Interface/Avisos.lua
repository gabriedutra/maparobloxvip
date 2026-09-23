--[[
	Avisos.lua
	Mensagens na tela:
	  • notificações pequenas (embaixo) vindas do servidor (RemoteEvent Notificacao);
	  • avisos grandes (em cima) para o servidor inteiro — Lendário/Mítico na
	    esteira, sorte ativada... (RemoteEvent AvisoGlobal). Também vão para o chat.
	O tipo "dinheiro" é mostrado pelo HUD (texto "+$" subindo), não aqui.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local TweenService = game:GetService("TweenService")

local Remotos = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotos"))
local UI = require(script.Parent.UI)

local Avisos = {}

local MAXIMO_NOTIFICACOES = 5
local DURACAO_NOTIFICACAO = 3.5
local DURACAO_AVISO = 5

local CORES_TIPO: { [string]: Color3 } = {
	sucesso = UI.Cores.Sucesso,
	erro = UI.Cores.Erro,
	info = UI.Cores.Info,
	alerta = UI.Cores.Alerta,
}

local listaNotificacoes: Frame? = nil
local areaAviso: Frame? = nil
local filaAvisos: { { Titulo: string, Texto: string, Cor: Color3 } } = {}
local mostrandoAviso = false
local contadorNotificacoes = 0

-- Notificação pequena (some sozinha)
function Avisos.notificar(texto: string, tipo: string?)
	local lista = listaNotificacoes
	if not lista then
		return
	end
	local cor = CORES_TIPO[tipo or "info"] or UI.Cores.Info

	-- Remove as mais antigas se tiver muitas
	local existentes = {}
	for _, filho in lista:GetChildren() do
		if filho:IsA("Frame") then
			table.insert(existentes, filho)
		end
	end
	table.sort(existentes, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	while #existentes >= MAXIMO_NOTIFICACOES do
		local maisAntiga = table.remove(existentes, 1)
		if maisAntiga then
			maisAntiga:Destroy()
		end
	end

	contadorNotificacoes += 1
	local cartao: Frame = UI.criar("Frame", {
		Name = "Notificacao",
		BackgroundColor3 = cor,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 40),
		LayoutOrder = contadorNotificacoes,
		Parent = lista,
	})
	UI.cantos(cartao, 10)
	local rotulo = UI.texto({
		Size = UDim2.new(1, -16, 1, -8),
		Position = UDim2.fromOffset(8, 4),
		Text = texto,
		TextTransparency = 1,
		TextStrokeTransparency = 1,
		TamanhoMaximo = 22,
		Parent = cartao,
	})

	local entrada = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(cartao, entrada, { BackgroundTransparency = 0.1 }):Play()
	TweenService:Create(rotulo, entrada, { TextTransparency = 0, TextStrokeTransparency = 0.6 }):Play()

	task.delay(DURACAO_NOTIFICACAO, function()
		if cartao.Parent == nil then
			return
		end
		local saida = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(cartao, saida, { BackgroundTransparency = 1 }):Play()
		local tween = TweenService:Create(rotulo, saida, { TextTransparency = 1, TextStrokeTransparency = 1 })
		tween:Play()
		tween.Completed:Wait()
		cartao:Destroy()
	end)
end

-- Mensagem de sistema no chat (TextChatService)
local function mensagemNoChat(texto: string, cor: Color3)
	task.spawn(function()
		local canais = TextChatService:FindFirstChild("TextChannels")
		local geral = canais and canais:FindFirstChild("RBXGeneral")
		if geral and geral:IsA("TextChannel") then
			pcall(function()
				geral:DisplaySystemMessage('<font color="#' .. cor:ToHex() .. '">' .. texto .. "</font>")
			end)
		end
	end)
end

local function mostrarProximoAviso()
	local area = areaAviso
	if mostrandoAviso or not area or #filaAvisos == 0 then
		return
	end
	mostrandoAviso = true
	local dados = table.remove(filaAvisos, 1) :: { Titulo: string, Texto: string, Cor: Color3 }

	local cartao: Frame = UI.criar("Frame", {
		Name = "Aviso",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, -130),
		Size = UDim2.new(1, 0, 0, 104),
		BackgroundColor3 = UI.Cores.Fundo,
		BackgroundTransparency = 0.1,
		Parent = area,
	})
	UI.cantos(cartao, 16)
	UI.borda(cartao, dados.Cor, 3)
	UI.texto({
		Size = UDim2.new(1, -24, 0, 50),
		Position = UDim2.fromOffset(12, 8),
		Text = dados.Titulo,
		TextColor3 = dados.Cor,
		TextStrokeTransparency = 0.2,
		TamanhoMaximo = 40,
		Parent = cartao,
	})
	UI.texto({
		Size = UDim2.new(1, -24, 0, 34),
		Position = UDim2.fromOffset(12, 60),
		Text = dados.Texto,
		TamanhoMaximo = 24,
		Parent = cartao,
	})

	local entrada = TweenService:Create(
		cartao,
		TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0.5, 0, 0, 0) }
	)
	entrada:Play()
	task.delay(DURACAO_AVISO, function()
		local saida = TweenService:Create(
			cartao,
			TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Position = UDim2.new(0.5, 0, 0, -130) }
		)
		saida:Play()
		saida.Completed:Wait()
		cartao:Destroy()
		mostrandoAviso = false
		mostrarProximoAviso()
	end)
end

-- Aviso grande para o servidor inteiro
function Avisos.aviso(titulo: string, texto: string, cor: Color3)
	table.insert(filaAvisos, { Titulo = titulo, Texto = texto, Cor = cor })
	mensagemNoChat(titulo .. " " .. texto, cor)
	mostrarProximoAviso()
end

function Avisos.iniciar(tela: ScreenGui)
	local lista: Frame = UI.criar("Frame", {
		Name = "Notificacoes",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -20),
		Size = UDim2.fromOffset(560, 260),
		BackgroundTransparency = 1,
		Parent = tela,
	})
	UI.criar("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 6),
		Parent = lista,
	})
	UI.escalaAutomatica(lista)
	listaNotificacoes = lista

	local area: Frame = UI.criar("Frame", {
		Name = "Avisos",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 132), -- abaixo dos indicadores do HUD
		Size = UDim2.fromOffset(620, 110),
		BackgroundTransparency = 1,
		ClipsDescendants = false,
		Parent = tela,
	})
	UI.escalaAutomatica(area)
	areaAviso = area

	Remotos.Notificacao.OnClientEvent:Connect(function(texto: any, tipo: any)
		if type(texto) ~= "string" then
			return
		end
		if tipo == "dinheiro" then
			return -- o HUD mostra
		end
		Avisos.notificar(texto, if type(tipo) == "string" then tipo else "info")
	end)

	Remotos.AvisoGlobal.OnClientEvent:Connect(function(dados: any)
		if type(dados) ~= "table" or type(dados.Titulo) ~= "string" or type(dados.Texto) ~= "string" then
			return
		end
		local cor = if typeof(dados.Cor) == "Color3" then dados.Cor else UI.Cores.Alerta
		Avisos.aviso(dados.Titulo, dados.Texto, cor)
	end)
end

return Avisos
