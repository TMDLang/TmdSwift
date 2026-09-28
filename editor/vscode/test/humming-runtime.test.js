const test = require('node:test');
const assert = require('node:assert/strict');
const Module = require('node:module');

test('activated extension opens the humming webview through the real command handler', async () => {
  const registeredCommands = new Map();
  const subscriptions = [];
  const panels = [];
  const disposable = () => ({ dispose() {} });
  const generic = new Proxy(function GenericVSCodeValue() {}, {
    apply: () => generic,
    construct: () => generic,
    get: (target, property) => {
      if (property === 'dispose') return () => {};
      if (property === 'event') return generic;
      if (property === 'then') return undefined;
      if (!(property in target)) target[property] = (...args) => generic;
      return target[property];
    },
  });

  const fakeVscode = {
    EventEmitter: class {
      event = () => disposable();
      fire() {}
      dispose() {}
    },
    commands: {
      registerCommand(id, handler) { registeredCommands.set(id, handler); return disposable(); },
      executeCommand() { return Promise.resolve(); },
    },
    env: { language: 'en' },
    l10n: { t: (message) => message },
    Uri: {
      joinPath: (...parts) => parts.join('/'),
      file: (filePath) => filePath,
    },
    ViewColumn: { Beside: 2 },
    ProgressLocation: { Notification: 15 },
    DiagnosticSeverity: { Warning: 1 },
    window: {
      activeTextEditor: null,
      terminals: [],
      createWebviewPanel(viewType, title, column, options) {
        const messageHandlers = [];
        const panel = {
          viewType, title, column, options,
          webview: {
            cspSource: 'vscode-resource-test',
            asWebviewUri: (uri) => String(uri),
            onDidReceiveMessage(handler) { messageHandlers.push(handler); return disposable(); },
            get messageHandlers() { return messageHandlers; },
            html: '',
          },
          reveal() {},
          dispose() {},
          onDidDispose: () => disposable(),
        };
        panels.push(panel);
        return panel;
      },
      registerWebviewViewProvider: () => disposable(),
      registerTreeDataProvider: () => disposable(),
      onDidChangeActiveTextEditor: () => disposable(),
      onDidChangeTextEditorSelection: () => disposable(),
      onDidChangeTextEditorVisibleRanges: () => disposable(),
      onDidOpenTextDocument: () => disposable(),
      onDidSaveTextDocument: () => disposable(),
      onDidCloseTextDocument: () => disposable(),
      showErrorMessage() {},
      showInformationMessage() {},
      showWarningMessage() {},
      withProgress: async (_options, task) => task({ report() {} }, { isCancellationRequested: false }),
      createTerminal: () => generic,
    },
    workspace: {
      textDocuments: [],
      getConfiguration: () => ({ get: () => undefined }),
      onDidChangeConfiguration: () => disposable(),
      onDidChangeTextDocument: () => disposable(),
      onDidSaveTextDocument: () => disposable(),
      onDidOpenTextDocument: () => disposable(),
      onDidCloseTextDocument: () => disposable(),
      openTextDocument: async () => generic,
    },
    languages: {
      createDiagnosticCollection: () => ({ set() {}, clear() {}, dispose() {} }),
      registerCodeLensProvider: () => disposable(),
      registerCompletionItemProvider: () => disposable(),
      registerDocumentFormattingEditProvider: () => disposable(),
      registerDocumentSymbolProvider: () => disposable(),
    },
    lm: undefined,
    chat: undefined,
  };

  const originalLoad = Module._load;
  let extension;
  Module._load = function (request, parent, isMain) {
    if (request === 'vscode') return fakeVscode;
    return originalLoad.call(this, request, parent, isMain);
  };
  try {
    delete require.cache[require.resolve('../extension.js')];
    extension = require('../extension.js');
    extension.activate({
      subscriptions,
      extensionUri: '/test-extension',
      extensionPath: '/test-extension',
    });

    assert.ok(registeredCommands.has('tmd.openHummingPanel'));
    await registeredCommands.get('tmd.openHummingPanel')();

    assert.equal(panels.length, 1);
    assert.equal(panels[0].title, 'Hum to TMD');
    assert.match(panels[0].webview.html, /humming-panel\.js/);
    assert.match(panels[0].webview.html, /Basic Pitch|humming-quantizer/);
    assert.equal(panels[0].webview.messageHandlers.length, 1);
  } finally {
    extension?.deactivate();
    Module._load = originalLoad;
    delete require.cache[require.resolve('../extension.js')];
  }
});
