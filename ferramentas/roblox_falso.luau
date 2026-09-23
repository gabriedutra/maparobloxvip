--[[
	roblox_falso.luau — um "mini Roblox" para simular o servidor no Lune.

	Implementa só o necessário para os módulos do jogo rodarem de verdade:
	instâncias com propriedades livres, hierarquia (Parent, FindFirstChild...),
	atributos, tags, eventos (Touched, Triggered, CharacterAdded, Died...),
	jogadores, personagens e os serviços usados pelo servidor.
	Não tem física: a posição dos personagens é controlada pelo teste.
]]

local roblox = require("@lune/roblox")
local task = require("@lune/task")

local CFrame = roblox.CFrame
local Vector3 = roblox.Vector3

local RobloxFalso = {}

-- ------------------------------------------------------------
-- Sinais (eventos)
-- ------------------------------------------------------------

local Sinal = {}
Sinal.__index = Sinal

function RobloxFalso.novoSinal()
	return setmetatable({ conexoes = {} }, Sinal)
end

function Sinal:Connect(funcao)
	local conexao = { Connected = true, _funcao = funcao }
	function conexao:Disconnect()
		self.Connected = false
	end
	table.insert(self.conexoes, conexao)
	return conexao
end

function Sinal:Once(funcao)
	local conexao
	conexao = self:Connect(function(...)
		conexao:Disconnect()
		funcao(...)
	end)
	return conexao
end

-- Chama cada função em uma thread nova (como o Roblox), na hora
function Sinal:Fire(...)
	for _, conexao in table.clone(self.conexoes) do
		if conexao.Connected then
			task.spawn(conexao._funcao, ...)
		end
	end
end

function Sinal:_desconectarTudo()
	for _, conexao in self.conexoes do
		conexao.Connected = false
	end
end

-- ------------------------------------------------------------
-- Instâncias
-- ------------------------------------------------------------

local dados: { [any]: any } = setmetatable({}, { __mode = "k" }) :: any
local Meta = {}
local Metodos = {}

local HERANCA: { [string]: { string } } = {
	Part = { "BasePart", "PVInstance" },
	SpawnLocation = { "Part", "BasePart", "PVInstance" },
	Model = { "PVInstance" },
	Workspace = { "Model", "PVInstance" },
	TextLabel = { "GuiObject", "GuiBase2d" },
	TextButton = { "GuiButton", "GuiObject", "GuiBase2d" },
	Frame = { "GuiObject", "GuiBase2d" },
	SurfaceGui = { "LayerCollector", "GuiBase2d" },
	BillboardGui = { "LayerCollector", "GuiBase2d" },
	Weld = { "JointInstance" },
	IntValue = { "ValueBase" },
	RemoteEvent = { "BaseRemoteEvent" },
}

local EVENTOS = {
	Touched = true,
	TouchEnded = true,
	Triggered = true,
	PromptButtonHoldBegan = true,
	PromptButtonHoldEnded = true,
	CharacterAdded = true,
	CharacterRemoving = true,
	DescendantAdded = true,
	DescendantRemoving = true,
	ChildAdded = true,
	ChildRemoved = true,
	Died = true,
	PlayerAdded = true,
	PlayerRemoving = true,
	Heartbeat = true,
	OnServerEvent = true,
	OnClientEvent = true,
	AncestryChanged = true,
	Changed = true,
	PromptGamePassPurchaseFinished = true,
}

local PADROES: { [string]: any } = {
	Transparency = 0,
	Anchored = false,
	CanCollide = true,
	CanTouch = true,
	CanQuery = true,
	Massless = false,
	Size = Vector3.new(4, 1, 2),
	CFrame = CFrame.new(),
	Health = 100,
	MaxHealth = 100,
	WalkSpeed = 16,
	Enabled = true,
	Visible = true,
	Text = "",
	HoldDuration = 0,
	MaxActivationDistance = 10,
	CollisionGroup = "Default",
	JobId = "servidor-simulado",
}

local function eh(obj: any): boolean
	return type(obj) == "table" and dados[obj] ~= nil
end
RobloxFalso.eh = eh

-- Peças (BasePart) têm Position derivada do CFrame; em GUIs, Position é um UDim2 comum
local function ehPeca(d): boolean
	local pais = HERANCA[d.ClassName]
	return pais ~= nil and table.find(pais, "BasePart") ~= nil
end

