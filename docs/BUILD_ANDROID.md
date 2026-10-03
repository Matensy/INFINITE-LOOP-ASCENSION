# Build Android (APK / AAB)

Configuração do projeto: retrato, renderer **GL Compatibility** (celulares intermediários), `arm64-v8a` apenas, permissão `VIBRATE`, ícones adaptativos (`assets/art/`), `quit_on_go_back=false` (o botão voltar navega entre telas).

Presets em `export_presets.cfg`:

| Preset | Saída | Observação |
|---|---|---|
| `Android` | APK debug/release | sem gradle; usa os templates oficiais |
| `Android AAB` | AAB release | gradle build (Google Play) |

## Requisitos

1. Godot **4.7.x** + export templates da mesma versão (Editor → Manage Export Templates).
2. JDK 17+ e Android SDK com `platform-tools`, `build-tools` (apksigner) e `platforms;android-35`.
3. Editor Settings → Export → Android: caminho do SDK e do Java (ou edite `~/.config/godot/editor_settings-4.7.tres`).

## Comandos

```bash
tools/build_android.sh debug
# build/android/InfiniteLoopAscension-debug.apk  (keystore debug gerada pelo Godot)

export GODOT_ANDROID_KEYSTORE_RELEASE_PATH=/caminho/release.keystore
export GODOT_ANDROID_KEYSTORE_RELEASE_USER=alias
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=senha
tools/build_android.sh release   # APK assinado
tools/build_android.sh aab       # AAB assinado (instala o template gradle)
```

Criar uma keystore de release (guarde fora do repositório; `*.keystore` está no `.gitignore`):

```bash
keytool -genkeypair -v -keystore release.keystore -alias ila -keyalg RSA -keysize 2048 -validity 10000
```

## CI (GitHub Actions)

- `.github/workflows/ci.yml` — em todo push/PR: compila todos os scripts, roda os testes unitários, o smoke test de UI e um stress test (5.000 níveis + amostragem logarítmica até 10⁹). Relatórios JSON ficam como artefato.
- `.github/workflows/android.yml` — em todo push de código (exceto só docs), manual (*Run workflow*) e em tags `v*`: exporta o APK debug; se os segredos abaixo existirem, também o APK release e o AAB. Os builds ficam como artefato `android-builds`.

Segredos do repositório (Settings → Secrets and variables → Actions):

| Segredo | Conteúdo |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | `base64 -w0 release.keystore` |
| `ANDROID_KEYSTORE_ALIAS` | alias da chave |
| `ANDROID_KEYSTORE_PASSWORD` | senha da keystore/chave |

## Verificado neste repositório

Neste ambiente foram gerados, com os templates oficiais 4.7.1:

- `InfiniteLoopAscension-debug.apk` — 28,9 MB, assinatura v2+v3 verificada (`apksigner verify`), apenas `lib/arm64-v8a`.
- `InfiniteLoopAscension-release.apk` — 27,1 MB, assinado com keystore de teste.

Ambos dentro da meta de tamanho (< 60 MB). O pacote contém `data/*.json`, fontes e scripts compilados; `tests/`, `tools/` e `docs/` ficam de fora. O AAB depende do gradle build (download de dependências do Google Maven), então é gerado pela CI. Não houve dispositivo/emulador neste ambiente: a instalação em aparelho real é o próximo passo (§90, fase 8).

## Checklist em aparelho real

- [ ] instala e abre (720p, 1080p, 1440p; 16:9, 20:9, 21:9; tablet)
- [ ] safe area com notch/câmera e barra de navegação
- [ ] toque, segurar, toque duplo, pinça, arrastar, dois dedos
- [ ] vibração liga/desliga
- [ ] 60 FPS em tabuleiro 30×30+ (Configurações → Efeitos "Baixos" se necessário)
- [ ] save sobrevive a fechar o app pelo multitarefa
