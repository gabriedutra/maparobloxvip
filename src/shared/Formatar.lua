--[[
	Formatar.lua
	Funções de formatação de números e tempo no padrão brasileiro
	(vírgula como separador decimal): 950, 1,5K, 12,3M, 4B...
]]

local Formatar = {}

local SUFIXOS = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

-- Troca o ponto decimal por vírgula e remove zeros sobrando ("1,50" -> "1,5", "2,00" -> "2")
local function limparDecimais(texto: string): string
	if string.find(texto, ".", 1, true) then
		texto = string.gsub(texto, "0+$", "")
		texto = string.gsub(texto, "%.$", "")
	end
	return (string.gsub(texto, "%.", ","))
end

-- Número abreviado. Sempre arredonda para BAIXO (nunca mostra mais do que o jogador tem).
function Formatar.numero(valor: number, casasAbaixoDeMil: number?): string
	if type(valor) ~= "number" or valor ~= valor then
		return "0"
	end
	if valor == math.huge or valor == -math.huge then
		return if valor > 0 then "∞" else "-∞"
	end
	local sinal = ""
	if valor < 0 then
		sinal = "-"
		valor = -valor
	end

	if valor < 1000 then
		local casas = casasAbaixoDeMil or 0
		if casas <= 0 or valor == math.floor(valor) then
			return sinal .. tostring(math.floor(valor))
		end
		local fator = 10 ^ casas
		local truncado = math.floor(valor * fator) / fator
		return sinal .. limparDecimais(string.format("%." .. casas .. "f", truncado))
	end

	local grupo = math.floor(math.log10(valor) / 3)
	grupo = math.clamp(grupo, 1, #SUFIXOS - 1)
	local reduzido = valor / (1000 ^ grupo)
	-- Correção de ponto flutuante (ex.: 999.9999 por causa do log10)
	if reduzido >= 1000 and grupo < #SUFIXOS - 1 then
		grupo += 1
		reduzido = valor / (1000 ^ grupo)
	end

	local texto
	if reduzido >= 100 then
		texto = tostring(math.floor(reduzido))
	elseif reduzido >= 10 then
		texto = limparDecimais(string.format("%.1f", math.floor(reduzido * 10) / 10))
	else
		texto = limparDecimais(string.format("%.2f", math.floor(reduzido * 100) / 100))
	end
	return sinal .. texto .. SUFIXOS[grupo + 1]
end

function Formatar.dinheiro(valor: number): string
	return "$" .. Formatar.numero(valor)
end

-- Renda por segundo: mostra 1 casa decimal para valores pequenos (ex.: $1,5/s)
function Formatar.renda(valor: number): string
	return "$" .. Formatar.numero(valor, 1) .. "/s"
end

-- Multiplicador: x1, x1,5, x2,25
function Formatar.multiplicador(valor: number): string
	local arredondado = math.floor(valor * 100 + 0.5) / 100
	return "x" .. limparDecimais(string.format("%.2f", arredondado))
end

-- Tempo: 45s, 1:05, 1:02:03
function Formatar.tempo(segundos: number): string
	segundos = math.max(0, math.ceil(segundos))
	if segundos < 60 then
		return segundos .. "s"
	end
	local horas = math.floor(segundos / 3600)
	local minutos = math.floor((segundos % 3600) / 60)
	local resto = segundos % 60
	if horas > 0 then
		return string.format("%d:%02d:%02d", horas, minutos, resto)
	end
	return string.format("%d:%02d", minutos, resto)
end

return Formatar