function RobloxFalso.novo(classe: string, pai: any?): any
	local obj = setmetatable({}, Meta)
	dados[obj] = {
		ClassName = classe,
		Name = classe,
		Parent = nil,
		Filhos = {},
		Props = {},
		Atributos = {},
		SinaisAtributo = {},
		SinaisPropriedade = {},
		Tags = {},
		Sinais = {},
		Destruido = false,
		Enviados = {},
	}
	if pai then
		obj.Parent = pai
	end
	return obj
end

local function sinal(obj: any, nome: string)
	local d = dados[obj]
	local s = d.Sinais[nome]
	if not s then
		s = RobloxFalso.novoSinal()
		d.Sinais[nome] = s
	end
	return s
end
RobloxFalso.sinal = sinal

local function descendentes(obj: any, lista: { any })
	for _, filho in dados[obj].Filhos do
		table.insert(lista, filho)
		descendentes(filho, lista)
	end
	return lista
end

Meta.__index = function(obj, chave)
	local d = dados[obj]
	local metodo = Metodos[chave]
	if metodo then
		return metodo
	end
	if chave == "Parent" then
		return d.Parent
	elseif chave == "Name" then
		return d.Name
	elseif chave == "ClassName" then
		return d.ClassName
	elseif chave == "Position" and ehPeca(d) then
		local cf = d.Props.CFrame
		return if cf then cf.Position else Vector3.zero
	end
	if EVENTOS[chave] then
		return sinal(obj, chave)
	end
	local valor = d.Props[chave]
	if valor ~= nil then
		return valor
	end
	for _, filho in d.Filhos do
		if dados[filho].Name == chave then
			return filho
		end
	end
	return PADROES[chave]
end

Meta.__newindex = function(obj, chave, valor)
	local d = dados[obj]
	if chave == "Parent" then
		if d.Destruido and valor ~= nil then
			error("Parent de instância destruída não pode mudar (" .. d.Name .. ")", 2)
		end
		local antigo = d.Parent
		if antigo == valor then
			return
		end
		if antigo then
			local irmaos = dados[antigo].Filhos
			local indice = table.find(irmaos, obj)
			if indice then
				table.remove(irmaos, indice)
			end
		end
		d.Parent = valor
		if valor then
			table.insert(dados[valor].Filhos, obj)
			-- DescendantAdded em todos os ancestrais (para ela e seus descendentes)
			local adicionados = descendentes(obj, { obj })
			local ancestral = valor
			while ancestral do
				local s = dados[ancestral].Sinais.DescendantAdded
				if s then
					for _, item in adicionados do
						s:Fire(item)
					end
				end
				ancestral = dados[ancestral].Parent
			end
		end
		return
	elseif chave == "Name" then
		d.Name = valor
		return
	elseif chave == "Position" and ehPeca(d) then
		local atual = d.Props.CFrame or CFrame.new()
		d.Props.CFrame = CFrame.new(valor) * (atual - atual.Position)
		return
	end
	d.Props[chave] = valor
	local s = d.SinaisPropriedade[chave]
	if s then
		s:Fire()
	end
end

Meta.__tostring = function(obj)
	return "Falso<" .. dados[obj].ClassName .. ">(" .. dados[obj].Name .. ")"
end

function Metodos.FindFirstChild(self, nome: string, recursivo: boolean?)
	for _, filho in dados[self].Filhos do
		if dados[filho].Name == nome then
			return filho
		end
	end
	if recursivo then
		for _, item in descendentes(self, {}) do
			if dados[item].Name == nome then
				return item
			end
		end
	end
	return nil
end

function Metodos.WaitForChild(self, nome: string)
	return Metodos.FindFirstChild(self, nome)
end

function Metodos.IsA(self, classe: string): boolean
	local minha = dados[self].ClassName
	if classe == "Instance" or classe == minha then
		return true
	end
	local pais = HERANCA[minha]
	return pais ~= nil and table.find(pais, classe) ~= nil
end

function Metodos.FindFirstChildOfClass(self, classe: string)
	for _, filho in dados[self].Filhos do
		if dados[filho].ClassName == classe then
			return filho
		end
	end
	return nil
end

function Metodos.FindFirstChildWhichIsA(self, classe: string)
	for _, filho in dados[self].Filhos do
		if Metodos.IsA(filho, classe) then
			return filho
		end
	end
	return nil
end

function Metodos.GetChildren(self)
	return table.clone(dados[self].Filhos)
end

function Metodos.GetDescendants(self)
	return descendentes(self, {})
end

