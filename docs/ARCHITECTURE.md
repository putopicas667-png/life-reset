# LIFE RESET — Arquitetura técnica e plano de desenvolvimento

> Documento de referência. Nenhum módulo de funcionalidades é implementado antes de esta arquitetura ser aprovada.
> Versão 0.1 · 15/11/2026

---

## 1. Resumo das decisões

| Tema | Decisão | Porquê |
|---|---|---|
| Linguagem / UI | Swift 5.10+, SwiftUI, `@Observable` | Pedido pela especificação; estado reativo simples |
| iOS mínimo | **iOS 17.0** | SwiftData, `@Observable`, widgets interativos e `containerBackground` só existem a partir do 17 |
| Dispositivo | iPhone (só vertical na v1) | Prioridade da especificação |
| Persistência | **SwiftData** com esquemas versionados (`VersionedSchema` + `SchemaMigrationPlan`) | Nativa, sem dependências, com migrações declaradas |
| Lógica de negócio | Pacote Swift local **`LifeResetCore`**, sem SwiftUI nem SwiftData | Motor de planeamento, recorrências, finanças, XP e parser são testáveis isoladamente (`swift test`) |
| Arquitetura de UI | Por funcionalidade (`Features/…`): View + ViewModel `@Observable` + acesso a dados por repositórios | Módulos independentes, como pedido na especificação |
| Dependências externas | **Nenhuma** na v1 | Sem serviços pagos, tudo offline |
| Projeto Xcode | Gerado por **XcodeGen** (`project.yml`) | O PC é Windows: o projeto é gerado e compilado no macOS do GitHub; também abre em qualquer Mac |
| Compilação | **GitHub Actions** (macOS): testes do Core, build da app, `.ipa` | Não há Mac disponível; é o mesmo método que já funcionou com o Despertar |
| Distribuição | `.ipa` sem assinatura → assinado pelo **AltStore** (ou Sideloadly) com o Apple ID do utilizador | Sideload. Um `.ipa` sem assinatura **não instala** sozinho (ver §12) |
| Widgets | Extensão WidgetKit a ler um **snapshot JSON** num App Group | Os widgets não abrem a base de dados; leitura rápida e segura |
| Notificações | Locais (`UserNotifications`), janela rolante de agendamento | O iOS limita a 64 notificações pendentes |
| Privacidade | Dados só no dispositivo; proteção de ficheiros iOS; backups cifrados com palavra-passe | Requisitos §20.4 |

---

## 2. Inconsistências e decisões em falta (para confirmar)

Cada ponto tem uma **decisão por omissão**. É essa que sigo se não disseres nada.

1. **Versão do iOS do iPhone.** Assumo iOS 17 ou mais recente. Se o iPhone tiver iOS 16, troco SwiftData por SQLite e perco os widgets interativos.
2. **Limites do Apple ID gratuito (sideload).**
   - Com um Apple ID gratuito só podes ter **3 apps assinadas ativas, incluindo o próprio AltStore**.
   - Há também um limite de **10 App IDs por semana**, e cada extensão de widget conta como um App ID.
   - O LIFE RESET usa 2 App IDs (app + widgets). Se o Despertar e o Stand Magnata também estiverem instalados, ultrapassas o limite.
   - Decisão: avisar nas instruções. Com conta paga de programador (99 USD/ano) estes limites desaparecem e a renovação passa a ser anual em vez de semanal.
3. **XP e correções.** A especificação diz "nunca retirar XP". Mas se marcares uma tarefa como feita por engano e a desmarcares, o XP dessa marcação deve sair, senão o XP deixa de refletir o real.
   - Decisão: desmarcar no **mesmo dia** anula apenas o XP dessa marcação.
   - Falhar uma tarefa nunca retira XP.
   - Níveis já atingidos nunca descem: o nível mostrado é o máximo alguma vez atingido.
4. **Recovery Mode em dias de trabalho.** A especificação não diz se só pode ser ativado em folgas.
   - Decisão: pode ser ativado em qualquer dia, com um máximo de 2 por semana (segunda a domingo).
   - Num dia de trabalho, só reduz as tarefas fora do turno.
5. **Dias de trabalho do café.**
   - Decisão: o café é sempre ao domingo, mas o domingo de cada semana pode ser editado ou desmarcado no Sunday Reset.
   - A semana tem de somar 4 turnos de hambúrgueres + 1 de café + 2 folgas = 7 dias. Se não somar, aparece um aviso, mas sem bloquear (para cobrir baixas, férias e trocas de turno).
