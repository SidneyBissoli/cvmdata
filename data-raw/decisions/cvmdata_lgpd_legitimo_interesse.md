# Teste de legítimo interesse e registro do tratamento — espelho do cvmdata

Registro de 2026-11-14, feito pelo responsável pelo espelho com apoio do
assistente. Não é parecer jurídico. Cada artigo citado foi lido no texto
da Lei 13.709/2018 (LGPD) publicado no Planalto em 2026-11-14; o que não
foi conferido está dito como tal, na última seção.

Cumpre dois deveres da lei: o registro das operações de tratamento,
"especialmente quando baseado no legítimo interesse" (art. 37), e a
transparência do tratamento baseado nele (art. 10, § 2º). O aviso
público é [`PRIVACY.pt-BR.md`](../../PRIVACY.pt-BR.md); as regras do que
o espelho retira estão em
[`cvmdata_dados_pessoais_espelho_decisao.md`](cvmdata_dados_pessoais_espelho_decisao.md).

## 1. Registro do tratamento

| Item | Conteúdo |
|---|---|
| Responsável (controlador e encarregado) | Sidney da Silva Pereira Bissoli, pessoa física, <sbissoli76@gmail.com> |
| Operação | cópia semanal dos dados abertos de companhias da CVM, conversão para Parquet, publicação aberta |
| Origem | Portal de Dados Abertos da CVM, <https://dados.cvm.gov.br/>, 9 conjuntos do grupo `companhias` |
| Titulares | administradores, conselheiros fiscais, membros de comitês, diretores de relações com investidores, responsáveis técnicos de auditoria, acionistas pessoas físicas, pessoas com relação familiar ou de subordinação declarada |
| Dados pessoais guardados | nome; CPF mascarado; ano de nascimento; cargo, órgão, mandatos, profissão; experiência profissional e declarações do formulário; participações e relações declaradas; cidade, estado e país |
| Dados sensíveis | nenhum ligado a pessoa identificável: as três tabelas de contagem de administradores saíram; as de empregados saem sem os grupos pequenos ou unânimes |
| Onde fica | GitHub Releases (cópia corrente e fotos datadas) e, a partir de 2027, Zenodo (edições trimestrais); os dois fora do Brasil |
| Acesso | público, sem cadastro |
| Duração | cópia corrente refeita toda semana; fotos datadas e edições sem prazo |
| Segurança | o dado é público por desenho; a integridade é conferida por sha256 em cada arquivo; guardas no ETL param a publicação e o depósito se algum dado retirado reaparecer |
| Base legal declarada | legítimo interesse (art. 7º, IX), sobre dado de acesso público (art. 7º, §§ 3º e 7º) |

## 2. O teste

A lei dá os elementos do teste: o interesse tem de ser legítimo e
considerado "a partir de situações concretas" (art. 10, caput); só os
dados "estritamente necessários para a finalidade pretendida" podem ser
tratados (art. 10, § 1º); o legítimo interesse não vale "no caso de
prevalecerem direitos e liberdades fundamentais do titular" (art. 7º,
IX); e o dado de acesso público deve ser tratado considerando "a
finalidade, a boa-fé e o interesse público que justificaram sua
disponibilização" (art. 7º, § 3º), com nova finalidade só se observados
"propósitos legítimos e específicos" e os direitos do titular (§ 7º).

### 2.1 Finalidade: o interesse é legítimo e concreto?

- **Interesse:** permitir pesquisa, ensino e acompanhamento público da
  governança das companhias abertas, com leitura rápida e resultado
  reproduzível (fotos datadas e edições citáveis).
