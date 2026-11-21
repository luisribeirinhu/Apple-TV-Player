# Live TV para Apple TV

Esta branch adapta a aplicação de [Mikhail Demidov](https://github.com/mikehouse/Apple-TV-Player) para TV em direto e EPG no tvOS. Mantém o projeto Xcode, os parsers, os serviços de listas e XMLTV, a base de dados SwiftData e a licença MIT original em `LICENSE.txt`.

## Utilização com o Siri Remote

- No primeiro arranque, adicionar uma lista M3U/M3U8 por URL ou escolher uma lista já guardada. A última lista utilizada é recuperada no próximo arranque; listas protegidas continuam a pedir o PIN existente.
- A coluna esquerda ocupa 35% da área útil e apresenta três quadrados fixos e uma única lista de todos os canais, na ordem original. Os grupos presentes no ficheiro não são apresentados.
- Selecionar um canal muda a reprodução. Selecionar novamente o canal em reprodução, ou selecionar o vídeo, abre o ecrã inteiro. BACK regressa à interface principal.
- Uma posição vazia adiciona o canal em reprodução. Manter SELECT numa posição permite substituir ou remover. Manter SELECT numa linha permite atribuí-la a uma das três posições. As mesmas três posições são geridas nas definições.
- LEFT numa linha revela e foca a engrenagem à esquerda. SELECT abre as definições; RIGHT ou BACK na engrenagem regressa à lista. O leitor continua ativo ao navegar e abrir as definições.
- Os favoritos guardam identificadores resumidos por SHA-256, sem URLs ou credenciais. Um `tvg-id` estável permite recuperar o favorito após mudança de URL. As posições pertencem às listas de origem; uma posição de uma lista diferente ou de um canal removido fica indisponível até essa lista regressar ou a posição ser substituída.
- As definições permitem adicionar/mudar/atualizar a lista, configurar/atualizar XMLTV, ajustar o comportamento de buffering e gerir as três posições. Guardar alterações numa lista protegida exige o respetivo PIN, que não é guardado nas preferências.

## Implementação

O caminho tvOS de `ContentView` apresenta `LiveTVView`. `LiveTVViewModel` usa os serviços existentes; a transformação dos canais decorre fora do ator principal. A lista usa `LazyVStack` e identidades por posição, preservando entradas duplicadas. Os logótipos usam a cache Nuke já presente e podem vir da lista ou de XMLTV.

`TvOSPlayer` mantém um único `AVPlayer`, troca apenas o item quando a URL muda e partilha o leitor entre a apresentação compacta e o ecrã inteiro. A navegação e as atualizações do relógio não chamam `play()` nem voltam a criar o leitor. Os erros de reprodução são apresentados junto ao vídeo.

O EPG dá prioridade a `tvg-id`, mantendo a associação por nome como recurso. As datas XMLTV usam calendário gregoriano e o desvio UTC indicado na origem. A interface apresenta as horas no fuso do dispositivo, calcula o progresso pela duração real e mostra uma indicação discreta quando falta informação.

## Compilação e testes

Num Mac com Xcode e `xcbeautify`, executar na raiz:

```sh
bash scripts/validate-tvos.sh
```

O script apresenta as versões e runtimes disponíveis, compila o target existente para tvOS Simulator e executa as suites de favoritos, Live TV, mapeamento/fusos XMLTV e regressões dos parsers, serviço de listas e StreamViewModel. Usa a pasta DerivedData predefinida do Xcode e um simulador Apple TV já instalado. Não requer assinatura nem credenciais IPTV. Os testes novos de reprodução usam composições AVFoundation vazias, sem contactar canais reais.

O workflow `.github/workflows/tvos-live-tv.yml` usa o runner `xcode-27`, Xcode 27.1 e executa o mesmo script em pushes para branches `codex/**`, pull requests e execução manual. A disponibilidade destes nomes foi confirmada na [documentação oficial dos runners](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md). O workflow só valida; não distribui a aplicação.

Na implementação inicial, o ambiente local é Linux, sem Swift/Xcode. Foram verificados a sintaxe Bash e `git diff --check`; a compilação e os testes Swift só podem ser declarados aprovados depois de executados num Mac/runner. Um ficheiro `.rdp` permite acesso gráfico ao Mac a partir do Windows, mas não configura SSH para o Codex.

## Validação pendente no Apple TV

1. Com uma lista autorizada com milhares de canais, verificar deslocação, repetição rápida UP/DOWN, recuperação do foco e logótipos; medir latência e memória com Instruments.
2. Verificar LEFT → engrenagem → SELECT, RIGHT/BACK → linha anterior e transições entre quadrados, lista e vídeo com o Siri Remote físico.
3. Confirmar continuidade de áudio/vídeo durante navegação, definições e transições para/de ecrã inteiro; testar Play/Pause e aplicação em segundo plano.
4. Atribuir/substituir/remover as três posições, terminar/reabrir a aplicação e atualizar uma lista com URLs diferentes e `tvg-id` estável.
5. Testar EPG em mudanças de dia e hora de verão, ausência de guia, falhas de rede, URLs inválidas e atualização de listas protegidas com PIN correto/incorreto.

Não foram medidas latências de zapping nem desempenho em hardware nesta implementação.
