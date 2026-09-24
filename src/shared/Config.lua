--[[
	============================================================
	  ROUBE O MONSTRINHO — Config.lua
	============================================================
	Todas as configurações do jogo ficam aqui: IDs de monetização,
	preços, chances, rendas, tempos e o layout do mapa.

	Este módulo fica em ReplicatedStorage.Shared e é lido pelo
	servidor e pelo cliente. Não coloque segredos aqui.

	>>> PASSO 1: preencha os IDs dos Game Passes e Developer Products
	    (Creator Hub > sua experiência > Monetização). Enquanto um ID
	    for 0, o item aparece na loja como "Em breve" e não pode ser
	    comprado.
]]

local Config = {}

-- ============================================================
-- MONETIZAÇÃO — coloque aqui os seus IDs
-- ============================================================

Config.GamePasses = {
	VIP = 1995224348, -- Tag [VIP] no chat + renda 1.5x
	DinheiroDobrado = 1994276361, -- 2x Dinheiro (renda dobrada)
	SlotsExtras = 1996022354, -- +4 slots na base
	CarregarRapido = 1995200362, -- Anda mais rápido carregando um monstrinho roubado
}

Config.Produtos = {
	TrancarAgora = 3714489689, -- Tranca a base na hora (ignora o cooldown)
	SorteBoost = 3714489735, -- Sorte na esteira por 10 minutos (vale para o servidor todo)
	PacoteDinheiro = 3714489748, -- Pacote de dinheiro
}

-- Como cada item aparece na loja (a chave precisa bater com as tabelas acima)
Config.Loja = {
	GamePasses = {
		{
			Chave = "VIP",
			Nome = "VIP",
			Emoji = "👑",
			Descricao = "Tag [VIP] no chat e 1.5x de renda para sempre!",
			Cor = Color3.fromRGB(255, 196, 40),
		},
		{
			Chave = "DinheiroDobrado",
			Nome = "2x Dinheiro",
			Emoji = "💸",
			Descricao = "Todos os seus monstrinhos rendem o dobro.",
			Cor = Color3.fromRGB(70, 210, 110),
		},
		{
			Chave = "SlotsExtras",
			Nome = "+4 Slots",
			Emoji = "🧱",
			Descricao = "Libera 4 slots extras (dourados) na sua base.",
			Cor = Color3.fromRGB(80, 150, 255),
		},
		{
			Chave = "CarregarRapido",
			Nome = "Carregar Rápido",
			Emoji = "⚡",
			Descricao = "Corra bem mais rápido carregando um monstrinho roubado.",
			Cor = Color3.fromRGB(255, 120, 50),
		},
	},
	Produtos = {
		{
			Chave = "TrancarAgora",
			Nome = "Trancar Agora",
			Emoji = "🔒",
			Descricao = "Tranca sua base na hora, sem esperar o cooldown.",
			Cor = Color3.fromRGB(235, 70, 80),
		},
		{
			Chave = "SorteBoost",
			Nome = "Sorte na Esteira (10 min)",
			Emoji = "🍀",
			Descricao = "Raros aparecem bem mais na esteira do servidor por 10 min!",
			Cor = Color3.fromRGB(60, 200, 90),
		},
		{
			Chave = "PacoteDinheiro",
			Nome = "Pacote de Dinheiro",
			Emoji = "💰",
			Descricao = "Dinheiro na hora! O valor cresce junto com a sua renda.",
			Cor = Color3.fromRGB(255, 205, 60),
		},
	},
}

-- Efeitos dos Game Passes
Config.Bonus = {
	VIPMultiplicador = 1.5, -- VIP: renda x1.5
	DinheiroDobradoMultiplicador = 2, -- 2x Dinheiro: renda x2
	TagVIP = "[VIP]", -- texto da tag no chat
	CorTagVIP = Color3.fromRGB(255, 205, 60),
}

-- Pacote de dinheiro (Developer Product): o jogador ganha o MAIOR valor entre
-- "Minimo" e "MinutosDeRenda" minutos da renda atual dele.
Config.PacoteDinheiro = {
	Minimo = 10_000,
	MinutosDeRenda = 15,
}

-- ============================================================
-- ECONOMIA
-- ============================================================

Config.Economia = {
	DinheiroInicial = 100, -- dinheiro de quem entra pela primeira vez (e após rebirth)
	IntervaloRenda = 1, -- a cada X segundos a renda cai no coletor da base
}

