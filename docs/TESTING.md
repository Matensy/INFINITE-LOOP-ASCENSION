# Testes

Tudo roda headless (sem janela) com o mesmo binário do Godot 4.7.1 usado no CI.

```bash
godot --headless --path . --import                                   # uma vez, gera o cache de classes
godot --headless --path . --script res://tools/check_scripts.gd      # compila todos os scripts
tools/run_tests.sh                                                   # testes unitários
godot --headless --path . --script res://tests/ui_smoke_test.gd -- --ephemeral-save
godot --headless --path . --script res://tests/performance/stress_test.gd -- --count=100000 --shard=0/3
gdlint scripts tests tools                                           # gdtoolkit 4 (config em gdlintrc)
```

## Testes unitários (91)

| Arquivo | O que cobre |
|---|---|
| `tests/core/test_topology.gd` | vizinhança quadrada/hex, ângulos das direções, rotação de máscaras, período e forma canônica, `cell_at`, formatos irregulares conexos |
| `tests/core/test_connections.gd` | conexões e bordas, LOOP/DARK/CORE/MULTI, ilhas sem energia, núcleos unidos, portais, peças fixas e ligadas, serialização e rejeição de dados inválidos |
| `tests/generator/test_rng_and_seeds.gd` | xoshiro128** determinístico (valores de referência, 32 bits), seeds por nível/data, códigos `ASCENSION-…`/`DAILY-…` só como dados, dificuldade do diário ao longo da semana |
| `tests/generator/test_generator.gd` | mesma seed → mesma fase, código reproduz a fase, todos os modos/topologias/formatos, mecânicas especiais, níveis enormes, eventos, unicidade real no PERFECT, anti-repetição do Zen |
| `tests/generator/test_fingerprint.gd` | fingerprint canônico (invariante a rotação/espelho) e anti-repetição |
| `tests/solver/test_solver.gd` | resolve, detecta impossível, conta soluções, poda de ilhas no CORE, peças ligadas, concorda com o gerador, rotações forçadas, orçamento de nós |
| `tests/solver/test_difficulty.gd` | curva monotônica e sem teto (e sua inversa), faixas, componentes do analisador, mínimo de movimentos, planner, viés adaptativo, variação entre níveis seguidos |
| `tests/gameplay/test_session.gd` | toque gira e conta movimentos, vitória, reset, peças fixas/marcadas, dicas 1–5 (também CORE e ligadas), replay, salvar/restaurar progresso, cronômetro |
| `tests/gameplay/test_save.gd` | padrões, ida e volta, backup em corrupção, checksum adulterado, migração da v1, estatísticas e sequência, conquistas, viés adaptativo, cache LRU, telemetria |
| `tests/performance/test_performance.gd` | tempo de geração por faixa, solver e dica em tabuleiro grande, checagem de vitória barata, memória estável após muitas gerações |

## Smoke test de UI

`tests/ui_smoke_test.gd` abre cada tela (menu, jogo em vários modos, pausa, resultado, perfil, configurações, debug), gera fases de nível 1 a 5.000, toca em peças, usa dica, desfaz, carrega fase do diário, de desafio e por código, e falha se houver qualquer erro do motor. `--ephemeral-save` não toca no save do usuário.

`tools/screenshot.gd` (com Xvfb) renderiza as telas usadas no README.

## Stress test: 100.000 fases

Níveis 1 a 100.000 consecutivos (3 shards em paralelo), cada fase com validação estrutural, validação da solução guardada e uma passada independente do solver.

| Métrica | Resultado |
|---|---|
| Fases geradas | **100.000** |
| Válidas | **100.000** |
| Impossíveis | **0** |
| Inválidas | **0** |
| Erros do motor | **0** |
| Duplicatas (fingerprint canônico) | **0** dentro de cada shard (entre todos os 100.000: segunda passada abaixo) |
| Tempo médio de geração | 59,4 ms |
| Pior caso | 1.107 ms (nível 81.554) |
| Dificuldade média / máxima | 238,2 / 564,1 |
| Fases com solução única | 54,1% |
| Solver no limite do orçamento | 9 (todas validadas pela solução guardada) |
| Memória | 26,6 MB → pico 32,5 MB (estável, sem crescimento) |
| Tempo de parede | ~40 min por shard |

Distribuição: modos LOOP 33.431 · CORE 33.241 · DARK 16.696 · MULTI 16.632; topologias quadrada 55.880 · hex 44.120; faixas Tutorial 41 · Easy 209 · Normal 193 · Hard 618 · Very Hard 2.200 · Brutal 10.311 · Insane 77.601 · Nightmare 8.825 · Ascension 2 (a curva sobe rápido; Insane domina entre os níveis 10.000 e 100.000).

O gerador ficou incremental (fatias de tempo, sem threads) depois desse teste; `tools/fingerprints.gd` comparou as fingerprints de uma amostra de 304 níveis antes e depois da mudança e elas são idênticas.

### Segunda passada com o gerador atual: duplicatas entre todas as fases

Com o gerador incremental, os mesmos níveis 1 a 100.000 foram gerados de novo (3 shards, `--no-verify --dump=…`) e as fingerprints canônicas dos três shards foram juntadas:

| Métrica | Resultado |
|---|---|
| Fases geradas / válidas | 100.000 / 100.000 |
| Impossíveis / inválidas / erros do motor | 0 / 0 / 0 |
| Fingerprints distintas | **100.000** (0 duplicatas, invariante a rotação e espelho) |
| Tempo médio de geração | 60,8 ms |

```bash
for i in 0 1 2; do
  godot --headless --path . --script res://tests/performance/stress_test.gd -- \
      --count=100000 --shard=$i/3 --no-verify --dump=/tmp/fp$i.txt &
done; wait
cat /tmp/fp*.txt | awk '{print $2}' | sort | uniq -d | wc -l    # 0
```

## CI

`.github/workflows/ci.yml` roda em todo push: gdlint, compilação de todos os scripts, testes unitários, smoke test de UI e stress test de 5.000 níveis + 300 níveis amostrados em escala logarítmica até 10⁹. `.github/workflows/android.yml` exporta o APK debug e o publica como artefato `android-builds`.