6. **Jantar nos dias de hambúrgueres.** Regressas às 23:00 e a hora de deitar de referência é 00:00.
   - Decisão: o jantar fica na pausa ou às 23:00 (configurável).
   - A app avisa quando a janela entre o jantar e a hora de deitar for curta, mas não impõe nada.
7. **Saldo atual (finanças).** Sem ligação ao banco, a app não pode saber o saldo real.
   - Decisão: crias contas manuais (por exemplo "Revolut") com um saldo inicial. O saldo atual = saldo inicial + rendimentos − despesas.
   - É sempre apresentado como "estimado".
8. **Eletricidade (variável).** Decisão: despesa fixa com valor estimado editável. Quando chega a fatura, registas o valor real.
9. **Relatórios mensais "automáticos".** O iOS não garante que a app corra em segundo plano.
   - Decisão: o relatório do mês anterior é gerado na **primeira abertura da app** no mês seguinte e fica guardado no histórico.
10. **Nomes dos separadores.** Mantenho-os em inglês, como na especificação: Home, Calendar, Tasks, Progress, Finance. O resto da interface fica em português de Portugal.
11. **Fotografias de progresso.** Ficam guardadas **dentro da app** (não na galeria), com proteção de ficheiros completa. Só ficam fora do iPhone se as exportares num backup.
12. **Passos (HealthKit).**
    - A capacidade HealthKit deve funcionar com Apple ID gratuito, mas só é confirmada no primeiro teste no iPhone.
    - A app funciona sem HealthKit.
    - Se a autorização falhar, o cartão de passos explica porquê, em vez de mostrar zeros.

---

## 3. Dependências externas, permissões e limitações reais do iOS

| Funcionalidade | Depende de | Situação | Alternativa implementada |
|---|---|---|---|
| Notificações e ações rápidas | Permissão do utilizador | ✅ Possível | — |
| Mais de 64 notificações | Limite do iOS | ⚠️ Limite fixo | Agendamento rolante (§8) |
| Widgets | App Group (entitlement) | ✅ Possível; o entitlement é embutido no build | Snapshot JSON |
| Atualização dos widgets | Orçamento de refresh do iOS | ⚠️ Não é em tempo real | Timeline por hora + recarga sempre que os dados mudam |
| Passos | HealthKit (entitlement + permissão) | ⚠️ A confirmar com Apple ID gratuito | Cartão com explicação; app funciona sem passos |
| Screen Time real | `FamilyControls` / `DeviceActivity` | ❌ O entitlement *Family Controls* exige aprovação da Apple para distribuição e não está disponível com Apple ID gratuito | **Registo manual** de tempo (produtivo, entretenimento, livre) com metas de redução gradual. A limitação é explicada no ecrã |
| Revolut | API bancária | ❌ A Revolut não tem uma API pessoal para contas de particulares. As APIs Open Banking são para empresas reguladas, e a Suíça não está coberta pela PSD2 | **Importação de extratos CSV** exportados da app Revolut. Nunca são pedidas palavras-passe bancárias |
| Calendário Apple | EventKit | Fora da v1 (pedido) | Calendário interno |
| Execução em segundo plano | Background App Refresh | ⚠️ Sem garantias | Tudo o que é crítico corre ao abrir a app ou numa notificação |
| Câmara / fotos | `PhotosPicker` | ✅ Não precisa de permissão para escolher fotos | Fotos copiadas para o armazenamento privado |

---

## 4. Estrutura do projeto