-- Rebirth: ao juntar o valor, o jogador reseta e ganha multiplicador permanente
Config.Rebirth = {
	CustoBase = 5_000_000, -- custo do 1º rebirth
	CrescimentoCusto = 3, -- cada rebirth custa 3x o anterior
	BonusPorRebirth = 0.5, -- +50% de renda por rebirth (1 rebirth = x1.5, 2 = x2.0, ...)
	ResetarMonstrinhos = true, -- se true, os monstrinhos da base são perdidos no rebirth
}

-- Venda de monstrinhos da própria base (libera espaço)
Config.Venda = {
	Ativa = true,
	Percentual = 0.5, -- vende por 50% do preço de compra
	TempoSegurar = 1, -- segundos segurando o botão
	DistanciaPrompt = 7,
}

-- Compra na esteira
Config.Compra = {
	TempoSegurar = 0, -- 0 = compra instantânea ao apertar E
	DistanciaPrompt = 12,
}

-- ============================================================
-- ESTEIRA
-- ============================================================

Config.Esteira = {
	IntervaloSpawn = 3.5, -- segundos entre um monstrinho e outro
	Velocidade = 7, -- studs por segundo
	GiroPorSegundo = 40, -- rotação dos monstrinhos na esteira (graus/s)
	MaximoNaEsteira = 25, -- limite de monstrinhos ao mesmo tempo
}

-- Boost de sorte (Developer Product "SorteBoost")
-- As chances com e sem sorte aparecem no jogo (botão "🎲 Chances" e antes de
-- comprar), como o Roblox exige para itens pagos que mexem na sorte.
Config.Sorte = {
	Duracao = 600, -- 10 minutos (compras repetidas somam tempo)
	-- A chance de cada raridade é multiplicada por estes valores enquanto a sorte estiver ativa
	Multiplicadores = {
		Comum = 1,
		Incomum = 1.5,
		Raro = 2.5,
		Epico = 4,
		Lendario = 6,
		Mitico = 8,
	},
}

-- ============================================================
-- ROUBO
-- ============================================================

Config.Roubo = {
	TempoSegurar = 2.5, -- segundos segurando o botão para pegar o monstrinho
	DistanciaPrompt = 6,
	DistanciaToque = 6, -- se o DONO chegar a essa distância do ladrão, o roubo falha
	TempoMaximo = 60, -- se o ladrão não chegar na base nesse tempo, o monstrinho volta
	Recarga = 3, -- tempo mínimo entre duas tentativas de roubo
	VelocidadeNormal = 16, -- WalkSpeed padrão do Roblox
	VelocidadeCarregando = 13, -- WalkSpeed carregando um monstrinho
	VelocidadeCarregandoRapido = 22, -- WalkSpeed carregando com o Game Pass "Carregar Rápido"
}

-- ============================================================
-- TRANCAR BASE
-- ============================================================

Config.Trancar = {
	Duracao = 60, -- a base fica trancada por 60 segundos
	Recarga = 45, -- depois que destranca, espera 45 s para trancar de novo
}

-- ============================================================
-- ANTI-EXPLOIT
-- ============================================================

Config.AntiExploit = {
	ToleranciaDistancia = 5, -- folga (studs) sobre a distância dos prompts (compensa o ping)
	VelocidadeMaxima = 60, -- velocidade máxima aceita carregando um monstrinho (studs/s)
	MargemTeleporte = 10, -- folga extra (studs) antes de considerar teleporte
	FolgaTempoSegurar = 0.75, -- aceita segurar 75% do tempo do prompt (ping)
}

-- ============================================================
-- DADOS (DataStore)
-- ============================================================

Config.Dados = {
	NomeDataStore = "RoubeOMonstrinho_Dados_v1",
	IntervaloAutoSave = 60, -- segundos entre salvamentos automáticos
	AtrasoSalvamento = 6, -- salvamento "em breve" depois de eventos importantes
	Tentativas = 5, -- tentativas de carregar/salvar antes de desistir
	TempoTravaSessao = 180, -- trava de sessão sem atualização por X s é considerada abandonada
	TentativasTrava = 4, -- quantas vezes esperar outro servidor liberar os dados
	EsperaTrava = 4, -- segundos entre essas esperas
	MaxComprasRegistradas = 100, -- recibos guardados para evitar entrega duplicada
}

-- ============================================================
-- MAPA E BASES
-- (se mudar algo aqui, rode "lune run ferramentas/gerar_mapa" e
--  "rojo build" de novo; se não rodar, o servidor reconstrói o
--  mapa sozinho ao iniciar, mas você não verá a mudança no Studio)
-- ============================================================

