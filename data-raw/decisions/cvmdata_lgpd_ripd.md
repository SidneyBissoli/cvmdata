# Relatório de Impacto à Proteção de Dados Pessoais (RIPD) — espelho do cvmdata

> **RASCUNHO de 2026-11-14, à espera da leitura do responsável.** Não é
> parecer jurídico. Segue o roteiro que a ANPD recomenda na página
> "Relatório de Impacto à Proteção de Dados Pessoais (RIPD)", perguntas e
> respostas, lida em 2026-11-14. Toda afirmação sobre lei, norma ou
> documento de terceiro traz a data em que a fonte foi lida; o que não
> foi lido está na última seção, só com o nome. Os números são contagens;
> nenhuma linha de dado foi copiada para cá.

## a) Agentes de tratamento e encarregado

- **Controlador e encarregado:** Sidney da Silva Pereira Bissoli, pessoa
  natural, mantenedor do pacote `cvmdata`. Contato:
  sbissoli76@gmail.com.
- **Serviços que guardam e distribuem os arquivos:** GitHub (repositório,
  robô e releases do espelho) e Zenodo, mantido pelo CERN (edições com
  DOI). A classificação desses serviços como operadores não foi
  examinada; ver "Pendências".

## b) Outras partes consultadas

Nenhuma. Não houve consulta a advogado, a titulares, à CVM nem à ANPD. A
página da ANPD diz que a consulta ao encarregado é desejável; aqui
controlador e encarregado são a mesma pessoa.

## c) Por que este relatório foi feito

A página da ANPD (lida em 2026-11-14) recomenda o RIPD "em todo contexto
em que as operações de tratamento de dados pessoais possam gerar alto
risco" e adota como parâmetro, enquanto não há regulamento próprio, o
art. 4º do regulamento aprovado pela Resolução nº 2/2022: há alto risco
com ao menos um critério geral e um específico.

| Critério | O que a página diz | No espelho |
|---|---|---|
| Geral: "larga escala" | "número significativo de titulares", sem número | 6.498 pessoas só na tabela de administradores do FRE de 2025; o total de pessoas em todas as tabelas e anos não foi medido |
| Específico: "utilização de dados pessoais sensíveis ou de dados pessoais de crianças, de adolescentes e de idosos" | basta um | 30,1% dos administradores do FRE de 2025 têm 60 anos ou mais |

O critério específico está presente e o geral não pôde ser afastado. A
mesma página lembra que a ANPD pode exigir o relatório "quando o
tratamento tiver como fundamento a hipótese de interesse legítimo (art.
10, § 3º)", que é a base usada aqui. O responsável trata o espelho como
de alto risco e por isso não usa o regime simplificado dos agentes de
pequeno porte (Resolução CD/ANPD nº 2/2022, arts. 3º e 4º, texto do DOU
lido em 2026-11-14): há encarregado indicado e os prazos não são
dobrados.

## d) Projeto que justifica o relatório

O **espelho** do `cvmdata`: cópia em formato parquet dos dados abertos
da CVM sobre companhias abertas, publicada para que o pacote leia mais
rápido e para que uma análise possa ser refeita sobre os mesmos dados.
São nove conjuntos do grupo `companhias`. Três formas de publicação:

1. **cópia corrente** (`-latest`), refeita toda semana;
2. **fotos datadas**, uma a cada rodada que publica, nunca apagadas;
3. **edições trimestrais no Zenodo**, com DOI. Nenhuma edição
   permanente foi publicada até 2026-11-14; a primeira está prevista
   para janeiro de 2027.

A leitura direta do portal da CVM pelo pacote (`source = "cvm"`) não
passa pelo espelho e está fora deste relatório: nela o pacote só baixa o
arquivo para o computador do usuário.

## e) Sistemas de informação

- Portal de dados abertos da CVM (`dados.cvm.gov.br`): a origem.
- GitHub Actions: o robô (`inst/etl/`), que baixa, converte, aplica a
  regra de privacidade e publica.
- GitHub Releases: guarda a cópia corrente e as fotos datadas.
- Zenodo: guarda as edições.
- Pacote R `cvmdata`: lê o espelho no computador do usuário.

## f) Tratamento de dados

### i. Descrição, da coleta à eliminação

