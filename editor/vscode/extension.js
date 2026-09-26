const vscode = require('vscode');
const { execFile, spawn, execFileSync } = require('child_process');
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
    const candidates = [
        '/usr/local/bin/tmd',
        '/opt/homebrew/bin/tmd',
        path.join(os.homedir(), '.local/bin/tmd')
    ];
    for (const c of candidates) {
        if (fs.existsSync(c)) return c;
    }
    return 'tmd';
}

/**
 * Generate client-side localization script for Webviews
 */
function getWebviewL10nScript() {
    const keys = [
        "TMD Score", "Song Inspector", "Valid Score", "Ready", "Error", "Refresh",
        "Duration", "Movable-do base", "Tempo", "Arrangement Density",
        "Peak concurrency (avg {0})", "Quarter note beat", "Meter <{0}>",
        "Major", "Minor", "Modal", "Insufficient evidence", "Inferred Tonality", "Playback Context", "Best Fit Tonalities (K-S)",
        "bars", "tracks", "notes", "notes total",
        "Pitch Range & Tessitura Analysis", "Analyzing track notes...",
        "No notes detected.", "No data for selected track.",
        "Pitch Range", "Pitch Span", "octaves", "semitones",
        "Difficulty: {0}", "Center Tessitura", "Average pitch",
        "Recommended Voice Classification", "Based on pitch range",
        "Harmonic Vocabulary & Modulations", "Distinct Chords",
        "Key Modulations", "None", "Structure & Conductor Timeline",
        "Tonality & Key Profile Analysis", "Analyzing tonality profile...",
        "Inferred Tonality", "Diatonic Purity", "Correlation: {0}", "Diatonic / Chromatic",
        "Best Fit Tonalities (K-S)", "Playback Context", "Circle of Fifths Trajectory",
        "12-Tone Pitch Class Weight Distribution", "Music Producer Diagnosis",
        "Musical Character & Mood", "Modulation Journey", "Inferred Modulations",
        "Detailed Theoretical Analysis", "No tonality data available",
        "Clean major tonality", "Contemporary major tonality",
        "Click to search {0} in score",
        "Easy", "Moderate", "Challenging", "Difficult",
        "High", "Ambiguous",
        "Soprano", "Mezzo-Soprano", "Contralto", "Tenor", "Baritone", "Bass",
        "Section {0}", "Piano", "Key: {0}", "Audition", "Audition note",
        "Insert", "Insert TMD note at cursor", "Octave down", "Octave up",
        "TMD Web MIDI Player", "Loading...", "Play", "Pause", "Stop", "Synth:",
        "General MIDI (FluidR3 Multi-Track)", "Grand Piano (FluidR3)",
        "Tiny Synth (Chiptune)", "System MIDI Out"
    ];
    const dict = {};
    for (const k of keys) {
        dict[k] = vscode.l10n.t(k);
    }
    return `<script>
  window.__TMD_L10N__ = ${JSON.stringify(dict)};
  window.__tmd_t = function(key, ...args) {
    var str = (window.__TMD_L10N__ && window.__TMD_L10N__[key]) || key;
    for (var i = 0; i < args.length; i++) {
      str = str.replace('{' + i + '}', args[i]);
    }
    return str;
  };
</script>`;
}

function getTmdInspectLocale() {
    const language = (vscode.env.language || 'en').toLowerCase();
    return language.startsWith('zh') ? 'zh-Hant' : 'en';
}

/**
 * Get active editor's file path, ensuring it is a .tmd file.
 */