Config.Base = {
	Quantidade = 8, -- número de bases (metade de cada lado da esteira; use número par)
	Largura = 44,
	Profundidade = 52,
	AlturaParede = 14,
	LarguraEntrada = 12,
	SlotsIniciais = 10, -- slots de todo mundo
	SlotsExtras = 4, -- slots liberados pelo Game Pass "+4 Slots"
	Cores = {
		Color3.fromRGB(255, 90, 90), -- vermelho
		Color3.fromRGB(255, 160, 60), -- laranja
		Color3.fromRGB(255, 215, 70), -- amarelo
		Color3.fromRGB(90, 210, 110), -- verde
		Color3.fromRGB(70, 205, 220), -- ciano
		Color3.fromRGB(80, 140, 255), -- azul
		Color3.fromRGB(170, 100, 255), -- roxo
		Color3.fromRGB(255, 120, 200), -- rosa
	},
}

Config.Mapa = {
	ComprimentoEsteira = 200,
	LarguraEsteira = 10,
	LarguraPraca = 52, -- distância entre as duas fileiras de bases (a esteira fica no meio)
	EspacoEntreBases = 6,
	CorGrama = Color3.fromRGB(96, 178, 74),
	CorPraca = Color3.fromRGB(238, 228, 206),
	CorEsteira = Color3.fromRGB(45, 45, 58),
	CorTrilho = Color3.fromRGB(255, 214, 64),
	CorPortalEntrada = Color3.fromRGB(170, 90, 255),
	CorPortalSaida = Color3.fromRGB(255, 90, 90),
}

-- ============================================================
-- RARIDADES
-- Chance = peso relativo (não precisa somar 100).
-- Tamanho = diâmetro do corpo em studs.
-- Efeitos: Luz (brilho da luz), Particulas (faíscas), Estrelas (Sparkles),
--          Aura (bolha de energia), ArcoIris (faíscas e texto coloridos).
-- Anunciar = avisa o servidor inteiro quando aparece na esteira.
-- ============================================================

Config.Raridades = {
	{
		Id = "Comum",
		Nome = "Comum",
		Chance = 55,
		Cor = Color3.fromRGB(200, 200, 210),
		Tamanho = 2.4,
		Luz = 0,
		Particulas = false,
		Estrelas = false,
		Aura = false,
		ArcoIris = false,
		Anunciar = false,
	},
	{
		Id = "Incomum",
		Nome = "Incomum",
		Chance = 25,
		Cor = Color3.fromRGB(85, 220, 100),
		Tamanho = 2.8,
		Luz = 0,
		Particulas = false,
		Estrelas = false,
		Aura = false,
		ArcoIris = false,
		Anunciar = false,
	},
	{
		Id = "Raro",
		Nome = "Raro",
		Chance = 12,
		Cor = Color3.fromRGB(70, 150, 255),
		Tamanho = 3.2,
		Luz = 1,
		Particulas = false,
		Estrelas = false,
		Aura = false,
		ArcoIris = false,
		Anunciar = false,
	},
	{
		Id = "Epico",
		Nome = "Épico",
		Chance = 5.5,
		Cor = Color3.fromRGB(175, 90, 255),
		Tamanho = 3.7,
		Luz = 1.5,
		Particulas = true,
		Estrelas = false,
		Aura = false,
		ArcoIris = false,
		Anunciar = false,
	},
	{
		Id = "Lendario",
		Nome = "Lendário",
		Chance = 2,
		Cor = Color3.fromRGB(255, 190, 40),
		Tamanho = 4.2,
		Luz = 2,
		Particulas = true,
		Estrelas = true,
		Aura = false,
		ArcoIris = false,
		Anunciar = true,
	},
	{
		Id = "Mitico",
		Nome = "Mítico",
		Chance = 0.5,
		Cor = Color3.fromRGB(255, 60, 130),
		Tamanho = 4.8,
		Luz = 3,
		Particulas = true,
		Estrelas = true,
		Aura = true,
		ArcoIris = true,
		Anunciar = true,
	},
}

-- ============================================================
-- MONSTRINHOS
-- Preco = custo na esteira | Renda = dinheiro por segundo
-- Forma = "Bola", "Cubo" ou "Cilindro" | Olhos = 1, 2 ou 3
-- Extras = "Orelhas", "Chifres", "Antena", "Coroa", "Asas",
--          "Espinhos", "Cauda", "Tentaculos", "Aureola", "Chapeu"
-- Material / Transparencia são opcionais.
-- Peso (opcional) = chance relativa dentro da mesma raridade (padrão 1).
-- ============================================================