```text
LifeReset/
├── project.yml                     # XcodeGen: alvos, capacidades, definições
├── README.md                       # Como compilar, assinar e instalar
├── docs/
│   └── ARCHITECTURE.md             # Este documento
├── .github/workflows/
│   └── ci.yml                      # Testes do Core + build + .ipa
│
├── Packages/
│   └── LifeResetCore/              # Lógica pura, sem UI e sem base de dados
│       ├── Package.swift
│       ├── Sources/LifeResetCore/
│       │   ├── Shared/             # TimeOfDay, intervalos, calendário PT, IDs
│       │   ├── Scheduling/         # Motor de planeamento, recorrências, rollover
│       │   ├── Work/               # Regras de turnos, deslocações, validação semanal
│       │   ├── Nutrition/          # Horários de refeições, metas, sugestões a partir da despensa
│       │   ├── Training/           # Distribuição de treinos, progressão de cargas
│       │   ├── Finance/            # Saldos, previsão, orçamentos, CSV, dívidas
│       │   ├── Progression/        # XP, níveis, sequências, conquistas
│       │   ├── Travel/             # Janelas de viagem, fusos, lembretes
│       │   ├── Insights/           # Análises de comportamento, frases dos resumos
│       │   └── Parsing/            # Entrada rápida em linguagem natural (pt-PT)
│       └── Tests/LifeResetCoreTests/
│
├── LifeReset/                      # Alvo da app
│   ├── App/
│   │   ├── LifeResetApp.swift      # @main, ModelContainer, injeção de serviços
│   │   ├── AppState.swift          # Estado global (data atual, modo viagem, etc.)
│   │   ├── AppConfiguration.swift  # Constantes, IDs do App Group
│   │   └── RootTabView.swift       # Home · Calendar · Tasks · Progress · Finance
│   ├── Core/
│   │   ├── Models/                 # @Model SwiftData, por domínio
│   │   ├── Persistence/            # Container, esquemas versionados, migrações, repositórios, backup
│   │   ├── Services/               # Planeamento (ponte para o Core), HealthKit, fotos, snapshot dos widgets, CSV
│   │   ├── Notifications/          # Agendador rolante, categorias, tratamento das ações
│   │   ├── DesignSystem/           # Cores, tipografia, espaçamentos, componentes
│   │   └── Utilities/
│   ├── Features/
│   │   ├── Home/  Calendar/  Tasks/  Progress/  Finance/
│   │   ├── Work/  SundayReset/  Hygiene/  Household/
│   │   ├── Nutrition/  Pantry/  Inventory/  Training/  Body/
│   │   ├── Goals/  Travel/  Leisure/  Settings/  QuickEntry/
│   └── Resources/
│       ├── Assets.xcassets
│       ├── Info.plist
│       ├── LifeReset.entitlements
│       └── pt-PT.lproj/Localizable.strings
│
├── LifeResetWidgets/               # Extensão WidgetKit
│   ├── Widgets/                    # Próxima tarefa, Progresso, Semana, Objetivos, Finanças
│   ├── Intents/                    # AppIntent "Concluir" (widget interativo)
│   ├── Info.plist
│   └── LifeResetWidgets.entitlements
│
├── Shared/                         # Código partilhado entre a app e os widgets
│   ├── WidgetSnapshot.swift        # Formato do snapshot (Codable, versionado)
│   ├── AppGroup.swift              # Caminhos no container partilhado
│   └── PendingActions.swift        # Fila de ações vindas dos widgets
│
└── LifeResetTests/                 # Testes de integração (persistência, migrações)
```

**Regras de dependência**
- `LifeResetCore` não importa nada da app.
- A app usa o Core.
- Os widgets usam só `Shared/`.
- As features não se importam umas às outras. Partilham dados através de repositórios e serviços de `Core/`.

---

## 5. Camadas

```text
┌──────────────────────────────────────────────────────────┐
│ Features (SwiftUI Views + ViewModels @Observable)        │  apresentação
├──────────────────────────────────────────────────────────┤
│ Services (Planning, Notifications, Snapshot, Health…)    │  orquestração
├──────────────────────────────────────────────────────────┤
│ Repositories (SwiftData → tipos de valor do Core)        │  acesso a dados
├────────────────────────────┬─────────────────────────────┤
│ SwiftData (@Model)         │ LifeResetCore (lógica pura) │
└────────────────────────────┴─────────────────────────────┘
```

- **Os ViewModels nunca chamam o motor de planeamento diretamente.** Pedem a um serviço, que lê os dados (repositório), converte-os em tipos de valor, chama o Core e devolve o resultado.
- **Alterações importantes passam sempre por uma proposta** (`PlanProposal`) que o utilizador aceita ou rejeita (§7.4).
- **Fluxo após uma alteração aos dados:** depois de cada gravação, o `ChangeCoordinator` faz três coisas:
  1. reagenda as notificações afetadas;
  2. regenera o snapshot dos widgets;
  3. pede ao WidgetKit para recarregar.

---

## 6. Modelo de dados (SwiftData)

Convenções:
- todos os modelos têm `id: UUID`, `createdAt` e `updatedAt`;
- os valores monetários são `Decimal` (CHF), nunca `Double`;
- as horas guardam-se como minutos desde a meia-noite (`TimeOfDay`) ou como `Date` com fuso explícito.