function Metodos.Destroy(self)
	local d = dados[self]
	if d.Destruido then
		return
	end
	for _, filho in table.clone(d.Filhos) do
		Metodos.Destroy(filho)
	end
	self.Parent = nil
	d.Destruido = true
	for _, s in d.Sinais do
		s:_desconectarTudo()
	end
end

function Metodos.ClearAllChildren(self)
	for _, filho in table.clone(dados[self].Filhos) do
		Metodos.Destroy(filho)
	end
end

function Metodos.SetAttribute(self, chave: string, valor: any)
	local d = dados[self]
	d.Atributos[chave] = valor
	local s = d.SinaisAtributo[chave]
	if s then
		s:Fire()
	end
end

function Metodos.GetAttribute(self, chave: string)
	return dados[self].Atributos[chave]
end

function Metodos.GetAttributes(self)
	return table.clone(dados[self].Atributos)
end

function Metodos.GetAttributeChangedSignal(self, chave: string)
	local d = dados[self]
	d.SinaisAtributo[chave] = d.SinaisAtributo[chave] or RobloxFalso.novoSinal()
	return d.SinaisAtributo[chave]
end

function Metodos.GetPropertyChangedSignal(self, chave: string)
	local d = dados[self]
	d.SinaisPropriedade[chave] = d.SinaisPropriedade[chave] or RobloxFalso.novoSinal()
	return d.SinaisPropriedade[chave]
end

function Metodos.AddTag(self, tag: string)
	dados[self].Tags[tag] = true
end

function Metodos.HasTag(self, tag: string): boolean
	return dados[self].Tags[tag] == true
end

function Metodos.RemoveTag(self, tag: string)
	dados[self].Tags[tag] = nil
end

function Metodos.GetFullName(self): string
	local partes = {}
	local atual = self
	while atual do
		table.insert(partes, 1, dados[atual].Name)
		atual = dados[atual].Parent
	end
	return table.concat(partes, ".")
end

function Metodos.IsDescendantOf(self, outro): boolean
	local atual = dados[self].Parent
	while atual do
		if atual == outro then
			return true
		end
		atual = dados[atual].Parent
	end
	return false
end

function Metodos.IsAncestorOf(self, outro): boolean
	return eh(outro) and Metodos.IsDescendantOf(outro, self)
end

function Metodos.GetPivot(self)
	local primaria = dados[self].Props.PrimaryPart
	if primaria then
		return primaria.CFrame
	end
	return dados[self].Props.CFrame or CFrame.new()
end

-- Move o modelo inteiro (todas as peças mantêm a posição relativa)
function Metodos.PivotTo(self, cf)
	if Metodos.IsA(self, "BasePart") then
		self.CFrame = cf
		return
	end
	local pivo = Metodos.GetPivot(self)
	local delta = cf * pivo:Inverse()
	for _, item in descendentes(self, {}) do
		if Metodos.IsA(item, "BasePart") then
			item.CFrame = delta * item.CFrame
		end
	end
end

function Metodos.Kick(self, mensagem: string?)
	dados[self].Props.Chutado = mensagem or ""
end

-- RemoteEvent: guarda o que foi enviado para os clientes
function Metodos.FireClient(self, player, ...)
	table.insert(dados[self].Enviados, { Para = player, Args = { ... } })
end

function Metodos.FireAllClients(self, ...)
	table.insert(dados[self].Enviados, { Para = "todos", Args = { ... } })
end

function RobloxFalso.enviados(remote): { any }
	return dados[remote].Enviados
end

-- Players
function Metodos.GetPlayers(self)
	local lista = {}
	for _, filho in dados[self].Filhos do
		if dados[filho].ClassName == "Player" then
			table.insert(lista, filho)
		end
	end
	return lista
end

function Metodos.GetPlayerByUserId(self, id: number)
	for _, p in Metodos.GetPlayers(self) do
		if p.UserId == id then
			return p
		end
	end
	return nil
end

function Metodos.GetPlayerFromCharacter(self, personagem)
	for _, p in Metodos.GetPlayers(self) do
		if p.Character == personagem then
			return p
		end
	end
	return nil
end

-- Workspace
local inicioRelogio = os.clock()
RobloxFalso.Velocidade = 1 -- o relógio simulado anda X vezes mais rápido que o real
function RobloxFalso.agora(): number
	return (os.clock() - inicioRelogio) * RobloxFalso.Velocidade
end
function Metodos.GetServerTimeNow(_self): number
	return RobloxFalso.agora()
end

RobloxFalso.Instance = {
	new = function(classe: string, pai: any?)
		return RobloxFalso.novo(classe, pai)
	end,
}

return RobloxFalso
