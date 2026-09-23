--[[
	HUD.lua
	Interface principal:
	  • painel com dinheiro, renda por segundo, multiplicador e rebirths;
	  • botões: Loja, Trancar Base (com contagem) e Renascer (com confirmação);
	  • indicadores no topo: sorte ativa, carregando monstrinho, carregando dados;
	  • marcador "SUA BASE" em cima da sua base.

	Os valores vêm dos atributos do Player, que só o servidor altera.
	Os botões apenas PEDEM ações ao servidor (RemoteEvents).
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Formatar = require(Shared:WaitForChild("Formatar"))
local Regras = require(Shared:WaitForChild("Regras"))
local Remotos = require(Shared:WaitForChild("Remotos"))
local Avisos = require(script.Parent.Avisos)
local UI = require(script.Parent.UI)

local HUD = {}

local jogador = Players.LocalPlayer

local function numeroAtributo(nome: string, padrao: number): number
	local valor = jogador:GetAttribute(nome)
	return if type(valor) == "number" then valor else padrao
end

local function pilula(pai: Instance, nome: string, cor: Color3, ordem: number): (Frame, TextLabel)
	local quadro: Frame = UI.criar("Frame", {
		Name = nome,
		Size = UDim2.fromOffset(460, 34),
		BackgroundColor3 = cor,
		BackgroundTransparency = 0.1,
		Visible = false,
		LayoutOrder = ordem,
		Parent = pai,
	})
	UI.cantos(quadro, 17)
	local texto = UI.texto({
		Size = UDim2.new(1, -20, 1, -6),
		Position = UDim2.fromOffset(10, 3),
		Text = "",
		TamanhoMaximo = 24,
		Parent = quadro,
	})
	return quadro, texto
end

function HUD.iniciar(tela: ScreenGui, acoes: { abrirLoja: () -> () })
	-- --------------------------------------------------------
	-- Painel de status (canto superior esquerdo)
	-- --------------------------------------------------------
	local painel: Frame = UI.criar("Frame", {
		Name = "Status",
		Position = UDim2.fromOffset(14, 14),
		Size = UDim2.fromOffset(290, 150),
		BackgroundColor3 = UI.Cores.Fundo,
		BackgroundTransparency = 0.15,
		Parent = tela,
	})
	UI.cantos(painel, 16)
	UI.borda(painel, Color3.new(1, 1, 1), 2, 0.8)
	UI.escalaAutomatica(painel)

	local textoDinheiro = UI.texto({
		Name = "Dinheiro",
		Position = UDim2.fromOffset(12, 8),
		Size = UDim2.new(1, -24, 0, 50),
		Text = "💰 $0",
		TextColor3 = UI.Cores.Dinheiro,
		TextXAlignment = Enum.TextXAlignment.Left,
		TamanhoMaximo = 44,
		Parent = painel,
	})
	local textoRenda = UI.texto({
		Name = "Renda",
		Position = UDim2.fromOffset(12, 60),
		Size = UDim2.new(1, -24, 0, 32),
		Text = "📈 $0/s",
		TextColor3 = UI.Cores.Renda,
		TextXAlignment = Enum.TextXAlignment.Left,
		TamanhoMaximo = 28,
		Parent = painel,
	})
	local textoMultiplicador = UI.texto({
		Name = "Multiplicador",
		Position = UDim2.fromOffset(12, 94),
		Size = UDim2.new(1, -24, 0, 24),
		Text = "✖️ Multiplicador x1",
		TextColor3 = UI.Cores.Multiplicador,
		TextXAlignment = Enum.TextXAlignment.Left,
		TamanhoMaximo = 22,
		Parent = painel,
	})
	local textoRebirths = UI.texto({
		Name = "Rebirths",
		Position = UDim2.fromOffset(12, 120),
		Size = UDim2.new(1, -24, 0, 24),
		Text = "♻️ Rebirths: 0",
		TextColor3 = UI.Cores.Rebirth,
		TextXAlignment = Enum.TextXAlignment.Left,
		TamanhoMaximo = 22,
		Parent = painel,
	})

	-- --------------------------------------------------------
	-- Botões (lado esquerdo)
	-- --------------------------------------------------------
	local coluna: Frame = UI.criar("Frame", {
		Name = "Botoes",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 14, 0.5, 20),
		Size = UDim2.fromOffset(190, 200),
		BackgroundTransparency = 1,
		Parent = tela,
	})
	UI.escalaAutomatica(coluna)
	UI.criar("UIListLayout", {
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = coluna,
	})
	local botaoLoja = UI.botao({
		Name = "Loja",
		Text = "🛒 Loja",
		BackgroundColor3 = UI.Cores.Loja,
		Size = UDim2.fromOffset(190, 56),
		LayoutOrder = 1,
		Parent = coluna,
	})
	local botaoTrancar = UI.botao({
		Name = "Trancar",
		Text = "🔒 Trancar Base",
		BackgroundColor3 = UI.Cores.Trancar,
		Size = UDim2.fromOffset(190, 56),
		LayoutOrder = 2,
		Parent = coluna,
	})
	local botaoRenascer = UI.botao({
		Name = "Renascer",
		Text = "♻️ Renascer",
		BackgroundColor3 = UI.Cores.Renascer,
		Size = UDim2.fromOffset(190, 66),
		LayoutOrder = 3,
		TamanhoMaximo = 22,
		Parent = coluna,
	})

	-- --------------------------------------------------------
	-- Indicadores no topo
	-- --------------------------------------------------------
	local topo: Frame = UI.criar("Frame", {
		Name = "Indicadores",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromOffset(460, 120),
		BackgroundTransparency = 1,
		Parent = tela,
	})
	UI.escalaAutomatica(topo)
	UI.criar("UIListLayout", {
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Parent = topo,
	})
	local pilulaDados, textoDados = pilula(topo, "CarregandoDados", UI.Cores.Desativado, 0)
	textoDados.Text = "⏳ Carregando seus dados..."
	local pilulaSorte, textoSorte = pilula(topo, "Sorte", UI.Cores.Sucesso, 1)
	local pilulaCarregando, textoCarregando = pilula(topo, "Carregando", UI.Cores.Alerta, 2)

	-- --------------------------------------------------------
	-- Atualizações
	-- --------------------------------------------------------
	local confirmandoRebirth = false
	local tokenConfirmacao = 0
	local ultimoDinheiro = numeroAtributo("Dinheiro", 0)

	local function atualizarValores()
		local dinheiro = numeroAtributo("Dinheiro", 0)
		local rebirths = numeroAtributo("Rebirths", 0)
		textoDinheiro.Text = "💰 " .. Formatar.dinheiro(dinheiro)
		textoRenda.Text = "📈 " .. Formatar.renda(numeroAtributo("RendaPorSegundo", 0))
		textoMultiplicador.Text = "✖️ Multiplicador " .. Formatar.multiplicador(numeroAtributo("Multiplicador", 1))
		textoRebirths.Text = "♻️ Rebirths: " .. rebirths

		local custo = Regras.custoRebirth(rebirths)
		if confirmandoRebirth then
			botaoRenascer.Text = if Config.Rebirth.ResetarMonstrinhos
				then "Confirmar? ✔\n(perde dinheiro e monstrinhos)"
				else "Confirmar? ✔\n(perde o dinheiro)"
		else
			botaoRenascer.Text = "♻️ Renascer\n" .. Formatar.dinheiro(custo)
		end
		botaoRenascer.BackgroundColor3 = if dinheiro >= custo then UI.Cores.Renascer else UI.Cores.Renascer:Lerp(UI.Cores.Desativado, 0.6)

		if dinheiro > ultimoDinheiro then
			UI.pulsar(textoDinheiro)
		end
		ultimoDinheiro = dinheiro
	end

	local function atualizarTempos()
		local agora = Workspace:GetServerTimeNow()
		local trancadaAte = numeroAtributo("TrancadaAte", 0)
		local recargaAte = numeroAtributo("RecargaAte", 0)
		if numeroAtributo("BaseIndice", 0) == 0 then
			botaoTrancar.Text = "🔒 Sem base"
			botaoTrancar.BackgroundColor3 = UI.Cores.Desativado
		elseif trancadaAte > agora then
			botaoTrancar.Text = "🔒 Trancada " .. Formatar.tempo(trancadaAte - agora)
			botaoTrancar.BackgroundColor3 = UI.Cores.Sucesso
		elseif recargaAte > agora then
			botaoTrancar.Text = "⏳ Recarga " .. Formatar.tempo(recargaAte - agora)
			botaoTrancar.BackgroundColor3 = UI.Cores.Desativado
		else
			botaoTrancar.Text = "🔒 Trancar Base"
			botaoTrancar.BackgroundColor3 = UI.Cores.Trancar
		end

		local sorteAte = Workspace:GetAttribute("SorteAte")
		local sorteAtiva = type(sorteAte) == "number" and sorteAte > agora
		pilulaSorte.Visible = sorteAtiva
		if sorteAtiva then
			textoSorte.Text = "🍀 Sorte ativa na esteira! " .. Formatar.tempo((sorteAte :: number) - agora)
		end
	end

	local function atualizarCarregando()
		local nome = jogador:GetAttribute("Carregando")
		local carregando = type(nome) == "string" and nome ~= ""
		pilulaCarregando.Visible = carregando
		if carregando then
			textoCarregando.Text = "🏃 Leve o " .. nome .. " para a SUA base! Não deixe o dono te pegar!"
		end
	end

	local function atualizarDados()
		pilulaDados.Visible = jogador:GetAttribute("Carregado") ~= true
	end

	-- Marcador "SUA BASE" (só você vê)
	local marcador: BillboardGui? = nil
	local tokenMarcador = 0
	local function atualizarMarcador()
		tokenMarcador += 1
		local meuToken = tokenMarcador
		if marcador then
			marcador:Destroy()
			marcador = nil
		end
		local indice = numeroAtributo("BaseIndice", 0)
		if indice == 0 then
			return
		end
		task.spawn(function()
			local mapa = Workspace:WaitForChild("Mapa", 30)
			local bases = mapa and mapa:WaitForChild("Bases", 10)
			local base = bases and bases:WaitForChild("Base" .. indice, 10)
			local placa = base and base:WaitForChild("Placa", 10)
			if not placa or not placa:IsA("BasePart") or meuToken ~= tokenMarcador then
				return
			end
			local novo: BillboardGui = UI.criar("BillboardGui", {
				Name = "MarcadorSuaBase",
				Adornee = placa,
				Size = UDim2.fromOffset(220, 56),
				StudsOffset = Vector3.new(0, 7, 0),
				AlwaysOnTop = true,
				MaxDistance = 2000,
				ResetOnSpawn = false,
				LightInfluence = 0,
			})
			UI.texto({
				Size = UDim2.fromScale(1, 1),
				Text = "⬇ SUA BASE ⬇",
				TextColor3 = UI.Cores.Renda,
				TextStrokeTransparency = 0,
				TamanhoMaximo = 34,
				Parent = novo,
			})
			novo.Parent = jogador:WaitForChild("PlayerGui")
			marcador = novo
		end)
	end

	for _, nome in { "Dinheiro", "RendaPorSegundo", "Multiplicador", "Rebirths" } do
		jogador:GetAttributeChangedSignal(nome):Connect(atualizarValores)
	end
	jogador:GetAttributeChangedSignal("Carregando"):Connect(atualizarCarregando)
	jogador:GetAttributeChangedSignal("Carregado"):Connect(atualizarDados)
	jogador:GetAttributeChangedSignal("BaseIndice"):Connect(atualizarMarcador)
	atualizarValores()
	atualizarCarregando()
	atualizarDados()
	atualizarMarcador()
	atualizarTempos()

	task.spawn(function()
		while true do
			task.wait(0.2)
			atualizarTempos()
		end
	end)

	-- "+$" subindo ao coletar dinheiro
	Remotos.Notificacao.OnClientEvent:Connect(function(texto: any, tipo: any)
		if tipo ~= "dinheiro" or type(texto) ~= "string" then
			return
		end
		local flutuante = UI.texto({
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -12, 0, 33),
			Size = UDim2.fromOffset(170, 34),
			Text = texto,
			TextColor3 = UI.Cores.Renda,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextStrokeTransparency = 0.2,
			TamanhoMaximo = 30,
			ZIndex = 5,
			Parent = painel,
		})
		TweenService:Create(
			flutuante,
			TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Position = UDim2.new(1, -12, 0, -12), TextTransparency = 1, TextStrokeTransparency = 1 }
		):Play()
		task.delay(1.3, function()
			flutuante:Destroy()
		end)
	end)

	-- --------------------------------------------------------
	-- Cliques
	-- --------------------------------------------------------
	botaoLoja.Activated:Connect(function()
		acoes.abrirLoja()
	end)

	botaoTrancar.Activated:Connect(function()
		local agora = Workspace:GetServerTimeNow()
		if numeroAtributo("BaseIndice", 0) == 0 then
			Avisos.notificar("Você ainda não tem uma base.", "erro")
			return
		end
		if numeroAtributo("TrancadaAte", 0) > agora then
			Avisos.notificar("Sua base já está trancada!", "info")
			return
		end
		local recargaAte = numeroAtributo("RecargaAte", 0)
		if recargaAte > agora then
			local idProduto = Config.Produtos.TrancarAgora
			if idProduto > 0 then
				Avisos.notificar("Base em recarga! Use 'Trancar Agora' para trancar na hora.", "alerta")
				MarketplaceService:PromptProductPurchase(jogador, idProduto)
			else
				Avisos.notificar("Aguarde " .. Formatar.tempo(recargaAte - agora) .. " para trancar de novo.", "erro")
			end
			return
		end
		Remotos.PedirTrancar:FireServer()
	end)

	botaoRenascer.Activated:Connect(function()
		local custo = Regras.custoRebirth(numeroAtributo("Rebirths", 0))
		if numeroAtributo("Dinheiro", 0) < custo then
			local bonus = math.floor(Config.Rebirth.BonusPorRebirth * 100 + 0.5)
			Avisos.notificar("Junte " .. Formatar.dinheiro(custo) .. " para renascer e ganhar +" .. bonus .. "% de renda para sempre!", "info")
			return
		end
		if not confirmandoRebirth then
			-- Primeiro clique: pede confirmação por 4 segundos
			confirmandoRebirth = true
			tokenConfirmacao += 1
			local meuToken = tokenConfirmacao
			atualizarValores()
			task.delay(4, function()
				if tokenConfirmacao == meuToken then
					confirmandoRebirth = false
					atualizarValores()
				end
			end)
			return
		end
		confirmandoRebirth = false
		tokenConfirmacao += 1
		atualizarValores()
		Remotos.PedirRenascer:FireServer()
	end)
end

return HUD