### 6.1 Perfil e definições
- **UserProfile**
  - Horas de referência (deitar 00:00, acordar 07:30)
  - Metas: peso 65 kg, 2800 kcal, 3 L de água, 4 treinos por semana, proteína opcional
  - Moeda: CHF
  - Preferências alimentares (lista livre, não obrigatória)
- **Job**
  - Nome e tipo (`burger` / `cafe` / outro)
  - Horários por omissão: entrada, saída, saída de casa, deslocação de ida e regresso, duração da pausa
  - Antecedência de chegada (30 min nos hambúrgueres)

### 6.2 Semana e turnos
- **WeekPlan**
  - `weekStart` (segunda-feira)
  - Estado: `draft` / `confirmed`
  - Prioridades semanais (texto) e notas
- **DayAssignment** (1 por dia da semana)
  - `date` e `kind`: `burgerShift` / `cafeShift` / `dayOff` / `travel` / `custom`
  - Início e fim do turno; início previsto da pausa e duração
  - Horas extra (minutos); saída de casa e regresso (derivados, editáveis)
  - `isRecovery`
- Regras de validação (no Core, `WeekValidator`): ver §2.5 e o máximo de 2 dias de recuperação.

### 6.3 Tarefas
- **TaskItem** (a definição)
  - Título, descrição, categoria (`hygiene`, `household`, `shopping`, `health`, `training`, `finance`, `admin`, `personal`…) e prioridade (1–4)
  - Duração estimada
  - **Modo de agendamento:**
    - `fixed`: data/hora exata
    - `flexible`: janela (por exemplo 09:00–20:00) e dias permitidos
    - `anchored`: relativa a um momento do dia, por exemplo "Manhã", "Após almoço", "Noite"
  - **Recorrência** (`RecurrenceRule`, Codable): diária, semanal, mensal, dias específicos, intervalo de N dias, ou personalizada
  - **Local:** `home` / `anywhere` / `breakCompatible` (compatível com a pausa no trabalho)
  - **Partilha:** `personal` / `shared` / `waitingOther`
  - **Política quando falha:** `carryToNextPeriod` (higiene), `proposeReschedule` (compras, treino, limpeza), `keepDeadline` (com prazo)
  - Prazo opcional
  - **Notificação:** ativa ou não, antecedência, repetição
  - Essencial (sim/não): preservada em Recovery e Travel
  - XP base e área de progressão
  - Subtarefas (relação com outros `TaskItem`)
- **TaskOccurrence** (cada vez que a tarefa acontece)
  - `taskId`, `date` e início planeado
  - Estado: `pending` / `done` / `skippedToday` / `failed` / `rescheduled` / `waiting`
  - Hora de conclusão e XP atribuído
- **DailyPriority**: `date` e 3 posições, cada uma a apontar para uma ocorrência.

As ocorrências são **materializadas** para a janela de hoje até +14 dias (e geradas ao abrir a app). O histórico nunca é apagado.

### 6.4 Saúde, nutrição e corpo
- **FoodItem** (biblioteca): nome, kcal e proteína por 100 g ou por unidade.
- **MealLog**: data, tipo (`breakfast` / `lunch` / `dinner` / `snack`) e entradas (alimento, quantidade, kcal, proteína).
- **WaterLog**: data e ml.
- **WeightEntry**: data e kg.
- **BodyMeasurement**: data, tipo (peito, braço, cintura…) e cm.
- **ProgressPhoto**: data, nome do ficheiro e nota. O ficheiro fica na pasta privada da app, com proteção `complete`.
- **PantryItem**: nome, quantidade, unidade e validade opcional.
- **ShoppingItem**: nome, quantidade e se já foi comprado.
- **Recipe**: nome e ingredientes (nome + quantidade). Pré-carregadas com receitas simples a partir dos alimentos preferidos; editáveis.
- **PersonalProduct**: nome e estado (`have` / `out`). Sem previsões.

### 6.5 Treino
- **Exercise**: nome, grupos musculares e equipamento. Pré-carregados com exercícios para o equipamento disponível.
- **WorkoutTemplate**: nome e exercícios com séries e repetições alvo.
- **WorkoutSession**: data, duração, notas e séries (exercício, nº da série, repetições, peso).