1. A companhia entrega os formulários à CVM por dever regulatório, e a
   CVM os publica no portal de dados abertos (Resolução CVM 80, texto
   consolidado lido em 2026-11-14: arts. 17, 18 e 22; Anexo C, item 7.3).
2. Toda terça-feira o robô baixa os arquivos da CVM.
3. Converte para parquet e aplica a regra de privacidade
   (`inst/etl/util-privacy.R`, regra "4") antes de gravar qualquer
   arquivo que será publicado.
4. Uma guarda (`02b-validate.R`) recusa a rodada se sobrar algo que a
   regra tiraria.
5. Publica a cópia corrente e a foto datada; o histórico de entregas
   substituídas passa pela mesma regra.
6. A cada trimestre o robô prepara um rascunho de edição no Zenodo, com
   nova guarda. O robô nunca publica: quem publica é o responsável.
7. Eliminação: ver "x. Armazenamento".

### ii. Dados pessoais tratados

Inventário feito em 2026-11-14 pelas colunas com nome de pessoa no
dicionário de dados (`cad`, `fca` e `fre`), depois da regra "4":

| Dado | Onde |
|---|---|
| Nome | administradores, conselheiros fiscais e membros de comitês; diretor de relações com investidores; responsável pela companhia no cadastro; responsáveis técnicos de auditoria; acionistas, acionistas relacionados e representantes legais; partes de relações familiares e de subordinação; partes relacionadas em transações; quem assina o formulário |
| CPF mascarado (`***.456.789-**`) | onde a CVM publica o CPF |
| Ano de nascimento | administradores, conselheiros fiscais e membros de comitês |
| Profissão, órgão, cargo, datas de eleição, posse e mandato, se foi eleito pelo controlador | administradores, conselheiros fiscais e membros de comitês |
| Participação acionária, nacionalidade e UF | acionistas pessoa física |
| Parentesco entre administradores e relação de subordinação | `fre/relacao_familiar`, `fre/relacao_subordinacao` |
| Município, UF e país de uma pessoa | cadastro e tabelas de contato |
| Menções a pessoas em texto livre | colunas de observação e de descrição de contratos |

O que a CVM publica e o espelho **não** leva: CPF completo e documento
estrangeiro; data de nascimento; e-mail, telefone e fax de qualquer
pessoa ou companhia; endereço de rua de pessoa; a biografia
(`experiencia_profissional`); as três tabelas de declaração de gênero,
raça e deficiência dos administradores.

### iii. Dados pessoais sensíveis

A LGPD, art. 5º, II (lido em 2026-11-14), lista como sensível o dado
sobre "origem racial ou étnica, convicção religiosa, opinião política,
filiação a sindicato ou a organização de caráter religioso, filosófico
ou político, dado referente à saúde ou à vida sexual, dado genético ou
biométrico, quando vinculado a uma pessoa natural".

O espelho não leva de propósito nenhum dado dessa lista ligado a uma
pessoa:

- as contagens de gênero, raça e deficiência dos administradores por
  órgão ficaram fora do espelho;
- as cinco tabelas de contagem de empregados vêm sem a companhia que tem
  grupo com menos de 10 pessoas ou unânime;
- as biografias saíram.

**O que resta e não foi examinado:** as outras 25 colunas de texto longo
do FRE e do FCA de 2025 têm 78 linhas que batem em palavras ligadas a
essa lista, 48 delas numa coluna que descreve contratos
(`fre/transacao_parte_relacionada/natureza_razao_operacao`). As linhas
não foram lidas; não se sabe se alguma revela dado sensível de uma
pessoa.

### iv. Categorias de titulares

Administradores, conselheiros fiscais e membros de comitês de companhias
abertas; diretores de relações com investidores e pessoas de contato;
responsáveis técnicos de auditorias; acionistas pessoa física e seus
representantes; parentes de administradores citados no formulário;
pessoas físicas que são parte relacionada em transações.

### v. Crianças, adolescentes e idosos

- **Idosos:** 30,1% dos 6.498 administradores e conselheiros fiscais do
  FRE de 2025 têm 60 anos ou mais (pelo ano de nascimento).
- **Menores de 18:** três registros do FRE de 2025 têm ano de nascimento
  que daria menos de 18 anos. Não foram conferidos; podem ser erro de
  digitação na origem.

### vi. Volume e número de titulares

