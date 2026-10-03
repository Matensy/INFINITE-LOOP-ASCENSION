# Gerador procedural e solver

## Pipeline (§10, §54, §55)

```text
PuzzleRequest (kind, level, seed, bias)
 → LevelPlanner.plan()           vetor de dificuldade (LevelPlan)
 → BoardShapes.build()           topologia + formato (camada 1)
 → SolutionBuilder.build()       solução válida conhecida (camada 2)
 → SpecialMechanics.apply()      travas, peças ligadas (camadas 3–4)
 → Scrambler.scramble()          embaralha, nunca começa resolvido (camada 5)
 → Validator                     estrutura + solução armazenada (camada 6)
 → PuzzleSolver.solve(2)         solução existe? única? quanto custa? (camada 6)
 → DifficultyAnalyzer.analyze()  DifficultyScore (camada 7)
 → Fingerprint                   anti-repetição
 → ThemeCatalog.theme_for()      tema/efeitos (camada 8)
```

O gerador tenta até `max_attempts` candidatos. Se o score medido erra o alvo, o próximo candidato tem a área corrigida por `(alvo/score)^(1/0.9)` (malha fechada) e o candidato mais próximo é mantido. Se o tabuleiro já está no tamanho máximo, ele para cedo. Não existe limite por tempo de relógio — só contagem de nós — então todos os aparelhos geram exatamente a mesma fase.

### Soluções por modo

- **LOOP** – qualquer subconjunto de arestas é uma solução; cada aresta escolhida vira um par de conectores frente a frente.
- **DARK** – cada aresta escolhida recebe exatamente um conector, de um lado aleatório; nenhum par se toca.
- **CORE / MULTI** – floresta crescida simultaneamente a partir de cada núcleo com um *growing tree* (`branching` mistura "mais novo primeiro" = corredores longos e "aleatório" = redes ramificadas). Portais juntam duas células distantes de forma atômica (as duas entram na mesma árvore).

### Por que CORE/MULTI proíbem ciclos sem regra extra

Com todos os conectores casados, o número de arestas é fixo: `E = n − K` (n células da rede, K núcleos). Um grafo com C componentes tem `E ≥ n − C`, com igualdade só se for floresta. Se houvesse um ciclo, `C > K`, então algum componente ficaria sem núcleo — inválido. Por isso "cada componente tem exatamente um núcleo" já implica floresta, e o solver pode podar qualquer ciclo parcial.

## Seeds e códigos (§11, §41, §52)

- PRNG próprio **xoshiro128\*\*** em aritmética explícita de 32 bits (valores conferidos contra uma implementação Python independente; teste "golden").
- `SeedManager.level_seed(N)` = hash(masterSeed, N) → número de 12 dígitos.
- Códigos (apenas dados, validados):
  - `ASCENSION-<nível>-<seed>[-P|-M<viés>]` — puzzle de progressão (mesmo planejamento do modo infinito)
  - `ASCENSION-F<nível>-<seed>` — puzzle "livre" (zen/desafio)
  - `ASCENSION-<seed>` — seed avulsa (nível derivado da seed)
  - `DAILY-AAAA-MM-DD` — desafio diário (dificuldade sobe de segunda a domingo)

## Solver (§13)

Variáveis = unidades giráveis (uma peça, ou um grupo ligado inteiro). Domínio = orientações distintas (bitmask ≤ 6).

1. **Propagação local** (AC-3) com as relações do `RuleSet`: igualdade (LOOP/CORE/MULTI) ou exclusão (DARK); bordas e células vazias proíbem conectores.
2. **Poda global** (florestas): união das arestas certamente ligadas (+ portais); ciclo → contradição; dois núcleos unidos → contradição; componente fechado sem núcleo → contradição; no CORE, componente fechado com o núcleo mas sem todas as peças → contradição.
3. **Busca** MRV com pilha explícita e orçamento de nós; ordenação de valores pode preferir as rotações atuais do jogador (dicas = "solução mais próxima").
4. Folhas são conferidas pelo `Validator`. `solve(2)` prova unicidade quando a busca termina.

Saídas usadas pela dificuldade: decisões reais, peças não resolvidas por dedução local, nós de busca, backtracks, profundidade.

## PERFECT (solução única)

Se o plano exige unicidade e o solver encontra uma segunda solução, uma peça que difere entre as soluções é travada na orientação correta e o solver roda de novo (limitado). Se ainda assim não for única, o requisito é relaxado após algumas tentativas (tempo de geração limitado). `puzzle.unique` só é `true` com prova.

## Anti-repetição (§18, §19, §95)

- **Fingerprint canônico**: hash SHA-256 da estrutura da solução (máscaras + marcas especiais) no menor dos 8 (quadrado) ou 4 (retângulo) espelhamentos/rotações — tabuleiros perceptivelmente iguais têm a mesma impressão.
- **Vetor de características** (modo, topologia, dimensões, distribuição de peças, especiais) com distância para rejeitar fases "parecidas demais".
- **Decks determinísticos**: modo e formato vêm de baralhos embaralhados por bloco de níveis, então níveis vizinhos variam e qualquer nível continua computável em O(1), sem depender do histórico.
- No modo **Zen** (sem número de nível), o gerador recebe as últimas 40 impressões do jogador e rejeita repetições. Nos níveis numerados a lista fica vazia de propósito: o nível N precisa ser idêntico para todos.
- O stress test mede duplicatas exatas em 100.000 níveis (ver TESTING.md).