- **De quem:** do responsável, que mantém o pacote, e de terceiros, os
  pesquisadores que o usam (o art. 7º, IX fala em interesse "do
  controlador ou de terceiro").
- **Situação concreta:** o portal da CVM regrava os arquivos sem guardar
  versões, o que impede refazer um resultado publicado; o espelho resolve
  isso.
- **Compatibilidade com a finalidade de origem:** a divulgação existe
  para que o mercado e o público saibam quem administra e fiscaliza as
  companhias. O espelho serve à mesma finalidade e não acrescenta outra.
  Não há uso para decisão sobre pessoas, perfil, publicidade ou venda.

### 2.2 Necessidade: só o estritamente necessário?

Aplicada campo a campo e tabela a tabela, com cada escolha registrada:

| Dado | Decisão | Por quê |
|---|---|---|
| Nome | fica | é o conteúdo da divulgação; sem ele a finalidade se perde |
| CPF | mascarado | a máscara com o nome ainda segue a pessoa entre tabelas (medido); o número completo não é necessário |
| Data de nascimento | só o ano | a pesquisa usa idade; a data completa confirma identidade em bancos |
| Biografia e declarações | ficam, sem CPF | são o conteúdo exigido pelo formulário |
| E-mail, telefone, fax | saem todos | a pesquisa não usa; o campo da empresa traz endereço de pessoa |
| Endereço de rua de pessoa | sai | a pesquisa não usa; cidade e estado bastam |
| Contagens de administradores por órgão | saem | com os nomes ao lado, a contagem revela a declaração de cada pessoa |
| Contagens de empregados | ficam sem grupo pequeno ou unânime | agregado que não se reverte não é dado pessoal (art. 12) |

### 2.3 Balanceamento: os direitos do titular prevalecem?

**A favor do tratamento:**

- o dado já é público, publicado por dever legal, e continua disponível
  na origem com mais detalhe do que no espelho;
- as pessoas exercem função de administração ou fiscalização de
  companhia aberta, sobre a qual a lei quer publicidade;
- a expectativa razoável de quem assina um formulário de divulgação
  pública é que ele seja lido e estudado;
- não há decisão automatizada, perfil nem contato com o titular.

**Contra, e o que foi feito a respeito:**

| Risco para o titular | Salvaguarda |
|---|---|
| fraude com CPF e data de nascimento | não são guardados |
| contato indesejado | e-mail, telefone e endereço não são guardados |
| revelação de dado sensível | tabelas e grupos que o revelariam não são guardados |
| permanência: a foto datada e a edição guardam o que a CVM depois corrigir ou retirar | aviso público, canal de contato, procedimento para pedidos; compromisso de pedir a retirada ao Zenodo quando o pedido proceder |
| informação desabonadora antiga nas biografias (declarações de condenação) | sem salvaguarda específica hoje; ver pontos abertos |

**Conclusão do responsável:** com as salvaguardas acima, o interesse não
é superado pelos direitos dos titulares. A conclusão é revista quando
mudar o que o espelho guarda, a cada edição depositada, e sempre que um
pedido de titular mostrar um risco não previsto.

## 3. Transparência e direitos

- Aviso público nas duas línguas, na raiz do repositório e dentro de
  cada edição do Zenodo, com a identificação e o contato do responsável
  (art. 9º, III e IV) e a menção explícita aos direitos do art. 18
  (art. 9º, VII).
- Procedimento para pedidos:
  [`cvmdata_lgpd_pedidos_de_titular.md`](cvmdata_lgpd_pedidos_de_titular.md).

## 4. Pontos abertos, para decisão do responsável ou consulta a advogado

Nada abaixo sustenta a conclusão do teste; são as dúvidas que ele deixa.

1. **Agente de pequeno porte.** A Resolução CD/ANPD nº 2/2022 (lida no
   texto do DOU de 28/01/2022; alterações posteriores não conferidas)
   inclui pessoas naturais entre os agentes de pequeno porte (art. 2º, I)
   e os dispensa de indicar encarregado, exigindo um canal de comunicação
   (art. 11). Ela exclui quem faz tratamento de alto risco (art. 3º, I),
   que soma um critério geral, como "larga escala", a um específico, como
   o uso de dados "de idosos" (art. 4º). O espelho tem milhares de
   titulares e muitos têm mais de 60 anos. Por isso o aviso não se apoia
   na dispensa: indica encarregado e usa os prazos normais.
2. **Transferência internacional.** GitHub e Zenodo guardam os arquivos
   fora do Brasil. O art. 33 lista as hipóteses em que a transferência
   internacional é permitida; qual delas se aplica à publicação aberta de
   dado já público não foi analisada.
3. **Supressão por pessoa.** O ETL não tem hoje como retirar uma pessoa
   específica do espelho. O procedimento diz o que fazer enquanto isso
   não existir.
4. **Fotos datadas ainda sem as regras de 14/11.** Dependem do reparo,
   que reescreve arquivos públicos sem volta.
5. **Histórico do git** com 4 CPFs reais numa fixture antiga, e o
   depósito de ensaio no sandbox do Zenodo com 1 CPF completo.
6. **Declarações de condenação nas biografias**, que a foto datada e a
   edição guardam mesmo depois de a pessoa deixar o cargo.
7. **Não lidos:** o guia da ANPD sobre legítimo interesse, decisões de
   tribunais sobre republicação de dado público, e a Resolução CVM que
   rege os formulários.
