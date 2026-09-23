--[[
	Mapa.lua
	Encontra as peças do mapa (Workspace.Mapa) que a lógica do jogo usa.
	Se o mapa não existir ou estiver diferente do Config.lua, reconstrói
	com o MapaConstrutor.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local MapaConstrutor = require(script.Parent.MapaConstrutor)

local Mapa = {}

export type SlotInfo = {
	Indice: number,
	Parte: BasePart,
	Extra: boolean,
}

export type BaseInfo = {
	Indice: number,
	Modelo: Model,
	Chao: BasePart,
	Barreira: BasePart,
	Coletor: BasePart,
	BotaoTrancar: BasePart,
	Spawn: SpawnLocation,
	Placa: BasePart,
	Slots: { SlotInfo },
}

export type MapaInfo = {
	Modelo: Model,
	Inicio: BasePart,
	Fim: BasePart,
	Bases: { BaseInfo },
}

-- Procura um filho obrigatório e dá um erro claro se ele não existir
local function exigir(pai: Instance, nome: string): any
	local filho = pai:FindFirstChild(nome)
	if not filho then
		error(("[Mapa] Não encontrei '%s' dentro de '%s'. Não renomeie/apague as peças do mapa."):format(nome, pai:GetFullName()), 0)
	end
	return filho
end

function Mapa.iniciar(): MapaInfo
	local assinatura = MapaConstrutor.assinatura()
	local modelo = workspace:FindFirstChild("Mapa")

	if modelo and modelo:GetAttribute("AssinaturaLayout") ~= assinatura then
		warn(
			"[Mapa] O mapa salvo não corresponde ao Config.lua; reconstruindo em tempo de execução. "
				.. "Para ver o mapa novo no Studio rode: lune run ferramentas/gerar_mapa  e depois  rojo build."
		)
		modelo:Destroy()
		modelo = nil
	end
	if not modelo then
		modelo = MapaConstrutor.construir()
		modelo.Parent = workspace
	end

	local esteira = exigir(modelo, "Esteira")
	local info: MapaInfo = {
		Modelo = modelo,
		Inicio = exigir(esteira, "Inicio"),
		Fim = exigir(esteira, "Fim"),
		Bases = {},
	}

	local pastaBases = exigir(modelo, "Bases")
	local totalSlots = Config.Base.SlotsIniciais + Config.Base.SlotsExtras
	for i = 1, Config.Base.Quantidade do
		local base = exigir(pastaBases, "Base" .. i) :: Model
		local pastaSlots = exigir(base, "Slots")
		local slots: { SlotInfo } = {}
		for s = 1, totalSlots do
			local parte = exigir(pastaSlots, "Slot" .. s) :: BasePart
			table.insert(slots, {
				Indice = s,
				Parte = parte,
				Extra = parte:GetAttribute("Extra") == true,
			})
		end
		table.insert(info.Bases, {
			Indice = i,
			Modelo = base,
			Chao = exigir(base, "Chao"),
			Barreira = exigir(base, "Barreira"),
			Coletor = exigir(base, "Coletor"),
			BotaoTrancar = exigir(base, "BotaoTrancar"),
			Spawn = exigir(base, "Spawn"),
			Placa = exigir(base, "Placa"),
			Slots = slots,
		})
	end
	return info
end

return Mapa