### 6.6 Finanças
- **Account**: nome e saldo inicial (o saldo atual é sempre estimado).
- **IncomeEntry**: valor, data, tipo (`salary` / `extra` / `other`) e nota.
- **Expense**: valor, data, categoria, descrição, meio de pagamento, se é fixa, e conta.
- **ExpenseCategory**: nome editável e ícone.
- **FixedExpense**: nome, valor (ou estimativa, se for variável), dia do mês e se está ativa.
  - Pré-carregadas: renda 550 CHF, seguro de saúde 600, telemóvel 70, internet 50, transportes 125, eletricidade (estimada).
- **Budget**: categoria e limite mensal (para os alertas).
- **Debt**: credor, valor inicial, data, prazo e estado; mais **DebtPayment** (valor e data).
- **SavingsGoal**: nome, alvo e prazo opcional; mais **SavingsContribution** (valor e data).
- **MonthlyReport**: mês e um snapshot dos totais, gerado uma vez.

### 6.7 Progressão
- **XPEvent** (registo só de acrescento): data, área (Físico / Saúde / Finanças / Aparência / Produtividade / Vida pessoal), valor e origem.
  - O nível e o XP de cada área são **calculados** a partir deste registo.
  - O nível máximo atingido fica guardado e nunca desce.
- **Goal**: área, horizonte (curto / médio / longo), título, métrica (por exemplo kg, CHF, treinos por semana), valor inicial, alvo, prazo e estado.
- **AchievementUnlock**: id da conquista e data. As definições das conquistas estão no Core.
- **Sequências:** calculadas a partir das ocorrências; não são guardadas.

### 6.8 Calendário e viagens
- **CalendarEvent**: só para eventos pessoais (título, início, fim, dia inteiro, local).
  - Turnos, tarefas, refeições, treinos e viagens são mostrados no calendário por um `CalendarAggregator`, sem duplicar dados.
- **Trip**: destino, partida, regresso, alojamento, transporte e tempo até ao aeroporto.
- **Flight**: número, aeroportos, hora de partida e chegada, e o identificador do fuso horário de cada aeroporto.
- **ChecklistTemplate**: nome e itens (categoria e texto).
- **TripChecklistItem**: cópia de um modelo, com estado próprio em cada viagem.
- **TripReminder**: tipo (malas, check-in, documentos, transporte, dinheiro, bagagem) e antecedência.

### 6.9 Tempo livre
- **TimeLog**: data, tipo (`productive` / `entertainment` / `free`), minutos e atividade (texto).
- **ScreenTimeTarget**: meta semanal de entretenimento com redução gradual sugerida.
- **LeisureActivity**: sugestões opcionais.
- **Música:** existe só como atividade de tempo livre. Está explicitamente excluída de XP, tarefas e notificações. A regra é imposta no Core.

---

## 7. Motor de planeamento (`LifeResetCore/Scheduling`)

É código puro e determinístico: com os mesmos dados de entrada dá sempre o mesmo resultado. É totalmente coberto por testes.

### 7.1 Entradas
- `DayAssignment` do dia, `Job`s e `UserProfile`
- O dia seguinte, para calcular a hora de acordar
- Ocorrências do dia (fixas, flexíveis e ancoradas), refeições e treino previsto
- Estado de viagem (`Trip` ativa) e de Recovery

### 7.2 Construção do contexto do dia (`DayContextBuilder`)
1. **Dia de hambúrgueres:**
   - Linha do tempo: acordar (sugerido) → preparação → saída de casa 09:20 → comboio → chegada ~10:00 → janela de 30 min (`breakCompatible`) → turno 10:30–22:30 + horas extra
   - A pausa de 60 min fica na hora definida para esse dia
   - Regresso ~23:00 → noite → deitar
2. **Café (domingo):** saída 12:50 → turno 14:00–20:30 (pausa de 30 min) → regresso ~22:00.
3. **Folga:** acordar 07:30, dia livre, deitar 00:00.
4. **Hora de acordar sugerida** = mínimo de 07:30 e (saída de casa − tempo de preparação configurado). Se for mais cedo do que a referência, é gerado um **aviso** ("Amanhã tens de acordar às 07:50").
5. **Resultado:** intervalos ocupados (trabalho, deslocação), janelas livres em casa, janelas compatíveis com a pausa, e âncoras (Manhã / Após almoço / Noite / Antes de deitar).

