--[[
	Main.client.lua — ponto de entrada do cliente de "Roube o Monstrinho".
	Monta a interface (HUD, loja, chances, avisos), filtra os prompts e liga a tag VIP no chat.
]]

local Players = game:GetService("Players")

local Interface = script.Parent:WaitForChild("Interface")
local Avisos = require(Interface:WaitForChild("Avisos"))
local Chances = require(Interface:WaitForChild("Chances"))
local ChatVIP = require(Interface:WaitForChild("ChatVIP"))
local HUD = require(Interface:WaitForChild("HUD"))
local Loja = require(Interface:WaitForChild("Loja"))
local Prompts = require(Interface:WaitForChild("Prompts"))
local UI = require(Interface:WaitForChild("UI"))

local jogador = Players.LocalPlayer

local tela: ScreenGui = UI.criar("ScreenGui", {
	Name = "RoubeOMonstrinhoUI",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = jogador:WaitForChild("PlayerGui"),
})

Avisos.iniciar(tela)
Chances.iniciar(tela)
Loja.iniciar(tela)
HUD.iniciar(tela, { abrirLoja = Loja.alternar, abrirChances = Chances.alternar })
Prompts.iniciar()
ChatVIP.iniciar()
