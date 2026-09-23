--[[
	Regras.lua
	Fórmulas do jogo usadas pelo servidor (que decide) e pelo cliente
	(que só mostra os valores na tela). Tudo baseado no Config.
]]

local Config = require(script.Parent.Config)

local Regras = {}

-- Quanto custa o próximo rebirth para quem já tem "rebirths" rebirths
function Regras.custoRebirth(rebirths: number): number
	return math.floor(Config.Rebirth.CustoBase * (Config.Rebirth.CrescimentoCusto ^ rebirths))
end

-- Multiplicador permanente vindo dos rebirths
function Regras.multiplicadorRebirth(rebirths: number): number
	return 1 + rebirths * Config.Rebirth.BonusPorRebirth
end

-- Multiplicador total de renda (rebirths x VIP x 2x Dinheiro)
function Regras.multiplicadorTotal(rebirths: number, temVIP: boolean, temDinheiroDobrado: boolean): number
	local mult = Regras.multiplicadorRebirth(rebirths)
	if temVIP then
		mult *= Config.Bonus.VIPMultiplicador
	end
	if temDinheiroDobrado then
		mult *= Config.Bonus.DinheiroDobradoMultiplicador
	end
	return mult
end

-- Valor recebido ao vender um monstrinho da própria base
function Regras.precoVenda(info: { Preco: number }): number
	return math.floor(info.Preco * Config.Venda.Percentual)
end

-- Quantos slots o jogador pode usar
function Regras.slotsDisponiveis(temSlotsExtras: boolean): number
	return Config.Base.SlotsIniciais + (if temSlotsExtras then Config.Base.SlotsExtras else 0)
end

-- Valor do pacote de dinheiro (Developer Product)
function Regras.valorPacoteDinheiro(rendaPorSegundo: number): number
	local porRenda = rendaPorSegundo * 60 * Config.PacoteDinheiro.MinutosDeRenda
	return math.floor(math.max(Config.PacoteDinheiro.Minimo, porRenda))
end

-- WalkSpeed de quem está carregando um monstrinho roubado
function Regras.velocidadeCarregando(temCarregarRapido: boolean): number
	return if temCarregarRapido then Config.Roubo.VelocidadeCarregandoRapido else Config.Roubo.VelocidadeCarregando
end

return Regras