### 7.3 Colocação das tarefas (`DayPlanner`)
Ordem de colocação:
1. **Fixas:** ficam na hora definida. Se houver choque com o turno ou a deslocação, é criado um **conflito** (não são movidas).
2. **Ancoradas** (higiene, por exemplo): colocadas na âncora certa. A higiene da manhã cabe antes da saída de casa; a "escovar dentes após almoço" vai para a pausa.
3. **Refeições:** regras por tipo de dia (§9.1), dentro de janelas permitidas.
4. **Treino:** completo em folgas; curto em dias de trabalho, só se houver uma janela livre em casa suficiente.
5. **Flexíveis:** ordenadas por prazo, prioridade e duração. Cada uma vai para a primeira janela compatível (em casa / qualquer sítio / pausa).
   - As tarefas domésticas e partilhadas têm preferência pelos dias de folga.
6. **Recovery:** só entram as tarefas `essential`. O treino pesado é removido e há um bloco de tempo livre protegido.
7. **Viagem:** as tarefas `home` não são agendadas nem marcadas como falhadas. Os hábitos essenciais mantêm-se.

**Saída** — `DayPlan`, com:
- blocos ordenados;
- tarefas que não couberam e o motivo;
- conflitos e avisos;
- as 3 prioridades sugeridas, que o utilizador confirma.

### 7.4 Replaneamento após alterações
Uma alteração a um turno, horas extra ou um dia de Recovery provoca:
1. o cálculo do novo `DayPlan`;
2. uma comparação entre o plano antigo e o novo;
3. uma **`PlanProposal`** com a lista de mudanças ("Mover *Aspirar* de terça para sábado").

O utilizador aceita tudo, aceita em parte, ou rejeita. **As tarefas fixas e as prioridades nunca são alteradas sem confirmação.**

### 7.5 Tarefas não concluídas (rollover)
Ao virar o dia, ou ao abrir a app:

| Política | Comportamento |
|---|---|
| `carryToNextPeriod` | A ocorrência fica `failed` (sem XP, registada). A próxima ocorrência normal mantém-se |
| `proposeReschedule` | Fica `failed` e é criada uma proposta para a próxima janela compatível (por exemplo a próxima folga) |
| `keepDeadline` | Mantém-se pendente até ao prazo, com destaque. Depois do prazo, fica `failed` com histórico |

Nada é apagado em silêncio.

### 7.6 Recorrências (`RecurrenceEngine`)
Gera as datas de uma regra num intervalo. Suporta:
- diária;
- semanal (dias da semana);
- mensal (dia N, ou "último dia");
- a cada N dias desde uma data;
- datas específicas.

Respeita os períodos de viagem quando a tarefa é `home`.

---

## 8. Notificações

- **Categorias com ações:** `Concluído`, `Adiar 15 min`, `Reagendar` (abre a app na tarefa) e `Ignorar hoje`.
  - As ações `Concluído`, `Adiar` e `Ignorar` correm em segundo plano. A app grava a alteração, reagenda e atualiza os widgets.
- **Agendamento rolante:** o iOS só mantém 64 notificações pendentes.
  - O `NotificationScheduler` agenda as próximas ~50, ordenadas por data.
  - Reserva lugares para os resumos da manhã e da noite e para os lembretes de viagem.
  - Recalcula ao abrir a app, ao gravar dados e no Background App Refresh (quando o iOS o permitir).
- **Resumo da manhã:** horário, prioridades, trabalho e hora de saída, e refeições.
- **Resumo da noite:** concluídas, pendentes, progresso, objetivos e amanhã.
  - A frase vem de um gerador baseado nos dados reais (`Insights/SummaryComposer`). Exemplo: "Concluíste 4 de 11 tarefas; o treino ficou por fazer."
  - Sem elogios quando o dia correu mal.
- **Permissão:** pedida apenas quando ativas a primeira notificação, e não no arranque.

---

## 9. Regras de domínio relevantes

### 9.1 Horários das refeições (`MealTimingRules`)
| Tipo de dia | Pequeno-almoço | Almoço | Jantar |
|---|---|---|---|
| Hambúrgueres | Em casa antes das 09:20, ou na janela de 30 min antes do turno | Na pausa de 60 min | Na pausa ou ao regressar (~23:00), configurável |
| Café | Manhã em casa | Antes das 12:50 | Ao regressar (~22:00), mais um snack opcional na pausa de 30 min |
| Folga / Recovery | Horário normal (por exemplo 08:00 / 13:00 / 20:00) | | |
| Viagem | Horário flexível; o registo de kcal e proteína continua disponível | | |

