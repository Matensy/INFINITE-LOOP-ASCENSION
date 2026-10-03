# Status do escopo

Legenda: ✅ feito · 🟡 parcial · ⬜ futuro

## MVP (§91)

| Item | Status | Onde |
|---|---|---|
| Grid | ✅ | `Topology`, `SquareTopology`, `HexTopology`, `BoardShapes` |
| Tile rotation | ✅ | `BoardState.rotate`, mola em `BoardView` |
| Connection system | ✅ | `Connectivity`, `RuleSet` |
| Procedural generation | ✅ | `PuzzleGenerator` e camadas |
| Solver | ✅ | `PuzzleSolver` |
| Seed | ✅ | `SeededRng`, `SeedManager` |
| Difficulty | ✅ | `LevelPlanner`, `DifficultyAnalyzer`, `DifficultyCurve` |
| Infinite levels | ✅ | `Puzzle(N) = Generator(Seed(N), Difficulty(N))` |
| Touch | ✅ | `BoardGestures` |
| Basic animations | ✅ | mola, faíscas, onda de vitória, pulso |
| Save | ✅ | `SaveStore` (versão, checksum, backup, migração) |
| Android export | ✅ | APK debug/release gerados; AAB via CI |

## V2 (§92)

| Item | Status | Observação |
|---|---|---|
| Special pieces | 🟡 | ✅ Locked, Portal, Rotator (peças ligadas), núcleos; ⬜ One-Way, Switch, Mirror, Splitter, Merger, Timer, Gravity, Quantum, Corrupted, Double Corner |
| Themes | ✅ | 12 temas, desbloqueio por nível, automático por fase |
| Particles | ✅ | `ParticleField` |
| Audio | ✅ | síntese procedural, música adaptativa em camadas |
| Daily puzzle | ✅ | seed por data, dificuldade por dia da semana, histórico |
| Achievements | ✅ | 29 conquistas data-driven + títulos + prestígio |
| Sharing | ✅ | texto + PNG + códigos `ASCENSION-…` / `DAILY-…` |
| Replay | ✅ | replay comprimido dos movimentos gravados |

## V3 (§93)

| Item | Status | Observação |
|---|---|---|
| Dynamic puzzles | 🟡 | peças ligadas (CHAOS); peças que mudam por timer/energia ⬜ |
| Multi-network | 🟡 | MULTI CORE / FRACTURE (regiões por núcleo); redes coloridas RGB ⬜ |
| Advanced topology | ✅ | hexagonal + 10 formatos irregulares (inclui ∞ e anéis) |
| Hardcore | ✅ | Desafio: sem dicas, cronômetro |
| Nightmare / Ascension | ✅ | tiers de desafio + eventos boss |
| Leaderboards | ⬜ | requer servidor opcional (§23) |
| Cloud save | ⬜ | requer servidor opcional |

## Outros itens do escopo

| Seção | Status |
|---|---|
| §25 Hints 1–5 | ✅ (dica 2 prefere uma dedução lógica forçada) |
| §26 Controles (tap, long press, double tap configurável, pinch, drag, dois dedos configurável) | ✅ |
| §27 Acessibilidade (animação, vibração, efeitos, contraste, daltonismo, velocidade, tamanho de UI, canhoto, som) | ✅ — tamanho das peças via zoom |
| §33 Haptics | ✅ |
| §35 Som adaptativo | ✅ |
| §36–38 UI, HUD, Perfil | ✅ (redesign moderno: Outfit, pílulas com degradê, vidro fosco, ícones vetoriais) |
| §56–57 Dificuldade adaptativa sem trapaça | ✅ |
| §59 Zen | ✅ |
| §62 Rotation cost | 🟡 toque horário/anti-horário = 1 movimento; custo 180° ⬜ |
| §63–64 Peças com estado / cadeia | 🟡 cadeia via peças ligadas |
| §65 Multi-color | ⬜ |
| §71–72 Prestígio e títulos | ✅ |
| §73 Monetização | ⬜ (nada que bloqueie progresso foi adicionado) |
| §78 Safe area | ✅ |
| §79 Landscape | ⬜ (retrato) |
| §82–84 Debug generator, visualizador, Generate 10.000 | ✅ |
| §85–86 Telemetria local e logs | ✅ |
| §87 Segurança | ✅ |
| §88 Save corruption | ✅ |
| Estabilidade / crash report | ✅ sem threads de GDScript, log em arquivo, detecção de fechamento inesperado, relatório copiável, modo seguro |
| §89 i18n | ✅ pt-BR, en-US (estrutura para es/fr/de/ja/ko/zh) |

## Próximos passos sugeridos

1. Testar em aparelhos reais (checklist em BUILD_ANDROID.md); se algo fechar, copiar o relatório em Configurações → Diagnóstico. Ajustar `data/difficulties/difficulty.json` com a telemetria local.
2. Novas peças compatíveis com o solver: One-Way (aresta direcionada na propagação), Double Corner/Bridge (canais por célula), Switch/Timer (estados como variáveis extras).
3. Tabuleiro toroidal (bordas que dão a volta) como nova dimensão de dificuldade: remove as âncoras de borda e exige busca real.
4. Servidor opcional para leaderboard do diário e cloud save.
