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
    if (ext !== '.tmd') {
        vscode.window.showWarningMessage('The active file does not appear to be a .tmd file.');
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
            // verse:Piano (line 10, measure 2): Expected 4 units (4/4 at <4*>), found 3 units (-1 units)
            const issueRegex = /([^\n()]+?)\s*\(line\s+(\d+),\s*measure\s+(\d+)\):\s*([^\n]+)/g;
            let match;

            while ((match = issueRegex.exec(output)) !== null) {
                const prefix = match[1].trim();
                const lineNum = Math.max(0, parseInt(match[2], 10) - 1);
                const measureNum = match[3];
                const detail = match[4].trim();

                const message = `${prefix} (measure ${measureNum}): ${detail}`;

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