FRE de 2025: 8.989 linhas de administradores e conselheiros fiscais,
6.498 pessoas; 1.089 delas (16,8%) em duas ou mais companhias; 4.478
biografias de membros de comitês havia antes da regra "4". O total de
pessoas em todas as tabelas, conjuntos e anos **não foi medido**.

### vii. Fonte

Portal de dados abertos da CVM. Nenhum dado é colhido do titular nem de
outra fonte, e o espelho não cruza a CVM com outras bases.

### viii. Finalidade

Pesquisa, ensino e acompanhamento público da governança das companhias
abertas brasileiras. Não é a finalidade original: a Resolução CVM 80
(arts. 17 e 18, lidos em 2026-11-14) manda divulgar informações "úteis à
avaliação dos valores mobiliários" emitidos, "para todo o mercado". O
estudo da governança é finalidade nova.

| Dado | Para quê |
|---|---|
| Nome | seguir a pessoa entre companhias e anos; um código no lugar foi examinado e recusado em 2026-11-14 (90,8% das linhas se casariam de volta com o arquivo da CVM) |
| CPF mascarado | separar homônimos; medido em 2026-11-08 que máscara mais nome não junta pessoas diferentes |
| Ano de nascimento | idade e geração dos conselhos |
| Profissão, órgão, cargo, mandatos | composição e rotatividade dos órgãos |
| Participação acionária | estrutura de controle |
| Parentesco e subordinação | independência dos administradores |

### ix. Compartilhamento e transferência internacional

O espelho é aberto: qualquer pessoa pode baixá-lo, sem cadastro. Não há
compartilhamento reservado com ninguém.

Os arquivos ficam fora do Brasil (políticas dos dois serviços lidas em
2026-11-14): o Zenodo informa que os arquivos ficam nos centros de dados
do CERN, "primarily Geneva, with replicas in Budapest"; o GitHub informa
que armazena e processa dados "in a variety of locations, including your
local region, the United States".

O que as regras dizem (lidas em 2026-11-14):

- LGPD, art. 33: a transferência internacional "somente é permitida"
  nos casos que o artigo lista, entre eles país ou organismo com
  proteção adequada (I) e cláusulas-padrão contratuais (II, b).
- Regulamento de Transferência Internacional de Dados (Resolução CD/ANPD
  nº 19/2024, texto do DOU): transferência é a operação em que "um
  agente de tratamento transmite, compartilha ou disponibiliza acesso a
  dados pessoais a outro agente de tratamento" (art. 3º, III); cabe ao
  controlador verificar se a operação "caracteriza transferência
  internacional de dados" e se está amparada em "mecanismo de
  transferência internacional válidos" (art. 4º); a validade das
  cláusulas-padrão "pressupõe a adoção integral e sem alteração do
  texto" do Anexo II, "mediante instrumento contratual firmado entre o
  exportador e o importador" (art. 16).
- Página da ANPD sobre transferência internacional: "Até o momento, a
  União Europeia foi considerada como organismo internacional adequado"
  (Resolução nº 32/2026), e nenhuma cláusula equivalente, cláusula
  específica ou norma corporativa global foi aprovada.

Leitura do responsável, ainda sem conclusão: Budapeste está na União
Europeia; Genebra e os Estados Unidos não estão cobertos por decisão de
adequação. Não se sabe se guardar os arquivos no GitHub e no Zenodo
caracteriza transferência no sentido do regulamento, nem se algum dos
dois oferece contrato com as cláusulas-padrão brasileiras. Ver
"Pendências".

### x. Armazenamento, retenção e descarte

| Onde | Por quanto tempo | Como sai |
|---|---|---|
| Cópia corrente | refeita toda semana; o que a CVM corrige ou retira muda na atualização semanal seguinte | a própria rodada |
| Fotos datadas | sem prazo: nunca são apagadas, porque as seguintes apontam para elas | reescrita por `repair-personal-data.R` e `repair-snapshot-digests.R`; é reescrita de arquivo público |
| Edições no Zenodo | o Zenodo guarda os itens "for the lifetime of the repository" (termos lidos em 2026-11-14) | o dono apaga o próprio registro "within 30 days after publication"; depois, só por pedido ao suporte "in duly justified cases, such as copyright infringement or exposure of personal data", e fica uma página com a citação |
| Cópias baixadas por terceiros | fora do alcance do responsável | não saem |

## g) Hipótese legal

