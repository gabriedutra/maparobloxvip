--[[
	Prompts.lua
	Mostra só os ProximityPrompts que fazem sentido para você:
	  • "Roubar" aparece nos monstrinhos dos OUTROS (se a base não estiver
	    trancada e ninguém já estiver roubando);
	  • "Vender" aparece só nos SEUS monstrinhos;
	  • "Comprar" (esteira) aparece sempre.
	Isto é só visual: o servidor valida tudo de novo.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local Prompts = {}

local jogador = Players.LocalPlayer
local TAG = "PromptMonstrinho"

local function atualizar(instancia: Instance)
	if not instancia:IsA("ProximityPrompt") then
		return
	end
	local acao = instancia:GetAttribute("Acao")
	if acao ~= "Roubar" and acao ~= "Vender" then
		return
	end
	local raiz = instancia.Parent
	local modelo = raiz and raiz.Parent
	if not modelo then
		return
	end
	local dono = modelo:GetAttribute("DonoUserId")
	local trancado = modelo:GetAttribute("Trancado") == true
	local sendoRoubado = modelo:GetAttribute("SendoRoubado") == true
	local ehMeu = dono == jogador.UserId

	local habilitar
	if acao == "Roubar" then
		habilitar = type(dono) == "number" and dono ~= 0 and not ehMeu and not trancado and not sendoRoubado
	else
		habilitar = ehMeu and not sendoRoubado
	end
	if instancia.Enabled ~= habilitar then
		instancia.Enabled = habilitar
	end
end

function Prompts.iniciar()
	CollectionService:GetInstanceAddedSignal(TAG):Connect(atualizar)
	task.spawn(function()
		while true do
			for _, prompt in CollectionService:GetTagged(TAG) do
				atualizar(prompt)
			end
			task.wait(0.2)
		end
	end)
end

return Prompts
