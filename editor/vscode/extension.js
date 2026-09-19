const vscode = require('vscode');
const { execFile } = require('child_process');
const path = require('path');
const fs = require('fs');
const os = require('os');

/**
 * Get configured or discovered path to tmd binary.
 */
function getTmdExecutable() {
    const config = vscode.workspace.getConfiguration('tmd');
    const customPath = config.get('executablePath');
    if (customPath && customPath.trim().length > 0) {
        return customPath.trim();
    }
    return 'tmd';
}

/**
 * Get active editor's file path, ensuring it is a .tmd file.
 */
function getActiveTmdFilePath() {
    const editor = vscode.window.activeTextEditor;
    if (!editor) {
        vscode.window.showErrorMessage('No active editor found. Please open a .tmd file.');
        return null;
    }
    const doc = editor.document;
    if (doc.isUntitled) {
        vscode.window.showErrorMessage('Please save the file before exporting.');
        return null;
    }
    const ext = path.extname(doc.fileName).toLowerCase();
    if (doc.languageId !== 'tmd' && ext !== '.tmd') {
        vscode.window.showErrorMessage('TMD export commands can only be used on .tmd files.');
        return null;
    }
    return doc.fileName;
}

/**
 * Runs a tmd command with arguments.
 */
function runTmdExport(args, successMessage, outputFilePath) {
    const tmdBin = getTmdExecutable();
    const activeDoc = vscode.window.activeTextEditor?.document;

    // Save document if dirty before running export
    const savePromise = (activeDoc && activeDoc.isDirty) ? activeDoc.save() : Promise.resolve(true);

    savePromise.then(() => {
        vscode.window.withProgress({
            location: vscode.ProgressLocation.Notification,
            title: 'TMD: Exporting...',
            cancellable: false
        }, () => {
            return new Promise((resolve) => {
                execFile(tmdBin, args, (error, stdout, stderr) => {
                    if (error) {
                        const errMsg = (stderr && stderr.trim().length > 0) ? stderr.trim() : error.message;
                        vscode.window.showErrorMessage(`TMD Export Failed: ${errMsg}`);
                        resolve();
                        return;
                    }

                    if (outputFilePath && fs.existsSync(outputFilePath)) {
                        vscode.window.showInformationMessage(successMessage, 'Reveal in Finder', 'Open')
                            .then(selection => {
                                if (selection === 'Reveal in Finder') {
                                    vscode.commands.executeCommand('revealFileInOS', vscode.Uri.file(outputFilePath));
                                } else if (selection === 'Open') {
                                    vscode.commands.executeCommand('vscode.open', vscode.Uri.file(outputFilePath));
                                }
                            });
                    } else {
                        vscode.window.showInformationMessage(successMessage);
                    }
                    resolve();
                });
            });
        });
    });
}

