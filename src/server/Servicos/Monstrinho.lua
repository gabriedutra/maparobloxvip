--[[
	Monstrinho.lua
	Um monstrinho no mundo (na esteira, em uma base ou sendo carregado).
	Cuida do modelo, da placa (BillboardGui) e dos ProximityPrompts.

	Prompts (criados pelo servidor, com o atributo "Acao"):
	  • "Comprar" — na esteira;
	  • "Roubar" e "Vender" — na base. O cliente só mostra "Roubar" para quem
	    NÃO é dono e "Vender" para o dono (o servidor valida de novo).

	O ProximityPrompt.Triggered roda no servidor: o cliente não consegue
	"inventar" uma compra; mesmo assim distância, tempo segurando, saldo e
	cooldown são conferidos no módulo Interacoes.
]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalogo = require(Shared:WaitForChild("Catalogo"))
local Config = require(Shared:WaitForChild("Config"))
local Formatar = require(Shared:WaitForChild("Formatar"))
local Regras = require(Shared:WaitForChild("Regras"))
local MonstrinhoModelo = require(script.Parent.MonstrinhoModelo)

local Monstrinho = {}
Monstrinho.__index = Monstrinho

export type Modo = "Nenhum" | "Esteira" | "Base" | "Carregado"

export type Monstrinho = typeof(setmetatable(
	{} :: {
		Uid: string,
		Id: string,
		Info: Catalogo.Monstrinho,
		Raridade: Catalogo.Raridade,
		Modelo: Model,
		Raiz: BasePart,
		AlturaBase: number,
		AlturaTopo: number,
		Modo: Modo,
		Prompts: { [string]: ProximityPrompt },
		Base: any, -- base onde está (definido pelo módulo Bases)
		Slot: any, -- slot onde está (definido pelo módulo Bases)
		SendoRoubado: boolean,
		Destruido: boolean,
	},
	Monstrinho
))

-- Função chamada quando um jogador aciona um prompt (definida pelo módulo Interacoes)
type AoAcionar = (monstrinho: Monstrinho, acao: string, player: Player, prompt: ProximityPrompt, segurado: number) -> ()
local aoAcionar: AoAcionar? = nil

-- Fica true quando o servidor recebe o primeiro PromptButtonHoldBegan. Só então
-- o tempo segurado passa a ser exigido (garante que o evento chega ao servidor).
local segurarObservado = false

function Monstrinho.segurarObservado(): boolean
	return segurarObservado
end

function Monstrinho.definirAoAcionar(funcao: AoAcionar)
	aoAcionar = funcao
end

function Monstrinho.novo(id: string): Monstrinho
	local info = Catalogo.obter(id)
	assert(info, "[Monstrinho] Id desconhecido: " .. tostring(id))
	local modelo, raiz = MonstrinhoModelo.construir(info)
	local self = setmetatable({
		Uid = HttpService:GenerateGUID(false) :: string,
		Id = info.Id,
		Info = info,
		Raridade = Catalogo.raridadeDe(info),
		Modelo = modelo,
		Raiz = raiz,
		AlturaBase = (modelo:GetAttribute("AlturaBase") :: number?) or 1,
		AlturaTopo = (modelo:GetAttribute("AlturaTopo") :: number?) or 1,
		Modo = "Nenhum" :: Modo,
		Prompts = {},
		Base = nil,
		Slot = nil,
		SendoRoubado = false,
		Destruido = false,
	}, Monstrinho)
	modelo:SetAttribute("Uid", self.Uid)
	modelo:SetAttribute("DonoUserId", 0)
	modelo:SetAttribute("Trancado", false)
	modelo:SetAttribute("SendoRoubado", false)
	return self
end

function Monstrinho._limparPrompts(self: Monstrinho)
	for _, prompt in self.Prompts do
		prompt:Destroy() -- também desconecta os eventos do prompt
	end
	table.clear(self.Prompts)
end

function Monstrinho._criarPrompt(
	self: Monstrinho,
	acao: string,
	texto: string,
	tecla: Enum.KeyCode,
	teclaControle: Enum.KeyCode,
	segurar: number,
	distancia: number
): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Prompt" .. acao
	prompt.ActionText = texto
	prompt.ObjectText = self.Info.Nome .. " (" .. self.Raridade.Nome .. ")"
	prompt.KeyboardKeyCode = tecla
	prompt.GamepadKeyCode = teclaControle
	prompt.HoldDuration = segurar
	prompt.MaxActivationDistance = distancia
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("Acao", acao)
	prompt:AddTag("PromptMonstrinho")

	-- Guarda quando cada jogador começou a segurar (anti-exploit do tempo de segurar)
	local inicios: { [Player]: number } = {}
	prompt.PromptButtonHoldBegan:Connect(function(player: Player)
		segurarObservado = true
		inicios[player] = os.clock()
	end)
	prompt.Triggered:Connect(function(player: Player)
		local inicio = inicios[player]
		inicios[player] = nil
		local segurado = if inicio then os.clock() - inicio else 0
		if aoAcionar and not self.Destruido then
			aoAcionar(self, acao, player, prompt, segurado)
		end
	end)

	prompt.Parent = self.Raiz
	self.Prompts[acao] = prompt
	return prompt
end

function Monstrinho._mostrarPreco(self: Monstrinho, visivel: boolean)
	local gui = self.Raiz:FindFirstChild("Info")
	local preco = gui and gui:FindFirstChild("Preco")
	if preco and preco:IsA("TextLabel") then
		preco.Visible = visivel
	end
end

-- Na esteira: mostra o preço e o prompt "Comprar"
function Monstrinho.modoEsteira(self: Monstrinho)
	self.Modo = "Esteira"
	self:_limparPrompts()
	self:_mostrarPreco(true)
	self.Modelo:SetAttribute("DonoUserId", 0)
	self:_criarPrompt(
		"Comprar",
		"Comprar " .. Formatar.dinheiro(self.Info.Preco),
		Enum.KeyCode.E,
		Enum.KeyCode.ButtonX,
		Config.Compra.TempoSegurar,
		Config.Compra.DistanciaPrompt
	)
end

-- Na base de um jogador: prompts "Roubar" (para os outros) e "Vender" (para o dono)
function Monstrinho.modoBase(self: Monstrinho, dono: Player)
	self.Modo = "Base"
	self:_limparPrompts()
	self:_mostrarPreco(false)
	self.Modelo:SetAttribute("DonoUserId", dono.UserId)
	self:_criarPrompt("Roubar", "Roubar", Enum.KeyCode.E, Enum.KeyCode.ButtonX, Config.Roubo.TempoSegurar, Config.Roubo.DistanciaPrompt)
	if Config.Venda.Ativa then
		self:_criarPrompt(
			"Vender",
			"Vender por " .. Formatar.dinheiro(Regras.precoVenda(self.Info)),
			Enum.KeyCode.F,
			Enum.KeyCode.ButtonY,
			Config.Venda.TempoSegurar,
			Config.Venda.DistanciaPrompt
		)
	end
end

-- Sendo carregado por um ladrão: sem prompts
function Monstrinho.modoCarregado(self: Monstrinho)
	self.Modo = "Carregado"
	self:_limparPrompts()
end

-- Move o monstrinho inteiro: as outras peças estão soldadas na Raiz, então basta
-- mover a Raiz (bem mais leve para o servidor e para a rede do que mover peça por peça).
function Monstrinho.posicionar(self: Monstrinho, cframe: CFrame)
	if not self.Destruido then
		self.Raiz.CFrame = cframe
	end
end

function Monstrinho.destruir(self: Monstrinho)
	if self.Destruido then
		return
	end
	self.Destruido = true
	self:_limparPrompts()
	self.Modelo:Destroy()
end

return Monstrinho
