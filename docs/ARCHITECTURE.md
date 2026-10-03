# Arquitetura

O puzzle é **dado**, não sprites. Lógica, geração, solver, apresentação e persistência são módulos separados; só a apresentação e a UI conhecem o scene tree.

```text
scripts/
├── core/           Topology (Square/Hex), BoardShapes, PieceCatalog, Puzzle, BoardState,
│   │               Connectivity, GameMode, GameLog, JsonUtil
│   ├── rules/      RuleSet → LoopRules, DarkRules, ForestRules → CoreRules, MultiCoreRules
│   ├── game_services.gd   (autoload "Game": fluxo de níveis, progressão)
│   └── localization.gd    (autoload "I18n")
├── generator/      SeededRng, SeedManager, PuzzleRequest, DifficultyConfig, DifficultyCurve,
│                   LevelPlan, LevelPlanner, SolutionBuilder, SpecialMechanics, Scrambler,
│                   Fingerprint, PuzzleGenerator
├── solver/         Validator, PuzzleSolver, DifficultyAnalyzer
├── gameplay/       GameSession, HintSystem, GeneratorService (thread + cache)
├── presentation/   BoardView (renderer + input), ParticleField, Palette, ThemeCatalog,
│                   theme_manager.gd (autoload "Themes")
├── ui/             main (router), main_menu, gameplay_screen, profile, settings, debug,
│                   UiKit, UiTheme
├── audio/          Synth (síntese offline), audio_manager (autoload "Audio"), haptics
└── save/           SaveStore, LevelCache, Statistics, AchievementSystem,
                    AdaptiveDifficulty, Telemetry, save_manager (autoload "Save")
data/               difficulties/, themes/, achievements/, i18n/  (tudo ajustável sem código)
scenes/             main, menu, gameplay, profile, settings, debug (.tscn finos; UI montada em código)
shaders/            background.gdshader
tests/              core/, generator/, solver/, gameplay/, performance/, ui_smoke_test.gd
tools/              run_tests.sh, check_scripts.gd, gen_report.gd, screenshot.gd,
                    make_icons.gd, build_android.sh
```

Mapeamento para o §80 do escopo:

| Escopo | Implementação |
|---|---|
| Core: Piece, Grid, Connection, Puzzle, Rules | `PieceCatalog`, `Topology`/`BoardShapes`, `Connectivity`, `Puzzle`/`BoardState`, `RuleSet` e filhos |
| Generator: Topology, Piece, Difficulty, Scrambler, SeedManager | `BoardShapes`+`TopologyFactory`, `SolutionBuilder`+`SpecialMechanics`, `LevelPlanner`+`DifficultyCurve`, `Scrambler`, `SeedManager`+`SeededRng` |
| Solver: Validator, Solver, DifficultyAnalyzer, SolutionCounter | `Validator`, `PuzzleSolver` (conta soluções até um limite), `DifficultyAnalyzer` |
| Presentation: TileRenderer, Effects, Particles, Animation, Theme | `BoardView` (camadas), `ParticleField`, molas/onda em `BoardView`, `ThemeCatalog`/`Palette`/`Themes` |
| UI: MainMenu, HUD, Profile, Settings, Results | `main_menu.gd`, `gameplay_screen.gd` (HUD, pausa, resultados, dicas, replay), `profile_screen.gd`, `settings_screen.gd` |
| Persistence: SaveManager, Statistics, Achievements | `SaveStore`/`save_manager.gd`, `Statistics`, `AchievementSystem` |

## Modelo de dados

- **Direções** são índices horários; uma peça é uma máscara de bits (4 bits no quadrado, 6 no hexágono). Girar no sentido horário = deslocamento circular de 1 bit. Simetria/período e forma canônica saem da própria máscara.
- **Puzzle** guarda as máscaras na orientação da solução (`masks`), a rotação inicial (`start_rot`), células ativas (formato), travadas, núcleos, pares de portais e grupos ligados. Rotação 0 é sempre uma solução válida.
- **BoardState** é só o vetor de rotações atuais + cache de máscaras.
- **RuleSet** separa a relação local de arestas (igualdade no LOOP/CORE/MULTI, exclusão no DARK) da checagem global (florestas com exatamente um núcleo por componente). Nova mecânica = nova subclasse, sem reescrever o core.

## Renderização (§47–49)

`BoardView` é um `Control` com um `Node2D` de transformação (zoom/pan/pulso) e camadas desenhadas em lote:

1. **cells** – fundo das células em um único `canvas_item_add_triangle_array` (redesenha só ao trocar puzzle/tema);
2. **tiles** – todas as peças em repouso: braços como quads texturizados (núcleo nítido + glow gaussiano + filamento quente) em 3 chamadas de triângulos; redesenha só quando o tabuleiro muda;
3. **fx** – peças girando (mola), núcleos, portais, destaque de dica, anel da vitória;
4. **particles** – pool com teto de 700 partículas, blend aditivo.

Não existe um Node por peça; um tabuleiro 40×40 continua com poucas chamadas de desenho. Quando nada está animando, `_process` é desligado.

## Threads

`GeneratorService` gera em uma thread de trabalho (fila com prioridade, resultados entregues via `call_deferred`) e pré-carrega o próximo nível enquanto o jogador resolve o atual. Toda configuração estática (JSONs de dificuldade/temas/conquistas) é carregada na thread principal antes. Em plataformas sem threads o serviço gera de forma síncrona. A síntese de áudio roda no `WorkerThreadPool`.

## Segurança (§87)

Códigos e seeds são dados: `SeedManager.parse_code` aceita apenas `[0-9A-Z-]`, tamanho limitado e formatos fixos. Saves/caches são lidos com `JsonUtil` (sem `str_to_var`, sem objetos), validados (tamanhos, faixas de máscara, índices) e verificados por checksum.