Legítimo interesse (LGPD, art. 7º, IX), sobre dados de acesso público
(art. 7º, § 3º) usados para finalidade nova (art. 7º, § 7º); artigos
lidos em 2026-11-14. O § 4º do art. 7º não se aplica: trata de dados
tornados públicos pelo titular, e aqui quem publica é a companhia.

O teste de legítimo interesse, no modelo do Anexo II do Guia Orientativo
da ANPD (versão 1.0, fevereiro de 2024, lido em 2026-11-14), fica em
`cvmdata_lgpd_legitimo_interesse.md` e ainda é rascunho. O guia diz que
essa hipótese não vale para dado sensível; por isso o que era sensível
saiu do espelho (item f.iii), em vez de se procurar outra hipótese.

## h) Princípios da LGPD (art. 6º, lido em 2026-11-14)

| Princípio | Como o espelho responde |
|---|---|
| Finalidade | declarada no aviso de privacidade; é finalidade nova, e isso é dito |
| Adequação | só dados do formulário que servem ao estudo da governança |
| Necessidade | teste coluna a coluna: saíram CPF completo, data de nascimento, contato, biografias e as declarações dos administradores |
| Livre acesso | canal por e-mail; procedimento em `cvmdata_lgpd_pedidos_de_titular.md` |
| Qualidade | cópia fiel da CVM, refeita toda semana; correção se faz na origem |
| Transparência | aviso público (`PRIVACY.pt-BR.md`), `DATA-LICENSE.md`, este relatório |
| Segurança | guardas automáticas antes de publicar; lista de quem pediu para sair só em segredo do repositório; conferência de sha256 |
| Prevenção | regras aplicadas antes da primeira edição permanente |
| Não discriminação | o espelho não decide nada sobre pessoas; os dados de raça, gênero e deficiência ligados a pessoas ou a grupos pequenos saíram |
| Responsabilização | registro de decisão com fontes e medições; testes automáticos da regra |

## i) Riscos ao titular, j) resultado e k) medidas

Método: para cada risco, probabilidade e impacto em três níveis (baixo,
médio, alto), antes e depois das medidas; o nível do risco é o maior dos
dois. É uma avaliação do responsável, sem metodologia externa.

| # | Risco | Antes | Medida | Depois |
|---|---|---|---|---|
| 1 | Fraude de identidade com nome, CPF e data de nascimento | alto | CPF mascarado; só o ano de nascimento | baixo |
| 2 | Contato indesejado, golpe por e-mail ou telefone, visita ao endereço | alto | colunas de contato e endereço de rua de pessoa fora do espelho | baixo |
| 3 | Revelar raça, gênero ou deficiência de uma pessoa por contagem de grupo pequeno ou unânime | alto | três tabelas fora; mínimo de 10 pessoas e regra dos unânimes nas outras cinco | baixo |
| 4 | Revelar filiação sindical ou política, religião, saúde ou condenação pela biografia | alto | coluna de biografia fora do espelho | baixo; resta o texto livre não examinado (f.iii) |
| 5 | Cópia permanente que não se recolhe (Zenodo, cópias de terceiros) | alto | todas as regras valem antes da primeira edição; pedido de retirada ao Zenodo quando couber; carência de 14 dias e conferências antes de publicar | médio: o que já foi baixado não volta |
| 6 | Titular sem meio de sair | alto | todo pedido de quem comprovar ser a pessoa é atendido; a linha fica, o nome vira rótulo, os dados da pessoa ficam vazios | baixo na cópia corrente; médio nas fotos datadas e edições já publicadas, que pedem reparo caso a caso |
| 7 | Formação de perfil por terceiros: o espelho junta num só lugar o que na CVM está em muitos arquivos | médio | nenhuma técnica; aviso de privacidade e `DATA-LICENSE.md` dizem que quem reutiliza responde pelo seu tratamento | médio |
| 8 | Idoso identificado por nome, ano de nascimento e cargo | médio | o ano no lugar da data; a Receita Federal, nos dados abertos do CNPJ, usa faixa etária, que é menos fina (notas técnicas lidas em 2026-11-14) | médio; ver "Pendências" |
| 9 | Dado errado ou desatualizado sobre a pessoa | médio | cópia refeita toda semana; a correção se faz na origem | baixo na cópia corrente; as fotos datadas guardam o erro da data |
| 10 | Vazamento da lista de quem pediu para sair | médio | lista só em segredo do repositório, nunca em arquivo nem em log; o sidecar publica só a contagem | baixo; a retirada em si é visível a quem compara com a CVM |
| 11 | CPF completo em cópias antigas | alto | fotos datadas limpas em 2026-11-14; registro de teste no Zenodo sandbox e quatro CPFs no histórico do git ainda pendentes | médio até fechar as pendências |
| 12 | Arquivos guardados fora do Brasil | não avaliado | — | não avaliado; ver "Pendências" |

