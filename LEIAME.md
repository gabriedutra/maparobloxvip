# Roube o Monstrinho 👾🦹

Compre monstrinhos na esteira, ganhe dinheiro na sua base, roube os dos outros e tranque a sua!

## 1. Abrir no Roblox Studio

1. Abra o Roblox Studio → **Arquivo → Abrir do arquivo** (*File → Open from File*) e escolha `RoubeOMonstrinho.rbxlx`.
2. Aperte **Play** (F5) para testar sozinho. Para testar roubos, use a aba **Testar → Clientes e servidores** (*Test → Clients and Servers*) com 2 jogadores.

> No Studio, o progresso só é salvo depois de publicar o jogo e ligar
> **Configurações do jogo → Segurança → Permitir acesso do Studio aos serviços de API**
> (*Game Settings → Security → Enable Studio Access to API Services*).
> Sem isso o jogo roda em "modo teste" e avisa que não vai salvar.

## 2. Colocar os IDs de Game Passes e Developer Products

1. Publique o jogo (passo 3); passes e produtos só podem ser criados em um jogo publicado.
2. No [Creator Hub](https://create.roblox.com) → sua experiência → **Monetização**:
   - **Passes** (coloque à venda): VIP, 2x Dinheiro, +4 Slots, Carregar Rápido;
   - **Produtos de desenvolvedor**: Trancar Agora, Sorte na Esteira, Pacote de Dinheiro.
3. No Studio, abra **ReplicatedStorage → Shared → Config** e troque os `0` pelos IDs, no topo do arquivo:

   ```lua
   Config.GamePasses = { VIP = 0, DinheiroDobrado = 0, SlotsExtras = 0, CarregarRapido = 0 }
   Config.Produtos = { TrancarAgora = 0, SorteBoost = 0, PacoteDinheiro = 0 }
   ```

   Enquanto um ID for `0`, o item aparece como "Em breve" na loja.
4. Publique de novo.

> A **Sorte na Esteira** mostra as chances (com e sem sorte) antes da compra, e o botão
> **🎲 Chances** mostra as chances a qualquer hora. O Roblox exige isso para itens pagos
> que mexem na sorte, então não remova essa janela. Onde a lei não deixa vender itens de
> sorte pagos (o Roblox avisa pelo `ArePaidRandomItemsRestricted`), a Sorte não aparece
> para o jogador. No questionário de maturidade, responda **Sim** para "itens aleatórios
> pagos" e **Sim** para "respeita ArePaidRandomItemsRestricted".

Preços, chances, renda, tempos (trancar, roubo, rebirth) e o catálogo de monstrinhos também ficam no `Config`.

## 3. Publicar

1. **Arquivo → Publicar no Roblox** (*File → Publish to Roblox*, Alt+P), preencha nome e descrição e clique em **Create**.
2. Limite o servidor a **8 jogadores** (uma base por jogador): Creator Hub → sua experiência → **Configure → Places** → clique no lugar → **Access** → **Maximum Visitor Count** = `8` → **Save Changes**. Se entrar mais gente, ela espera uma base vagar.
3. Para deixar **Público**: verifique a idade da conta (Roblox → Configurações → Informações da conta), responda o questionário em **Configure → Questionnaire** e depois escolha **Public** em **Configure → Settings → Audience**.
4. Depois de publicar uma atualização, use **Configure → Server Management → Restart Servers** para todo mundo pegar a versão nova.

---

### Para quem for mexer no código (opcional)

O código-fonte está em `src/` (projeto [Rojo](https://rojo.space)). Ferramentas: Rojo 7.7 e [Lune](https://lune-org.github.io/docs) 0.10 (`rokit install` instala as duas).

- `rojo build -o RoubeOMonstrinho.rbxlx`: gera o arquivo do jogo.
- `rojo serve` + plugin do Rojo no Studio: sincroniza o código ao vivo.
- `lune run ferramentas/gerar_mapa`: gera o mapa de novo depois de mudar o layout (seção "MAPA E BASES" do Config).
- `lune run ferramentas/testes`: roda os testes automáticos (DataStore, compras, fórmulas, mapa, monstrinhos).
- `lune run ferramentas/simulacao`: sobe o servidor num Roblox simulado e joga partidas completas (comprar, roubar, trancar, rebirth...).