function activate(context) {
    // 1. Export to MIDI (.mid)
    context.subscriptions.push(vscode.commands.registerCommand('tmd.exportMIDI', () => {
        const filePath = getActiveTmdFilePath();
        if (!filePath) return;
        const outputPath = filePath.replace(/\.[^/.]+$/, '') + '.mid';
        runTmdExport([filePath, '-m', outputPath], `Exported to MIDI: ${path.basename(outputPath)}`, outputPath);
    }));

    // 2. Export to MusicXML (.musicxml)
    context.subscriptions.push(vscode.commands.registerCommand('tmd.exportMusicXML', () => {
        const filePath = getActiveTmdFilePath();
        if (!filePath) return;
        const outputPath = filePath.replace(/\.[^/.]+$/, '') + '.musicxml';
        runTmdExport([filePath, '-x', outputPath], `Exported to MusicXML: ${path.basename(outputPath)}`, outputPath);
    }));

    // 3. Export to ABC (.abc)
    context.subscriptions.push(vscode.commands.registerCommand('tmd.exportABC', () => {
        const filePath = getActiveTmdFilePath();
        if (!filePath) return;
        const outputPath = filePath.replace(/\.[^/.]+$/, '') + '.abc';
        runTmdExport([filePath, '-a', outputPath], `Exported to ABC notation: ${path.basename(outputPath)}`, outputPath);
    }));

    // 4. Export to LilyPond (.ly)
    context.subscriptions.push(vscode.commands.registerCommand('tmd.exportLilyPond', () => {
        const filePath = getActiveTmdFilePath();
        if (!filePath) return;
        const outputPath = filePath.replace(/\.[^/.]+$/, '') + '.ly';
        runTmdExport([filePath, '-l', outputPath], `Exported to LilyPond: ${path.basename(outputPath)}`, outputPath);
    }));

    // 5. Render to PDF via LilyPond (.pdf)
    context.subscriptions.push(vscode.commands.registerCommand('tmd.renderPDF', () => {
        const filePath = getActiveTmdFilePath();
        if (!filePath) return;
        const outputPath = filePath.replace(/\.[^/.]+$/, '') + '.pdf';
        runTmdExport([filePath, '--pdf-output', outputPath], `Rendered to PDF: ${path.basename(outputPath)}`, outputPath);
    }));

    // 6. Render to WAV Audio (.wav)
    context.subscriptions.push(vscode.commands.registerCommand('tmd.renderWAV', () => {
        const filePath = getActiveTmdFilePath();
        if (!filePath) return;
        const outputPath = filePath.replace(/\.[^/.]+$/, '') + '.wav';
        runTmdExport([filePath, '-w', outputPath], `Rendered to WAV Audio: ${path.basename(outputPath)}`, outputPath);
    }));

    // 6.1. Export to VOCALOID3/4 (.vsqx)
    context.subscriptions.push(vscode.commands.registerCommand('tmd.exportVSQX', () => {
        const filePath = getActiveTmdFilePath();
        if (!filePath) return;
        const outputPath = filePath.replace(/\.[^/.]+$/, '') + '.vsqx';
        runTmdExport([filePath, '--vsqx-output', outputPath], `Exported to VOCALOID3/4: ${path.basename(outputPath)}`, outputPath);
    }));

    // 6.2. Export to VOCALOID2 (.vsq)
    context.subscriptions.push(vscode.commands.registerCommand('tmd.exportVSQ', () => {
        const filePath = getActiveTmdFilePath();
        if (!filePath) return;
        const outputPath = filePath.replace(/\.[^/.]+$/, '') + '.vsq';
        runTmdExport([filePath, '--vsq-output', outputPath], `Exported to VOCALOID2: ${path.basename(outputPath)}`, outputPath);
    }));

    // 6.3. Export to UTAU (.ust)
    context.subscriptions.push(vscode.commands.registerCommand('tmd.exportUST', () => {
        const filePath = getActiveTmdFilePath();
        if (!filePath) return;
        const outputPath = filePath.replace(/\.[^/.]+$/, '') + '.ust';
        runTmdExport([filePath, '--ust-output', outputPath], `Exported to UTAU: ${path.basename(outputPath)}`, outputPath);
    }));

    // Webview MIDI Player Panel tracking
    let currentMidiPanel = null;

    function getMidiWebviewContent(webview, extensionUri) {
        const jzzUri = webview.asWebviewUri(vscode.Uri.joinPath(extensionUri, 'media', 'JZZ.js'));
        const jzzSmfUri = webview.asWebviewUri(vscode.Uri.joinPath(extensionUri, 'media', 'JZZ.midi.SMF.js'));
        const jzzTinyUri = webview.asWebviewUri(vscode.Uri.joinPath(extensionUri, 'media', 'JZZ.synth.Tiny.js'));
        const soundfontUri = webview.asWebviewUri(vscode.Uri.joinPath(extensionUri, 'media', 'soundfont-player.min.js'));
        const playerJsUri = webview.asWebviewUri(vscode.Uri.joinPath(extensionUri, 'media', 'player.js'));
        const playerCssUri = webview.asWebviewUri(vscode.Uri.joinPath(extensionUri, 'media', 'player.css'));

        return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>TMD MIDI Player</title>
  <link rel="stylesheet" href="${playerCssUri}">
</head>
<body>
  <div class="player-container">
    <div class="player-header">
      <div id="player-icon" class="player-icon">🎵</div>
      <div class="player-header-info">
        <div id="score-title" class="score-title">TMD Web MIDI Player</div>
        <div id="score-subtitle" class="score-subtitle">Loading...</div>
      </div>
    </div>

    <!-- Progress Timeline -->
    <div class="progress-section">
      <div class="slider-container">
        <input type="range" id="timeline-slider" class="timeline-slider" min="0" max="100" value="0" step="0.1" />
      </div>
      <div class="time-row">
        <span id="current-time">00:00</span>
        <span id="total-time">00:00</span>
      </div>
    </div>

    <!-- Controls -->
    <div class="controls-section">
      <div class="playback-buttons">
        <button id="btn-play-pause" class="btn-ctrl btn-main" title="Play">▶</button>
        <button id="btn-stop" class="btn-ctrl" title="Stop">⏹</button>
      </div>

      <div class="synth-selector-group">
        <span class="synth-label">Synth:</span>
        <select id="synth-select" class="synth-select">
          <option value="piano">🎹 Grand Piano (FluidR3)</option>
          <option value="tiny">⚡ Tiny Synth (Chiptune)</option>
          <option value="webmidi">🎛 System MIDI Out</option>
        </select>
      </div>
    </div>

    <div id="status-text" class="status-bar">Ready</div>
  </div>

  <script src="${jzzUri}"></script>
  <script src="${jzzSmfUri}"></script>
  <script src="${jzzTinyUri}"></script>
  <script src="${soundfontUri}"></script>
  <script src="${playerJsUri}"></script>
</body>
</html>`;
    }

    function playMidiWithFilter(options = {}) {
        const filePath = getActiveTmdFilePath();
        if (!filePath) return;

        const activeDoc = vscode.window.activeTextEditor?.document;
        const savePromise = (activeDoc && activeDoc.isDirty) ? activeDoc.save() : Promise.resolve(true);

        savePromise.then(() => {
            const column = vscode.ViewColumn.Beside;
            if (currentMidiPanel) {
                currentMidiPanel.reveal(column);
            } else {
                currentMidiPanel = vscode.window.createWebviewPanel(
                    'tmdMidiPlayer',
                    'TMD MIDI Player',
                    column,
                    {
                        enableScripts: true,
                        retainContextWhenHidden: true,
                        localResourceRoots: [vscode.Uri.joinPath(context.extensionUri, 'media')]
                    }
                );

                currentMidiPanel.iconPath = vscode.Uri.joinPath(context.extensionUri, 'media', 'player.svg');
                currentMidiPanel.webview.html = getMidiWebviewContent(currentMidiPanel.webview, context.extensionUri);

                currentMidiPanel.onDidDispose(() => {
                    currentMidiPanel = null;
                }, null, context.subscriptions);
            }

            // Export to temporary MIDI and send base64 to webview
            const tmdBin = getTmdExecutable();
            const tempMidiPath = path.join(os.tmpdir(), `tmd_preview_${Date.now()}.mid`);

            const args = [filePath, '-m', tempMidiPath];
            if (options.section) {
                args.push('--section', options.section);
            }
            if (options.instrument) {
                args.push('--instrument', options.instrument);
            }

            execFile(tmdBin, args, (error, stdout, stderr) => {
                if (error) {
                    const errMsg = (stderr && stderr.trim().length > 0) ? stderr.trim() : error.message;
                    vscode.window.showErrorMessage(`Failed to export MIDI for player: ${errMsg}`);
                    return;
                }

                try {
                    const midiBuffer = fs.readFileSync(tempMidiPath);
                    const base64Midi = midiBuffer.toString('base64');
                    try { fs.unlinkSync(tempMidiPath); } catch (_) {}

                    const scoreBaseName = path.basename(filePath);

                    // Extract score name from file header if available
                    let displayTitle = scoreBaseName;
                    if (activeDoc) {
                        const match = activeDoc.getText().match(/^\s*name\s*:\s*(.+)$/m);
                        if (match) {
                            displayTitle = match[1].trim();
                        }
                    }

                    if (options.section && options.instrument) {
                        displayTitle += ` [${options.section}:${options.instrument}]`;
                    } else if (options.section) {
                        displayTitle += ` [Section: ${options.section}]`;
                    } else if (options.instrument) {
                        displayTitle += ` [Track: ${options.instrument}]`;
                    }

                    currentMidiPanel.webview.postMessage({
                        command: 'loadMidi',
                        title: displayTitle,
                        sourceFile: scoreBaseName,
                        base64: base64Midi,
                        autoPlay: true
                    });
                } catch (readErr) {
                    vscode.window.showErrorMessage(`Failed to read MIDI preview data: ${readErr.message}`);
                }
            });
        });
    }

    // 6.5. Open Web MIDI Player
    context.subscriptions.push(vscode.commands.registerCommand('tmd.openMidiPlayer', () => {
        playMidiWithFilter();
    }));

    // 7. Play Audio in Terminal Preview
    context.subscriptions.push(vscode.commands.registerCommand('tmd.playAudio', () => {
        const filePath = getActiveTmdFilePath();
        if (!filePath) return;
        const tmdBin = getTmdExecutable();
        const termName = 'TMD Audio Playback';
        let term = vscode.window.terminals.find(t => t.name === termName);
        if (!term) {
            term = vscode.window.createTerminal(termName);
        }
        term.show();
        term.sendText(`"${tmdBin}" "${filePath}" -p`);
    }));

    // 8. Install AI Skills
    context.subscriptions.push(vscode.commands.registerCommand('tmd.installSkills', () => {
        const tmdBin = getTmdExecutable();
        vscode.window.withProgress({
            location: vscode.ProgressLocation.Notification,
            title: 'TMD: Installing AI Agent Skills...',
            cancellable: false
        }, () => {
            return new Promise((resolve) => {
                execFile(tmdBin, ['--install-skills'], (error, stdout, stderr) => {
                    if (error) {
                        const errMsg = (stderr && stderr.trim().length > 0) ? stderr.trim() : error.message;
                        vscode.window.showErrorMessage(`Failed to install skills: ${errMsg}`);
                    } else {
                        vscode.window.showInformationMessage('Successfully installed TMD AI Skills for Codex, Claude, Antigravity, and Gemini.');
                    }
                    resolve();
                });
            });
        });
    }));

    // Diagnostic collection for measure consistency
    const diagnosticCollection = vscode.languages.createDiagnosticCollection('tmd');
    context.subscriptions.push(diagnosticCollection);

    function runMeasureCheck(document, showNotification = false) {
        if (!document || document.languageId !== 'tmd') {
            return;
        }

        const tmdBin = getTmdExecutable();
        let targetFilePath = document.fileName;
        let isTempFile = false;

        // If document is dirty or untitled, write buffer to a temporary file
        if (document.isDirty || document.isUntitled) {
            const tempDir = os.tmpdir();
            targetFilePath = path.join(tempDir, `tmd_check_${Date.now()}_${path.basename(document.fileName || 'untitled.tmd')}`);
            try {
                fs.writeFileSync(targetFilePath, document.getText(), 'utf8');
                isTempFile = true;
            } catch (err) {
                console.error('Failed to write temporary file for measure check:', err);
                return;
            }
        }

        execFile(tmdBin, ['check', targetFilePath], (error, stdout, stderr) => {
            if (isTempFile) {
                try {
                    fs.unlinkSync(targetFilePath);
                } catch (e) {}
            }

            const output = (stdout || '') + '\n' + (stderr || '');
            const diagnostics = [];

            if (!error && output.includes('✅ All measures')) {
                diagnosticCollection.set(document.uri, []);
                if (showNotification) {
                    vscode.window.showInformationMessage('TMD: All measures conform to expected time signatures.');
                }
                return;
            }

            // Regex parsing TMDMeasureIssue format:
            // Format 1 (Measure issue): verse:Piano (line 10, measure 2): Expected 4 units (4/4 at <4*>), found 3 units (-1 units)
            // Format 2 (Section length mismatch): verse:Bass (line 45): Expected 4 measures (16.0 beats based on Piano...), found 2 measures (-2 measures)
            const issueRegex = /([^\n()]+?)\s*\(line\s+(\d+)(?:,\s*measure\s+(\d+))?\):\s*([^\n]+)/g;
            let match;

            while ((match = issueRegex.exec(output)) !== null) {
                const prefix = match[1].trim();
                const lineNum = Math.max(0, parseInt(match[2], 10) - 1);
                const measureNum = match[3];
                const detail = match[4].trim();

                const message = measureNum
                    ? `${prefix} (measure ${measureNum}): ${detail}`
                    : `${prefix}: ${detail}`;

                let lineRange;
                if (lineNum < document.lineCount) {
                    const lineText = document.lineAt(lineNum).text;
                    const firstNonWhitespace = lineText.search(/\S/);
                    const startCol = firstNonWhitespace >= 0 ? firstNonWhitespace : 0;
                    lineRange = new vscode.Range(lineNum, startCol, lineNum, lineText.length);
                } else {
                    lineRange = new vscode.Range(lineNum, 0, lineNum, 0);
                }

                const diagnostic = new vscode.Diagnostic(
                    lineRange,
                    message,
                    vscode.DiagnosticSeverity.Warning
                );
                diagnostic.source = 'tmd';
                diagnostics.push(diagnostic);
            }

            diagnosticCollection.set(document.uri, diagnostics);

            if (showNotification) {
                if (diagnostics.length > 0) {
                    vscode.window.showWarningMessage(`TMD: Found ${diagnostics.length} measure discrepancy issue(s). Check the Problems panel for details.`);
                } else if (error) {
                    const errMsg = (stderr && stderr.trim().length > 0) ? stderr.trim() : (stdout || error.message);
                    vscode.window.showErrorMessage(`TMD Check Error: ${errMsg}`);
                }
            }
        });
    }

    // Command: Check Measure Consistency
    context.subscriptions.push(vscode.commands.registerCommand('tmd.checkMeasures', () => {
        const editor = vscode.window.activeTextEditor;
        if (!editor) {
            vscode.window.showErrorMessage('No active editor found. Please open a .tmd file.');
            return;
        }
        runMeasureCheck(editor.document, true);
    }));

    // Command: Format Document
    context.subscriptions.push(vscode.commands.registerCommand('tmd.formatDocument', () => {
        return vscode.commands.executeCommand('editor.action.formatDocument');
    }));

    // Helper: Execute in-place TMD refactoring and replace document buffer
    function runTmdRefactor(args, description) {
        const editor = vscode.window.activeTextEditor;
        if (!editor || (editor.document.languageId !== 'tmd' && !editor.document.fileName.endsWith('.tmd'))) {
            vscode.window.showErrorMessage('TMD refactoring commands require an active .tmd file.');
            return;
        }

        const tmdBin = getTmdExecutable();
        const document = editor.document;
        const tempDir = os.tmpdir();
        const tempFilePath = path.join(tempDir, `tmd_refactor_${Date.now()}_${path.basename(document.fileName || 'untitled.tmd')}`);

        try {
            fs.writeFileSync(tempFilePath, document.getText(), 'utf8');
        } catch (err) {
            vscode.window.showErrorMessage(`TMD refactor failed to prepare file: ${err.message}`);
            return;
        }

        vscode.window.withProgress({
            location: vscode.ProgressLocation.Notification,
            title: `TMD: ${description}...`,
            cancellable: false
        }, () => {
            return new Promise((resolve) => {
                const fullArgs = ['refactor', ...args, tempFilePath];
                execFile(tmdBin, fullArgs, (error, stdout, stderr) => {
                    try { fs.unlinkSync(tempFilePath); } catch (e) {}

                    if (error) {
                        const errMsg = (stderr && stderr.trim().length > 0) ? stderr.trim() : (stdout || error.message);
                        vscode.window.showErrorMessage(`TMD Refactor Error: ${errMsg}`);
                        resolve();
                        return;
                    }

                    if (!stdout || stdout.trim().length === 0) {
                        vscode.window.showWarningMessage('TMD Refactor produced empty output.');
                        resolve();
                        return;
                    }

                    const fullRange = new vscode.Range(
                        document.positionAt(0),
                        document.positionAt(document.getText().length)
                    );

                    editor.edit(editBuilder => {
                        editBuilder.replace(fullRange, stdout);
                    }).then(success => {
                        if (success) {
                            vscode.window.showInformationMessage(`TMD: ${description} completed successfully.`);
                            runMeasureCheck(document);
                        }
                        resolve();
                    });
                });
            });
        });
    }

    /**
     * Detects the section and instrument name at the active editor's cursor position.
     */
    function detectContextAtCursor() {
        const editor = vscode.window.activeTextEditor;
        if (!editor) return { section: undefined, instrument: undefined };

        const document = editor.document;
        const currentLine = editor.selection.active.line;

        // Scan upwards from current line to find the enclosing paragraph header
        for (let i = currentLine; i >= 0; i--) {
            const line = document.lineAt(i).text.trim();
            const match = line.match(/^([a-zA-Z0-9_\u4e00-\u9fa5-]+)\s*:\s*([a-zA-Z0-9_\u4e00-\u9fa5-]+)(@[^{]*)?\s*\{/);
            if (match) {
                return { section: match[1], instrument: match[2] };
            }
            // If we hit a closing brace before a header going upwards, we might be outside
            // but check if there is an outer paragraph
        }
        return { section: undefined, instrument: undefined };
    }

    /**
     * Helper to prompt user whether to apply refactor globally or to current section.
     */
    async function promptScopeChoice(detectedContext, actionName) {
        if (!detectedContext.section) {
            return { section: undefined };
        }

        const choice = await vscode.window.showQuickPick([
            {
                label: `Current Section only (${detectedContext.section})`,
                description: `Apply ${actionName} only to section '${detectedContext.section}'`,
                section: detectedContext.section
            },
            {
                label: 'Entire Score (All Sections)',
                description: `Apply ${actionName} across all sections in the score`,
                section: undefined
            }
        ], {
            placeHolder: `Select the target scope for ${actionName}`
        });

        if (!choice) return null; // user cancelled
        return { section: choice.section };
    }

    // 1. Refactor: Double Grid
    context.subscriptions.push(vscode.commands.registerCommand('tmd.refactorDoubleGrid', async () => {
        const context = detectContextAtCursor();
        const scope = await promptScopeChoice(context, 'Double Grid');
        if (!scope) return;

        const args = ['double-grid'];
        if (scope.section) {
            args.push('--section', scope.section);
        }
        runTmdRefactor(args, scope.section ? `Double Grid (${scope.section})` : 'Double Grid Resolution');
    }));

    // 2. Refactor: Halve Grid
    context.subscriptions.push(vscode.commands.registerCommand('tmd.refactorHalveGrid', async () => {
        const context = detectContextAtCursor();
        const scope = await promptScopeChoice(context, 'Halve Grid');
        if (!scope) return;

        const args = ['halve-grid'];
        if (scope.section) {
            args.push('--section', scope.section);
        }
        runTmdRefactor(args, scope.section ? `Halve Grid (${scope.section})` : 'Halve Grid Resolution');
    }));

    // 3. Refactor: Duplicate Track
    context.subscriptions.push(vscode.commands.registerCommand('tmd.refactorDuplicateTrack', async () => {
        const cursorContext = detectContextAtCursor();

        const sourceInst = await vscode.window.showInputBox({
            prompt: 'Enter source instrument name to duplicate (e.g. Lead, Piano)',
            value: cursorContext.instrument || '',
            validateInput: v => v && v.trim().length > 0 ? null : 'Source instrument name is required'
        });
        if (!sourceInst) return;

        const targetInst = await vscode.window.showInputBox({
            prompt: 'Enter new target instrument name (e.g. Synth, Lead2)',
            validateInput: v => v && v.trim().length > 0 ? null : 'Target instrument name is required'
        });
        if (!targetInst) return;

        const octaveStr = await vscode.window.showInputBox({
            prompt: 'Octave shift (e.g. 0, +1, -1)',
            value: '0'
        });
        if (octaveStr === undefined) return;

        let targetSection = cursorContext.section;
        if (cursorContext.section) {
            const scope = await promptScopeChoice(cursorContext, 'Duplicate Track');
            if (!scope) return;
            targetSection = scope.section;
        } else {
            const secInput = await vscode.window.showInputBox({
                prompt: 'Optional section filter (leave blank for all sections)'
            });
            targetSection = secInput && secInput.trim().length > 0 ? secInput.trim() : undefined;
        }

        const args = ['duplicate-track', '--source', sourceInst.trim(), '--target', targetInst.trim()];
        const oct = parseInt(octaveStr, 10);
        if (!isNaN(oct) && oct !== 0) {
            args.push('--octave', String(oct));
        }
        if (targetSection) {
            args.push('--section', targetSection);
        }

        runTmdRefactor(args, `Duplicate Track ${sourceInst} -> ${targetInst}`);
    }));

    // 4. Refactor: Generate Harmony
    context.subscriptions.push(vscode.commands.registerCommand('tmd.refactorGenerateHarmony', async () => {
        const cursorContext = detectContextAtCursor();

        const sourceInst = await vscode.window.showInputBox({
            prompt: 'Enter melody source instrument name (e.g. Vocal)',
            value: cursorContext.instrument || '',
            validateInput: v => v && v.trim().length > 0 ? null : 'Source instrument name is required'
        });
        if (!sourceInst) return;

        const targetInst = await vscode.window.showInputBox({
            prompt: 'Enter harmony instrument name (e.g. Harmony)',
            value: 'Harmony',
            validateInput: v => v && v.trim().length > 0 ? null : 'Harmony instrument name is required'
        });
        if (!targetInst) return;

        const intervalStr = await vscode.window.showInputBox({
            prompt: 'Interval steps: +2 for parallel 3rd up, -2 for 3rd down, +4 for 5th up',
            value: '2'
        });
        if (intervalStr === undefined) return;

        let targetSection = cursorContext.section;
        if (cursorContext.section) {
            const scope = await promptScopeChoice(cursorContext, 'Generate Harmony');
            if (!scope) return;
            targetSection = scope.section;
        } else {
            const secInput = await vscode.window.showInputBox({
                prompt: 'Optional section filter (leave blank for all sections)'
            });
            targetSection = secInput && secInput.trim().length > 0 ? secInput.trim() : undefined;
        }

        const args = ['generate-harmony', '--source', sourceInst.trim(), '--target', targetInst.trim()];
        const interval = parseInt(intervalStr, 10);
        if (!isNaN(interval)) {
            args.push('--interval', String(interval));
        }
        if (targetSection) {
            args.push('--section', targetSection);
        }

        runTmdRefactor(args, `Generate Harmony for ${sourceInst}`);
    }));

    // 5. Refactor: Inline Orders
    context.subscriptions.push(vscode.commands.registerCommand('tmd.refactorInlineOrders', async () => {
        const confirm = await vscode.window.showWarningMessage(
            'Unroll and unroll orders into a single linear score sequence? This will flatten playback orders.',
            { modal: true },
            'Unroll Orders'
        );
        if (confirm === 'Unroll Orders') {
            runTmdRefactor(['inline-orders'], 'Inline Playback Orders');
        }
    }));

    // 6. Refactor: Rename Instrument
    context.subscriptions.push(vscode.commands.registerCommand('tmd.refactorRenameInstrument', async () => {
        const fromInst = await vscode.window.showInputBox({
            prompt: 'Existing instrument name to rename (e.g. Piano)',
            validateInput: v => v && v.trim().length > 0 ? null : 'Existing instrument name is required'
        });
        if (!fromInst) return;

        const toInst = await vscode.window.showInputBox({
            prompt: `Rename '${fromInst}' to:`,
            validateInput: v => v && v.trim().length > 0 ? null : 'New instrument name is required'
        });
        if (!toInst) return;

        runTmdRefactor(['rename-instrument', '--from', fromInst.trim(), '--to', toInst.trim()], `Rename Instrument ${fromInst} -> ${toInst}`);
    }));

    // 7. Refactor: Rename Section
    context.subscriptions.push(vscode.commands.registerCommand('tmd.refactorRenameSection', async () => {
        const fromSec = await vscode.window.showInputBox({
            prompt: 'Existing section name to rename (e.g. verse, intro)',
            validateInput: v => v && v.trim().length > 0 ? null : 'Existing section name is required'
        });
        if (!fromSec) return;

        const toSec = await vscode.window.showInputBox({
            prompt: `Rename section '${fromSec}' to:`,
            validateInput: v => v && v.trim().length > 0 ? null : 'New section name is required'
        });
        if (!toSec) return;

        runTmdRefactor(['rename-section', '--from', fromSec.trim(), '--to', toSec.trim()], `Rename Section ${fromSec} -> ${toSec}`);
    }));

    // 8. Refactor: Extract Instrument
    context.subscriptions.push(vscode.commands.registerCommand('tmd.refactorExtractInstrument', async () => {
        const inst = await vscode.window.showInputBox({
            prompt: 'Instrument name to extract into a separate TMD document (e.g. Vocal, Bass)',
            validateInput: v => v && v.trim().length > 0 ? null : 'Instrument name is required'
        });
        if (!inst) return;

        const editor = vscode.window.activeTextEditor;
        if (!editor) return;
        const defaultOut = editor.document.fileName.replace(/\.tmd$/i, '') + `_${inst.trim()}.tmd`;
        const uri = await vscode.window.showSaveDialog({
            defaultUri: vscode.Uri.file(defaultOut),
            filters: { 'TMD Music Score': ['tmd'] }
        });
        if (!uri) return;

        const tmdBin = getTmdExecutable();
        const document = editor.document;
        const tempDir = os.tmpdir();
        const tempFilePath = path.join(tempDir, `tmd_extract_${Date.now()}_${path.basename(document.fileName || 'untitled.tmd')}`);
        try {
            fs.writeFileSync(tempFilePath, document.getText(), 'utf8');
        } catch (err) {
            vscode.window.showErrorMessage(`Failed to prepare file: ${err.message}`);
            return;
        }

        execFile(tmdBin, ['refactor', 'extract-instrument', tempFilePath, '--instrument', inst.trim(), '-o', uri.fsPath], (error, stdout, stderr) => {
            try { fs.unlinkSync(tempFilePath); } catch (e) {}
            if (error) {
                const errMsg = (stderr && stderr.trim().length > 0) ? stderr.trim() : error.message;
                vscode.window.showErrorMessage(`Extract Instrument Failed: ${errMsg}`);
                return;
            }

            vscode.window.showInformationMessage(`Extracted instrument '${inst.trim()}' to ${path.basename(uri.fsPath)}`, 'Open')
                .then(selection => {
                    if (selection === 'Open') {
                        vscode.commands.executeCommand('vscode.open', uri);
                    }
                });
        });
    }));

    // Document Formatting Provider
    context.subscriptions.push(
        vscode.languages.registerDocumentFormattingEditProvider('tmd', {
            provideDocumentFormattingEdits(document) {
                return new Promise((resolve) => {
                    const tmdBin = getTmdExecutable();
                    const tempDir = os.tmpdir();
                    const tempFilePath = path.join(tempDir, `tmd_format_${Date.now()}_${path.basename(document.fileName || 'untitled.tmd')}`);

                    try {
                        fs.writeFileSync(tempFilePath, document.getText(), 'utf8');
                    } catch (err) {
                        vscode.window.showErrorMessage(`TMD Format failed to create temp file: ${err.message}`);
                        resolve([]);
                        return;
                    }

                    execFile(tmdBin, ['format', tempFilePath], (error, stdout, stderr) => {
                        try {
                            fs.unlinkSync(tempFilePath);
                        } catch (e) {}

                        if (error) {
                            const errMsg = (stderr && stderr.trim().length > 0) ? stderr.trim() : error.message;
                            vscode.window.showErrorMessage(`TMD Format failed: ${errMsg}`);
                            resolve([]);
                            return;
                        }

                        if (!stdout || stdout.trim().length === 0) {
                            resolve([]);
                            return;
                        }

                        const fullRange = new vscode.Range(
                            document.positionAt(0),
                            document.positionAt(document.getText().length)
                        );
                        resolve([vscode.TextEdit.replace(fullRange, stdout)]);
                    });
                });
            }
        })
    );

    // Document Symbol (Outline) Provider
    context.subscriptions.push(
        vscode.languages.registerDocumentSymbolProvider('tmd', {
            provideDocumentSymbols(document, token) {
                return new Promise((resolve) => {
                    const tmdBin = getTmdExecutable();
                    let tempFilePath = null;
                    let targetPath = document.fileName;

                    if (document.isDirty || document.isUntitled) {
                        const tempDir = os.tmpdir();
                        tempFilePath = path.join(tempDir, `tmd_outline_${Date.now()}_${path.basename(document.fileName || 'untitled.tmd')}`);
                        try {
                            fs.writeFileSync(tempFilePath, document.getText(), 'utf8');
                            targetPath = tempFilePath;
                        } catch (err) {
                            resolve([]);
                            return;
                        }
                    }

                    execFile(tmdBin, ['outline', '--json', targetPath], (error, stdout, stderr) => {
                        if (tempFilePath) {
                            try { fs.unlinkSync(tempFilePath); } catch (e) {}
                        }

                        if (error || !stdout || stdout.trim().length === 0) {
                            resolve([]);
                            return;
                        }

                        try {
                            const rawNodes = JSON.parse(stdout);

                            function mapKind(kindStr) {
                                switch (kindStr) {
                                    case 'file': return vscode.SymbolKind.File;
                                    case 'class': return vscode.SymbolKind.Class;
                                    case 'namespace': return vscode.SymbolKind.Namespace;
                                    case 'field': return vscode.SymbolKind.Field;
                                    case 'method': return vscode.SymbolKind.Method;
                                    case 'event': return vscode.SymbolKind.Event;
                                    case 'string': return vscode.SymbolKind.String;
                                    case 'number': return vscode.SymbolKind.Number;
                                    default: return vscode.SymbolKind.Object;
                                }
                            }

                            function toSymbolRange(r) {
                                const startLine = Math.max(0, (r.startLine || 1) - 1);
                                const startCol = Math.max(0, (r.startColumn || 1) - 1);
                                const endLine = Math.max(startLine, (r.endLine || 1) - 1);
                                const endCol = Math.max(0, (r.endColumn || 1) - 1);
                                return new vscode.Range(startLine, startCol, endLine, endCol);
                            }

                            function convertNode(node) {
                                const range = toSymbolRange(node.range);
                                const selRange = node.selectionRange ? toSymbolRange(node.selectionRange) : range;
                                const symbol = new vscode.DocumentSymbol(
                                    node.name,
                                    node.detail || '',
                                    mapKind(node.kind),
                                    range,
                                    selRange
                                );
                                if (Array.isArray(node.children) && node.children.length > 0) {
                                    symbol.children = node.children.map(convertNode);
                                }
                                return symbol;
                            }

                            const symbols = rawNodes.map(convertNode);
                            resolve(symbols);
                        } catch (parseErr) {
                            resolve([]);
                        }
                    });
                });
            }
        })
    );

    // Auto-check on save / open / close / text change / active editor change
    context.subscriptions.push(
        vscode.workspace.onDidOpenTextDocument((doc) => {
            if (doc.languageId === 'tmd') {
                runMeasureCheck(doc);
            }
        })
    );

    context.subscriptions.push(
        vscode.workspace.onDidSaveTextDocument((doc) => {
            if (doc.languageId === 'tmd') {
                const config = vscode.workspace.getConfiguration('tmd');
                if (config.get('checkOnSave') !== false) {
                    runMeasureCheck(doc);
                }
            }
        })
    );

    // Debounced check while typing
    let changeDebounceTimer = null;
    context.subscriptions.push(
        vscode.workspace.onDidChangeTextDocument((event) => {
            const doc = event.document;
            if (doc.languageId === 'tmd') {
                const config = vscode.workspace.getConfiguration('tmd');
                if (config.get('checkOnChange') !== false) {
                    if (changeDebounceTimer) {
                        clearTimeout(changeDebounceTimer);
                    }
                    changeDebounceTimer = setTimeout(() => {
                        runMeasureCheck(doc);
                    }, 400);
                }
            }
        })
    );

    context.subscriptions.push(
        vscode.window.onDidChangeActiveTextEditor((editor) => {
            if (editor && editor.document.languageId === 'tmd') {
                runMeasureCheck(editor.document);
            }
        })
    );

    context.subscriptions.push(
        vscode.workspace.onDidCloseTextDocument((doc) => {
            diagnosticCollection.delete(doc.uri);
        })
    );

    // Outline & Play Commands
    context.subscriptions.push(vscode.commands.registerCommand('tmd.playSection', (nodeOrArg) => {
        let section = null;
        if (typeof nodeOrArg === 'string') {
            section = nodeOrArg;
        } else if (nodeOrArg && nodeOrArg.sectionName) {
            section = nodeOrArg.sectionName;
        }
        if (section) {
            playMidiWithFilter({ section });
        } else {
            vscode.window.showWarningMessage('No section specified to play.');
        }
    }));

    context.subscriptions.push(vscode.commands.registerCommand('tmd.playTrack', (nodeOrArg) => {
        let section = null;
        let instrument = null;
        if (nodeOrArg && typeof nodeOrArg === 'object') {
            section = nodeOrArg.sectionName;
            instrument = nodeOrArg.instrument;
        }
        if (section && instrument) {
            playMidiWithFilter({ section, instrument });
        } else if (instrument) {
            playMidiWithFilter({ instrument });
        } else {
            vscode.window.showWarningMessage('No track/instrument specified to play.');
        }
    }));

    // Play Section / Track at current cursor position
    function getCursorContext() {
        const editor = vscode.window.activeTextEditor;
        if (!editor || editor.document.languageId !== 'tmd') return null;
        const lineIndex = editor.selection.active.line;
        const doc = editor.document;

        // Search backward from cursor line to find enclosing paragraph header
        const headerRegex = /^\s*([a-zA-Z0-9_-]+)\s*:\s*([a-zA-Z0-9_\-+]+)\s*@/i;
        for (let l = lineIndex; l >= 0; l--) {
            const text = doc.lineAt(l).text;
            const match = text.match(headerRegex);
            if (match) {
                return { section: match[1], instrument: match[2] };
            }
        }
        return null;
    }

    context.subscriptions.push(vscode.commands.registerCommand('tmd.playCurrentSection', () => {
        const ctx = getCursorContext();
        if (ctx && ctx.section) {
            playMidiWithFilter({ section: ctx.section });
        } else {
            vscode.window.showInformationMessage('Cursor is not inside any recognizable TMD section.');
        }
    }));

    context.subscriptions.push(vscode.commands.registerCommand('tmd.playCurrentTrack', () => {
        const ctx = getCursorContext();
        if (ctx && ctx.section && ctx.instrument) {
            playMidiWithFilter({ section: ctx.section, instrument: ctx.instrument });
        } else {
            vscode.window.showInformationMessage('Cursor is not inside any recognizable TMD track.');
        }
    }));

    // CodeLens Provider: Add [▶ Play Section] and [▶ Play Track] above each track block
    context.subscriptions.push(
        vscode.languages.registerCodeLensProvider('tmd', {
            provideCodeLenses(document, token) {
                const lenses = [];
                const headerRegex = /^\s*([a-zA-Z0-9_-]+)\s*:\s*([a-zA-Z0-9_\-+]+)\s*@/i;
                const lineCount = document.lineCount;

                for (let i = 0; i < lineCount; i++) {
                    const line = document.lineAt(i);
                    const match = line.text.match(headerRegex);
                    if (match) {
                        const sectionName = match[1];
                        const instrument = match[2];
                        const range = new vscode.Range(i, 0, i, line.text.length);

                        lenses.push(new vscode.CodeLens(range, {
                            title: `▶ Play Section (${sectionName})`,
                            command: 'tmd.playSection',
                            arguments: [sectionName]
                        }));

                        lenses.push(new vscode.CodeLens(range, {
                            title: `▶ Play Track (${instrument})`,
                            command: 'tmd.playTrack',
                            arguments: [{ sectionName, instrument }]
                        }));
                    }
                }
                return lenses;
            }
        })
    );

    // Custom TreeDataProvider for TMD Outline in Explorer Sidebar
    class TMDOutlineTreeDataProvider {
        constructor() {
            this._onDidChangeTreeData = new vscode.EventEmitter();
            this.onDidChangeTreeData = this._onDidChangeTreeData.event;
        }

        refresh() {
            this._onDidChangeTreeData.fire();
        }

        getTreeItem(element) {
            return element;
        }

        async getChildren(element) {
            const editor = vscode.window.activeTextEditor;
            if (!editor || editor.document.languageId !== 'tmd') {
                return [];
            }
            const doc = editor.document;

            if (!element) {
                // Root items: fetch outline JSON from CLI
                const rawNodes = await new Promise((resolve) => {
                    const tmdBin = getTmdExecutable();
                    let tempFilePath = null;
                    let targetPath = doc.fileName;

                    if (doc.isDirty || doc.isUntitled) {
                        const tempDir = os.tmpdir();
                        tempFilePath = path.join(tempDir, `tmd_tree_${Date.now()}_${path.basename(doc.fileName || 'untitled.tmd')}`);
                        try {
                            fs.writeFileSync(tempFilePath, doc.getText(), 'utf8');
                            targetPath = tempFilePath;
                        } catch (err) {
                            resolve([]);
                            return;
                        }
                    }

                    execFile(tmdBin, ['outline', '--json', targetPath], (error, stdout) => {
                        if (tempFilePath) {
                            try { fs.unlinkSync(tempFilePath); } catch (e) {}
                        }
                        if (error || !stdout) {
                            resolve([]);
                            return;
                        }
                        try {
                            resolve(JSON.parse(stdout));
                        } catch (_) {
                            resolve([]);
                        }
                    });
                });

                return rawNodes.map(node => this.buildTreeItem(node, null));
            } else if (element.rawNode && element.rawNode.children) {
                return element.rawNode.children.map(child => this.buildTreeItem(child, element));
            }
            return [];
        }

        buildTreeItem(node, parentItem) {
            const hasChildren = Array.isArray(node.children) && node.children.length > 0;
            const collapsibleState = hasChildren
                ? vscode.TreeItemCollapsibleState.Expanded
                : vscode.TreeItemCollapsibleState.None;

            const item = new vscode.TreeItem(node.name, collapsibleState);
            item.description = node.detail || '';
            item.rawNode = node;

            if (node.range) {
                const line = Math.max(0, (node.range.startLine || 1) - 1);
                const col = Math.max(0, (node.range.startColumn || 1) - 1);
                item.command = {
                    command: 'vscode.open',
                    title: 'Jump to Symbol',
                    arguments: [
                        vscode.window.activeTextEditor.document.uri,
                        { selection: new vscode.Range(line, col, line, col) }
                    ]
                };
            }

            // Identify section and track nodes to attach contextValue for inline play buttons
            if (parentItem && parentItem.label === 'Sections') {
                // This is a section node (e.g. "intro", "verse")
                item.contextValue = 'sectionNode';
                item.sectionName = node.name;
                item.iconPath = new vscode.ThemeIcon('symbol-namespace');
            } else if (parentItem && parentItem.contextValue === 'sectionNode') {
                // This is a track node within a section
                item.contextValue = 'trackNode';
                item.sectionName = parentItem.sectionName;
                item.instrument = node.name;
                item.iconPath = new vscode.ThemeIcon('symbol-field');
            } else if (node.name.startsWith('Score:')) {
                item.iconPath = new vscode.ThemeIcon('file-submodule');
            } else if (node.name === 'Sections') {
                item.iconPath = new vscode.ThemeIcon('list-tree');
            } else if (node.name === 'Orders') {
                item.iconPath = new vscode.ThemeIcon('git-commit');
            } else {
                item.iconPath = new vscode.ThemeIcon('symbol-event');
            }

            return item;
        }
    }

    const outlineTreeProvider = new TMDOutlineTreeDataProvider();
    context.subscriptions.push(
        vscode.window.registerTreeDataProvider('tmdOutlineView', outlineTreeProvider)
    );

    context.subscriptions.push(vscode.commands.registerCommand('tmd.refreshOutline', () => {
        outlineTreeProvider.refresh();
    }));

    // Update context when active editor changes
    function updateActiveDocContext(editor) {
        const isTmd = editor && editor.document.languageId === 'tmd';
        vscode.commands.executeCommand('setContext', 'tmdHasActiveDocument', !!isTmd);
        if (isTmd) {
            outlineTreeProvider.refresh();
        }
    }

    // Helper functions for Language Model Tools & Chat Participant
    function runTmdCheckBuffer(text) {
        return new Promise((resolve) => {
            const tmdBin = getTmdExecutable();
            const tempDir = os.tmpdir();
            const tempFilePath = path.join(tempDir, `tmd_chat_check_${Date.now()}.tmd`);

            try {
                fs.writeFileSync(tempFilePath, text, 'utf8');
            } catch (err) {
                resolve({ success: false, error: err.message, output: '' });
                return;
            }

            execFile(tmdBin, ['check', tempFilePath], (error, stdout, stderr) => {
                try { fs.unlinkSync(tempFilePath); } catch (_) {}
                const output = ((stdout || '') + '\n' + (stderr || '')).trim();
                const isClean = !error && output.includes('✅ All measures');
                resolve({
                    success: isClean,
                    output: output,
                    error: error ? (stderr || error.message) : undefined
                });
            });
        });
    }

    function runTmdFormatBuffer(text) {
        return new Promise((resolve) => {
            const tmdBin = getTmdExecutable();
            const tempDir = os.tmpdir();
            const tempFilePath = path.join(tempDir, `tmd_chat_format_${Date.now()}.tmd`);

            try {
                fs.writeFileSync(tempFilePath, text, 'utf8');
            } catch (err) {
                resolve({ success: false, error: err.message, formattedText: text });
                return;
            }

            execFile(tmdBin, ['format', tempFilePath], (error, stdout, stderr) => {
                try { fs.unlinkSync(tempFilePath); } catch (_) {}
                if (error || !stdout || stdout.trim().length === 0) {
                    resolve({ success: false, error: (stderr || error?.message || 'Format failed'), formattedText: text });
                } else {
                    resolve({ success: true, formattedText: stdout });
                }
            });
        });
    }

    function getTmdSpecificationText() {
        try {
            const skillPath = path.join(context.extensionPath, 'skill.md');
            if (fs.existsSync(skillPath)) {
                return fs.readFileSync(skillPath, 'utf8');
            }
        } catch (_) {}
        return `TMD (Timebase Mark Down) Musical Notation DSL:
- Root marker: ::SCORE::
- Header: ** Title **, != 120 (BPM), ?= C (Key), <4/4> (Meter)
- Paragraphs: section:instrument@|offset|{ <subdivision*> units... }
- Jianpu scale degrees: 1 to 7. Accidentals: ' (sharp), , (flat). Octaves: ^ (up), _ (down).
- Rest: 0. Tie/sustain: -. Chords: [Cmaj7], [1], [6m].
- Tuplets: (1 2 3)%(--). Directives: {!=140}, {?+2}.
- Playback order: -> intro -> verse ->#`;
    }

    // 1. Register VS Code Language Model Tools (if API is available)
    if (vscode.lm && typeof vscode.lm.registerTool === 'function') {
        // Tool: tmd_check
        context.subscriptions.push(
            vscode.lm.registerTool('tmd_check', {
                async invoke(options, token) {
                    const input = options.input || {};
                    let scoreText = input.text;
                    if (!scoreText && input.filePath && fs.existsSync(input.filePath)) {
                        scoreText = fs.readFileSync(input.filePath, 'utf8');
                    }
                    if (!scoreText) {
                        const editor = vscode.window.activeTextEditor;
                        if (editor && editor.document.languageId === 'tmd') {
                            scoreText = editor.document.getText();
                        }
                    }

                    if (!scoreText) {
                        return new vscode.LanguageModelToolResult([
                            new vscode.LanguageModelTextPart('Error: No TMD score text provided or active TMD document found.')
                        ]);
                    }

                    const result = await runTmdCheckBuffer(scoreText);
                    return new vscode.LanguageModelToolResult([
                        new vscode.LanguageModelTextPart(result.output || (result.success ? '✅ All measures conform to expected time signatures.' : 'Discrepancy detected.'))
                    ]);
                }
            })
        );

        // Tool: tmd_format
        context.subscriptions.push(
            vscode.lm.registerTool('tmd_format', {
                async invoke(options, token) {
                    const input = options.input || {};
                    const scoreText = input.text || '';
                    const result = await runTmdFormatBuffer(scoreText);
                    return new vscode.LanguageModelToolResult([
                        new vscode.LanguageModelTextPart(result.formattedText)
                    ]);
                }
            })
        );

        // Tool: tmd_get_specification
        context.subscriptions.push(
            vscode.lm.registerTool('tmd_get_specification', {
                async invoke(options, token) {
                    const spec = getTmdSpecificationText();
                    return new vscode.LanguageModelToolResult([
                        new vscode.LanguageModelTextPart(spec)
                    ]);
                }
            })
        );
    }

    // 2. Register GitHub Copilot Chat Participant @tmd (if API is available)
    if (vscode.chat && typeof vscode.chat.createChatParticipant === 'function') {
        const participant = vscode.chat.createChatParticipant('tmd', async (request, chatContext, stream, token) => {
            const spec = getTmdSpecificationText();
            const activeEditor = vscode.window.activeTextEditor;
            const activeCode = (activeEditor && activeEditor.document.languageId === 'tmd')
                ? activeEditor.document.getText()
                : '';

            if (request.command === 'check') {
                stream.progress('Checking TMD measure consistency and syntax...');
                const textToCheck = request.prompt.trim().length > 0 ? request.prompt : activeCode;
                if (!textToCheck) {
                    stream.markdown('Please open a `.tmd` file or provide TMD score text to check.');
                    return;
                }
                const result = await runTmdCheckBuffer(textToCheck);
                stream.markdown('### TMD Measure Consistency Inspection\n\n');
                if (result.success) {
                    stream.markdown('✅ **All measures conform to time signatures with no discrepancies.**\n');
                } else {
                    stream.markdown('⚠️ **Issues detected:**\n\n```text\n' + result.output + '\n```\n');
                    stream.markdown('\n*Tip: Use `@tmd /fix` to automatically repair measure beat counts.*');
                }
                return;
            }

            if (request.command === 'fix') {
                stream.progress('Analyzing and repairing measure beat discrepancies...');
                const textToFix = request.prompt.trim().length > 0 ? request.prompt : activeCode;
                const checkRes = await runTmdCheckBuffer(textToFix);

                const messages = [
                    vscode.LanguageModelChatMessage.User(
                        `You are an expert TMD notation arranger and music theorist.
TMD Specification:
${spec}

Diagnose and repair the following TMD score. Make sure all measures strictly match their time signature beat counts. Add or remove units, ties (-), or rests (0) where necessary. Output the repaired TMD code inside a \`\`\`tmd code block:

${textToFix}

Compiler diagnostics:
${checkRes.output}`
                    )
                ];

                const [model] = await vscode.lm.selectChatModels({ family: 'gpt-4o' });
                if (model) {
                    const response = await model.sendRequest(messages, {}, token);
                    for await (const fragment of response.text) {
                        stream.markdown(fragment);
                    }
                } else {
                    stream.markdown('No language model available to repair score. Diagnostic report:\n\n' + checkRes.output);
                }
                return;
            }

            if (request.command === 'compose') {
                stream.progress('Composing TMD musical score...');
                const messages = [
                    vscode.LanguageModelChatMessage.User(
                        `You are an expert composer proficient in TMD (Timebase Mark Down) musical notation.
Follow these composition rules:
1. Always start with ::SCORE::, title, != tempo, ?= key, and <meter>.
2. Group tracks modularly (e.g. verse:Piano@|0|{ ... }, verse:CHORD@|0|{ ... }, verse:Bass@|0|{ ... }).
3. In numbered musical notation: 1=Do, 2=Re, 3=Mi, 4=Fa, 5=Sol, 6=La, 7=Ti. Accidentals BEFORE octave (e.g. 1'^, 7,_).
4. Strict measure math: In <4*> and <4/4>, every bar |...| must have exactly 4 beats.
5. End with execution flow -> ... ->#.

TMD Reference:
${spec}

User Request:
${request.prompt}

Active document context (if relevant):
${activeCode ? '```tmd\n' + activeCode + '\n```' : 'None'}`
                    )
                ];

                const [model] = await vscode.lm.selectChatModels({ family: 'gpt-4o' });
                if (model) {
                    const response = await model.sendRequest(messages, {}, token);
                    for await (const fragment of response.text) {
                        stream.markdown(fragment);
                    }
                } else {
                    stream.markdown('Unable to connect to Copilot Language Model.');
                }
                return;
            }

            if (request.command === 'explain') {
                stream.progress('Analyzing TMD score and musical theory...');
                const textToExplain = request.prompt.trim().length > 0 ? request.prompt : activeCode;
                const messages = [
                    vscode.LanguageModelChatMessage.User(
                        `You are an expert music theorist and TMD notation specialist.
Explain the structure, melody, chord progression, harmonic functions, and rhythmic devices in the following score:

${textToExplain}`
                    )
                ];

                const [model] = await vscode.lm.selectChatModels({ family: 'gpt-4o' });
                if (model) {
                    const response = await model.sendRequest(messages, {}, token);
                    for await (const fragment of response.text) {
                        stream.markdown(fragment);
                    }
                } else {
                    stream.markdown('Unable to connect to Copilot Language Model.');
                }
                return;
            }

            // Default general conversation
            stream.progress('Thinking...');
            const messages = [
                vscode.LanguageModelChatMessage.User(
                    `You are the official TMD (Timebase Mark Down) AI assistant, in memory of composer Chen, Chih-Han / aguai (阿怪, 1974–2019).
You help musicians write, analyze, format, and debug TMD music scores.
TMD Specification:
${spec}

Active score in editor (if any):
${activeCode ? '```tmd\n' + activeCode + '\n```' : 'No active .tmd score'}

User Question:
${request.prompt}`
                )
            ];

            const [model] = await vscode.lm.selectChatModels({ family: 'gpt-4o' });
            if (model) {
                const response = await model.sendRequest(messages, {}, token);
                for await (const fragment of response.text) {
                    stream.markdown(fragment);
                }
            } else {
                stream.markdown(`### TMD (Timebase Mark Down) Assistant
I am ready to help you compose, check, or format TMD music scores!
- Use \`@tmd /check\` to inspect measure lengths and beat consistency.
- Use \`@tmd /compose\` to generate arrangements and melodies.
- Use \`@tmd /fix\` to repair measure discrepancies.
- Use \`@tmd /explain\` to analyze chord progressions and song structure.`);
            }
        });

        participant.iconPath = vscode.Uri.joinPath(context.extensionUri, 'media', 'player.svg');
        context.subscriptions.push(participant);
    }
}

function deactivate() {}

module.exports = {
    activate,
    deactivate
};
