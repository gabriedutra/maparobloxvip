--[[
	Notificar.lua
	Envia mensagens para a tela dos jogadores.
	Tipos: "sucesso", "erro", "info", "alerta", "dinheiro".
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotos = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotos"))

local Notificar = {}

function Notificar.jogador(player: Player?, texto: string, tipo: string?)
	if player and player.Parent then
		Remotos.Notificacao:FireClient(player, texto, tipo or "info")
	end
end

function Notificar.todos(texto: string, tipo: string?)
	Remotos.Notificacao:FireAllClients(texto, tipo or "info")
end

-- Aviso grande no topo da tela de todo mundo (e no chat)
function Notificar.avisoGlobal(titulo: string, texto: string, cor: Color3)
	Remotos.AvisoGlobal:FireAllClients({ Titulo = titulo, Texto = texto, Cor = cor })
end

return Notificar
