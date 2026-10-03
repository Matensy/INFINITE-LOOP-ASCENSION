# Arquitetura

O puzzle é **dado**, não sprites. Lógica, geração, solver, apresentação e persistência são módulos separados; só a apresentação e a UI conhecem o scene tree.

```text
scripts/
├── core/           Topology (Square/Hex), BoardShapes, PieceCatalog, Puzzle, BoardState,
│   │               Connectivity, GameMode, GameLog, JsonUtil
│   ├── rules/      RuleSet → LoopRules, DarkRules, ForestRules → CoreRules, MultiCoreRules
│   ├── diagnostics.gd     (relatório de aparelho + logs para suporte)
│   ├── game_services.gd   (autoload "Game": fluxo de níveis, progressão)
│   └── localization.gd    (autoload "I18n")
├── generator/      SeededRng, SeedManager, PuzzleRequest, DifficultyConfig, DifficultyCurve,
│                   LevelPlan, LevelPlanner, SolutionBuilder, SpecialMechanics, Scrambler,
│                   Fingerprint, PuzzleGenerator
├── solver/         Validator, PuzzleSolver, DifficultyAnalyzer
├── gameplay/       GameSession, HintSystem, GeneratorService (fatias de tempo + cache)
├── presentation/   BoardView (renderer), BoardGestures (gestos), PipeGeometry (malhas),
│                   BoardGlyphs, ParticleField, Palette, ThemeCatalog,
│                   theme_manager.gd (autoload "Themes")
├── ui/             main (router), main_menu, gameplay_screen, profile, settings, debug,
│                   UiKit, UiTheme, VectorIcon, PillBackground, CircleBackground,
│                   DiagnosticsPanel
├── audio/          Synth (receitas de efeitos), MusicEngine (música generativa em tempo
│                   real), audio_manager (autoload "Audio"), haptics
└── save/           SaveStore, LevelCache, Statistics, AchievementSystem,
                    AdaptiveDifficulty, Telemetry, save_manager (autoload "Save")
data/               difficulties/, themes/, achievements/, i18n/  (tudo ajustável sem código)
scenes/             main, menu, gameplay, profile, settings, debug (.tscn finos; UI montada em código)
shaders/            background (aurora), pipe_gradient (degradê por vértice), gradient_text
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

`BoardView` é um `Control` com um `Node2D` de transformação (zoom/pan/pulso) e camadas desenhadas em lote, cada uma com um único `canvas_item_add_triangle_array` por quadro:

1. **cells** – matriz de pontos e placas de peças fixas (redesenha só ao trocar puzzle/tema);
2. **glow** – halo aditivo de todo cano energizado;
3. **tiles** – todas as peças em repouso; redesenha só quando o tabuleiro muda;
4. **fx glow / fx** – peças girando (mola), orbes dos núcleos, portais, anéis de dica e de toque, onda da vitória;
5. **particles** – pool com teto de partículas, blend aditivo.

As peças são montadas a partir de **malhas pré-tesseladas** (`PipeGeometry`): meio arco por par de braços, raio por braço, discos e pontas arredondadas. Curvas são **arcos circulares** tangentes às duas bordas (centro no canto da célula para braços vizinhos), então as duas metades de uma curva compartilham exatamente os mesmos vértices na emenda e o halo largo de curvas fechadas (hexágono) vira um setor limpo em vez de dobrar em "espinhos". Desenhar uma peça é só `Transform2D * PackedVector2Array` + `append_array` (código nativo). UV.x atravessa o traço e amostra um perfil 1-D (núcleo nítido com anti-aliasing ou glow suave); o shader `pipe_gradient` usa UV.y como marcador para aplicar o degradê do tema **por vértice**, contínuo de peça para peça. Cores translúcidas são achatadas sobre a cor de fundo (`Palette.solid`) para que traços sobrepostos não criem emendas.

Não existe um Node por peça; um tabuleiro 40×40 continua com poucas chamadas de desenho. Quando nada está animando, `_process` é desligado. Gestos (toque, toque duplo, segurar, pinça, arrastar, dois dedos, roda do mouse) ficam em `BoardGestures`, separados do renderizador.

## Sem threads (estabilidade)

O jogo **não usa threads de GDScript**. Versões anteriores geravam fases numa `Thread` e sintetizavam áudio no `WorkerThreadPool`; em aparelhos reais isso causava fechamentos. O GDScript do Godot 4.x tem condições de corrida conhecidas quando duas threads executam o mesmo código ainda não "aquecido" (cache de operadores/tipos), o que termina em SIGSEGV nativo sem nenhuma mensagem de erro no jogo. A solução adotada foi eliminar a concorrência:

- `PuzzleGenerator` tem API incremental (`begin()` / `step()` / `result()`, uma tentativa por passo). `GeneratorService` executa passos em **fatias de tempo** no `_process` da thread principal: até 12 ms por quadro para o nível que o jogador está esperando, 4 ms para pré-carregar o próximo (só quando nada está animando). A saída é idêntica à geração síncrona (mesmas seeds → mesmas fases).
- O áudio usa um `AudioStreamGenerator`: o `MusicEngine` gera a música em tempo real em blocos pequenos, e as receitas de efeitos (`Synth.sfx_recipes`) são pré-renderizadas uma por quadro na inicialização.
- A tela de debug também gera lotes (1.000 / 10.000) em fatias de tempo.

## Diagnóstico de falhas

- `project.godot` liga o log em arquivo (`user://logs/`, 6 arquivos).
- `save_manager` cria `user://running.lock` ao abrir e o remove ao pausar/fechar. Se o arquivo ainda existir na próxima abertura, a sessão anterior terminou em falha: o menu mostra um aviso com o **relatório copiável** (aparelho, versão, configurações e o fim do log anterior). Depois de 2 falhas seguidas o **modo seguro** reduz efeitos e animações automaticamente.
- Configurações → Dados → **Diagnóstico** abre o mesmo relatório a qualquer momento.
- O save é gravado com atraso curto e sempre ao pausar, perder o foco ou fechar, com backup (`SaveStore`).

## Segurança (§87)

Códigos e seeds são dados: `SeedManager.parse_code` aceita apenas `[0-9A-Z-]`, tamanho limitado e formatos fixos. Saves/caches são lidos com `JsonUtil` (sem `str_to_var`, sem objetos), validados (tamanhos, faixas de máscara, índices) e verificados por checksum.
