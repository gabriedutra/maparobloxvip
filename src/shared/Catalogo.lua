--[[
	Catalogo.lua
	Monta tabelas de consulta a partir do Config (raridades e monstrinhos)
	e faz o sorteio de monstrinhos da esteira.
	Valida o Config ao carregar: se algo estiver errado, o erro explica o quê.
]]

local Config = require(script.Parent.Config)

local Catalogo = {}

export type Raridade = {
	Id: string,
	Nome: string,
	Chance: number,
	Cor: Color3,
	Tamanho: number,
	Luz: number,
	Particulas: boolean,
	Estrelas: boolean,
	Aura: boolean,
	ArcoIris: boolean,
	Anunciar: boolean,
	Ordem: number,
}

export type Monstrinho = {
	Id: string,
	Nome: string,
	Raridade: string,
	Preco: number,
	Renda: number,
	Forma: string,
	Cor: Color3,
	CorDetalhe: Color3,
	Olhos: number,
	Extras: { string },
	Material: Enum.Material?,
	Transparencia: number?,
	Arcoiris: boolean?,
	Peso: number?,
}

Catalogo.Raridades = {} :: { Raridade } -- em ordem (da mais comum para a mais rara)
Catalogo.RaridadePorId = {} :: { [string]: Raridade }
Catalogo.Monstrinhos = {} :: { [string]: Monstrinho }
Catalogo.Lista = {} :: { Monstrinho } -- na ordem do Config
Catalogo.PorRaridade = {} :: { [string]: { Monstrinho } }

local FORMAS = { Bola = true, Cubo = true, Cilindro = true }

local function erroConfig(mensagem: string)
	error("[Config.lua] " .. mensagem, 0)
end

-- Raridades
for ordem, r in Config.Raridades do
	if type(r.Id) ~= "string" or Catalogo.RaridadePorId[r.Id] then
		erroConfig("Raridade #" .. ordem .. " sem Id ou com Id repetido.")
	end
	if type(r.Chance) ~= "number" or r.Chance < 0 then
		erroConfig("Raridade '" .. r.Id .. "' precisa de uma Chance >= 0.")
	end
	local raridade = table.clone(r) :: any
	raridade.Ordem = ordem
	table.insert(Catalogo.Raridades, raridade)
	Catalogo.RaridadePorId[r.Id] = raridade
	Catalogo.PorRaridade[r.Id] = {}
end

-- Monstrinhos
for indice, m in Config.Monstrinhos do
	local nome = tostring(m.Id or ("#" .. indice))
	if type(m.Id) ~= "string" or m.Id == "" then
		erroConfig("Monstrinho #" .. indice .. " está sem Id.")
	end
	if Catalogo.Monstrinhos[m.Id] then
		erroConfig("Id de monstrinho repetido: '" .. m.Id .. "'.")
	end
	if not Catalogo.RaridadePorId[m.Raridade] then
		erroConfig("Monstrinho '" .. nome .. "' usa a raridade desconhecida '" .. tostring(m.Raridade) .. "'.")
	end
	if type(m.Preco) ~= "number" or m.Preco < 0 then
		erroConfig("Monstrinho '" .. nome .. "' precisa de um Preco >= 0.")
	end
	if type(m.Renda) ~= "number" or m.Renda < 0 then
		erroConfig("Monstrinho '" .. nome .. "' precisa de uma Renda >= 0.")
	end
	if not FORMAS[m.Forma] then
		erroConfig("Monstrinho '" .. nome .. "' tem Forma inválida (use Bola, Cubo ou Cilindro).")
	end
	local info = table.clone(m) :: any
	info.Extras = info.Extras or {}
	info.Olhos = math.clamp(math.floor(info.Olhos or 2), 1, 3)
	Catalogo.Monstrinhos[m.Id] = info
	table.insert(Catalogo.Lista, info)
	table.insert(Catalogo.PorRaridade[m.Raridade], info)
end

if #Catalogo.Lista == 0 then
	erroConfig("Nenhum monstrinho configurado em Config.Monstrinhos.")
end

function Catalogo.obter(id: any): Monstrinho?
	if type(id) ~= "string" then
		return nil
	end
	return Catalogo.Monstrinhos[id]
end

function Catalogo.raridadeDe(info: Monstrinho): Raridade
	return Catalogo.RaridadePorId[info.Raridade]
end

-- Peso efetivo de cada raridade (considerando o boost de sorte, se houver)
local function pesoRaridade(raridade: Raridade, multiplicadores: { [string]: number }?): number
	if #Catalogo.PorRaridade[raridade.Id] == 0 then
		return 0
	end
	local mult = 1
	if multiplicadores and type(multiplicadores[raridade.Id]) == "number" then
		mult = multiplicadores[raridade.Id]
	end
	return math.max(0, raridade.Chance * mult)
end

-- Chance (em %) de cada raridade aparecer; útil para mostrar na interface
function Catalogo.chances(multiplicadores: { [string]: number }?): { [string]: number }
	local total = 0
	for _, r in Catalogo.Raridades do
		total += pesoRaridade(r, multiplicadores)
	end
	local resultado = {}
	for _, r in Catalogo.Raridades do
		resultado[r.Id] = if total > 0 then pesoRaridade(r, multiplicadores) / total * 100 else 0
	end
	return resultado
end

-- aleatorio: função que devolve um número em [0, 1)
function Catalogo.sortearRaridade(aleatorio: () -> number, multiplicadores: { [string]: number }?): Raridade
	local total = 0
	for _, r in Catalogo.Raridades do
		total += pesoRaridade(r, multiplicadores)
	end
	local sorteio = aleatorio() * total
	local ultimaValida: Raridade? = nil
	for _, r in Catalogo.Raridades do
		local peso = pesoRaridade(r, multiplicadores)
		if peso > 0 then
			ultimaValida = r
			sorteio -= peso
			if sorteio < 0 then
				return r
			end
		end
	end
	-- Arredondamento: devolve a última raridade possível
	return ultimaValida or Catalogo.Raridades[1]
end

function Catalogo.sortear(aleatorio: () -> number, multiplicadores: { [string]: number }?): Monstrinho
	local raridade = Catalogo.sortearRaridade(aleatorio, multiplicadores)
	local opcoes = Catalogo.PorRaridade[raridade.Id]
	if #opcoes == 0 then
		return Catalogo.Lista[1]
	end
	local total = 0
	for _, m in opcoes do
		total += math.max(0, m.Peso or 1)
	end
	local sorteio = aleatorio() * total
	for _, m in opcoes do
		sorteio -= math.max(0, m.Peso or 1)
		if sorteio < 0 then
			return m
		end
	end
	return opcoes[#opcoes]
end

return Catalogo
