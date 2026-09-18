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

    // Auto-check on save / open / close / text change
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

    context.subscriptions.push(
        vscode.workspace.onDidCloseTextDocument((doc) => {
            diagnosticCollection.delete(doc.uri);
        })
    );

    // Initial check for currently active editor
    if (vscode.window.activeTextEditor && vscode.window.activeTextEditor.document.languageId === 'tmd') {
        runMeasureCheck(vscode.window.activeTextEditor.document);
    }
}

function deactivate() {}

module.exports = {
    activate,
    deactivate
};
