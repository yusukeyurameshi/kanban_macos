# Meu Kanban para macOS

App nativo para organizar tarefas por projetos, com arrastar-e-soltar entre **A fazer**, **Em andamento** e **Concluídas**.

## Executar

No Terminal, dentro desta pasta:

```bash
swift run MeuKanban
```

## Dados em JSON

O app grava automaticamente as alterações em `~/Library/Application Support/Meu Kanban/kanban.json`.

Use os itens **Importar Kanban JSON…** e **Exportar Kanban JSON…** no menu Arquivo para trabalhar diretamente com um arquivo JSON em qualquer pasta.

## Pacote para instalação

Para criar o pacote instalável, execute:

```bash
zsh scripts/package-macos.sh
```

O arquivo `dist/Meu-Kanban-macOS.zip` conterá o app. Extraia-o e arraste **Meu Kanban.app** para a pasta Aplicativos.

## Versionamento e atualização

O número da versão fica no arquivo `VERSION`, usando o formato `MAIOR.MENOR.CORREÇÃO` (por exemplo, `1.0.0`). O pacote de instalação usa esse número automaticamente.

Ao abrir a aplicação a partir de uma cópia Git do projeto, ela executa uma verificação silenciosa no remoto da branch atual. Quando houver commits novos, pergunta se deseja executar uma atualização segura (`git pull --ff-only`). A atualização só é oferecida quando não há alterações locais pendentes, evitando sobrescrever trabalho em andamento.
