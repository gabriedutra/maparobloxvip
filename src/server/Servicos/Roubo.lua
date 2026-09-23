--[[
	Roubo.lua
	Como funciona um roubo:
	  1. O ladrão entra numa base destrancada e segura "Roubar" em um monstrinho
	     (Config.Roubo.TempoSegurar segundos).
	  2. O monstrinho vai para cima da cabeça dele e ele fica mais lento
	     (ou mais rápido com o Game Pass "Carregar Rápido").
	  3. Se chegar na PRÓPRIA base, o monstrinho é dele.
	  4. Se o DONO encostar nele no caminho (Config.Roubo.DistanciaToque), se o
	     ladrão morrer, demorar demais ou sair do jogo, o monstrinho volta.

	Tudo é verificado no servidor a cada 0,1 s (inclusive teleporte suspeito).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Regras = require(Shared:WaitForChild("Regras"))
local Bases = require(script.Parent.Bases)
local Dados = require(script.Parent.Dados)
local Jogadores = require(script.Parent.Jogadores)
local Limitador = require(script.Parent.Limitador)
local Monstrinho = require(script.Parent.Monstrinho)
local Notificar = require(script.Parent.Notificar)
local Passes = require(script.Parent.Passes)

local Roubo = {}

type RouboAtivo = {
	Ladrao: Player,
	Vitima: Player,
	M: Monstrinho.Monstrinho,
	BaseOrigem: Bases.Base,
	SlotOrigem: Bases.Slot,
	BaseDestino: Bases.Base,
	SlotDestino: Bases.Slot,
	Inicio: number,
	UltimaPosicao: Vector3,
	UltimoTempo: number,
	IgnorarProximoSalto: boolean,
	Solda: Weld,
	Destaque: Highlight,
	Etiqueta: BillboardGui,
	ConexaoMorte: RBXScriptConnection?,
	Finalizado: boolean,
}

local ativos: { [Player]: RouboAtivo } = {}

local function personagemVivo(player: Player): (Model?, BasePart?, Humanoid?)
	local personagem = player.Character
	if not personagem then
		return nil, nil, nil
	end
	local raiz = personagem:FindFirstChild("HumanoidRootPart")
	local humanoide = personagem:FindFirstChildOfClass("Humanoid")
	if raiz and raiz:IsA("BasePart") and humanoide and humanoide.Health > 0 then
		return personagem, raiz, humanoide
	end
	return nil, nil, nil
end

local function listaAtivos(): { RouboAtivo }
	local lista = {}
	for _, roubo in ativos do
		table.insert(lista, roubo)
	end
	return lista
end

local function velocidadeCarregando(player: Player): number
	return Regras.velocidadeCarregando(Passes.possui(player, "CarregarRapido"))
end

-- Mensagens para o ladrão e para a vítima quando o roubo falha
local function mensagensFalha(roubo: RouboAtivo, motivo: string?): (string?, string?)
	local nome = roubo.M.Info.Nome
	local voltou = "✅ Seu " .. nome .. " voltou para a base!"
	if motivo == "tocado" then
		return "❌ " .. roubo.Vitima.DisplayName .. " te pegou! O " .. nome .. " voltou para a base dele.",
			"✅ Você pegou " .. roubo.Ladrao.DisplayName .. " e recuperou seu " .. nome .. "!"
	elseif motivo == "morreu" then
		return "❌ Você caiu e o " .. nome .. " voltou para a base.", voltou
	elseif motivo == "tempo" then
		return "⌛ Demorou demais! O " .. nome .. " voltou para a base.", voltou
	elseif motivo == "suspeito" then
		return "❌ Roubo cancelado (movimento suspeito).", voltou
	elseif motivo == "trancou" then
		return "🔒 A base foi trancada! O " .. nome .. " voltou.", voltou
	elseif motivo == "ladraoSaiu" then
		return nil, "✅ O ladrão saiu do jogo e seu " .. nome .. " voltou!"
	elseif motivo == "vitimaSaiu" then
		return "O dono saiu do jogo. O roubo foi cancelado.", nil
	elseif motivo == "rebirth" then
		return "O roubo foi cancelado.", nil
	end
	return "O roubo foi cancelado.", voltou
end

local function finalizar(roubo: RouboAtivo, sucesso: boolean, motivo: string?)
	if roubo.Finalizado then
		return
	end
	roubo.Finalizado = true
	if ativos[roubo.Ladrao] == roubo then
		ativos[roubo.Ladrao] = nil
	end
	if roubo.ConexaoMorte then
		roubo.ConexaoMorte:Disconnect()
	end

	-- Solta o monstrinho e desfaz os efeitos
	roubo.Solda:Destroy()
	roubo.Destaque:Destroy()
	roubo.Etiqueta:Destroy()
	local personagem = roubo.Ladrao.Character
	local humanoide = personagem and personagem:FindFirstChildOfClass("Humanoid")
	if humanoide then
		humanoide.WalkSpeed = Config.Roubo.VelocidadeNormal
	end
	roubo.Ladrao:SetAttribute("Carregando", "")

	roubo.SlotDestino.Reservado = false
	local m = roubo.M
	m.SendoRoubado = false
	if m.Destruido then
		return
	end
	m.Raiz.Anchored = true
	m.Modelo:SetAttribute("SendoRoubado", false)

	local podeEntregar = sucesso
		and roubo.BaseDestino.Dono == roubo.Ladrao
		and roubo.SlotDestino.Monstrinho == nil
		and roubo.SlotOrigem.Monstrinho == m

	if podeEntregar then
		Bases.retirarMonstrinho(roubo.BaseOrigem, roubo.SlotOrigem)
		Bases.colocarMonstrinho(roubo.BaseDestino, roubo.SlotDestino, m)
		Notificar.jogador(roubo.Ladrao, "🎉 Você roubou " .. m.Info.Nome .. "!", "sucesso")
		Notificar.jogador(roubo.Vitima, "😭 " .. roubo.Ladrao.DisplayName .. " roubou seu " .. m.Info.Nome .. "!", "erro")
		if m.Raridade.Anunciar then
			Notificar.todos(
				"🦹 " .. roubo.Ladrao.DisplayName .. " roubou " .. m.Info.Nome .. " (" .. m.Raridade.Nome .. ") de " .. roubo.Vitima.DisplayName .. "!",
				"alerta"
			)
		end
		Dados.solicitarSalvamento(roubo.Ladrao)
		Dados.solicitarSalvamento(roubo.Vitima)
		return
	end

	-- Falhou: o monstrinho volta para o slot de origem
	if roubo.BaseOrigem.Dono == roubo.Vitima and roubo.SlotOrigem.Monstrinho == m then
		Bases.colocarMonstrinho(roubo.BaseOrigem, roubo.SlotOrigem, m)
	else
		m:destruir()
	end
	local mensagemLadrao, mensagemVitima = mensagensFalha(roubo, motivo)
	if mensagemLadrao then
		Notificar.jogador(roubo.Ladrao, mensagemLadrao, "erro")
	end
	if mensagemVitima then
		Notificar.jogador(roubo.Vitima, mensagemVitima, "sucesso")
	end
end

function Roubo.estaCarregando(player: Player): boolean
	return ativos[player] ~= nil
end

-- Tenta começar um roubo (chamado pelo módulo Interacoes)
function Roubo.tentar(ladrao: Player, m: Monstrinho.Monstrinho)
	if ativos[ladrao] then
		Notificar.jogador(ladrao, "Você já está carregando um monstrinho!", "erro")
		return
	end
	if m.Modo ~= "Base" or m.SendoRoubado or m.Destruido then
		return
	end
	local baseOrigem: Bases.Base? = m.Base
	local slotOrigem: Bases.Slot? = m.Slot
	local vitima = baseOrigem and baseOrigem.Dono
	if not baseOrigem or not slotOrigem or not vitima then
		return
	end
	if vitima == ladrao then
		Notificar.jogador(ladrao, "Esse monstrinho já é seu!", "info")
		return
	end
	if not Jogadores.obterCarregado(ladrao) then
		return
	end
	if Bases.estaTrancada(baseOrigem) then
		Notificar.jogador(ladrao, "🔒 Essa base está trancada!", "erro")
		return
	end
	local personagem, raiz, humanoide = personagemVivo(ladrao)
	if not personagem or not raiz or not humanoide then
		return
	end
	if not Bases.dentroDaBase(baseOrigem, raiz.Position, 1) then
		Notificar.jogador(ladrao, "Entre na base para roubar!", "erro")
		return
	end
	local baseDestino = Bases.obterBase(ladrao)
	if not baseDestino then
		Notificar.jogador(ladrao, "Você precisa de uma base para roubar.", "erro")
		return
	end
	local slotDestino = Bases.slotLivre(baseDestino)
	if not slotDestino then
		Notificar.jogador(ladrao, "Sua base está cheia! Libere um slot antes de roubar.", "erro")
		return
	end
	if not Limitador.permitir(ladrao, "Roubar", Config.Roubo.Recarga) then
		Notificar.jogador(ladrao, "Espere um pouco para roubar de novo.", "erro")
		return
	end

	-- Começa o roubo
	slotDestino.Reservado = true
	m.SendoRoubado = true
	m.Modelo:SetAttribute("SendoRoubado", true)
	m:modoCarregado()
	Bases.recalcularRenda(baseOrigem)

	-- Monstrinho em cima da cabeça do ladrão (soldado no HumanoidRootPart).
	-- Desancora ANTES de soldar para não prender o personagem no lugar.
	m.Raiz.Anchored = false
	local solda = Instance.new("Weld")
	solda.Name = "SoldaRoubo"
	solda.Part0 = raiz
	solda.Part1 = m.Raiz
	solda.C0 = CFrame.new(0, 2.8 + m.AlturaBase, 0)
	solda.Parent = m.Raiz
	humanoide.WalkSpeed = velocidadeCarregando(ladrao)

	local destaque = Instance.new("Highlight")
	destaque.Name = "DestaqueLadrao"
	destaque.FillColor = Color3.fromRGB(255, 60, 60)
	destaque.FillTransparency = 0.75
	destaque.OutlineColor = Color3.fromRGB(255, 220, 80)
	destaque.Parent = personagem

	local etiqueta = Instance.new("BillboardGui")
	etiqueta.Name = "EtiquetaLadrao"
	etiqueta.Size = UDim2.fromScale(6, 1.4)
	etiqueta.StudsOffset = Vector3.new(0, m.AlturaTopo + 4.6, 0)
	etiqueta.LightInfluence = 0
	etiqueta.AlwaysOnTop = true
	etiqueta.MaxDistance = 150
	local texto = Instance.new("TextLabel")
	texto.BackgroundTransparency = 1
	texto.Size = UDim2.fromScale(1, 1)
	texto.Text = "🦹 LADRÃO!"
	texto.TextColor3 = Color3.fromRGB(255, 80, 80)
	texto.TextScaled = true
	texto.Font = Enum.Font.FredokaOne
	texto.TextStrokeTransparency = 0
	texto.Parent = etiqueta
	etiqueta.Parent = m.Raiz

	local agora = os.clock()
	local roubo: RouboAtivo = {
		Ladrao = ladrao,
		Vitima = vitima,
		M = m,
		BaseOrigem = baseOrigem,
		SlotOrigem = slotOrigem,
		BaseDestino = baseDestino,
		SlotDestino = slotDestino,
		Inicio = agora,
		UltimaPosicao = raiz.Position,
		UltimoTempo = agora,
		IgnorarProximoSalto = false,
		Solda = solda,
		Destaque = destaque,
		Etiqueta = etiqueta,
		ConexaoMorte = nil,
		Finalizado = false,
	}
	roubo.ConexaoMorte = humanoide.Died:Connect(function()
		finalizar(roubo, false, "morreu")
	end)
	ativos[ladrao] = roubo
	ladrao:SetAttribute("Carregando", m.Info.Nome)

	Notificar.jogador(ladrao, "Você pegou " .. m.Info.Nome .. "! Leve até a SUA base antes que o dono te pegue!", "alerta")
	Notificar.jogador(vitima, "⚠️ " .. ladrao.DisplayName .. " está roubando seu " .. m.Info.Nome .. "! Encoste nele para recuperar!", "alerta")
end

-- Cancela roubos em que o jogador é o ladrão ou a vítima (saiu do jogo, rebirth...)
function Roubo.cancelarEnvolvendo(player: Player, motivoComoLadrao: string, motivoComoVitima: string)
	local proprio = ativos[player]
	if proprio then
		finalizar(proprio, false, motivoComoLadrao)
	end
	for _, roubo in listaAtivos() do
		if roubo.Vitima == player then
			finalizar(roubo, false, motivoComoVitima)
		end
	end
end

-- Game Pass comprado no meio do roubo: atualiza a velocidade
function Roubo.aoMudarPasses(player: Player)
	local roubo = ativos[player]
	if not roubo then
		return
	end
	local _, _, humanoide = personagemVivo(player)
	if humanoide then
		humanoide.WalkSpeed = velocidadeCarregando(player)
	end
end

-- Confere todos os roubos em andamento
local function verificar()
	local agora = os.clock()
	for _, roubo in listaAtivos() do
		if roubo.Finalizado then
			continue
		end
		local _, raiz = personagemVivo(roubo.Ladrao)
		if not raiz or roubo.Solda.Parent == nil or roubo.Solda.Part0 ~= raiz then
			finalizar(roubo, false, "morreu")
			continue
		end
		local posicao = raiz.Position

		-- Anti-teleporte: andou mais do que é possível desde a última verificação?
		local intervalo = agora - roubo.UltimoTempo
		local limite = Config.AntiExploit.VelocidadeMaxima * intervalo + Config.AntiExploit.MargemTeleporte
		if not roubo.IgnorarProximoSalto and (posicao - roubo.UltimaPosicao).Magnitude > limite then
			finalizar(roubo, false, "suspeito")
			continue
		end
		roubo.IgnorarProximoSalto = false
		roubo.UltimaPosicao = posicao
		roubo.UltimoTempo = agora

		if agora - roubo.Inicio > Config.Roubo.TempoMaximo then
			finalizar(roubo, false, "tempo")
			continue
		end

		-- O dono encostou no ladrão?
		local _, raizVitima = personagemVivo(roubo.Vitima)
		if raizVitima and (raizVitima.Position - posicao).Magnitude <= Config.Roubo.DistanciaToque then
			finalizar(roubo, false, "tocado")
			continue
		end

		-- Chegou na própria base?
		if Bases.dentroDaBase(roubo.BaseDestino, posicao, -1) then
			finalizar(roubo, true, nil)
		end
	end
end

function Roubo.iniciar()
	-- Quem é expulso de uma base trancada perde o monstrinho que pegou dela
	Bases.definirAoExpulsar(function(player: Player, base: Bases.Base)
		local roubo = ativos[player]
		if not roubo then
			return
		end
		if roubo.BaseOrigem == base then
			finalizar(roubo, false, "trancou")
		else
			roubo.IgnorarProximoSalto = true -- o teleporte da expulsão não é trapaça
		end
	end)

	task.spawn(function()
		while true do
			task.wait(0.1)
			xpcall(verificar, function(erro)
				warn("[Roubo] Erro na verificação: " .. tostring(erro))
			end)
		end
	end)
end

return Roubo