### 9.2 Finanças (`FinanceCalculator`)
- **Saldo estimado** = saldo inicial + rendimentos − despesas, até hoje.
- **Previsão do fim do mês** = saldo estimado − despesas fixas ainda por pagar este mês − média diária das despesas variáveis dos últimos 60 dias × dias restantes + rendimentos já registados para datas futuras.
  - É sempre apresentada como **"Estimativa baseada nos dados introduzidos"**.
- **Alertas de orçamento** aos 80% e aos 100% do limite de cada categoria.
- **Importação CSV:**
  - parser configurável (separador, formato da data, colunas);
  - pré-visualização antes de importar;
  - deteção de duplicados (data + valor + descrição).

### 9.3 XP (`XPRules`)
- **XP base por prioridade da tarefa:** 5 / 10 / 15 / 20.
- **Bónus:**
  - +5 por cada prioridade diária concluída;
  - +10 por dia com todas as tarefas essenciais feitas;
  - XP de poupança por marcos (25%, 50%, 75%, 100%) de cada objetivo.
- **Nível:** cada nível exige `100 × n^1.5` de XP.
- **Atributos:** 6 áreas, cada uma com o seu próprio XP e nível.
- **Garantias de comportamento:**
  - nunca se perde XP por falhar;
  - as sequências partidas não apagam o progresso;
  - nunca há recompensas por gastar dinheiro;
  - a música nunca dá XP.

### 9.4 Entrada rápida (`QuickEntryParser`)
- Funciona por regras e localmente, em pt-PT.
- **Datas:** "hoje", "amanhã", "depois de amanhã", "sábado", "dia 20", "às 18h" e "18:30".
- **Categorias** por palavras-chave: comprar → compras, limpar/aspirar → casa, pagar → finanças, treino → treino.
- **Resultado:** uma `TaskDraft` com o grau de confiança de cada campo. É sempre mostrada para confirmação antes de criar a tarefa.

---

## 10. Widgets

| Widget | Tamanhos | Conteúdo |
|---|---|---|
| Próxima tarefa | Small, Medium, Lock Screen (retangular / inline) | Próxima tarefa e hora; botão "Concluir" (interativo, iOS 17) |
| Progresso diário | Small, Lock Screen circular | % de tarefas, prioridades e água |
| Calendário semanal | Medium, Large | Os 7 dias: turnos, folgas, Recovery e viagem |
| Objetivos | Medium | 3 objetivos com barra de progresso |
| Estado financeiro | Small, Medium | Saldo estimado, despesas do mês e previsão (rotulada "estimativa") |

- **Como os dados chegam aos widgets:** a app escreve `widget-snapshot.json` no App Group, com versão e data. Os widgets apenas o leem.
  - O snapshot inclui o plano de hoje e de amanhã, por isso a "próxima tarefa" avança sozinha com a timeline, sem abrir a app.
- **Botão "Concluir":** escreve na fila `PendingActions` do App Group e atualiza o snapshot logo no widget. A app aplica a fila à base de dados ao abrir ou na próxima ação em segundo plano.
- **Atualização:** timeline com entradas por hora e recarga quando os dados mudam. Não é tempo real (limitação do iOS).

---

## 11. Persistência, backups e privacidade

- **Base de dados:** a store SwiftData fica no container da app, com proteção `completeUntilFirstUserAuthentication`. Assim as ações das notificações funcionam mesmo com o iPhone bloqueado depois do primeiro desbloqueio.
- **Fotografias:** guardadas com `complete` (só acessíveis com o iPhone desbloqueado).
- **Snapshot dos widgets:** contém apenas totais. Nunca inclui movimentos financeiros detalhados nem fotografias.
- **Migrações:** cada alteração de modelo cria `SchemaV2`, `SchemaV3`, etc., com um `MigrationStage`. Há testes de migração no CI.
- **Backup:**
  - Exportação de todos os dados e fotos para um ficheiro `.lifereset`: um JSON versionado mais as fotos, cifrado com **AES-GCM (CryptoKit)** com uma chave derivada de uma palavra-passe que escolhes.
  - Partilhado pela folha de partilha (Ficheiros, AirDrop).
  - Importação com validação de versão.
- **Atualizar a app (reinstalar o `.ipa` por cima)** mantém os dados. Os dados só se perdem se apagares a app; para isso existe o backup.
- **Sem rede:** a app não faz pedidos de rede na v1.
- **Credenciais bancárias:** nunca são pedidas nem guardadas.
- **Permissões:** pedidas apenas quando a funcionalidade é usada (notificações, HealthKit).

