--[[
	Politica.lua
	Regras do Roblox por país e idade (PolicyService).

	Em alguns lugares a lei não deixa vender itens aleatórios pagos, e o
	Roblox trata a "Sorte na Esteira" (boost de sorte) como um deles. Quando
	ArePaidRandomItemsRestricted é true para o jogador, a loja não oferece a
	Sorte para ele. Se o Roblox não responder, a Sorte também não é oferecida
	(é o mais seguro). É isso que permite responder "sim" no questionário de
	maturidade: "o jogo respeita ArePaidRandomItemsRestricted".
]]

local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")

local Politica = {}

local TENTATIVAS = 3

-- nil = ainda consultando; true = pode oferecer a Sorte; false = não pode
local podeSorte: boolean? = nil
local ouvintes: { (boolean) -> () } = {}

local function definir(valor: boolean)
	podeSorte = valor
	for _, funcao in ouvintes do
		task.spawn(funcao, valor)
	end
end

function Politica.podeVenderSorte(): boolean?
	return podeSorte
end

-- Chama a função quando a resposta do Roblox chegar (e se ela mudar)
function Politica.aoMudar(funcao: (boolean) -> ())
	table.insert(ouvintes, funcao)
end

function Politica.iniciar()
	task.spawn(function()
		for tentativa = 1, TENTATIVAS do
			local ok, info = pcall(function()
				return PolicyService:GetPolicyInfoForPlayerAsync(Players.LocalPlayer)
			end)
			if ok and type(info) == "table" then
				definir(info.ArePaidRandomItemsRestricted ~= true)
				return
			end
			if tentativa < TENTATIVAS then
				task.wait(2 * tentativa)
			end
		end
		definir(false)
	end)
end

return Politica
