--[[
	Interacoes.lua
	Recebe os ProximityPrompts dos monstrinhos (Comprar, Roubar, Vender),
	faz as validações anti-exploit comuns e chama o módulo certo:
	  • anti-spam por jogador;
	  • personagem vivo;
	  • distância real entre o jogador e o monstrinho (com folga para o ping);
	  • tempo realmente segurado (o cliente pode tentar pular o "segurar").
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Bases = require(script.Parent.Bases)
local Esteira = require(script.Parent.Esteira)
local Limitador = require(script.Parent.Limitador)
local Monstrinho = require(script.Parent.Monstrinho)
local Roubo = require(script.Parent.Roubo)

local Interacoes = {}

local function aoAcionar(m: Monstrinho.Monstrinho, acao: string, player: Player, prompt: ProximityPrompt, segurado: number)
	if not Limitador.permitir(player, "Prompt", 0.2) then
		return
	end
	-- O prompt ainda é o atual deste monstrinho? (evita cliques "velhos")
	if m.Destruido or m.Prompts[acao] ~= prompt then
		return
	end

	local personagem = player.Character
	local raiz = personagem and personagem:FindFirstChild("HumanoidRootPart")
	local humanoide = personagem and personagem:FindFirstChildOfClass("Humanoid")
	if not raiz or not raiz:IsA("BasePart") or not humanoide or humanoide.Health <= 0 then
		return
	end

	local distancia = (raiz.Position - m.Raiz.Position).Magnitude
	if distancia > prompt.MaxActivationDistance + Config.AntiExploit.ToleranciaDistancia then
		return
	end

	if prompt.HoldDuration > 0 and Monstrinho.segurarObservado() then
		local minimo = prompt.HoldDuration * Config.AntiExploit.FolgaTempoSegurar
		if segurado < minimo or segurado > prompt.HoldDuration + 5 then
			return
		end
	end

	if acao == "Comprar" then
		Esteira.comprar(player, m)
	elseif acao == "Roubar" then
		Roubo.tentar(player, m)
	elseif acao == "Vender" then
		Bases.vender(player, m)
	end
end

function Interacoes.iniciar()
	Monstrinho.definirAoAcionar(aoAcionar)
end

return Interacoes