**Resultado.** Com as medidas, nenhum risco avaliado fica em nível alto.
Ficam em nível médio a permanência das cópias (5), o alcance da retirada
sobre o que já foi publicado (6), a formação de perfil por terceiros
(7), a idade (8) e as cópias antigas (11). O risco 12 não foi avaliado.

**O responsável conclui** que o tratamento pode prosseguir, com a
primeira edição permanente condicionada ao fechamento das pendências
abaixo.

## Pendências

1. Publicação de terça-feira, 2026-11-17: primeira prova das regras "3"
   e "4" no espelho real. Até lá elas só passaram em testes.
2. Fotos datadas: reparo depois dessa publicação.
3. Histórico do git com quatro CPFs reais e registro de teste no Zenodo
   sandbox.
4. Transferência internacional: regulamento lido; falta saber se a
   hospedagem no GitHub e no Zenodo é transferência e, se for, com que
   mecanismo (ler os contratos dos dois serviços; é a pergunta que
   mais pede advogado).
5. Classificação do GitHub e do Zenodo como operadores.
6. Texto livre fora das biografias: 78 linhas não examinadas.
7. Ano de nascimento ou faixa etária: decisão em aberto.
8. Total de titulares em todas as tabelas e anos: medir.
9. Teste de legítimo interesse: reescrever no modelo do Anexo II.
10. O mecanismo de retirada só foi provado com nomes inventados.

## l) Comentários e aprovações

| Data | Quem | O quê |
|---|---|---|
| 2026-11-14 | redação assistida (Claude) | rascunho |
| | Sidney da Silva Pereira Bissoli | leitura e aprovação pendentes |

Revisão: a cada mudança da regra de privacidade, a cada edição do
Zenodo, quando um pedido de titular mostrar risco não previsto, e quando
a ANPD publicar regulamento sobre o RIPD.

## Fontes lidas, com a data da leitura

- ANPD, "Relatório de Impacto à Proteção de Dados Pessoais (RIPD)",
  perguntas e respostas — 2026-11-14.
- Lei 13.709/2018 (LGPD), texto do Planalto: arts. 5º, 6º, 7º, 10, 11,
  18 — 2026-11-14.
- Resolução CD/ANPD nº 2/2022, texto do DOU, arts. 2º a 4º, 11 e 14 —
  2026-11-14. Alterações posteriores não conferidas.
- ANPD, Guia Orientativo "Hipóteses legais de tratamento de dados
  pessoais: legítimo interesse", versão 1.0, fevereiro de 2024 —
  2026-11-14.
- ANPD, "Estudo técnico sobre a anonimização de dados na LGPD: análise
  jurídica", versão 1.0, novembro de 2023, seções 3 e 4.4 — 2026-11-14.
- Resolução CVM 80, texto consolidado — 2026-11-14.
- Receita Federal, Notas Técnicas RFB/Cocad nº 47 e nº 86, de 2024 —
  2026-11-14.
- Resolução CD/ANPD nº 19/2024 (Regulamento de Transferência
  Internacional de Dados), texto do DOU, arts. 1º a 9º, 15 e 16 —
  2026-11-14. Retificação posterior não conferida.
- ANPD, página "Transferência Internacional de Dados" — 2026-11-14.
- LGPD, art. 33 — 2026-11-14.
- Zenodo, ajuda "Manage records", políticas gerais e termos de uso v1.3
  — 2026-11-14.
- GitHub, declaração de privacidade — 2026-11-14.

## Não lido

- Resolução CD/ANPD nº 32/2026 (adequação da União Europeia), citada
  só como a página da ANPD a cita.
- Contrato de tratamento de dados do GitHub.
- Regras do Zenodo e do CERN sobre transferência de dados.
- Resolução CD/ANPD nº 18/2024.
- LGPD, arts. 5º, VII, 38 e 55-J, no texto da lei (citados aqui só como
  a página da ANPD os cita).
