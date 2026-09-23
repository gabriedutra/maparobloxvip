--[[
	gerar_mapa.luau — gera mapa/Mapa.rbxmx a partir do Config.lua.

	Uso (na pasta do projeto):
	    lune run ferramentas/gerar_mapa
	    rojo build -o RoubeOMonstrinho.rbxlx

	O Rojo coloca o mapa gerado em Workspace.Mapa. Assim o mapa aparece
	no Studio mesmo antes de apertar Play.
]]

local fs = require("@lune/fs")
local Ambiente = require("./ambiente")

local MapaConstrutor = Ambiente.carregar("ServerScriptService/Servidor/Servicos/MapaConstrutor")

local mapa = MapaConstrutor.construir()

local total = 0
for _, descendente in mapa:GetDescendants() do
	if descendente:IsA("BasePart") then
		total += 1
	end
end

local xml = Ambiente.roblox.serializeModel({ mapa }, true)
if not fs.isDir("mapa") then
	fs.writeDir("mapa")
end
fs.writeFile("mapa/Mapa.rbxmx", xml)

print(("Mapa gerado: mapa/Mapa.rbxmx (%d peças, assinatura %s)"):format(total, mapa:GetAttribute("AssinaturaLayout")))
