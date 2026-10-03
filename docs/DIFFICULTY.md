# Dificuldade

Toda a calibragem fica em `data/difficulties/difficulty.json`.

## Curva alvo (sem último nível)

```text
T(N) = 4 + 5 · log10(N + 1) ^ 2.5
```

| Nível | T(N) | Faixa |
|---:|---:|---|
| 1 | 4 | Tutorial |
| 10 | 9.5 | Tutorial |
| 20 | 14 | Easy |
| 100 | 32 | Normal |
| 500 | 64 | Hard |
| 1.000 | 82 | Very Hard |
| 5.000 | 136 | Brutal |
| 18.492 | 192 | Insane |
| 100.000 | 284 | Insane |
| 1.000.000 | 445 | Nightmare |
| 100.000.000 | 909 | Ascension |

A função cresce sem limite. O tamanho do tabuleiro tem teto (40×40, jogável com zoom), então nos níveis astronômicos a dificuldade medida satura perto do máximo que as mecânicas atuais permitem (~600–900); a dimensão de mecânicas continua variando. Isso é dito abertamente em vez de prometer o impossível (§95).

## DifficultyScore (medido, §14)

```text
tiles     = 0.62 · decisões^0.9
reasoning = 0.22 · peças não resolvidas por dedução local + 2.2 · log2(1 + nós de busca)
steps     = 0.05 · movimentos mínimos a partir do embaralhamento
specials  = 2.5 · portais + 1.6 · peças ligadas + 1.5 · (núcleos − 1) − 0.4 · travas
score     = ((tiles + reasoning + steps) · modo · topologia + specials) · (1.12 se solução única)
modo: LOOP 1.0 · CORE 1.12 · MULTI 1.2 · DARK 1.08     topologia: hex 1.3
```

Faixas: 0 Tutorial · 10 Easy · 25 Normal · 50 Hard · 80 Very Hard · 120 Brutal · 180 Insane · 300 Nightmare · 500 Ascension.

## Vetor de dificuldade (LevelPlan, §9)

| Dimensão | Como varia |
|---|---|
| gridSize | resolvido a partir do orçamento restante após o custo das mecânicas; proporção retrato |
| density | LOOP 0.50–0.68 · DARK 0.55–0.85 · CORE/MULTI cobertura 0.82–1.0 |
| branching | 0.15–0.85 (corredores ↔ redes ramificadas) |
| topology | hexagonal a partir de T≥40, chance crescente até 45% |
| shape | formatos irregulares a partir de T≥12 (losango, elipse, cruz, anel, ∞, estrela, orgânico, espiral, buracos) |
| ambiguity / constraints | PERFECT (solução única) a partir de T≥22, chance crescente até 75% |
| specialPieces | portais (T≥50), peças ligadas/CHAOS (T≥62), núcleos extras no MULTI (T≥28), travas (âncoras no tutorial e desambiguação) |
| objectives | modo vindo do deck: LOOP, CORE (T≥9), DARK (T≥15), MULTI (T≥28) |

O primeiro nível em que cada mecânica aparece é "de introdução": modo forçado, alvo 30% menor e um cartão explicativo na primeira vez.

## Eventos (§20, §21)

| Intervalo | Evento | Efeito |
|---|---|---|
| 100 | GALAXY | formato espiral, tema galaxy, ×1.12 |
| 250 | FRACTURE | MULTI com mais núcleos, estrela, ×1.2 |
| 500 | MEGA GRID | tabuleiro maior, ×1.3 |
| 1.000 | VOID (boss) | DARK com buracos, ×1.35 |
| 2.500 | CHAOS (boss) | muitas peças ligadas, ×1.4 |
| 5.000 | ASCENSION (boss) | MULTI em formato ∞, ×1.6, solução única |

Os eventos se repetem para sempre (o maior intervalo vence). Bosses mostram um cartão com a composição do puzzle e têm animação/som/vibração próprios.

## Adaptação (§56, §57)

Após cada nível resolvido, `AdaptiveDifficulty` combina tempo vs. esperado, movimentos vs. mínimo e dicas em um desempenho em [−1, 1], suaviza e gera um **viés de −25% a +25%** no alvo dos próximos níveis. O viés é gravado junto com o nível atual quando ele é alcançado e entra no código compartilhável — o puzzle nunca muda depois de aparecer.