---

## 12. Compilação, assinatura e sideload

1. **CI (GitHub Actions, macOS):**
   1. `swift test` no `LifeResetCore`;
   2. `xcodegen generate`;
   3. testes de integração no simulador;
   4. `xcodebuild` para a app e os widgets, sem assinatura;
   5. `ldid` para embutir os entitlements (App Group e HealthKit);
   6. `.ipa` publicado em Releases.
2. **Instalação:** o `.ipa` **tem de ser assinado** pelo AltStore ou pelo Sideloadly com o teu Apple ID. O AltStore regista o App Group automaticamente.
3. **Renovação:** a cada 7 dias com Apple ID gratuito, ou anual com conta paga.
4. **Com um Mac:** `xcodegen generate` → abrir `LifeReset.xcodeproj` → escolher a equipa em *Signing & Capabilities* → correr no iPhone. As instruções completas vão no README.
5. **Atualizações:** cada push gera um build novo. Ao instalar por cima, o bundle ID mantém-se, e por isso os dados mantêm-se.

---

## 13. Estratégia de testes

| Nível | O quê | Onde |
|---|---|---|
| Unitários (Core) | Planeamento (dias de hambúrgueres e de café, folga, horas extra, Recovery, viagem), recorrências, rollover, validação semanal, finanças, XP, parser | `swift test` no CI, a cada push |
| Integração | Persistência, migrações, repositórios, backup (cifrar/decifrar) | Simulador iOS no CI |
| Manual | Notificações, ações, widgets, HealthKit, sideload | iPhone real, com uma checklist por fase |

Uma funcionalidade só é dada como concluída quando tiver testes do Core a passar **e** for verificada no iPhone (critério §24 da especificação).

---

## 14. Plano por fases

Cada fase termina com a app a compilar, os testes a passar e um `.ipa` instalável.

| Fase | Conteúdo | Entrega verificável |
|---|---|---|
| **0 — Estrutura** *(esta)* | Arquitetura, estrutura de pastas, `project.yml`, pacote Core, CI | O CI compila uma app vazia e corre os testes do Core |
| **1 — Fundação** | Design system (dark), 5 separadores, `ModelContainer` + `SchemaV1`, perfil e definições, onboarding com os valores iniciais | Os dados persistem depois de fechar e reabrir |
| **2 — Horários e tarefas** | Jobs, WeekPlan, Sunday Reset (com validação), pausas, deslocações, TaskItem e recorrências, motor de planeamento, prioridades, propostas de replaneamento, rollover, Recovery (limite 2), entrada rápida | Alterar um turno gera propostas corretas; testes do motor |
| **3 — Saúde e rotina** | Higiene (tarefas individuais), casa e tarefas partilhadas, refeições e kcal/proteína/água, peso e gráficos, despensa e lista de compras, receitas, inventário (tem/acabou), treino (registo e evolução), medidas, fotos privadas, passos (HealthKit) | Registos e gráficos com dados reais |
| **4 — Finanças** | Contas, rendimentos, despesas, fixas, categorias, orçamentos e alertas, dívidas, poupanças, dashboard e gráficos (dia/semana/mês/ano), previsão, relatórios mensais, importação CSV | Totais verificados contra casos de teste |
| **5 — Progressão** | XP, níveis, 6 áreas, objetivos (curto/médio/longo), conquistas, sequências, estatísticas, análises de comportamento | XP persistente e coerente com o histórico |
| **6 — Calendário e viagens** | Vistas de dia, semana e mês, eventos pessoais, Travel Mode, voos e fusos horários, checklists reutilizáveis, lembretes de viagem | Período de viagem sem falhas domésticas |
| **7 — Notificações e widgets** | Agendador rolante, ações rápidas, resumos da manhã e da noite, 5 widgets, widget interativo | Ações rápidas funcionam com o iPhone bloqueado |
| **8 — Polimento e distribuição** | Animações, acessibilidade (Dynamic Type), desempenho, backup e restauro, tempo livre e registo de tempo de ecrã, README de instalação, teste completo no iPhone | Checklist dos 19 critérios de aceitação |

---

## 15. O que fica explicitamente fora da v1

Fica de fora o que a especificação exclui (§26). Além disso:
- sincronização com o Apple Calendar;
- iCloud;
- Open Banking;
- Screen Time automático (por limitação técnica, §3).
