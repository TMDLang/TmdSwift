declare const require: (moduleName: string) => unknown;

type SpawnedProcess = {
  once(event: 'spawn' | 'error' | 'close', listener: (...args: unknown[]) => void): SpawnedProcess;
  kill(signal?: string): boolean;
};

type SpawnProcess = (command: string, args: string[], options: { stdio: string[] }) => SpawnedProcess;
type FileSystem = {
  existsSync(path: string): boolean;
  readFileSync(path: string): Uint8Array;
  unlinkSync(path: string): void;
};
type PathModule = { join(...parts: string[]): string };
type OsModule = { tmpdir(): string };

const { spawn } = require('child_process') as { spawn: SpawnProcess };
const fs = require('fs') as FileSystem;
const path = require('path') as PathModule;
const os = require('os') as OsModule;

export interface HummingRecorder {
  start(): Promise<void>;
  stop(): Promise<Uint8Array>;
  cancel(): void;
}

export interface HummingRecorderOptions {
  spawnProcess?: SpawnProcess;
  outputPath?: string;
  ffmpegPath?: string;
}

export function createHummingRecorder(options: HummingRecorderOptions = {}): HummingRecorder {
  const spawnProcess = options.spawnProcess || spawn;
  const ffmpegPath = options.ffmpegPath || ['/opt/homebrew/bin/ffmpeg', '/usr/local/bin/ffmpeg']
    .find((candidate) => fs.existsSync(candidate)) || 'ffmpeg';
  let process: SpawnedProcess | null = null;
  let outputPath = options.outputPath || '';

  function start(): Promise<void> {
    if (process) return Promise.reject(new Error('A humming recording is already in progress.'));
    outputPath = outputPath || path.join(os.tmpdir(), `tmd-humming-${Date.now()}.wav`);
    return new Promise((resolve, reject) => {
      let settled = false;
      try {
        process = spawnProcess(ffmpegPath, [
          '-hide_banner', '-loglevel', 'error', '-y',
          '-f', 'avfoundation', '-i', ':default',
          '-ac', '1', '-ar', '44100', outputPath,
        ], { stdio: ['ignore', 'ignore', 'pipe'] });
        process.once('spawn', () => { settled = true; resolve(); });
        process.once('error', (error) => {
          process = null;
          if (!settled) reject(new Error(`Microphone recording requires ffmpeg and an available microphone: ${(error as Error).message}`));
        });
      } catch (error) {
        process = null;
        reject(new Error(`Microphone recording requires ffmpeg and an available microphone: ${(error as Error).message}`));
      }
    });
  }

  function stop(): Promise<Uint8Array> {
    if (!process) return Promise.reject(new Error('No humming recording is active.'));
    const activeProcess = process;
    return new Promise((resolve, reject) => {
      activeProcess.once('close', (code) => {
        process = null;
        try {
          const audio = fs.readFileSync(outputPath);
          fs.unlinkSync(outputPath);
          resolve(audio);
        } catch (error) {
          const suffix = code === 0 ? '' : ' The microphone permission may have been denied.';
          reject(new Error(`The microphone recording did not produce an audio file: ${(error as Error).message}.${suffix}`));
        }
      });
      activeProcess.kill('SIGINT');
    });
  }

  function cancel(): void {
    if (!process) return;
    process.kill('SIGKILL');
    process = null;
    try { fs.unlinkSync(outputPath); } catch (_) { /* The process may not have created the file. */ }
  }

  return { start, stop, cancel };
}
