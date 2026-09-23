--[[
	Limitador.lua
	Anti-spam: limita quantas vezes cada jogador pode fazer uma ação.
	Ex.: Limitador.permitir(player, "Trancar", 1) -> no máximo 1 vez por segundo.
]]

local Limitador = {}

local ultimos: { [Player]: { [string]: number } } = {}

function Limitador.permitir(player: Player, acao: string, intervalo: number): boolean
	local agora = os.clock()
	local registro = ultimos[player]
	if not registro then
		registro = {}
		ultimos[player] = registro
	end
	local ultimo = registro[acao]
	if ultimo and agora - ultimo < intervalo then
		return false
	end
	registro[acao] = agora
	return true
end

function Limitador.limpar(player: Player)
	ultimos[player] = nil
end

return Limitador
