--[[
	Remotos.lua
	Acesso aos RemoteEvents (definidos no default.project.json, pasta
	ReplicatedStorage.Remotos). Funciona no servidor e no cliente.

	Cliente -> Servidor (pedidos; o servidor valida tudo):
	  PedirTrancar   ()  — trancar a própria base
	  PedirRenascer  ()  — fazer rebirth

	Servidor -> Cliente:
	  Notificacao    (texto: string, tipo: string)
	  AvisoGlobal    ({ Titulo: string, Texto: string, Cor: Color3 })
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local pasta = ReplicatedStorage:WaitForChild("Remotos")

local Remotos = {
	PedirTrancar = pasta:WaitForChild("PedirTrancar") :: RemoteEvent,
	PedirRenascer = pasta:WaitForChild("PedirRenascer") :: RemoteEvent,
	Notificacao = pasta:WaitForChild("Notificacao") :: RemoteEvent,
	AvisoGlobal = pasta:WaitForChild("AvisoGlobal") :: RemoteEvent,
}

return Remotos
