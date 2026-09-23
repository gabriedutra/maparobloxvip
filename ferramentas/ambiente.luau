--[[
	ambiente.luau — roda módulos do jogo fora do Roblox, usando o Lune (https://lune-org.github.io).

	Emula o suficiente do Roblox para carregar ModuleScripts que usam
	require(script.Parent.X) ou game:GetService("ReplicatedStorage"):WaitForChild(...):
	  - tipos (Instance, Vector3, CFrame, Color3, Enum, UDim2, Font...) vêm do @lune/roblox;
	  - "script", "game" e "require" são falsos e apontam para os arquivos em src/.

	Rode as ferramentas a partir da pasta do projeto (onde está o default.project.json).
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

local Ambiente = {}

-- Onde cada pasta do Rojo aparece no jogo (igual ao default.project.json)
local RAIZES = {
	{ Caminho = "ReplicatedStorage/Shared", Pasta = "src/shared" },
	{ Caminho = "ServerScriptService/Servidor", Pasta = "src/server" },
	{ Caminho = "StarterPlayer/StarterPlayerScripts/Cliente", Pasta = "src/client" },
}

local TIPOS_ROBLOX = {
	"Instance",
	"Vector2",
	"Vector3",
	"CFrame",
	"Color3",
	"Enum",
	"UDim",
	"UDim2",
	"Font",
	"BrickColor",
	"NumberRange",
	"NumberSequence",
	"NumberSequenceKeypoint",
	"ColorSequence",
	"ColorSequenceKeypoint",
	"Rect",
	"PhysicalProperties",
	"Ray",
	"Faces",
	"Axes",
}

-- Serviços falsos que os testes podem registrar (ex.: RunService)
Ambiente.Servicos = {} :: { [string]: any }

-- Objetos falsos por caminho, devolvidos por WaitForChild/FindFirstChild
-- (ex.: Ambiente.Falsos["ReplicatedStorage/Remotos"] = pastaComRemotesFalsos)
Ambiente.Falsos = {} :: { [string]: any }

-- Biblioteca "task" usada pelos módulos (os testes podem trocar por uma mais rápida)
Ambiente.Task = task

-- "Instance" e "os" usados pelos módulos (a simulação troca por versões falsas)
Ambiente.Instance = roblox.Instance
Ambiente.Os = os

-- Random do Roblox (o Lune não tem): mesma interface básica
local RandomFalso = {}
RandomFalso.__index = RandomFalso
function RandomFalso.new(semente: number?)
	local estado = math.floor(semente or (os.clock() * 1000)) % 2147483646 + 1
	return setmetatable({ estado = estado }, RandomFalso)
end
function RandomFalso:_proximo(): number
	self.estado = (self.estado * 16807) % 2147483647
	return (self.estado - 1) / 2147483646
end
function RandomFalso:NextNumber(minimo: number?, maximo: number?): number
	local a, b = minimo or 0, maximo or 1
	return a + (b - a) * self:_proximo()
end
function RandomFalso:NextInteger(minimo: number, maximo: number): number
	return minimo + math.floor(self:_proximo() * (maximo - minimo + 1))
end
Ambiente.Random = RandomFalso

-- ------------------------------------------------------------
-- Referências falsas de instâncias (script, script.Parent.X, ...)
-- ------------------------------------------------------------

local Ref = {}

local function novaRef(caminho: string): any
	return setmetatable({ __caminho = caminho }, Ref)
end

Ref.__index = function(self, chave)
	local caminho = rawget(self, "__caminho")
	if chave == "Parent" then
		local pai = string.match(caminho, "^(.*)/[^/]+$")
		return if pai then novaRef(pai) else nil
	elseif chave == "Name" then
		return string.match(caminho, "([^/]+)$")
	elseif chave == "WaitForChild" or chave == "FindFirstChild" then
		return function(_, nome: string)
			local filho = caminho .. "/" .. nome
			return Ambiente.Falsos[filho] or novaRef(filho)
		end
	elseif chave == "GetFullName" then
		return function()
			return caminho
		end
	end
	return novaRef(caminho .. "/" .. tostring(chave))
end

Ref.__tostring = function(self)
	return "Ref(" .. rawget(self, "__caminho") .. ")"
end

local function arquivoDe(caminho: string): string?
	for _, raiz in RAIZES do
		local prefixo = raiz.Caminho
		if caminho == prefixo or string.sub(caminho, 1, #prefixo + 1) == prefixo .. "/" then
			local resto = string.sub(caminho, #prefixo + 2)
			local base = raiz.Pasta .. (if resto ~= "" then "/" .. resto else "")
			for _, sufixo in { ".lua", ".luau", ".server.lua", ".client.lua", "/init.lua", "/init.luau" } do
				if fs.isFile(base .. sufixo) then
					return base .. sufixo
				end
			end
		end
	end
	return nil
end

-- ------------------------------------------------------------
-- Carregamento de módulos
-- ------------------------------------------------------------

local cache: { [string]: any } = {}
local carregar: (caminho: string) -> any

-- "game" falso (os testes podem mudar JobId e ler Ambiente.aoFechar)
Ambiente.Jogo = {
	JobId = "servidor-lune",
	GetService = function(_, nome: string)
		return Ambiente.Servicos[nome] or novaRef(nome)
	end,
	BindToClose = function(_, funcao)
		Ambiente.aoFechar = funcao
	end,
}
Ambiente.aoFechar = nil :: (() -> ())?

local function criarAmbiente(caminho: string): { [string]: any }
	local env: { [string]: any } = {}
	for _, nome in TIPOS_ROBLOX do
		env[nome] = (roblox :: any)[nome]
	end
	env.script = novaRef(caminho)
	env.game = Ambiente.Jogo
	env.workspace = Ambiente.Servicos.Workspace
	env.task = Ambiente.Task
	env.Random = Ambiente.Random
	env.Instance = Ambiente.Instance
	env.os = Ambiente.Os
	env.warn = function(...)
		print("[warn]", ...)
	end
	env.require = function(alvo: any)
		if type(alvo) == "table" and rawget(alvo, "__caminho") then
			return carregar(rawget(alvo, "__caminho"))
		end
		error("require inválido: " .. tostring(alvo))
	end
	return env
end

carregar = function(caminho: string): any
	if cache[caminho] ~= nil then
		return cache[caminho]
	end
	local arquivo = arquivoDe(caminho)
	if not arquivo then
		error("[ambiente] Módulo não encontrado: " .. caminho)
	end
	local fonte = fs.readFile(arquivo)
	local funcao = luau.load(fonte, {
		debugName = arquivo,
		environment = criarAmbiente(caminho),
	})
	local resultado = funcao()
	cache[caminho] = resultado
	return resultado
end

-- Carrega um módulo pelo caminho do Roblox, ex.: "ReplicatedStorage/Shared/Config"
function Ambiente.carregar(caminho: string): any
	return carregar(caminho)
end

-- Esquece os módulos já carregados (para testar com outra configuração)
function Ambiente.limparCache()
	table.clear(cache)
end

Ambiente.roblox = roblox

return Ambiente
