# LIFE RESET

Aplicação iOS nativa (Swift + SwiftUI) de gestão pessoal: horários de trabalho, tarefas, saúde, nutrição, treino, finanças, objetivos e viagens. Os dados ficam no iPhone.

- **Arquitetura e plano por fases:** [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
- **Estado atual:** fases 0–8 implementadas (ver "Estado da implementação" no topo de `docs/ARCHITECTURE.md`).

## O que a app faz
- **Home:** próximo compromisso, contagem até sair de casa, 3 prioridades, progresso e XP do dia, saúde, avisos e o dia de amanhã.
- **Calendar:** vistas de dia, semana e mês com turnos, folgas, Recovery, viagens e compromissos; modo viagem com voos (fusos horários), bagagem e lembretes.
- **Tasks:** plano do dia, tarefas fixas, ancoradas e flexíveis, recorrências, entrada rápida em português, Sunday Reset, edição do dia com propostas de alteração (nada muda sem aprovação) e reagendamento.
- **Progress:** nível total e por área, sequências, objetivos, conquistas, estatísticas e observações.
- **Finance:** entradas, despesas, fixas, previsão do mês (estimativa), orçamentos, dívidas, poupanças, contas, relatórios e importação de CSV.
- **Saúde e rotina** (a partir da Home): nutrição, água, peso, medidas, fotos privadas, treino, despensa, receitas, compras e produtos pessoais.
- **Widgets** (só leitura): A seguir, Prioridades, Progresso do dia, Sair de casa, Agenda de hoje (inclui ecrã bloqueado).
- **Notificações:** tarefas, hora de sair, resumos da manhã e da noite, pagamentos fixos e viagem, com ações "Concluir" e "Adiar 15 min".
- **Cópia de segurança** cifrada com palavra-passe (Definições).

## Requisitos
- iPhone com **iOS 17** ou mais recente
- Para compilar: GitHub Actions (já configurado) **ou** um Mac com Xcode 15+ e [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Compilar
### Opção A — GitHub (sem Mac)
Cada `push` para `main` corre o workflow **CI**, que faz três coisas:
1. corre os testes do pacote `LifeResetCore`;
2. compila a app sem assinatura e embute os entitlements (App Group);
3. publica `LifeReset.ipa` em **Releases** (pré-lançamento).

### Opção B — Mac com Xcode
```bash
brew install xcodegen
xcodegen generate
open LifeReset.xcodeproj
```
Em **Signing & Capabilities**, escolhe a tua equipa (Apple ID). Depois liga o iPhone e carrega em ▶︎.

## Instalar no iPhone (sideload)
Um `.ipa` sem assinatura **não instala** sozinho: tem de ser assinado no momento da instalação.

1. Instala o **AltServer** no PC e o **AltStore** no iPhone (altstore.io).
2. Copia o `LifeReset.ipa` para o iPhone (Ficheiros ou iCloud Drive).
3. No AltStore: **My Apps → +** → escolhe o ficheiro. O AltStore assina-o com o teu Apple ID e regista o App Group.
4. Se for pedido, em **Definições → Geral → VPN e gestão de dispositivos**, confia no perfil.

### Limites do Apple ID gratuito
- A assinatura dura **7 dias**. O AltStore renova-a automaticamente com o AltServer ligado na mesma rede.
- Só podes ter **3 apps ativas**, incluindo o AltStore, e **10 App IDs por semana**. A partir da Fase 7, os widgets do LIFE RESET contam como mais um App ID.
- Com uma conta paga de programador (99 USD/ano), estes limites desaparecem e a assinatura dura 1 ano.

### Atualizar sem perder dados
Instala o novo `.ipa` por cima da versão anterior. O bundle ID (`com.lifereset.app`) mantém-se, e por isso os dados mantêm-se. Os dados só se perdem se apagares a app; para isso existe a exportação de backup cifrado (Fase 8).

## Estrutura
Ver §4 de [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).
