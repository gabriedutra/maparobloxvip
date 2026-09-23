--[[
	ChatVIP.lua
	Coloca a tag [VIP] (Config.Bonus.TagVIP) antes do nome de quem tem o
	Game Pass VIP. O servidor marca o jogador com o atributo "VIP".
	Usa o TextChatService (chat novo do Roblox).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local ChatVIP = {}

function ChatVIP.iniciar()
	if TextChatService.ChatVersion ~= Enum.ChatVersion.TextChatService then
		warn("[ChatVIP] A tag VIP precisa do TextChatService (TextChatService.ChatVersion).")
		return
	end
	local corTag = Config.Bonus.CorTagVIP:ToHex()
	TextChatService.OnIncomingMessage = function(mensagem: TextChatMessage)
		local propriedades = Instance.new("TextChatMessageProperties")
		local fonte = mensagem.TextSource
		if fonte then
			local autor = Players:GetPlayerByUserId(fonte.UserId)
			if autor and autor:GetAttribute("VIP") == true then
				propriedades.PrefixText = '<font color="#' .. corTag .. '">' .. Config.Bonus.TagVIP .. "</font> " .. mensagem.PrefixText
			end
		end
		return propriedades
	end
end

return ChatVIP