function getActiveTmdFilePath() {
    const editor = vscode.window.activeTextEditor;
    if (!editor) {
        vscode.window.showErrorMessage(vscode.l10n.t('No active editor found. Please open a .tmd file.'));
        return null;
    }
    const doc = editor.document;
    if (doc.isUntitled) {
        vscode.window.showErrorMessage(vscode.l10n.t('Please save the file before exporting.'));
        return null;
    }
    const ext = path.extname(doc.fileName).toLowerCase();
    if (doc.languageId !== 'tmd' && ext !== '.tmd') {
        vscode.window.showErrorMessage(vscode.l10n.t('TMD export commands can only be used on .tmd files.'));
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
            title: vscode.l10n.t('TMD: Exporting...'),
            cancellable: false
        }, () => {
            return new Promise((resolve) => {
                execFile(tmdBin, args, (error, stdout, stderr) => {
                    if (error) {
                        const errMsg = (stderr && stderr.trim().length > 0) ? stderr.trim() : error.message;
                        vscode.window.showErrorMessage(vscode.l10n.t('TMD Export Failed: {0}', errMsg));
                        resolve();
                        return;
                    }

                    if (outputFilePath && fs.existsSync(outputFilePath)) {
                        const revealBtn = vscode.l10n.t('Reveal in Finder');
                        const openBtn = vscode.l10n.t('Open');
                        vscode.window.showInformationMessage(successMessage, revealBtn, openBtn)
                            .then(selection => {
                                if (selection === revealBtn) {
                                    vscode.commands.executeCommand('revealFileInOS', vscode.Uri.file(outputFilePath));
                                } else if (selection === openBtn) {
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

const TMD_TEMPLATES = [
    {
        id: 'starter',
        label: '$(sparkle) Starter Tutorial (Twinkle Twinkle / 小星星入門範本)',
        description: 'Lead melody, piano chords, bass, and educational comments',
        detail: 'Best for beginners learning TMD syntax, chord symbols, and multi-track structure.',
        defaultFilename: 'starter.tmd',
        content: `::SCORE::
** 小星星 (Twinkle Twinkle) **
!= 100
?= C
<4/4>

/*
 TMD (Timebase Mark Down) 入門範本：
 - 音符：1 2 3 4 5 6 7 (Do Re Mi Fa Sol La Si)
 - 高低八度：1^ (高音), 1_ (低音)
 - 升降記號：1' (升), 7, (降)
 - 延音線：-
 - 休止符：. 或 0
 - 和弦標記：[1], [4], [5] 或 [C], [F], [G]
 - 段落格式：段落名:樂器名@|小節偏移|{ <時值網格*> ... }
*/

A:Lead@|0|{
    <4*>
    | 1 1 5 5 | 6 6 5 - |
    | 4 4 3 3 | 2 2 1 - |
}

A:Piano@|0|{
    <2*>
    | [1] [1] | [4] [1] |
    | [4] [1] | [5] [1] |
}

A:Bass@|0|{
    <4*>
    | 1_ - 1_ - | 4__ - 1_ - |
    | 4__ - 1_ - | 5__ - 1_ - |
}

B:Lead@|0|{
    <4*>
    | 5 5 4 4 | 3 3 2 - |
    | 5 5 4 4 | 3 3 2 - |
}

B:Piano@|0|{
    <2*>
    | [1] [4] | [1] [5] |
    | [1] [4] | [1] [5] |
}

B:Bass@|0|{
    <4*>
    | 1_ - 4__ - | 1_ - 5__ - |
    | 1_ - 4__ - | 1_ - 5__ - |
}

/* 播放順序：A 段 -> B 段 -> A 段結尾 */
-> A -> B -> A ->#
`
    },
    {
        id: 'blank',
        label: '$(file-code) Minimal Blank Score (空白標準樂譜骨架)',
        description: 'Standard boilerplate with score header and piano track',
        detail: '::SCORE::, title, tempo, key, 4/4 beat, and intro track.',
        defaultFilename: 'song.tmd',
        content: `::SCORE::
** Untitled Song **
!= 120
?= C
<4/4>

intro:Piano@|0|{
    <4*>
    | 1 2 3 4 |
}

-> intro ->#
`
    },
    {
        id: 'leadsheet',
        label: '$(music) Pop Lead Sheet (流行歌主旋律與和弦)',
        description: 'Verse, Chorus, Bridge song form with Lead vocal and Chord tracks',
        detail: 'Standard commercial pop structure ready for songwriting and harmonization.',
        defaultFilename: 'leadsheet.tmd',
        content: `::SCORE::
** Pop Lead Sheet **
!= 128
?= C
<4/4>

/* Intro */
intro:Chord@|0|{
    <2*>
    | [1] [5] | [6m] [4] |
    | [1] [5] | [4]  [1] |
}

intro:Lead@|0|{
    <4*>
    | . . . . | . . . . |
    | 1 2 3 5 | 6 5 3 1 |
}

/* Verse */
verse:Chord@|0|{
    <2*>
    | [1] [5] | [6m] [4] |
    | [1] [5] | [4]  [1] |
}

verse:Lead@|0|{
    <4*>
    | 1 2 3 1 | 5 5 3 - |
    | 6 6 5 3 | 2 - - - |
    | 1 2 3 1 | 5 5 3 - |
    | 4 3 2 5 | 1 - - - |
}

/* Chorus */
chorus:Chord@|0|{
    <2*>
    | [4] [5] | [3m] [6m] |
    | [2m] [5] | [1]  [1]  |
}

chorus:Lead@|0|{
    <4*>
    | 6 6 7 1^ | 7 5 3 - |
    | 4 4 3 2  | 5 - - - |
    | 6 6 7 1^ | 7 5 3 - |
    | 4 3 2 5  | 1 - - - |
}

-> intro -> verse -> chorus ->#
`
    },
    {
        id: 'band',
        label: '$(organization) Pop/Rock Band (樂團多軌編制：人聲、鍵盤、吉他、貝斯、鼓組)',
        description: 'Multi-instrument arrangement with Vocal, Keyboard, Guitar, Bass, and Drums',
        detail: 'Complete rhythm section with drum grooves, bass lines, and chord comping.',
        defaultFilename: 'band_arrangement.tmd',
        content: `::SCORE::
** Band Arrangement **
!= 120
?= C
<4/4>

/* Verse Section */
verse:Vocal@|0|{
    <4*>
    | 1 2 3 5 | 6 5 3 - |
    | 4 4 3 3 | 2 - - - |
    | 1 2 3 5 | 6 5 3 - |
    | 4 3 2 5 | 1 - - - |
}

verse:Keyboard@|0|{
    <2*>
    | [C] [G] | [Am] [F] |
    | [C] [G] | [F]  [C] |
    | [C] [G] | [Am] [F] |
    | [F] [G] | [C]  [C] |
}

verse:Guitar@|0|{
    <4*>
    | [C] - [C] - | [G] - [G] - |
    | [Am] - [Am] - | [F] - [F] - |
    | [C] - [C] - | [G] - [G] - |
    | [F] - [G] - | [C] - - - |
}

verse:Bass@|0|{
    <4*>
    | 1_ - 1_ - | 5__ - 5__ - |
    | 6__ - 6__ - | 4__ - 4__ - |
    | 1_ - 1_ - | 5__ - 5__ - |
    | 4__ - 5__ - | 1_ - - - |
}

verse:Drums@|0|{
    <8*>
    | X-X-X-X- | X-X-X-X- |
    | X-X-X-X- | X-X-X-X- |
    | X-X-X-X- | X-X-X-X- |
    | X-X-X-X- | S-S-C--- |
}

-> verse ->#
`
    },
    {
        id: 'canon',
        label: '$(repo-forked) Polyphonic Canon (對位法與卡農範本)',
        description: 'Two-part canon with staggered measure entry offsets (@|+2|)',
        detail: 'Demonstrates contrapuntal imitation, measure offsets, and basso continuo.',
        defaultFilename: 'canon.tmd',
        content: `::SCORE::
** Canon in C **
!= 108
?= C
<4/4>

/*
 卡農特色：
 第一聲部 (Voice1) 在第 0 小節進入，
 第二聲部 (Voice2) 帶有偏移量 @|+2| (延遲 2 小節進入)，完全模仿第一聲部的旋律。
*/

theme:Voice1@|0|{
    <4*>
    | 1 2 3 1 | 1 2 3 1 |
    | 3 4 5 - | 3 4 5 - |
}

theme:Voice2@|+2|{
    <4*>
    | 1 2 3 1 | 1 2 3 1 |
    | 3 4 5 - | 3 4 5 - |
}

theme:Cello@|0|{
    <2*>
    | [1] [5] | [6m] [3m] |
    | [4] [1] | [4]  [5]  |
    | [1] [5] | [6m] [3m] |
}

-> theme ->#
`
    },
    {
        id: 'drums',
        label: '$(symbol-event) Drum & Percussion Grooves (打擊樂與節奏律動)',
        description: '8-beat & 16-beat drum patterns (Hi-Hat, Snare, Kick, Toms, Crash)',
        detail: 'Demonstrates drum notation symbols (X, S, B, T, C, O) and syncopated grooves.',
        defaultFilename: 'drums.tmd',
        content: `::SCORE::
** Drum Grooves **
!= 120
?= C
<4/4>

/*
 打擊樂代號：
 X/x: Hi-Hat (腳踏鈸)
 S/s: Snare (小鼓)
 B/b/D/d: Bass Drum (大鼓/底鼓)
 T/t: Tom (中鼓)
 C/c: Crash (碎音鈸)
 O/o: Open Hi-Hat (開鈸)
*/

beat:Drums@|0|{
    <8*>
    /* Measure 1: Rock 8-beat groove */
    | X-X-X-X- |
    /* Measure 2: Kick and snare groove */
    | B-S-B-S- |
    /* Measure 3: Syncopated kick */
    | B--BS-B- |
    /* Measure 4: Snare roll and crash */
    | SSSSC--- |
}

beat:Percussion@|0|{
    <8*>
    | X-X-X-X- |
    | X-X-X-X- |
    | X-X-X-X- |
    | X-X-X--- |
}

-> beat ->#
`
    },
    {
        id: 'program',
        label: '$(book) Show-Program & Lyrics (配詞與節目導演腳本)',
        description: 'Score with lyrics, credits (詞/曲/編), and triple-quoted show-program """ block',
        detail: 'For theater, stage shows, musical plays, and songs with spoken directions.',
        defaultFilename: 'show_program.tmd',
        content: `::SCORE::
** 月光小夜曲 **
!= 96
?= G
<4/4>
~ "詞：阿怪"
~ "曲：阿怪"
~ "編：TMD"

/*
 [Program / Stage Direction]
 Scene: A quiet night under the pale moonlight.
 Lead vocal enters gently with acoustic nylon guitar.
*/

verse:Vocal@|0|{
    <4*>
    | 5_ 1 2 3 | 2 1 2 - |
    | 3 5 6 5 | 3 - - - |
    | 6 1^ 6 5 | 3 2 1 - |
    | 2 3 2 1_ | 1 - - - |
}

verse:Guitar@|0|{
    <2*>
    | [1] [5] | [6m] [3m] |
    | [4] [1] | [2m] [5]  |
    | [4] [5] | [3m] [6m] |
    | [2m] [5] | [1]  [1]  |
}

verse:Bass@|0|{
    <4*>
    | 1_ - 5__ - | 6__ - 3__ - |
    | 4__ - 1_ - | 2__ - 5__ - |
    | 4__ - 5__ - | 3__ - 6__ - |
    | 2__ - 5__ - | 1_ - - - |
}

-> verse ->#
`
    }
];

function activate(context) {
    // Open embedded TMD snippet in side editor tab
    context.subscriptions.push(
        vscode.commands.registerCommand('tmd.openEmbeddedSnippet', async (arg) => {
            let text = '';
            if (typeof arg === 'string') {
                text = arg;
            } else if (Array.isArray(arg) && arg.length > 0) {
                text = arg[0];
            } else if (arg && arg.text) {
                text = arg.text;
            }
            if (!text || text.trim().length === 0) return;
            const doc = await vscode.workspace.openTextDocument({
                content: text,
                language: 'tmd'
            });
            await vscode.window.showTextDocument(doc, vscode.ViewColumn.Beside);
        })
    );

    // 0. New TMD Score from Template
    context.subscriptions.push(vscode.commands.registerCommand('tmd.newFromTemplate', async (uri) => {
        const items = TMD_TEMPLATES.map(t => ({
            label: t.label,
            description: t.description,
            detail: t.detail,
            template: t
        }));

        const picked = await vscode.window.showQuickPick(items, {
            placeHolder: vscode.l10n.t('Choose a template to quickly scaffold a TMD score'),
            matchOnDescription: true,
            matchOnDetail: true
        });
        if (!picked) return;

        const selected = picked.template;

        // If invoked from explorer folder context menu
        if (uri && uri.fsPath && fs.existsSync(uri.fsPath) && fs.statSync(uri.fsPath).isDirectory()) {
            const filename = await vscode.window.showInputBox({
                prompt: vscode.l10n.t('Enter filename for the new TMD score'),
                value: selected.defaultFilename,
                validateInput: (val) => {
                    if (!val || val.trim().length === 0) return vscode.l10n.t('Please provide a valid file name');
                    return null;
                }
            });
            if (!filename) return;
            const cleanName = filename.endsWith('.tmd') ? filename : `${filename}.tmd`;
            const targetPath = path.join(uri.fsPath, cleanName);
            if (fs.existsSync(targetPath)) {
                const overwrite = await vscode.window.showWarningMessage(
                    vscode.l10n.t('A file with this name already exists in the workspace. Please choose a different name.'),
                    'Overwrite',
                    'Cancel'
                );
                if (overwrite !== 'Overwrite') return;
            }
            fs.writeFileSync(targetPath, selected.content, 'utf8');
            const doc = await vscode.workspace.openTextDocument(vscode.Uri.file(targetPath));
            await vscode.window.showTextDocument(doc);
        } else {
            // Open as new untitled document with 'tmd' language mode
            const doc = await vscode.workspace.openTextDocument({
                language: 'tmd',
                content: selected.content
            });
            await vscode.window.showTextDocument(doc);
        }
    }));

    // 1. Export to MIDI (.mid)
    context.subscriptions.push(vscode.commands.registerCommand('tmd.exportMIDI', () => {
        const filePath = getActiveTmdFilePath();
        if (!filePath) return;
        const outputPath = filePath.replace(/\.[^/.]+$/, '') + '.mid';
        runTmdExport([filePath, '-m', outputPath], vscode.l10n.t('MIDI file exported successfully to {0}', path.basename(outputPath)), outputPath);
    }));

    // 2. Export to MusicXML (.musicxml)
    context.subscriptions.push(vscode.commands.registerCommand('tmd.exportMusicXML', () => {
        const filePath = getActiveTmdFilePath();
        if (!filePath) return;
        const outputPath = filePath.replace(/\.[^/.]+$/, '') + '.musicxml';
        runTmdExport([filePath, '-x', outputPath], vscode.l10n.t('MusicXML file exported successfully to {0}', path.basename(outputPath)), outputPath);
    }));

    // 3. Export to ABC (.abc)
    context.subscriptions.push(vscode.commands.registerCommand('tmd.exportABC', () => {
        const filePath = getActiveTmdFilePath();
        if (!filePath) return;
        const outputPath = filePath.replace(/\.[^/.]+$/, '') + '.abc';
        runTmdExport([filePath, '-a', outputPath], vscode.l10n.t('ABC notation exported successfully to {0}', path.basename(outputPath)), outputPath);
    }));

    // 4. Export to LilyPond (.ly)
    context.subscriptions.push(vscode.commands.registerCommand('tmd.exportLilyPond', () => {
        const filePath = getActiveTmdFilePath();
        if (!filePath) return;
        const outputPath = filePath.replace(/\.[^/.]+$/, '') + '.ly';
        runTmdExport([filePath, '-l', outputPath], vscode.l10n.t('LilyPond file exported successfully to {0}', path.basename(outputPath)), outputPath);
    }));

    // 5. Render to PDF via LilyPond (.pdf)
    context.subscriptions.push(vscode.commands.registerCommand('tmd.renderPDF', () => {
        const filePath = getActiveTmdFilePath();
        if (!filePath) return;
        const outputPath = filePath.replace(/\.[^/.]+$/, '') + '.pdf';
        runTmdExport([filePath, '--pdf-output', outputPath], vscode.l10n.t('PDF rendered successfully to {0}', path.basename(outputPath)), outputPath);
    }));

    // 6. Render to WAV Audio (.wav)
    context.subscriptions.push(vscode.commands.registerCommand('tmd.renderWAV', () => {
        const filePath = getActiveTmdFilePath();
        if (!filePath) return;
        const outputPath = filePath.replace(/\.[^/.]+$/, '') + '.wav';
        runTmdExport([filePath, '-w', outputPath], vscode.l10n.t('WAV rendered successfully to {0}', path.basename(outputPath)), outputPath);
    }));

    // 6.1. Export to VOCALOID3/4 (.vsqx)
    context.subscriptions.push(vscode.commands.registerCommand('tmd.exportVSQX', () => {
        const filePath = getActiveTmdFilePath();
        if (!filePath) return;
        const outputPath = filePath.replace(/\.[^/.]+$/, '') + '.vsqx';
        runTmdExport([filePath, '--vsqx-output', outputPath], vscode.l10n.t('VOCALOID3/4 (.vsqx) exported successfully to {0}', path.basename(outputPath)), outputPath);
    }));

    // 6.2. Export to VOCALOID2 (.vsq)
    context.subscriptions.push(vscode.commands.registerCommand('tmd.exportVSQ', () => {
        const filePath = getActiveTmdFilePath();
        if (!filePath) return;
        const outputPath = filePath.replace(/\.[^/.]+$/, '') + '.vsq';
        runTmdExport([filePath, '--vsq-output', outputPath], vscode.l10n.t('VOCALOID2 (.vsq) exported successfully to {0}', path.basename(outputPath)), outputPath);
    }));

    // 6.3. Export to UTAU (.ust)
    context.subscriptions.push(vscode.commands.registerCommand('tmd.exportUST', () => {
        const filePath = getActiveTmdFilePath();
        if (!filePath) return;
        const outputPath = filePath.replace(/\.[^/.]+$/, '') + '.ust';
        runTmdExport([filePath, '--ust-output', outputPath], vscode.l10n.t('UTAU (.ust) exported successfully to {0}', path.basename(outputPath)), outputPath);
    }));

    // Webview MIDI Player Panel tracking
    let currentMidiPanel = null;

    function getMidiWebviewContent(webview, extensionUri) {
        const jzzUri = webview.asWebviewUri(vscode.Uri.joinPath(extensionUri, 'media', 'JZZ.js'));
        const jzzSmfUri = webview.asWebviewUri(vscode.Uri.joinPath(extensionUri, 'media', 'JZZ.midi.SMF.js'));
        const jzzTinyUri = webview.asWebviewUri(vscode.Uri.joinPath(extensionUri, 'media', 'JZZ.synth.Tiny.js'));
        const soundfontCacheUri = webview.asWebviewUri(vscode.Uri.joinPath(extensionUri, 'media', 'soundfont-cache.js'));
        const soundfontUri = webview.asWebviewUri(vscode.Uri.joinPath(extensionUri, 'media', 'soundfont-player.min.js'));
        const soundfontMappingUri = webview.asWebviewUri(vscode.Uri.joinPath(extensionUri, 'media', 'soundfont-mapping.js'));
        const virtualKeyboardHelperUri = webview.asWebviewUri(vscode.Uri.joinPath(extensionUri, 'media', 'virtual-keyboard-helper.js'));
        const playerJsUri = webview.asWebviewUri(vscode.Uri.joinPath(extensionUri, 'media', 'player.js'));
        const playerCssUri = webview.asWebviewUri(vscode.Uri.joinPath(extensionUri, 'media', 'player.css'));

        return `<!DOCTYPE html>
<html lang="${vscode.env.language || 'en'}">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${vscode.l10n.t('TMD Web MIDI Player')}</title>
  <link rel="stylesheet" href="${playerCssUri}">
  ${getWebviewL10nScript()}
</head>
<body>
  <div class="player-container">
    <div class="player-header">
      <div id="player-icon" class="player-icon">🎵</div>
      <div class="player-header-info">
        <div id="score-title" class="score-title">${vscode.l10n.t('TMD Web MIDI Player')}</div>
        <div id="score-subtitle" class="score-subtitle">${vscode.l10n.t('Loading...')}</div>
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
        <button id="btn-play-pause" class="btn-ctrl btn-main" title="${vscode.l10n.t('Play')}">▶</button>
        <button id="btn-stop" class="btn-ctrl" title="${vscode.l10n.t('Stop')}">⏹</button>
      </div>

      <div class="synth-selector-group">
        <span class="synth-label">${vscode.l10n.t('Synth:')}</span>
        <select id="synth-select" class="synth-select">
          <option value="gm">🎼 ${vscode.l10n.t('General MIDI (FluidR3 Multi-Track)')}</option>
          <option value="piano">🎹 ${vscode.l10n.t('Grand Piano (FluidR3)')}</option>
          <option value="tiny">⚡ ${vscode.l10n.t('Tiny Synth (Chiptune)')}</option>
          <option value="webmidi">🎛 ${vscode.l10n.t('System MIDI Out')}</option>
        </select>
      </div>
    </div>

    <div id="status-text" class="status-bar">${vscode.l10n.t('Ready')}</div>
  </div>

  <script src="${jzzUri}"></script>
  <script src="${jzzSmfUri}"></script>
  <script src="${jzzTinyUri}"></script>
  <script src="${soundfontCacheUri}"></script>
  <script src="${soundfontUri}"></script>
  <script src="${soundfontMappingUri}"></script>
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

                currentMidiPanel.webview.onDidReceiveMessage((message) => {
                    if (message.command === 'insertNote') {
                        const activeEditor = vscode.window.activeTextEditor;
                        if (activeEditor) {
                            const textToInsert = message.note ? `${message.note} ` : '';
                            activeEditor.edit(editBuilder => {
                                editBuilder.insert(activeEditor.selection.active, textToInsert);
                            });
                        }
                    }
                }, null, context.subscriptions);

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

                    // Extract key signature (?= or {!K:...}) if available
                    let keySignature = 'C';
                    if (activeDoc) {
                        const keyMatch = activeDoc.getText().match(/^\s*(?:\?=|key)\s*:\s*([A-Ga-g][#'b,]?)/m);
                        if (keyMatch) {
                            keySignature = keyMatch[1];
                        }
                    }

                    currentMidiPanel.webview.postMessage({
                        command: 'loadMidi',
                        title: displayTitle,
                        sourceFile: scoreBaseName,
                        base64: base64Midi,
                        keySignature: keySignature,
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

    // Helper: get HTML content for dedicated Virtual Keyboard view
    function getKeyboardViewContent(webview, extensionUri) {
        const soundfontCacheUri = webview.asWebviewUri(vscode.Uri.joinPath(extensionUri, 'media', 'soundfont-cache.js'));
        const soundfontUri = webview.asWebviewUri(vscode.Uri.joinPath(extensionUri, 'media', 'soundfont-player.min.js'));
        const virtualKeyboardHelperUri = webview.asWebviewUri(vscode.Uri.joinPath(extensionUri, 'media', 'virtual-keyboard-helper.js'));
        const keyboardJsUri = webview.asWebviewUri(vscode.Uri.joinPath(extensionUri, 'media', 'keyboard.js'));
        const keyboardCssUri = webview.asWebviewUri(vscode.Uri.joinPath(extensionUri, 'media', 'keyboard.css'));

        return `<!DOCTYPE html>
<html lang="${vscode.env.language || 'en'}">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>TMD Virtual Keyboard</title>
  <link rel="stylesheet" href="${keyboardCssUri}">
  ${getWebviewL10nScript()}
</head>
<body>
  <div id="keyboard-container" class="keyboard-container">
    <div class="keyboard-toolbar">
      <div class="toolbar-left">
        <span class="keyboard-title">🎹 ${vscode.l10n.t('Piano')}</span>
        <span id="keyboard-key-badge" class="keyboard-key-badge">Key: C</span>
      </div>
      <div class="toolbar-right">
        <div class="mode-toggle">
          <button id="btn-mode-audition" class="btn-mode active" title="${vscode.l10n.t('Audition note')}">${vscode.l10n.t('Audition')}</button>
          <button id="btn-mode-insert" class="btn-mode" title="${vscode.l10n.t('Insert TMD note at cursor')}">${vscode.l10n.t('Insert')}</button>
        </div>
        <div class="octave-controls">
          <button id="btn-octave-down" class="btn-icon" title="${vscode.l10n.t('Octave down')}">◀</button>
          <span id="octave-display" class="octave-display">C4-C6</span>
          <button id="btn-octave-up" class="btn-icon" title="${vscode.l10n.t('Octave up')}">▶</button>
        </div>
      </div>
    </div>
    <div id="keyboard-body" class="keyboard-body">
      <div id="keyboard-keys-container" class="virtual-keyboard-keys"></div>
    </div>
  </div>

  <script src="${soundfontCacheUri}"></script>
  <script src="${soundfontUri}"></script>
  <script src="${virtualKeyboardHelperUri}"></script>
  <script src="${keyboardJsUri}"></script>
</body>
</html>`;
    }

    // Extract active score key signature
    function getActiveKeySignature() {
        const activeDoc = vscode.window.activeTextEditor?.document;
        if (activeDoc) {
            const match = activeDoc.getText().match(/^\s*(?:\?=|key)\s*:\s*([A-Ga-g][#'b,]?)/m);
            if (match) return match[1];
        }
        return 'C';
    }

    // 1. Virtual Keyboard Panel WebviewViewProvider
    let keyboardWebviewView = null;
    const keyboardViewProvider = {
        resolveWebviewView: (webviewView) => {
            keyboardWebviewView = webviewView;
            webviewView.webview.options = {
                enableScripts: true,
                localResourceRoots: [vscode.Uri.joinPath(context.extensionUri, 'media')]
            };
            webviewView.webview.html = getKeyboardViewContent(webviewView.webview, context.extensionUri);

            webviewView.webview.onDidReceiveMessage((message) => {
                if (message.command === 'insertNote') {
                    const activeEditor = vscode.window.activeTextEditor;
                    if (activeEditor) {
                        const textToInsert = message.note ? `${message.note} ` : '';
                        activeEditor.edit(editBuilder => {
                            editBuilder.insert(activeEditor.selection.active, textToInsert);
                        });
                    }
                }
            });

            webviewView.onDidDispose(() => {
                keyboardWebviewView = null;
            });

            // Send initial key signature
            const initialKey = getActiveKeySignature();
            webviewView.webview.postMessage({
                command: 'updateKeySignature',
                keySignature: initialKey
            });
        }
    };
    context.subscriptions.push(
        vscode.window.registerWebviewViewProvider('tmdKeyboardView', keyboardViewProvider)
    );

    // Command: Open Virtual Keyboard Panel
    context.subscriptions.push(vscode.commands.registerCommand('tmd.openKeyboard', async () => {
        await vscode.commands.executeCommand('tmdKeyboardView.focus');
    }));

    // Update keyboard key signature on active editor change or document change
    context.subscriptions.push(
        vscode.window.onDidChangeActiveTextEditor(ed => {
            if (keyboardWebviewView && ed && ed.document.languageId === 'tmd') {
                const key = getActiveKeySignature();
                keyboardWebviewView.webview.postMessage({
                    command: 'updateKeySignature',
                    keySignature: key
                });
            }
        })
    );

    // Visual Song Inspector Webview tracking (Panel View & Standalone Tab)
    let currentInspectorPanel = null;
    let inspectorWebviewView = null;

    function getInspectorWebviewContent(webview, extensionUri) {
        const inspectorCssUri = webview.asWebviewUri(vscode.Uri.joinPath(extensionUri, 'media', 'inspector.css'));
        const virtualKeyboardHelperUri = webview.asWebviewUri(vscode.Uri.joinPath(extensionUri, 'media', 'virtual-keyboard-helper.js'));
        const inspectorJsUri = webview.asWebviewUri(vscode.Uri.joinPath(extensionUri, 'media', 'inspector.js'));

        return `<!DOCTYPE html>
<html lang="${vscode.env.language || 'en'}">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${vscode.l10n.t('Song Inspector')}</title>
  <link rel="stylesheet" href="${inspectorCssUri}">
  ${getWebviewL10nScript()}
</head>
<body>
  <div class="inspector-header">
    <div class="header-title-row">
      <div class="score-title">
        <span id="score-title">${vscode.l10n.t('Song Inspector')}</span>
        <span id="status-badge" class="badge-valid">${vscode.l10n.t('Ready')}</span>
      </div>
      <div id="file-path" class="file-path"></div>
    </div>
    <button id="btn-refresh" class="btn-refresh" title="${vscode.l10n.t('Refresh')}">${vscode.l10n.t('Refresh')}</button>
  </div>

  <!-- Key Metrics Grid -->
  <div class="stats-grid">
    <div class="stat-card">
      <div class="stat-label">${vscode.l10n.t('Duration')}</div>
      <div id="val-duration" class="stat-value">-</div>
      <div id="sub-duration" class="stat-sub">-</div>
    </div>
    <div class="stat-card">
      <div class="stat-label">${vscode.l10n.t('Movable-do base')}</div>
      <div id="val-key" class="stat-value">-</div>
      <div id="sub-key" class="stat-sub">-</div>
    </div>
    <div class="stat-card">
      <div class="stat-label">${vscode.l10n.t('Tempo')}</div>
      <div id="val-tempo" class="stat-value">-</div>
      <div id="sub-tempo" class="stat-sub">-</div>
    </div>
    <div class="stat-card">
      <div class="stat-label">${vscode.l10n.t('Arrangement Density')}</div>
      <div id="val-density" class="stat-value">-</div>
      <div id="sub-density" class="stat-sub">-</div>
    </div>
  </div>

  <!-- Vocal & Pitch Tessitura Card -->
  <div class="section-card">
    <div class="section-card-header">
      <div class="section-card-title">${vscode.l10n.t('Pitch Range & Tessitura Analysis')}</div>
      <select id="track-select" class="track-select"></select>
    </div>
    <div id="range-container" class="range-display-container">
      <div class="stat-sub">${vscode.l10n.t('Analyzing track notes...')}</div>
    </div>
  </div>

  <!-- Harmony & Modulations Card -->
  <div class="section-card">
    <div class="section-card-header">
      <div class="section-card-title">${vscode.l10n.t('Harmonic Vocabulary & Modulations')}</div>
    </div>
    <div style="display: flex; flex-direction: column; gap: 10px;">
      <div>
        <div class="stat-label" style="margin-bottom: 6px;">${vscode.l10n.t('Distinct Chords')}</div>
        <div id="chords-list" class="tags-list"></div>
      </div>
      <div>
        <div class="stat-label" style="margin-bottom: 6px;">${vscode.l10n.t('Key Modulations')}</div>
        <div id="modulations-list" class="tags-list"></div>
      </div>
    </div>
  </div>

  <!-- Tonality & Key Profile Analysis Card -->
  <div class="section-card" id="tonality-card">
    <div class="section-card-header">
      <div class="section-card-title">${vscode.l10n.t('Tonality & Key Profile Analysis')}</div>
      <div id="tonality-stability-badge" class="badge-valid">-</div>
    </div>
    <div id="tonality-container" class="tonality-display-container">
      <div class="stat-sub">${vscode.l10n.t('Analyzing tonality profile...')}</div>
    </div>
  </div>

  <!-- Musical Structure Timeline -->
  <div class="section-card">
    <div class="section-card-header">
      <div class="section-card-title">${vscode.l10n.t('Structure & Conductor Timeline')}</div>
    </div>
    <div class="timeline-flow">
      <div id="timeline-bar-wrapper" class="timeline-bar-wrapper"></div>
      <div id="timeline-list" class="timeline-list"></div>
    </div>
  </div>

  <script src="${virtualKeyboardHelperUri}"></script>
  <script src="${inspectorJsUri}"></script>
</body>
</html>`;
    }

    async function updateInspectorTarget(target, document) {
        if (!target || !document) return;
        const webview = target.webview || target;
        const text = document.getText();
        const baseName = path.basename(document.fileName || 'Untitled.tmd');

        const res = await runTmdInspectBuffer(text, true);
        if (res.success && res.report) {
            try {
                const profile = JSON.parse(res.report);
                webview.postMessage({
                    type: 'update',
                    profile: profile,
                    fileName: baseName
                });
            } catch (err) {
                webview.postMessage({
                    type: 'error',
                    error: `JSON parsing error: ${err.message}`,
                    fileName: baseName
                });
            }
        } else {
            webview.postMessage({
                type: 'error',
                error: res.error || 'Failed to inspect score',
                fileName: baseName
            });
        }
    }

    function setupInspectorMessageHandling(webview, onRefresh) {
        webview.onDidReceiveMessage(message => {
            const activeEd = vscode.window.activeTextEditor;
            if (!activeEd) return;

            if (message.type === 'refresh') {
                if (onRefresh) onRefresh(activeEd.document);
            } else if (message.type === 'jumpToSection' && message.sectionName) {
                const doc = activeEd.document;
                const secRegex = new RegExp(`^\\s*${message.sectionName}\\s*:\\s*[a-zA-Z0-9_\\-+]+`, 'i');
                for (let i = 0; i < doc.lineCount; i++) {
                    if (secRegex.test(doc.lineAt(i).text)) {
                        const pos = new vscode.Position(i, 0);
                        activeEd.selection = new vscode.Selection(pos, pos);
                        activeEd.revealRange(new vscode.Range(pos, pos), vscode.TextEditorRevealType.InCenter);
                        break;
                    }
                }
            } else if (message.type === 'findText' && message.text) {
                vscode.commands.executeCommand('actions.find', { searchString: message.text });
            }
        }, null, context.subscriptions);
    }

    // 2. Song Inspector Panel WebviewViewProvider
    const inspectorViewProvider = {
        resolveWebviewView: (webviewView) => {
            inspectorWebviewView = webviewView;
            webviewView.webview.options = {
                enableScripts: true,
                localResourceRoots: [vscode.Uri.joinPath(context.extensionUri, 'media')]
            };
            webviewView.webview.html = getInspectorWebviewContent(webviewView.webview, context.extensionUri);

            setupInspectorMessageHandling(webviewView.webview, (doc) => {
                updateInspectorTarget(webviewView, doc);
            });

            webviewView.onDidDispose(() => {
                inspectorWebviewView = null;
            });

            const activeEditor = vscode.window.activeTextEditor;
            if (activeEditor && (activeEditor.document.languageId === 'tmd' || activeEditor.document.fileName.endsWith('.tmd'))) {
                updateInspectorTarget(webviewView, activeEditor.document);
            }
        }
    };
    context.subscriptions.push(
        vscode.window.registerWebviewViewProvider('tmdInspectorView', inspectorViewProvider)
    );

    // Command: Inspect Song Profile (Reveals the Panel View)
    context.subscriptions.push(vscode.commands.registerCommand('tmd.inspectSong', async () => {
        await vscode.commands.executeCommand('tmdInspectorView.focus');
        const editor = vscode.window.activeTextEditor;
        if (inspectorWebviewView && editor && (editor.document.languageId === 'tmd' || editor.document.fileName.endsWith('.tmd'))) {
            updateInspectorTarget(inspectorWebviewView, editor.document);
        }
    }));

    // Auto-update Inspector on document save or text change
    context.subscriptions.push(
        vscode.workspace.onDidSaveTextDocument(doc => {
            if (doc.languageId === 'tmd') {
                if (inspectorWebviewView) updateInspectorTarget(inspectorWebviewView, doc);
                if (currentInspectorPanel) updateInspectorTarget(currentInspectorPanel, doc);
            }
        })
    );

    let inspectorDebounce = null;
    context.subscriptions.push(
        vscode.workspace.onDidChangeTextDocument(event => {
            if (event.document.languageId === 'tmd') {
                if (inspectorDebounce) clearTimeout(inspectorDebounce);
                inspectorDebounce = setTimeout(() => {
                    if (inspectorWebviewView) updateInspectorTarget(inspectorWebviewView, event.document);
                    if (currentInspectorPanel) updateInspectorTarget(currentInspectorPanel, event.document);
                }, 800);
            }
        })
    );

    context.subscriptions.push(
        vscode.window.onDidChangeActiveTextEditor(ed => {
            if (ed && ed.document.languageId === 'tmd') {
                if (inspectorWebviewView) updateInspectorTarget(inspectorWebviewView, ed.document);
                if (currentInspectorPanel) updateInspectorTarget(currentInspectorPanel, ed.document);
            }
        })
    );

    // Command: Format Document
    context.subscriptions.push(vscode.commands.registerCommand('tmd.formatDocument', () => {
        return vscode.commands.executeCommand('editor.action.formatDocument');
    }));

    // Helper: Execute in-place TMD refactoring and replace document buffer or selection range
    function runTmdRefactor(args, description, targetRange = null) {
        const editor = vscode.window.activeTextEditor;
        if (!editor || (editor.document.languageId !== 'tmd' && !editor.document.fileName.endsWith('.tmd'))) {
            vscode.window.showErrorMessage('TMD refactoring commands require an active .tmd file.');
            return;
        }

        const tmdBin = getTmdExecutable();
        const document = editor.document;
        const tempDir = os.tmpdir();
        const tempFilePath = path.join(tempDir, `tmd_refactor_${Date.now()}_${path.basename(document.fileName || 'untitled.tmd')}`);

        const textToProcess = targetRange ? document.getText(targetRange) : document.getText();

        try {
            fs.writeFileSync(tempFilePath, textToProcess, 'utf8');
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

                    const replaceRange = targetRange || new vscode.Range(
                        document.positionAt(0),
                        document.positionAt(document.getText().length)
                    );

                    editor.edit(editBuilder => {
                        editBuilder.replace(replaceRange, stdout);
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

    // 2b. Refactor: Optimize Grid
    context.subscriptions.push(vscode.commands.registerCommand('tmd.refactorOptimizeGrid', async () => {
        const context = detectContextAtCursor();
        const scope = await promptScopeChoice(context, 'Optimize Grid');
        if (!scope) return;

        const args = ['optimize-grid'];
        if (scope.section) {
            args.push('--section', scope.section);
        }
        runTmdRefactor(args, scope.section ? `Optimize Grid (${scope.section})` : 'Optimize Grid Resolution');
    }));

    // 2c. Refactor: Transpose Pitch (Document, Scope, or Selected Text)
    async function executeTransposeRefactor(forceSelectionOnly = false) {
        const editor = vscode.window.activeTextEditor;
        if (!editor) return;

        const selection = editor.selection;
        const hasSelection = selection && !selection.isEmpty;
        let isSelectionOnly = forceSelectionOnly && hasSelection;

        const modeChoice = await vscode.window.showQuickPick([
            {
                label: 'By Semitones (Chromatic)',
                description: 'Shift pitch by semitone count (e.g. +2 for one whole tone up, -1 for semitone down)',
                mode: 'semitones'
            },
            {
                label: 'By Diatonic Steps (Scale Degrees)',
                description: 'Shift melody notes within current diatonic scale (e.g. +2 for 3rd up, -1 for step down)',
                mode: 'diatonic'
            }
        ], {
            placeHolder: 'Select transposition mode'
        });
        if (!modeChoice) return;

        const valInput = await vscode.window.showInputBox({
            prompt: modeChoice.mode === 'semitones'
                ? 'Enter semitone offset (e.g. +2, -3, 1)'
                : 'Enter diatonic scale steps offset (e.g. +2, -1, 1)',
            validateInput: v => {
                const n = parseInt(v, 10);
                return (!isNaN(n) && n !== 0) ? null : 'Please enter a non-zero integer offset (e.g. +2 or -1)';
            }
        });
        if (!valInput) return;
        const offset = parseInt(valInput, 10);

        let updateKey = false;
        if (modeChoice.mode === 'semitones' && !isSelectionOnly) {
            const updateKeyChoice = await vscode.window.showQuickPick([
                {
                    label: 'Yes, update ?= Key Signatures',
                    description: 'Automatically adjust {!K:...} / ?= key signature headers in the score',
                    updateKey: true
                },
                {
                    label: 'No, keep Key Signatures as-is',
                    description: 'Only transpose notes and chords without altering the score key header',
                    updateKey: false
                }
            ], {
                placeHolder: 'Also update score key signature (?=)?'
            });
            if (!updateKeyChoice) return;
            updateKey = updateKeyChoice.updateKey;
        }

        const cursorContext = detectContextAtCursor();
        let targetSection = undefined;
        let targetInstrument = undefined;

        if (!forceSelectionOnly && (hasSelection || cursorContext.section || cursorContext.instrument)) {
            const scopeItems = [];
            if (hasSelection) {
                scopeItems.push({
                    label: 'Selected text only',
                    description: 'Transpose only the currently selected note/score snippet',
                    scope: 'selection'
                });
            }
            scopeItems.push({
                label: 'Entire Score',
                description: 'Transpose all sections and all instruments',
                scope: 'all'
            });
            if (cursorContext.section) {
                scopeItems.push({
                    label: `Section '${cursorContext.section}' only`,
                    description: `Transpose only section '${cursorContext.section}'`,
                    scope: 'section',
                    section: cursorContext.section
                });
            }
            if (cursorContext.instrument) {
                scopeItems.push({
                    label: `Instrument '${cursorContext.instrument}' only`,
                    description: `Transpose only instrument '${cursorContext.instrument}' across all sections`,
                    scope: 'instrument',
                    instrument: cursorContext.instrument
                });
            }
            if (cursorContext.section && cursorContext.instrument) {
                scopeItems.push({
                    label: `'${cursorContext.instrument}' in Section '${cursorContext.section}'`,
                    description: `Transpose only this instrument track in this section`,
                    scope: 'both',
                    section: cursorContext.section,
                    instrument: cursorContext.instrument
                });
            }

            const scopeChoice = await vscode.window.showQuickPick(scopeItems, {
                placeHolder: 'Select target scope for transposition'
            });
            if (!scopeChoice) return;
            if (scopeChoice.scope === 'selection') {
                isSelectionOnly = true;
            } else {
                isSelectionOnly = false;
                if (scopeChoice.section) targetSection = scopeChoice.section;
                if (scopeChoice.instrument) targetInstrument = scopeChoice.instrument;
            }
        }

        const args = ['transpose'];
        if (modeChoice.mode === 'semitones') {
            args.push('--semitones', String(offset));
            if (updateKey && !isSelectionOnly) {
                args.push('--update-key');
            }
        } else {
            args.push('--diatonic', String(offset));
        }

        if (!isSelectionOnly) {
            if (targetSection) {
                args.push('--section', targetSection);
            }
            if (targetInstrument) {
                args.push('--instrument', targetInstrument);
            }
        }

        const desc = modeChoice.mode === 'semitones'
            ? `Transpose ${offset > 0 ? '+' : ''}${offset} Semitones${isSelectionOnly ? ' (Selection)' : ''}`
            : `Transpose ${offset > 0 ? '+' : ''}${offset} Diatonic Steps${isSelectionOnly ? ' (Selection)' : ''}`;

        runTmdRefactor(args, desc, isSelectionOnly ? selection : null);
    }

    context.subscriptions.push(vscode.commands.registerCommand('tmd.refactorTranspose', () => {
        return executeTransposeRefactor(false);
    }));

    context.subscriptions.push(vscode.commands.registerCommand('tmd.refactorTransposeSelection', () => {
        return executeTransposeRefactor(true);
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

    function runTmdInspectBuffer(text, asJson = false) {
        return new Promise((resolve) => {
            const tmdBin = getTmdExecutable();
            const tempDir = os.tmpdir();
            const tempFilePath = path.join(tempDir, `tmd_chat_inspect_${Date.now()}.tmd`);

            try {
                fs.writeFileSync(tempFilePath, text, 'utf8');
            } catch (err) {
                resolve({ success: false, error: err.message, report: '' });
                return;
            }

            const args = ['inspect', tempFilePath, '--locale', getTmdInspectLocale()];
            if (asJson) args.push('--json');
            execFile(tmdBin, args, (error, stdout, stderr) => {
                try { fs.unlinkSync(tempFilePath); } catch (_) {}
                if (error && (!stdout || stdout.trim().length === 0)) {
                    resolve({ success: false, error: (stderr || error?.message || 'Inspect failed'), report: '' });
                } else {
                    resolve({ success: true, report: stdout.trim() });
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

        // Tool: tmd_inspect
        context.subscriptions.push(
            vscode.lm.registerTool('tmd_inspect', {
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

                    const result = await runTmdInspectBuffer(scoreText, input.asJson ?? false);
                    return new vscode.LanguageModelToolResult([
                        new vscode.LanguageModelTextPart(result.report || result.error || 'Inspection failed')
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

            if (request.command === 'inspect') {
                stream.progress('Inspecting song musical profile, vocal tessitura, and arrangement density...');
                const textToInspect = request.prompt.trim().length > 0 ? request.prompt : activeCode;
                if (!textToInspect) {
                    stream.markdown('Please open a `.tmd` file or provide TMD score text to inspect.');
                    return;
                }
                const res = await runTmdInspectBuffer(textToInspect);
                if (res.success && res.report) {
                    stream.markdown('```text\n' + res.report + '\n```\n');
                } else {
                    stream.markdown('Inspection error: ' + (res.error || 'Unknown error'));
                }
                return;
            }

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

    // 3. Start TMD Language Server (LSP) Client over stdio
    class TMDLanguageClient {
        constructor() {
            this.process = null;
            this.nextId = 1;
            this.pendingRequests = new Map();
            this.buffer = Buffer.alloc(0);
            this.isInitialized = false;
        }

        start() {
            const tmdBin = getTmdExecutable();
            try {
                this.process = spawn(tmdBin, ['lsp'], {
                    stdio: ['pipe', 'pipe', 'pipe']
                });
            } catch (err) {
                console.warn('Failed to spawn TMD LSP process:', err.message);
                return;
            }

            this.process.stdout.on('data', (chunk) => {
                this.handleData(chunk);
            });

            this.process.stderr.on('data', (chunk) => {
                // Log LSP server warnings/errors to console
                console.warn('[TMD LSP STDERR]', chunk.toString());
            });

            this.process.on('error', (err) => {
                console.warn('TMD LSP process error:', err.message);
            });

            this.process.on('exit', (code) => {
                this.process = null;
                this.isInitialized = false;
            });

            // Send initialize request
            this.sendRequest('initialize', {
                processId: process.pid,
                rootUri: null,
                capabilities: {}
            }).then(() => {
                this.isInitialized = true;
                this.sendNotification('initialized', {});
                // Synchronize open documents
                for (const doc of vscode.workspace.textDocuments) {
                    if (doc.languageId === 'tmd') {
                        this.didOpen(doc);
                    }
                }
            }).catch(err => {
                console.warn('TMD LSP initialize error:', err);
            });
        }

        handleData(chunk) {
            this.buffer = Buffer.concat([this.buffer, chunk]);
            while (true) {
                const headerEnd = this.buffer.indexOf('\r\n\r\n');
                if (headerEnd === -1) break;

                const headerStr = this.buffer.slice(0, headerEnd).toString('utf8');
                let contentLength = null;
                for (const line of headerStr.split('\r\n')) {
                    const idx = line.indexOf(':');
                    if (idx !== -1) {
                        const key = line.slice(0, idx).trim().toLowerCase();
                        if (key === 'content-length') {
                            contentLength = parseInt(line.slice(idx + 1).trim(), 10);
                        }
                    }
                }

                if (contentLength === null) break;
                const bodyStart = headerEnd + 4;
                const bodyEnd = bodyStart + contentLength;
                if (this.buffer.length < bodyEnd) break;

                const bodyData = this.buffer.slice(bodyStart, bodyEnd);
                this.buffer = this.buffer.slice(bodyEnd);

                try {
                    const msg = JSON.parse(bodyData.toString('utf8'));
                    this.handleMessage(msg);
                } catch (e) {
                    console.error('Failed to parse LSP message JSON:', e);
                }
            }
        }

        handleMessage(msg) {
            if (msg.id !== undefined && msg.id !== null) {
                // Response
                const resolver = this.pendingRequests.get(msg.id);
                if (resolver) {
                    this.pendingRequests.delete(msg.id);
                    if (msg.error) {
                        resolver.reject(msg.error);
                    } else {
                        resolver.resolve(msg.result);
                    }
                }
            } else if (msg.method) {
                // Notification from server
                if (msg.method === 'textDocument/publishDiagnostics' && msg.params) {
                    this.handleDiagnostics(msg.params);
                }
            }
        }

        handleDiagnostics(params) {
            const uri = vscode.Uri.parse(params.uri);
            const diagnostics = (params.diagnostics || []).map(d => {
                const range = new vscode.Range(
                    d.range.start.line,
                    d.range.start.character,
                    d.range.end.line,
                    d.range.end.character
                );
                let severity = vscode.DiagnosticSeverity.Error;
                if (d.severity === 2) severity = vscode.DiagnosticSeverity.Warning;
                else if (d.severity === 3) severity = vscode.DiagnosticSeverity.Information;
                else if (d.severity === 4) severity = vscode.DiagnosticSeverity.Hint;

                const diag = new vscode.Diagnostic(range, d.message, severity);
                diag.source = d.source || 'tmd';
                return diag;
            });
            diagnosticCollection.set(uri, diagnostics);
        }

        sendRequest(method, params) {
            return new Promise((resolve, reject) => {
                if (!this.process) {
                    reject(new Error('LSP process not running'));
                    return;
                }
                const id = this.nextId++;
                this.pendingRequests.set(id, { resolve, reject });
                const payload = JSON.stringify({ jsonrpc: '2.0', id, method, params });
                const header = `Content-Length: ${Buffer.byteLength(payload, 'utf8')}\r\n\r\n`;
                this.process.stdin.write(header + payload);
            });
        }

        sendNotification(method, params) {
            if (!this.process) return;
            const payload = JSON.stringify({ jsonrpc: '2.0', method, params });
            const header = `Content-Length: ${Buffer.byteLength(payload, 'utf8')}\r\n\r\n`;
            this.process.stdin.write(header + payload);
        }

        didOpen(document) {
            this.sendNotification('textDocument/didOpen', {
                textDocument: {
                    uri: document.uri.toString(),
                    languageId: 'tmd',
                    version: document.version,
                    text: document.getText()
                }
            });
        }

        didChange(document) {
            this.sendNotification('textDocument/didChange', {
                textDocument: {
                    uri: document.uri.toString(),
                    version: document.version
                },
                contentChanges: [{ text: document.getText() }]
            });
        }

        didClose(document) {
            this.sendNotification('textDocument/didClose', {
                textDocument: {
                    uri: document.uri.toString()
                }
            });
        }

        async requestCompletion(document, position) {
            if (!this.isInitialized) return [];
            try {
                const res = await this.sendRequest('textDocument/completion', {
                    textDocument: { uri: document.uri.toString() },
                    position: { line: position.line, character: position.character }
                });
                if (!Array.isArray(res)) return [];
                return res.map(item => {
                    const ci = new vscode.CompletionItem(item.label);
                    if (item.kind) {
                        switch (item.kind) {
                            case 1: ci.kind = vscode.CompletionItemKind.Text; break;
                            case 2: ci.kind = vscode.CompletionItemKind.Method; break;
                            case 3: ci.kind = vscode.CompletionItemKind.Function; break;
                            case 4: ci.kind = vscode.CompletionItemKind.Constructor; break;
                            case 5: ci.kind = vscode.CompletionItemKind.Field; break;
                            case 6: ci.kind = vscode.CompletionItemKind.Variable; break;
                            case 7: ci.kind = vscode.CompletionItemKind.Class; break;
                            case 8: ci.kind = vscode.CompletionItemKind.Interface; break;
                            case 9: ci.kind = vscode.CompletionItemKind.Module; break;
                            case 10: ci.kind = vscode.CompletionItemKind.Property; break;
                            case 11: ci.kind = vscode.CompletionItemKind.Unit; break;
                            case 12: ci.kind = vscode.CompletionItemKind.Value; break;
                            case 13: ci.kind = vscode.CompletionItemKind.Enum; break;
                            case 14: ci.kind = vscode.CompletionItemKind.Keyword; break;
                            case 15: ci.kind = vscode.CompletionItemKind.Snippet; break;
                            default: ci.kind = vscode.CompletionItemKind.Value;
                        }
                    }
                    if (item.detail) ci.detail = item.detail;
                    if (item.documentation) ci.documentation = new vscode.MarkdownString(item.documentation);
                    if (item.insertText) {
                        ci.insertText = item.insertTextFormat === 2
                            ? new vscode.SnippetString(item.insertText)
                            : item.insertText;
                    }
                    return ci;
                });
            } catch (err) {
                return [];
            }
        }

        async requestFormatting(document) {
            if (!this.isInitialized) return [];
            try {
                const res = await this.sendRequest('textDocument/formatting', {
                    textDocument: { uri: document.uri.toString() },
                    options: { tabSize: 4, insertSpaces: true }
                });
                if (!Array.isArray(res)) return [];
                return res.map(edit => {
                    const range = new vscode.Range(
                        edit.range.start.line,
                        edit.range.start.character,
                        edit.range.end.line,
                        edit.range.end.character
                    );
                    return vscode.TextEdit.replace(range, edit.newText);
                });
            } catch (err) {
                return [];
            }
        }

        async requestDocumentSymbols(document) {
            if (!this.isInitialized) return [];
            try {
                const res = await this.sendRequest('textDocument/documentSymbol', {
                    textDocument: { uri: document.uri.toString() }
                });
                if (!Array.isArray(res)) return [];

                function mapSymbolKind(k) {
                    switch (k) {
                        case 1: return vscode.SymbolKind.File;
                        case 3: return vscode.SymbolKind.Namespace;
                        case 5: return vscode.SymbolKind.Class;
                        case 6: return vscode.SymbolKind.Method;
                        case 7: return vscode.SymbolKind.Property;
                        case 8: return vscode.SymbolKind.Field;
                        case 24: return vscode.SymbolKind.Event;
                        default: return vscode.SymbolKind.Object;
                    }
                }

                function convertSymbol(s) {
                    const range = new vscode.Range(
                        s.range.start.line,
                        s.range.start.character,
                        s.range.end.line,
                        s.range.end.character
                    );
                    const selRange = s.selectionRange ? new vscode.Range(
                        s.selectionRange.start.line,
                        s.selectionRange.start.character,
                        s.selectionRange.end.line,
                        s.selectionRange.end.character
                    ) : range;

                    const docSymbol = new vscode.DocumentSymbol(
                        s.name,
                        s.detail || '',
                        mapSymbolKind(s.kind),
                        range,
                        selRange
                    );
                    if (Array.isArray(s.children) && s.children.length > 0) {
                        docSymbol.children = s.children.map(convertSymbol);
                    }
                    return docSymbol;
                }

                return res.map(convertSymbol);
            } catch (err) {
                return [];
            }
        }

        stop() {
            if (this.process) {
                try {
                    this.sendNotification('exit', {});
                    this.process.kill();
                } catch (_) {}
                this.process = null;
            }
        }
    }

    const tmdLspClient = new TMDLanguageClient();
    tmdLspClient.start();

    // Register LSP completion provider with triggers: '>', '(', ':', '['
    context.subscriptions.push(
        vscode.languages.registerCompletionItemProvider('tmd', {
            provideCompletionItems(document, position) {
                return tmdLspClient.requestCompletion(document, position);
            }
        }, '>', '(', ':', '[')
    );

    // Register LSP formatting provider
    context.subscriptions.push(
        vscode.languages.registerDocumentFormattingEditProvider('tmd', {
            provideDocumentFormattingEdits(document) {
                return tmdLspClient.requestFormatting(document);
            }
        })
    );

    // Register LSP document symbol (outline) provider
    context.subscriptions.push(
        vscode.languages.registerDocumentSymbolProvider('tmd', {
            provideDocumentSymbols(document) {
                return tmdLspClient.requestDocumentSymbols(document);
            }
        })
    );

    // Synchronize LSP documents
    context.subscriptions.push(
        vscode.workspace.onDidOpenTextDocument((doc) => {
            if (doc.languageId === 'tmd') {
                tmdLspClient.didOpen(doc);
            }
        }),
        vscode.workspace.onDidChangeTextDocument((event) => {
            if (event.document.languageId === 'tmd') {
                tmdLspClient.didChange(event.document);
            }
        }),
        vscode.workspace.onDidCloseTextDocument((doc) => {
            if (doc.languageId === 'tmd') {
                tmdLspClient.didClose(doc);
            }
        })
    );

    activeLspClient = tmdLspClient;

    return {
        extendMarkdownIt
    };
}

let activeLspClient = null;

function deactivate() {
    if (activeLspClient) {
        activeLspClient.stop();
        activeLspClient = null;
    }
}

/**
 * Escapes HTML characters for safe embedding.
 */
function escapeHtml(str) {
    if (!str) return '';
    return str.replace(/&/g, '&amp;')
              .replace(/</g, '&lt;')
              .replace(/>/g, '&gt;')
              .replace(/"/g, '&quot;')
              .replace(/'/g, '&#039;');
}

/**
 * Compiles a raw TMD snippet into MIDI (Base64) and renders an interactive Markdown card.
 */
function renderTmdMarkdownCard(rawTmd) {
    const titleMatch = rawTmd.match(/\*\*([^\*]+)\*\*/);
    const title = titleMatch ? titleMatch[1].trim() : 'TMD Score';

    const tempoMatch = rawTmd.match(/!=\s*([0-9.]+)/);
    const tempo = tempoMatch ? tempoMatch[1].trim() : '';

    const keyMatch = rawTmd.match(/\?=\s*([A-Ga-g][b#m]*)/);
    const key = keyMatch ? keyMatch[1].trim() : '';

    const meterMatch = rawTmd.match(/<([0-9]+\/[0-9]+)>/);
    const meter = meterMatch ? meterMatch[1].trim() : '';

    let midiBase64 = '';
    try {
        const tmdBin = getTmdExecutable();
        const randId = Math.random().toString(36).slice(2);
        const tempTmd = path.join(os.tmpdir(), `tmd_md_${Date.now()}_${randId}.tmd`);
        const tempMid = path.join(os.tmpdir(), `tmd_md_${Date.now()}_${randId}.mid`);

        // Prepare compilable TMD score (wrap bare snippet if missing score header or orders)
        let compilableTmd = rawTmd.trim();
        if (!compilableTmd.includes('::SCORE::')) {
            const paragraphNames = [];
            const pRegex = /([A-Za-z0-9_]+)\s*:/g;
            let m;
            while ((m = pRegex.exec(compilableTmd)) !== null) {
                if (!paragraphNames.includes(m[1])) paragraphNames.push(m[1]);
            }
            const orderStr = paragraphNames.length > 0 ? paragraphNames.map(p => `-> ${p}`).join(' ') + ' ->#' : '-> main ->#';
            compilableTmd = `::SCORE::\n** TMD Snippet **\n!= 120\n?= C\n<4/4>\n\n${compilableTmd}\n\n${orderStr}\n`;
        } else if (!compilableTmd.includes('->')) {
            const paragraphNames = [];
            const pRegex = /([A-Za-z0-9_]+)\s*:/g;
            let m;
            while ((m = pRegex.exec(compilableTmd)) !== null) {
                if (!paragraphNames.includes(m[1])) paragraphNames.push(m[1]);
            }
            if (paragraphNames.length > 0) {
                compilableTmd += '\n' + paragraphNames.map(p => `-> ${p}`).join(' ') + ' ->#\n';
            }
        }

        fs.writeFileSync(tempTmd, compilableTmd, 'utf8');
        execFileSync(tmdBin, ['-f', tempTmd, '-m', tempMid], { timeout: 4000, stdio: ['ignore', 'pipe', 'pipe'] });
        if (fs.existsSync(tempMid)) {
            midiBase64 = fs.readFileSync(tempMid).toString('base64');
            try { fs.unlinkSync(tempMid); } catch (_) {}
        }
        try { fs.unlinkSync(tempTmd); } catch (_) {}
    } catch (err) {
        console.warn('[TMD Markdown Plugin] MIDI compile warning:', err.message);
    }

    const encodedTmd = encodeURIComponent(rawTmd);

    return `<div class="tmd-markdown-card" data-midi="${midiBase64}" data-tmd="${encodedTmd}">
  <div class="tmd-card-header">
    <div class="tmd-card-title-group">
      <span class="tmd-card-icon">🎵</span>
      <span class="tmd-card-title">${escapeHtml(title)}</span>
    </div>
    <div class="tmd-card-badges">
      ${tempo ? `<span class="tmd-badge tempo">♩ ${escapeHtml(tempo)} BPM</span>` : ''}
      ${key ? `<span class="tmd-badge key">Key: ${escapeHtml(key)}</span>` : ''}
      ${meter ? `<span class="tmd-badge meter">${escapeHtml(meter)}</span>` : ''}
    </div>
  </div>
  <div class="tmd-card-transport">
    <button type="button" class="tmd-btn tmd-btn-play" title="Play / Pause">
      <span class="tmd-btn-icon">▶</span>
      <span class="tmd-btn-label">Play</span>
    </button>
    <button type="button" class="tmd-btn btn-secondary tmd-btn-stop" title="Stop">
      <span class="tmd-btn-icon">⏹</span>
    </button>
    <input type="range" class="tmd-slider" min="0" max="1000" value="0">
    <span class="tmd-time-display">00:00 / 00:00</span>
  </div>
  <div class="tmd-card-actions">
    <button type="button" class="tmd-btn btn-secondary tmd-btn-open" title="Open score in editor tab beside this document">
      <span>✏️ Try in Editor (嘗試編輯)</span>
    </button>
  </div>
  <details class="tmd-code-details">
    <summary>查看 TMD 語法 (View Source)</summary>
    <pre><code class="language-tmd">${escapeHtml(rawTmd)}</code></pre>
  </details>
</div>
`;
}

/**
 * VS Code Markdown-it Extension point.
 */
function extendMarkdownIt(md) {
    const defaultFence = md.renderer.rules.fence || function (tokens, idx, options, env, self) {
        return self.renderToken(tokens, idx, options);
    };

    md.renderer.rules.fence = function (tokens, idx, options, env, self) {
        const token = tokens[idx];
        const info = token.info ? token.info.trim() : '';

        if (info.toLowerCase() === 'tmd') {
            const rawTmd = token.content;
            return renderTmdMarkdownCard(rawTmd);
        }

        return defaultFence(tokens, idx, options, env, self);
    };

    return md;
}

module.exports = {
    activate,
    deactivate,
    extendMarkdownIt
};
