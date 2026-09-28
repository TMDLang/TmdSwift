"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.createHummingRecorder = createHummingRecorder;
const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');
function createHummingRecorder(options = {}) {
    const spawnProcess = options.spawnProcess || spawn;
    const ffmpegPath = options.ffmpegPath || ['/opt/homebrew/bin/ffmpeg', '/usr/local/bin/ffmpeg']
        .find((candidate) => fs.existsSync(candidate)) || 'ffmpeg';
    const platform = options.platform || os.platform();
    let process = null;
    let outputPath = options.outputPath || '';
    function inputArguments() {
        if (platform === 'darwin')
            return ['avfoundation', options.inputDevice || ':default'];
        if (platform === 'win32')
            return ['dshow', options.inputDevice || 'audio=default'];
        if (platform === 'linux')
            return [options.linuxInputFormat || 'pulse', options.inputDevice || 'default'];
        throw new Error(`Unsupported microphone recording platform: ${platform}`);
    }
    function start() {
        if (process)
            return Promise.reject(new Error('A humming recording is already in progress.'));
        outputPath = outputPath || path.join(os.tmpdir(), `tmd-humming-${Date.now()}.wav`);
        return new Promise((resolve, reject) => {
            let settled = false;
            try {
                const [inputFormat, inputDevice] = inputArguments();
                process = spawnProcess(ffmpegPath, [
                    '-hide_banner', '-loglevel', 'error', '-y',
                    '-f', inputFormat, '-i', inputDevice,
                    '-ac', '1', '-ar', '44100', outputPath,
                ], { stdio: ['ignore', 'ignore', 'pipe'] });
                process.once('spawn', () => { settled = true; resolve(); });
                process.once('error', (error) => {
                    process = null;
                    if (!settled)
                        reject(new Error(`Microphone recording requires ffmpeg and an available microphone: ${error.message}`));
                });
            }
            catch (error) {
                process = null;
                reject(new Error(`Microphone recording requires ffmpeg and an available microphone: ${error.message}`));
            }
        });
    }
    function stop() {
        if (!process)
            return Promise.reject(new Error('No humming recording is active.'));
        const activeProcess = process;
        return new Promise((resolve, reject) => {
            activeProcess.once('close', (code) => {
                process = null;
                try {
                    const audio = fs.readFileSync(outputPath);
                    fs.unlinkSync(outputPath);
                    resolve(audio);
                }
                catch (error) {
                    const suffix = code === 0 ? '' : ' The microphone permission may have been denied.';
                    reject(new Error(`The microphone recording did not produce an audio file: ${error.message}.${suffix}`));
                }
            });
            activeProcess.kill('SIGINT');
        });
    }
    function cancel() {
        if (!process)
            return;
        process.kill('SIGKILL');
        process = null;
        try {
            fs.unlinkSync(outputPath);
        }
        catch (_) { /* The process may not have created the file. */ }
    }
    return { start, stop, cancel };
}
