--[[
	Jogadores.lua
	Guarda o estado de cada jogador enquanto ele está no servidor.
	Os dados persistentes (dinheiro, rebirths, monstrinhos...) ficam em
	estado.Dados e são carregados/salvos pelo módulo Dados.
]]

local Jogadores = {}

export type DadosJogador = {
	Versao: number,
	Dinheiro: number,
	Coletor: number, -- dinheiro acumulado no coletor da base (ainda não coletado)
	Rebirths: number,
	Monstrinhos: { { Id: string, Slot: number } },
	ComprasProcessadas: { [string]: number }, -- PurchaseId -> os.time() (idempotência)
}

export type Estado = {
	Player: Player,
	Dados: DadosJogador?,
	Carregado: boolean, -- true quando os dados vieram do DataStore
	Passes: { [string]: boolean }, -- Game Passes que o jogador possui
	RendaBase: number, -- soma da renda dos monstrinhos da base (sem multiplicador)
	MonstrinhosRestaurados: boolean, -- true quando os monstrinhos salvos já foram colocados na base
	Excedentes: { { Id: string, Slot: number } }, -- monstrinhos salvos que não couberam na base
	ProcessandoCompras: { [string]: boolean },
}

local estados: { [Player]: Estado } = {}

function Jogadores.criar(player: Player): Estado
	local estado: Estado = {
		Player = player,
		Dados = nil,
		Carregado = false,
		Passes = {},
		RendaBase = 0,
		MonstrinhosRestaurados = false,
		Excedentes = {},
		ProcessandoCompras = {},
	}
	estados[player] = estado
	return estado
end

function Jogadores.obter(player: Player): Estado?
	return estados[player]
end

-- Estado só se os dados já estiverem carregados
function Jogadores.obterCarregado(player: Player): Estado?
	local estado = estados[player]
	if estado and estado.Carregado and estado.Dados then
		return estado
	end
	return nil
end

function Jogadores.remover(player: Player)
	estados[player] = nil
end

return Jogadores