Config.Monstrinhos = {
	-- COMUNS
	{
		Id = "bolotinha",
		Nome = "Bolotinha",
		Raridade = "Comum",
		Preco = 25,
		Renda = 1,
		Forma = "Bola",
		Cor = Color3.fromRGB(150, 228, 95),
		CorDetalhe = Color3.fromRGB(85, 160, 55),
		Olhos = 2,
		Extras = {},
	},
	{
		Id = "pingo",
		Nome = "Pingo",
		Raridade = "Comum",
		Preco = 40,
		Renda = 2,
		Forma = "Bola",
		Cor = Color3.fromRGB(125, 205, 255),
		CorDetalhe = Color3.fromRGB(60, 130, 210),
		Olhos = 1,
		Extras = { "Antena" },
	},
	{
		Id = "tampinha",
		Nome = "Tampinha",
		Raridade = "Comum",
		Preco = 60,
		Renda = 3,
		Forma = "Cubo",
		Cor = Color3.fromRGB(255, 172, 85),
		CorDetalhe = Color3.fromRGB(210, 110, 40),
		Olhos = 2,
		Extras = { "Orelhas" },
	},
	{
		Id = "gosminha",
		Nome = "Gosminha",
		Raridade = "Comum",
		Preco = 90,
		Renda = 4,
		Forma = "Bola",
		Cor = Color3.fromRGB(205, 155, 255),
		CorDetalhe = Color3.fromRGB(150, 95, 220),
		Olhos = 3,
		Extras = {},
		Transparencia = 0.1,
	},
	{
		Id = "fofucho",
		Nome = "Fofucho",
		Raridade = "Comum",
		Preco = 120,
		Renda = 5,
		Forma = "Bola",
		Cor = Color3.fromRGB(255, 165, 205),
		CorDetalhe = Color3.fromRGB(230, 100, 150),
		Olhos = 2,
		Extras = { "Orelhas", "Cauda" },
	},

	-- INCOMUNS
	{
		Id = "cogumelinho",
		Nome = "Cogumelinho",
		Raridade = "Incomum",
		Preco = 300,
		Renda = 8,
		Forma = "Cilindro",
		Cor = Color3.fromRGB(245, 232, 205),
		CorDetalhe = Color3.fromRGB(230, 60, 60),
		Olhos = 2,
		Extras = { "Chapeu" },
	},
	{
		Id = "sapeca",
		Nome = "Sapeca",
		Raridade = "Incomum",
		Preco = 450,
		Renda = 11,
		Forma = "Bola",
		Cor = Color3.fromRGB(90, 200, 120),
		CorDetalhe = Color3.fromRGB(40, 140, 70),
		Olhos = 2,
		Extras = { "Orelhas", "Cauda" },
	},
	{
		Id = "espinhudo",
		Nome = "Espinhudo",
		Raridade = "Incomum",
		Preco = 650,
		Renda = 15,
		Forma = "Cubo",
		Cor = Color3.fromRGB(150, 150, 168),
		CorDetalhe = Color3.fromRGB(85, 85, 100),
		Olhos = 2,
		Extras = { "Espinhos" },
	},
	{
		Id = "bafinho",
		Nome = "Bafinho",
		Raridade = "Incomum",
		Preco = 900,
		Renda = 22,
		Forma = "Bola",
		Cor = Color3.fromRGB(255, 140, 60),
		CorDetalhe = Color3.fromRGB(200, 70, 30),
		Olhos = 2,
		Extras = { "Chifres" },
	},

	-- RAROS
	{
		Id = "chifrudinho",
		Nome = "Chifrudinho",
		Raridade = "Raro",
		Preco = 3_000,
		Renda = 60,
		Forma = "Bola",
		Cor = Color3.fromRGB(230, 70, 70),
		CorDetalhe = Color3.fromRGB(255, 235, 200),
		Olhos = 2,
		Extras = { "Chifres", "Cauda" },
	},
	{
		Id = "olhao",
		Nome = "Olhão",
		Raridade = "Raro",
		Preco = 4_500,
		Renda = 85,
		Forma = "Bola",
		Cor = Color3.fromRGB(70, 110, 230),
		CorDetalhe = Color3.fromRGB(140, 220, 255),
		Olhos = 1,
		Extras = { "Antena" },
	},
	{
		Id = "trovaozinho",
		Nome = "Trovãozinho",
		Raridade = "Raro",
		Preco = 6_500,
		Renda = 120,
		Forma = "Cubo",
		Cor = Color3.fromRGB(255, 225, 60),
		CorDetalhe = Color3.fromRGB(255, 255, 255),
		Olhos = 2,
		Extras = { "Antena", "Espinhos" },
	},
	{
		Id = "gelinho",
		Nome = "Gelinho",
		Raridade = "Raro",
		Preco = 9_000,
		Renda = 160,
		Forma = "Cubo",
		Cor = Color3.fromRGB(170, 230, 255),
		CorDetalhe = Color3.fromRGB(110, 190, 240),
		Olhos = 2,
		Extras = { "Orelhas" },
		Material = Enum.Material.Ice,
	},

	-- ÉPICOS
	{
		Id = "dragaozinho",
		Nome = "Dragãozinho",
		Raridade = "Epico",
		Preco = 35_000,
		Renda = 600,
		Forma = "Bola",
		Cor = Color3.fromRGB(60, 170, 90),
		CorDetalhe = Color3.fromRGB(250, 210, 80),
		Olhos = 2,
		Extras = { "Asas", "Chifres", "Cauda" },
	},
	{
		Id = "robozinho",
		Nome = "Robozinho",
		Raridade = "Epico",
		Preco = 55_000,
		Renda = 900,
		Forma = "Cubo",
		Cor = Color3.fromRGB(165, 175, 190),
		CorDetalhe = Color3.fromRGB(255, 80, 80),
		Olhos = 1,
		Extras = { "Antena" },
		Material = Enum.Material.DiamondPlate,
	},
	{
		Id = "fantasminha",
		Nome = "Fantasminha",
		Raridade = "Epico",
		Preco = 80_000,
		Renda = 1_250,
		Forma = "Cilindro",
		Cor = Color3.fromRGB(240, 240, 255),
		CorDetalhe = Color3.fromRGB(180, 180, 255),
		Olhos = 2,
		Extras = { "Cauda" },
		Transparencia = 0.35,
	},
	{
		Id = "polvinho",
		Nome = "Polvinho",
		Raridade = "Epico",
		Preco = 100_000,
		Renda = 1_500,
		Forma = "Bola",
		Cor = Color3.fromRGB(255, 110, 170),
		CorDetalhe = Color3.fromRGB(200, 60, 120),
		Olhos = 2,
		Extras = { "Tentaculos" },
	},

	-- LENDÁRIOS
	{
		Id = "rei_bolota",
		Nome = "Rei Bolota",
		Raridade = "Lendario",
		Preco = 500_000,
		Renda = 7_000,
		Forma = "Bola",
		Cor = Color3.fromRGB(255, 215, 80),
		CorDetalhe = Color3.fromRGB(255, 175, 0),
		Olhos = 2,
		Extras = { "Coroa" },
	},
	{
		Id = "fenix_mirim",
		Nome = "Fênix Mirim",
		Raridade = "Lendario",
		Preco = 900_000,
		Renda = 12_000,
		Forma = "Bola",
		Cor = Color3.fromRGB(255, 120, 40),
		CorDetalhe = Color3.fromRGB(255, 225, 60),
		Olhos = 2,
		Extras = { "Asas", "Cauda" },
		Material = Enum.Material.Neon,
	},
	{
		Id = "kraken_bebe",
		Nome = "Kraken Bebê",
		Raridade = "Lendario",
		Preco = 1_500_000,
		Renda = 18_000,
		Forma = "Bola",
		Cor = Color3.fromRGB(120, 60, 200),
		CorDetalhe = Color3.fromRGB(205, 125, 255),
		Olhos = 3,
		Extras = { "Tentaculos", "Chifres" },
	},

	-- MÍTICOS
	{
		Id = "cosmozinho",
		Nome = "Cosmozinho",
		Raridade = "Mitico",
		Preco = 10_000_000,
		Renda = 120_000,
		Forma = "Bola",
		Cor = Color3.fromRGB(45, 35, 110),
		CorDetalhe = Color3.fromRGB(120, 210, 255),
		Olhos = 1,
		Extras = { "Aureola", "Antena" },
	},
	{
		Id = "arco_iris_supremo",
		Nome = "Arco-Íris Supremo",
		Raridade = "Mitico",
		Preco = 25_000_000,
		Renda = 260_000,
		Forma = "Bola",
		Cor = Color3.fromRGB(255, 255, 255),
		CorDetalhe = Color3.fromRGB(255, 100, 200),
		Olhos = 2,
		Extras = { "Asas", "Aureola", "Cauda" },
		Arcoiris = true,
	},
	{
		Id = "deus_monstrao",
		Nome = "Deus Monstrão",
		Raridade = "Mitico",
		Preco = 40_000_000,
		Renda = 400_000,
		Forma = "Bola",
		Cor = Color3.fromRGB(255, 80, 80),
		CorDetalhe = Color3.fromRGB(255, 215, 0),
		Olhos = 3,
		Extras = { "Coroa", "Asas", "Chifres" },
	},
}

return Config
